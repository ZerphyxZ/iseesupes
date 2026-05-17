--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

local DjCfg = CharacterConfigs.DoubleJump
local PhaseCfg = DjCfg.Phases
local Features = CharacterConfigs.Features

local PHASE = {
	FlightTransit = "FlightTransit",
	AfterTransition = "AfterTransition",
	LeanUp = "LeanUp",
	LeapDown = "LeapDown",
	DownSupes = "DownSupes",
	CancelFall = "CancelFall",
	CancelLanding = "CancelLanding",
}

type AbilitySession = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	phase: string,
	holdingE: boolean,
	startPosition: Vector3,
	startCFrame: CFrame,
	phaseStartedAt: number,
	abilityStartedAt: number,
	cancelFallStartedAt: number?,
	autoRotateWas: boolean,
	rayParams: RaycastParams,
	landingSignaled: boolean,
	diedConn: RBXScriptConnection?,
}

local DoubleJumpService = Knit.CreateService({
	Name = "DoubleJumpService",
	Client = {
		PhaseChanged = Knit.CreateSignal(),
		AbilityEnded = Knit.CreateSignal(),
		Rejected = Knit.CreateSignal(),
	},
})

local sessions: { [Player]: AbilitySession } = {}
local cooldownEndsAt: { [Player]: number } = {}
local heartbeatConn: RBXScriptConnection? = nil

local function isGrounded(humanoid: Humanoid): boolean
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

local function getRootPart(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function flatDistance(from: Vector3, to: Vector3): number
	local a = Vector3.new(from.X, 0, from.Z)
	local b = Vector3.new(to.X, 0, to.Z)
	return (b - a).Magnitude
end

local function raycastDown(origin: Vector3, length: number, params: RaycastParams): RaycastResult?
	return workspace:Raycast(origin, Vector3.new(0, -length, 0), params)
end

local function phaseRequiresHold(phase: string): boolean
	if phase == PHASE.AfterTransition then
		return PhaseCfg.AfterTransition.RequiresHold == true
	elseif phase == PHASE.LeanUp then
		return PhaseCfg.LeanUp.RequiresHold == true
	end
	return false
end

local function canCancelOnRelease(phase: string): boolean
	return phase == PHASE.FlightTransit
		or phase == PHASE.AfterTransition
		or phase == PHASE.LeanUp
		or phase == PHASE.LeapDown
		or phase == PHASE.DownSupes
end

function DoubleJumpService:_setPhase(session: AbilitySession, phase: string)
	session.phase = phase
	session.phaseStartedAt = os.clock()
	if phase == PHASE.CancelFall then
		session.cancelFallStartedAt = os.clock()
		session.landingSignaled = false
	end
	self.Client.PhaseChanged:Fire(session.player, phase)
end

function DoubleJumpService:_endAbility(player: Player)
	local session = sessions[player]
	if not session then
		return
	end

	if session.diedConn then
		session.diedConn:Disconnect()
		session.diedConn = nil
	end

	session.humanoid.AutoRotate = session.autoRotateWas
	sessions[player] = nil
	self.Client.AbilityEnded:Fire(player)
end

function DoubleJumpService:_transitionToCancelFall(session: AbilitySession)
	if session.phase == PHASE.CancelFall or session.phase == PHASE.CancelLanding then
		return
	end
	self:_setPhase(session, PHASE.CancelFall)
end

function DoubleJumpService:_canActivate(player: Player, humanoid: Humanoid): (boolean, string?)
	local now = os.clock()
	local endsAt = cooldownEndsAt[player]
	if endsAt and now < endsAt then
		return false, "cooldown"
	end

	if sessions[player] then
		return false, "active"
	end

	if humanoid.Health <= 0 then
		return false, "dead"
	end

	local grounded = isGrounded(humanoid)
	if grounded and not DjCfg.Activation.AllowGrounded then
		return false, "grounded"
	end
	if not grounded and not DjCfg.Activation.AllowAirborne then
		return false, "airborne"
	end

	return true, nil
end

function DoubleJumpService:_tickSession(session: AbilitySession, _dt: number)
	local now = os.clock()
	local root = session.root
	local humanoid = session.humanoid

	if humanoid.Health <= 0 or not root.Parent then
		self:_endAbility(session.player)
		return
	end

	if now - session.abilityStartedAt >= DjCfg.MaxAbilityDuration then
		if session.phase ~= PHASE.CancelFall and session.phase ~= PHASE.CancelLanding then
			self:_transitionToCancelFall(session)
		end
	end

	local phase = session.phase
	local phaseElapsed = now - session.phaseStartedAt

	if phaseRequiresHold(phase) and not session.holdingE then
		self:_transitionToCancelFall(session)
		return
	end

	if phase == PHASE.FlightTransit then
		root.AssemblyLinearVelocity = Vector3.zero
		if phaseElapsed >= PhaseCfg.FlightTransit.Duration then
			self:_setPhase(session, PHASE.AfterTransition)
		end
		return
	end

	if phase == PHASE.AfterTransition then
		local cfg = PhaseCfg.AfterTransition
		local riseVel = Vector3.new(0, cfg.RiseSpeed, 0)
		root.AssemblyLinearVelocity = riseVel

		local heightGain = root.Position.Y - session.startPosition.Y
		if heightGain >= cfg.TargetHeightAboveStart or phaseElapsed >= cfg.MaxDuration then
			self:_setPhase(session, PHASE.LeanUp)
		end
		return
	end

	if phase == PHASE.LeanUp then
		local cfg = PhaseCfg.LeanUp
		local forward = session.startCFrame.LookVector
		local flatForward = Vector3.new(forward.X, 0, forward.Z)
		if flatForward.Magnitude > 0 then
			flatForward = flatForward.Unit
		else
			flatForward = Vector3.new(0, 0, -1)
		end

		local vel = flatForward * cfg.ForwardSpeed
		root.AssemblyLinearVelocity = vel

		local dist = flatDistance(session.startPosition, root.Position)
		if dist >= cfg.ForwardDistance or phaseElapsed >= cfg.MaxDuration then
			self:_setPhase(session, PHASE.LeapDown)
		end
		return
	end

	if phase == PHASE.LeapDown then
		local cfg = PhaseCfg.LeapDown
		local hit = raycastDown(root.Position, cfg.SurfaceRayLength, session.rayParams)

		if hit then
			local heightAbove = root.Position.Y - hit.Position.Y
			if heightAbove <= PhaseCfg.DownSupes.TriggerHeightAboveSurface then
				self:_setPhase(session, PHASE.DownSupes)
				return
			end

			if cfg.AlignToHit then
				local target = hit.Position + Vector3.new(0, 2, 0)
				local offset = target - root.Position
				local horizontal = Vector3.new(offset.X, 0, offset.Z)
				local lerp = cfg.HorizontalLerp or 0.15
				local steer = horizontal * lerp
				root.AssemblyLinearVelocity = Vector3.new(steer.X, -cfg.DescentSpeed, steer.Z)
			else
				root.AssemblyLinearVelocity = Vector3.new(0, -cfg.DescentSpeed, 0)
			end
		else
			root.AssemblyLinearVelocity = Vector3.new(0, -cfg.DescentSpeed, 0)
		end
		return
	end

	if phase == PHASE.DownSupes then
		local cfg = PhaseCfg.DownSupes
		local currentVel = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(currentVel.X, math.min(currentVel.Y, -20), currentVel.Z)

		if isGrounded(humanoid) or phaseElapsed >= cfg.Duration then
			self:_endAbility(session.player)
		end
		return
	end

	if phase == PHASE.CancelFall then
		local cancelStarted = session.cancelFallStartedAt or now
		local fallElapsed = now - cancelStarted

		if fallElapsed >= DjCfg.Cancel.MinFallTime then
			local hit = raycastDown(root.Position, DjCfg.Cancel.LandingRayDistance, session.rayParams)
			if hit and root.AssemblyLinearVelocity.Y <= 0 and not session.landingSignaled then
				session.landingSignaled = true
				self:_setPhase(session, PHASE.CancelLanding)
			end
		end

		if isGrounded(humanoid) then
			if session.landingSignaled then
				self:_endAbility(session.player)
			else
				self:_endAbility(session.player)
			end
			return
		end

		if fallElapsed >= DjCfg.Cancel.MaxFallDuration then
			self:_endAbility(session.player)
		end
		return
	end

	if phase == PHASE.CancelLanding then
		if isGrounded(humanoid) then
			self:_endAbility(session.player)
		end
		return
	end
end

function DoubleJumpService:_tryStart(player: Player): (boolean, string?)
	if not Features.UseDoubleJump then
		return false, "disabled"
	end

	local character = player.Character
	if not character then
		return false, "no_character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = getRootPart(character)
	if not humanoid or not root then
		return false, "no_character"
	end

	local ok, reason = self:_canActivate(player, humanoid)
	if not ok then
		return false, reason or "rejected"
	end

	cooldownEndsAt[player] = os.clock() + DjCfg.Cooldown

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local session: AbilitySession = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		phase = PHASE.FlightTransit,
		holdingE = true,
		startPosition = root.Position,
		startCFrame = root.CFrame,
		phaseStartedAt = os.clock(),
		abilityStartedAt = os.clock(),
		cancelFallStartedAt = nil,
		autoRotateWas = humanoid.AutoRotate,
		rayParams = rayParams,
		landingSignaled = false,
		diedConn = nil,
	}

	humanoid.AutoRotate = false
	sessions[player] = session

	session.diedConn = humanoid.Died:Connect(function()
		self:_endAbility(player)
	end)

	self.Client.PhaseChanged:Fire(player, PHASE.FlightTransit)
	return true, nil
end

function DoubleJumpService.Client:RequestStart(player: Player): (boolean, string?)
	local ok, reason = DoubleJumpService:_tryStart(player)
	if not ok then
		DoubleJumpService.Client.Rejected:Fire(player, reason or "rejected")
	end
	return ok, reason
end

function DoubleJumpService.Client:SetHolding(player: Player, isHolding: boolean)
	local session = sessions[player]
	if not session then
		return
	end

	session.holdingE = isHolding

	if not isHolding and canCancelOnRelease(session.phase) then
		if session.phase ~= PHASE.CancelFall and session.phase ~= PHASE.CancelLanding then
			DoubleJumpService:_transitionToCancelFall(session)
		end
	end
end

function DoubleJumpService:KnitStart()
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		for player, session in sessions do
			if player.Parent == Players then
				DoubleJumpService:_tickSession(session, dt)
			else
				DoubleJumpService:_endAbility(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		cooldownEndsAt[player] = nil
		if sessions[player] then
			DoubleJumpService:_endAbility(player)
		end
	end)

	print("[iseesupes] DoubleJumpService ready.")
end

return DoubleJumpService

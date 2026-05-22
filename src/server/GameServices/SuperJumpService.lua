--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DoubleJumpLanding = require(ReplicatedStorage.Shared.Utils.DoubleJumpLanding)

local Features = CharacterConfigs.Features
local SjCfg = CharacterConfigs.SuperJump

local PHASE = {
	LeanUp = "LeanUp",
	DownSupes = "DownSupes",
}

local PHASE_ATTR = "SjAbilityPhase"
local DJ_PHASE_ATTR = "DjAbilityPhase"

type SuperJumpSession = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	phase: string,
	startPosition: Vector3,
	flightDirection: Vector3,
	phaseStartedAt: number,
	abilityStartedAt: number,
	descentStartedAt: number?,
	glideStartPosition: Vector3?,
	glideStartedAt: number?,
	riseCompleteLatch: boolean,
	autoRotateWas: boolean,
	rayParams: RaycastParams,
	groundedAt: number?,
	diedConn: RBXScriptConnection?,
}

local SuperJumpService = Knit.CreateService({
	Name = "SuperJumpService",
	Client = {
		PhaseChanged = Knit.CreateSignal(),
		AbilityEnded = Knit.CreateSignal(),
		Rejected = Knit.CreateSignal(),
	},
})

local sessions: { [Player]: SuperJumpSession } = {}
local cooldownEndsAt: { [Player]: number } = {}
local heartbeatConn: RBXScriptConnection? = nil

local function isGrounded(humanoid: Humanoid): boolean
	return DoubleJumpLanding.isGrounded(humanoid)
end

local function getRootPart(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function flatUnit(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function flatDistance(from: Vector3, to: Vector3): number
	local a = Vector3.new(from.X, 0, from.Z)
	local b = Vector3.new(to.X, 0, to.Z)
	return (b - a).Magnitude
end

local function applyVelocityOnly(root: BasePart, velocity: Vector3)
	root.AssemblyLinearVelocity = velocity
end

local function getGlideForwardSpeed(leanCfg: { [string]: any }): number
	local distance = math.max(leanCfg.ForwardDistance or 0, 0)
	local duration = math.max(leanCfg.MaxGlideDuration or 0.5, 0.05)
	return distance / duration
end

local function restoreUprightPose(root: BasePart, flightDir: Vector3)
	local flat = flatUnit(flightDir)
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + flat)
	root.AssemblyAngularVelocity = Vector3.zero
end

function SuperJumpService:_setPhase(session: SuperJumpSession, phase: string)
	session.phase = phase
	session.phaseStartedAt = os.clock()
	if phase == PHASE.LeanUp then
		session.descentStartedAt = nil
		session.glideStartPosition = nil
		session.glideStartedAt = nil
		session.riseCompleteLatch = false
		session.groundedAt = nil
		restoreUprightPose(session.root, session.flightDirection)
	elseif phase == PHASE.DownSupes then
		session.groundedAt = nil
		restoreUprightPose(session.root, session.flightDirection)
	end
	session.player:SetAttribute(PHASE_ATTR, phase)
	self.Client.PhaseChanged:Fire(session.player, phase)
end

function SuperJumpService:_endAbility(player: Player)
	local session = sessions[player]
	if not session then
		player:SetAttribute(PHASE_ATTR, nil)
		return
	end

	sessions[player] = nil

	if session.diedConn then
		session.diedConn:Disconnect()
		session.diedConn = nil
	end

	pcall(function()
		session.root.AssemblyLinearVelocity = Vector3.zero
		session.root.AssemblyAngularVelocity = Vector3.zero
	end)
	pcall(function()
		session.humanoid.AutoRotate = session.autoRotateWas
		session.humanoid.PlatformStand = false
	end)
	pcall(function()
		session.root:SetNetworkOwner(session.player)
	end)

	player:SetAttribute(PHASE_ATTR, nil)
	self.Client.AbilityEnded:Fire(player)
end

function SuperJumpService:_tickSession(session: SuperJumpSession, dt: number)
	local character = session.character
	if not character.Parent then
		self:_endAbility(session.player)
		return
	end

	local humanoid = session.humanoid
	local root = session.root
	if not humanoid.Parent or not root.Parent then
		self:_endAbility(session.player)
		return
	end

	local now = os.clock()
	local phaseElapsed = now - session.phaseStartedAt
	local abilityElapsed = now - session.abilityStartedAt
	local leanCfg = SjCfg.LeanUp
	local downCfg = SjCfg.DownSupes

	if abilityElapsed >= SjCfg.MaxDuration then
		self:_endAbility(session.player)
		return
	end

	if session.phase == PHASE.LeanUp then
		local heightGain = root.Position.Y - session.startPosition.Y
		local riseHeight = leanCfg.RiseHeight or 5
		local riseMaxTime = leanCfg.RiseMaxDuration or 0.4

		if not session.riseCompleteLatch then
			if
				(phaseElapsed >= leanCfg.MinAirTime and heightGain >= riseHeight)
				or phaseElapsed >= riseMaxTime
			then
				session.riseCompleteLatch = true
				session.glideStartPosition = root.Position
				session.glideStartedAt = now
			end
		end

		if not session.riseCompleteLatch then
			applyVelocityOnly(root, Vector3.new(0, leanCfg.RiseSpeed, 0))
			return
		end

		local glideStart = session.glideStartPosition or root.Position
		if not session.glideStartPosition then
			session.glideStartPosition = glideStart
		end
		if not session.glideStartedAt then
			session.glideStartedAt = now
		end

		local glideElapsed = now - (session.glideStartedAt :: number)
		local glideDuration = math.max(leanCfg.MaxGlideDuration or 0.5, 0.05)
		local forwardDistance = math.max(leanCfg.ForwardDistance or 0, 0)

		if glideElapsed < glideDuration then
			local glideSpeed = getGlideForwardSpeed(leanCfg)
			local fallDrift = leanCfg.GlideFallSpeed or 6
			local vel = session.flightDirection * glideSpeed + Vector3.new(0, -fallDrift, 0)
			applyVelocityOnly(root, vel)
			return
		end

		-- Finish glide: ensure full ForwardDistance on the horizontal plane for this window.
		local flatDir = session.flightDirection
		local glideStartFlat = Vector3.new(glideStart.X, 0, glideStart.Z)
		local targetFlat = glideStartFlat + flatDir * forwardDistance
		local pos = root.Position
		root.CFrame = CFrame.lookAt(
			Vector3.new(targetFlat.X, pos.Y, targetFlat.Z),
			Vector3.new(targetFlat.X, pos.Y, targetFlat.Z) + flatDir
		)
		root.AssemblyAngularVelocity = Vector3.zero

		self:_setPhase(session, PHASE.DownSupes)
		return
	end

	if session.phase == PHASE.DownSupes then
		local grounded = DoubleJumpLanding.isGroundedForLanding(humanoid, root, session.rayParams, downCfg)
		if not grounded then
			session.groundedAt = nil
			restoreUprightPose(root, session.flightDirection)
			applyVelocityOnly(root, Vector3.new(0, -(downCfg.ApproachDescentSpeed or 40), 0))
			return
		end

		if not session.groundedAt then
			session.groundedAt = now
		end

		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid.PlatformStand = false

		local settle = downCfg.SettleDuration or 0.15
		local maxDown = downCfg.MaxDuration or 2
		if now - (session.groundedAt :: number) >= settle or phaseElapsed >= maxDown then
			self:_endAbility(session.player)
		end
	end
end

function SuperJumpService:_canStart(player: Player, humanoid: Humanoid): (boolean, string?)
	if not Features.UseSuperJump then
		return false, "disabled"
	end

	if sessions[player] then
		return false, "already_active"
	end

	if player:GetAttribute(DJ_PHASE_ATTR) then
		return false, "double_jump_active"
	end

	local ends = cooldownEndsAt[player]
	if ends and os.clock() < ends then
		return false, "cooldown"
	end

	if isGrounded(humanoid) then
		return false, "must_be_airborne"
	end

	return true, nil
end

function SuperJumpService:_tryStart(player: Player): (boolean, string?)
	local character = player.Character
	if not character then
		return false, "no_character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = getRootPart(character)
	if not humanoid or not root then
		return false, "no_character"
	end

	local ok, reason = self:_canStart(player, humanoid)
	if not ok then
		return false, reason or "rejected"
	end

	cooldownEndsAt[player] = os.clock() + SjCfg.Cooldown

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local startCFrame = root.CFrame
	local session: SuperJumpSession = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		phase = PHASE.LeanUp,
		startPosition = root.Position,
		flightDirection = flatUnit(startCFrame.LookVector),
		phaseStartedAt = os.clock(),
		abilityStartedAt = os.clock(),
		descentStartedAt = nil,
		glideStartPosition = nil,
		glideStartedAt = nil,
		riseCompleteLatch = false,
		autoRotateWas = humanoid.AutoRotate,
		rayParams = rayParams,
		groundedAt = nil,
		diedConn = nil,
	}

	humanoid.AutoRotate = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	sessions[player] = session

	session.diedConn = humanoid.Died:Connect(function()
		self:_endAbility(player)
	end)

	player:SetAttribute(PHASE_ATTR, PHASE.LeanUp)
	self.Client.PhaseChanged:Fire(player, PHASE.LeanUp)
	return true, nil
end

function SuperJumpService.Client:RequestStart(player: Player): (boolean, string?)
	local ok, reason = SuperJumpService:_tryStart(player)
	if not ok then
		SuperJumpService.Client.Rejected:Fire(player, reason or "rejected")
	end
	return ok, reason
end

function SuperJumpService:KnitStart()
	heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		for player, session in sessions do
			if player.Parent == Players then
				SuperJumpService:_tickSession(session, dt)
			else
				SuperJumpService:_endAbility(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		cooldownEndsAt[player] = nil
		if sessions[player] then
			SuperJumpService:_endAbility(player)
		end
	end)

	print("[iseesupes] SuperJumpService ready.")
end

return SuperJumpService

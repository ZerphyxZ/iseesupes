--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DoubleJumpLanding = require(ReplicatedStorage.Shared.Utils.DoubleJumpLanding)
local LevelDesignTuning = require(ReplicatedStorage.Shared.Utils.LevelDesignTuning)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local Features = CharacterConfigs.Features
local SjCfg = CharacterConfigs.SuperJump

type SjTuning = LevelDesignTuning.SuperJumpTuning

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
	arcComplete: boolean,
	arcCompletedAt: number?,
	autoRotateWas: boolean,
	rayParams: RaycastParams,
	groundedAt: number?,
	diedConn: RBXScriptConnection?,
	tuning: SjTuning,
	tuningConns: { RBXScriptConnection },
	clientSteerDirection: Vector3?,
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

local function refreshSessionTuning(session: SuperJumpSession)
	session.tuning = LevelDesignTuning.getSuperJump(session.player)
end

local function bindTuningChangeListeners(session: SuperJumpSession)
	for _, conn in session.tuningConns do
		conn:Disconnect()
	end
	table.clear(session.tuningConns)

	local function onAttrChanged(_name: string)
		refreshSessionTuning(session)
	end

	table.insert(session.tuningConns, session.player.AttributeChanged:Connect(onAttrChanged))
	if session.character then
		table.insert(session.tuningConns, session.character.AttributeChanged:Connect(onAttrChanged))
	end
end

local function disconnectTuningListeners(session: SuperJumpSession)
	for _, conn in session.tuningConns do
		conn:Disconnect()
	end
	table.clear(session.tuningConns)
end

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

local function playerHasSuperJumpToolEquipped(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local toolName = SjCfg.ToolName or "SuperJump"
	local tool = character:FindFirstChild(toolName)
	return tool ~= nil and tool:IsA("Tool")
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

--- Yaw only — never lerp full CFrame (that drifts position and fights velocity).
local function faceFlightDirectionSmooth(root: BasePart, flightDir: Vector3, dt: number, turnLerp: number)
	local flat = flatUnit(flightDir)
	local pos = root.Position
	local targetRot = CFrame.lookAt(Vector3.zero, flat).Rotation
	local currentRot = root.CFrame.Rotation
	if currentRot.LookVector:Dot(targetRot.LookVector) > 0.998 then
		root.AssemblyAngularVelocity = Vector3.zero
		return
	end
	local alpha = math.min(1, turnLerp * dt)
	root.CFrame = CFrame.new(pos) * currentRot:Lerp(targetRot, alpha)
	root.AssemblyAngularVelocity = Vector3.zero
end

local function isSteeringEnabled(tuning: SjTuning): boolean
	return tuning.Steering.Enabled ~= false
end

local function getSteerDirection(session: SuperJumpSession, _tuning: SjTuning): Vector3
	local clientSteer = session.clientSteerDirection
	if clientSteer then
		return flatUnit(clientSteer)
	end
	return flatUnit(session.flightDirection)
end

local function applySteerToFlightDirection(session: SuperJumpSession, dt: number, tuning: SjTuning)
	if not isSteeringEnabled(tuning) then
		return
	end

	local target = getSteerDirection(session, tuning)
	local alpha = math.min(1, (tuning.Steering.DirectionLerp or 12) * dt)
	session.flightDirection = flatUnit(session.flightDirection:Lerp(target, alpha))
end

local function blendHorizontalVelocity(
	session: SuperJumpSession,
	baseVel: Vector3,
	horizontalScale: number,
	tuning: SjTuning
): Vector3
	if horizontalScale <= 0 or not isSteeringEnabled(tuning) then
		return baseVel
	end

	local hSpeed = tuning.Steering.HorizontalSpeed or 50
	return baseVel + session.flightDirection * hSpeed * horizontalScale
end

function SuperJumpService:_setPhase(session: SuperJumpSession, phase: string)
	session.phase = phase
	session.phaseStartedAt = os.clock()
	if phase == PHASE.LeanUp then
		session.descentStartedAt = nil
		session.groundedAt = nil
		session.arcComplete = false
		session.arcCompletedAt = nil
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
	disconnectTuningListeners(session)

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

function SuperJumpService:HasActiveSession(player: Player): boolean
	return sessions[player] ~= nil
end

--- Ends active super jump before lobby teleport / profile reset.
function SuperJumpService:ForceEndForLobby(player: Player)
	if sessions[player] then
		self:_endAbility(player)
	else
		player:SetAttribute(PHASE_ATTR, nil)
	end
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
	local tuning = session.tuning
	local leanCfg = tuning.LeanUp
	local downCfg = tuning.DownSupes

	if abilityElapsed >= tuning.MaxDuration then
		self:_endAbility(session.player)
		return
	end

	if not playerHasSuperJumpToolEquipped(session.player) then
		self:_endAbility(session.player)
		return
	end

	applySteerToFlightDirection(session, dt, tuning)
	local descentBlend = tuning.Steering.DescentHorizontalBlend or 0.35
	local turnLerp = tuning.Steering.TurnLerp or 14

	if session.phase == PHASE.LeanUp then
		if not session.arcComplete then
			local heightGain = root.Position.Y - session.startPosition.Y
			local riseHeight = leanCfg.RiseHeight or 5
			local forwardDistance = math.max(leanCfg.ForwardDistance or 0, 0)
			local flatDist = flatDistance(session.startPosition, root.Position)

			local riseMaxTime = leanCfg.RiseMaxDuration or 0.4
			local glideDuration = math.max(leanCfg.MaxGlideDuration or 0.5, 0.05)
			local arcMaxTime = math.max(riseMaxTime, glideDuration)

			local reachedHeight = heightGain >= riseHeight
			local reachedDistance = flatDist >= forwardDistance
			local timeCap = phaseElapsed >= arcMaxTime

			if not ((reachedHeight and reachedDistance) or timeCap) then
				local forwardSpeed = getGlideForwardSpeed(leanCfg)
				local riseVy = if reachedHeight then -(leanCfg.GlideFallSpeed or 6) else leanCfg.RiseSpeed
				local vel = session.flightDirection * forwardSpeed + Vector3.new(0, riseVy, 0)
				applyVelocityOnly(root, vel)
				root.AssemblyAngularVelocity = Vector3.zero
				return
			end

			session.arcComplete = true
			session.arcCompletedAt = now
		end

		local rayLength = leanCfg.SurfaceRayLength or 250
		local hit = DoubleJumpLanding.raycastDownFromRoot(root, rayLength, session.rayParams)
		local descentElapsed = now - (session.arcCompletedAt :: number)
		if
			DoubleJumpLanding.shouldStartLeapDown(
				humanoid,
				root,
				hit,
				{ MinDuration = downCfg.MinDuration },
				downCfg,
				descentElapsed,
				session.rayParams,
				nil
			)
		then
			self:_setPhase(session, PHASE.DownSupes)
			return
		end

		local approachVel = Vector3.new(0, -(downCfg.ApproachDescentSpeed or 40), 0)
		applyVelocityOnly(root, blendHorizontalVelocity(session, approachVel, descentBlend, tuning))
		root.AssemblyAngularVelocity = Vector3.zero
		return
	end

	if session.phase == PHASE.DownSupes then
		local grounded = DoubleJumpLanding.isGroundedForLanding(humanoid, root, session.rayParams, downCfg)
		if not grounded then
			session.groundedAt = nil
			local fallVel = Vector3.new(0, -(downCfg.ApproachDescentSpeed or 40), 0)
			applyVelocityOnly(root, blendHorizontalVelocity(session, fallVel, descentBlend, tuning))
			faceFlightDirectionSmooth(root, session.flightDirection, dt, turnLerp)
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

	if not playerHasSuperJumpToolEquipped(player) then
		return false, "no_tool"
	end

	local ends = cooldownEndsAt[player]
	if ends and os.clock() < ends then
		return false, "cooldown"
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

	local tuning = LevelDesignTuning.getSuperJump(player)
	local level = SpeedConfigs.GetPlayerLevel(player)
	cooldownEndsAt[player] = os.clock() + SpeedConfigs.GetSuperJumpCooldown(level)

	StudioLog.print("LevelDesign", "[iseesupes] Super Jump using server tuning:", LevelDesignTuning.formatActiveTuning(player))

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
		arcComplete = false,
		arcCompletedAt = nil,
		autoRotateWas = humanoid.AutoRotate,
		rayParams = rayParams,
		groundedAt = nil,
		diedConn = nil,
		tuning = tuning,
		tuningConns = {},
		clientSteerDirection = nil,
	}

	humanoid.AutoRotate = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	sessions[player] = session
	bindTuningChangeListeners(session)

	session.diedConn = humanoid.Died:Connect(function()
		self:_endAbility(player)
	end)

	player:SetAttribute(PHASE_ATTR, PHASE.LeanUp)
	self.Client.PhaseChanged:Fire(player, PHASE.LeanUp)
	return true, nil
end

function SuperJumpService.Client:UpdateSteerInput(player: Player, direction: Vector3)
	local session = sessions[player]
	if not session then
		return
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude >= 0.01 then
		session.clientSteerDirection = flatUnit(flat)
	else
		session.clientSteerDirection = nil
	end
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

		for _, player in Players:GetPlayers() do
			if not sessions[player] and player:GetAttribute(PHASE_ATTR) ~= nil then
				player:SetAttribute(PHASE_ATTR, nil)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		cooldownEndsAt[player] = nil
		if sessions[player] then
			SuperJumpService:_endAbility(player)
		end
	end)

	local function onPlayerCharacterAdded(player: Player)
		SuperJumpService:_endAbility(player)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			onPlayerCharacterAdded(player)
		end)
	end)

	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			onPlayerCharacterAdded(player)
		end)
	end

	StudioLog.ready("SuperJumpService")
end

return SuperJumpService

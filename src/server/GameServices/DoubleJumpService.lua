--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DoubleJumpLanding = require(ReplicatedStorage.Shared.Utils.DoubleJumpLanding)
local DebugLog = require(ReplicatedStorage.Shared.Utils.DebugLog)

local DjCfg = CharacterConfigs.DoubleJump
local PhaseCfg = DjCfg.Phases
local PoseCfg = DjCfg.SupermanPose
local SteerCfg = DjCfg.Steering
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

local PHASE_ATTR = "DjAbilityPhase"

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
	flightDirection: Vector3,
	currentPitch: number,
	groundedAt: number?,
	leapDownFirstGroundedAt: number?,
	leapDownTouchdown: boolean,
	descentStartedAt: number?,
	debugLoggedLeapDownTrigger: boolean,
	afterTransitionComplete: boolean,
	clientSteerDirection: Vector3?,
	landingControlReleased: boolean,
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

local function raycastDown(origin: Vector3, length: number, params: RaycastParams): RaycastResult?
	return DoubleJumpLanding.raycastDown(origin, length, params)
end

local function getSteerThreshold(): number
	return SteerCfg.SteerMoveThreshold
		or PhaseCfg.AfterTransition.SteerMoveThreshold
		or CharacterConfigs.Locomotion.MoveThreshold
end

local function isSteeringEnabled(): boolean
	return SteerCfg.Enabled ~= false
end

local function getDescentHorizontalBlend(): number
	if typeof(SteerCfg.DescentHorizontalBlend) == "number" then
		return SteerCfg.DescentHorizontalBlend
	end
	return PhaseCfg.LeapDown.HorizontalLerp or 0.35
end

local function getSteerDirection(session: AbilitySession): Vector3
	local clientSteer = session.clientSteerDirection
	if clientSteer and clientSteer.Magnitude >= getSteerThreshold() then
		return flatUnit(clientSteer)
	end

	local move = session.humanoid.MoveDirection
	if move.Magnitude >= getSteerThreshold() then
		return flatUnit(move)
	end
	return flatUnit(session.flightDirection)
end

local function applySteerToFlightDirection(session: AbilitySession, dt: number)
	if not isSteeringEnabled() then
		return
	end

	local target = getSteerDirection(session)
	local alpha = math.min(1, (SteerCfg.DirectionLerp or 10) * dt)
	session.flightDirection = flatUnit(session.flightDirection:Lerp(target, alpha))
end

local function blendHorizontalVelocity(session: AbilitySession, baseVel: Vector3, horizontalScale: number): Vector3
	if horizontalScale <= 0 or not isSteeringEnabled() then
		return baseVel
	end

	local hSpeed = SteerCfg.HorizontalSpeed or 45
	return baseVel + session.flightDirection * hSpeed * horizontalScale
end

local function applyVelocityOnly(root: BasePart, velocity: Vector3)
	root.AssemblyLinearVelocity = velocity
end

local function restoreUprightPose(root: BasePart, flightDir: Vector3)
	local flat = flatUnit(flightDir)
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + flat)
	root.AssemblyAngularVelocity = Vector3.zero
end

local function setAutoRotateForPhase(session: AbilitySession, phase: string)
	if phase == PHASE.FlightTransit or phase == PHASE.AfterTransition then
		session.humanoid.AutoRotate = false
	else
		session.humanoid.AutoRotate = session.autoRotateWas
	end
end

local function finalizeCharacterControl(session: AbilitySession)
	local root = session.root
	local humanoid = session.humanoid

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	restoreUprightPose(root, session.flightDirection)

	humanoid.AutoRotate = session.autoRotateWas
	humanoid.PlatformStand = false

	if isGrounded(humanoid) then
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function cframeWithPitch(position: Vector3, flightDir: Vector3, pitchDeg: number): CFrame
	local flat = flatUnit(flightDir)
	local base = CFrame.lookAt(position, position + flat)
	return base * CFrame.Angles(math.rad(pitchDeg), 0, 0)
end

local function lerpPitch(session: AbilitySession, targetPitch: number, dt: number)
	local alpha = math.min(1, PoseCfg.PitchLerp * dt)
	session.currentPitch = session.currentPitch + (targetPitch - session.currentPitch) * alpha
end

local function applyFlightOrientation(session: AbilitySession, velocity: Vector3?)
	local root = session.root
	root.CFrame = cframeWithPitch(root.Position, session.flightDirection, session.currentPitch)
	if velocity then
		root.AssemblyLinearVelocity = velocity
	end
end

local function computeSupermanVelocity(session: AbilitySession, riseSpeed: number, forwardSpeed: number): Vector3
	return session.flightDirection * forwardSpeed + Vector3.new(0, riseSpeed, 0)
end

local function applyDownSupesEntrySnap(session: AbilitySession)
	local downCfg = PhaseCfg.DownSupes
	local leapCfg = PhaseCfg.LeapDown
	local snapHeight = downCfg.UprightSnapHeight or 6
	local hit = raycastDown(session.root.Position, leapCfg.SurfaceRayLength, session.rayParams)
	if not hit then
		return
	end
	local effectiveHeight = DoubleJumpLanding.getEffectiveHeightAbove(
		hit,
		session.root,
		session.humanoid,
		downCfg
	)
	if effectiveHeight <= snapHeight then
		restoreUprightPose(session.root, session.flightDirection)
	end
end

local function applyTouchdownUprightOnce(session: AbilitySession)
	restoreUprightPose(session.root, session.flightDirection)
	session.root.AssemblyLinearVelocity = Vector3.zero
	session.root.AssemblyAngularVelocity = Vector3.zero
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
		session.groundedAt = nil
		session.humanoid.PlatformStand = false
		restoreUprightPose(session.root, session.flightDirection)
	elseif phase == PHASE.CancelLanding then
		session.groundedAt = nil
		session.humanoid.PlatformStand = false
		restoreUprightPose(session.root, session.flightDirection)
	elseif phase == PHASE.LeanUp then
		session.currentPitch = PoseCfg.UprightPitch
		session.flightDirection = flatUnit(session.flightDirection)
		session.groundedAt = nil
		session.descentStartedAt = nil
		session.debugLoggedLeapDownTrigger = false
		restoreUprightPose(session.root, session.flightDirection)
	elseif phase == PHASE.LeapDown then
		session.currentPitch = PoseCfg.UprightPitch
		session.flightDirection = flatUnit(session.flightDirection)
		session.groundedAt = nil
		session.leapDownFirstGroundedAt = nil
		session.landingControlReleased = false
		session.leapDownTouchdown = true
		session.humanoid.PlatformStand = false
		applyTouchdownUprightOnce(session)
	end
	setAutoRotateForPhase(session, phase)
	-- #region agent log
	DebugLog.write("DoubleJumpService:_setPhase", "phase_changed", {
		phase = phase,
		player = session.player.Name,
		rootY = session.root.Position.Y,
		grounded = isGrounded(session.humanoid),
		platformStand = session.humanoid.PlatformStand,
	}, "A")
	-- #endregion
	session.player:SetAttribute(PHASE_ATTR, phase)
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

	finalizeCharacterControl(session)

	pcall(function()
		session.root:SetNetworkOwner(session.player)
	end)

	sessions[player] = nil
	player:SetAttribute(PHASE_ATTR, nil)
	self.Client.AbilityEnded:Fire(player)
end

function DoubleJumpService:_transitionToCancelFall(session: AbilitySession)
	if session.phase == PHASE.CancelFall or session.phase == PHASE.CancelLanding then
		return
	end
	if session.phase == PHASE.LeapDown then
		local landingCfg = PhaseCfg.DownSupes
		local minPlay = landingCfg.MinGroundedPlayDuration or 1
		if not session.leapDownFirstGroundedAt then
			return
		end
		if os.clock() - session.leapDownFirstGroundedAt < minPlay then
			return
		end
	end
	local landingCfg = PhaseCfg.DownSupes
	local cancelCfg = DjCfg.Cancel
	local hit = DoubleJumpLanding.raycastDownFromRoot(
		session.root,
		cancelCfg.LandingRayLength or 250,
		session.rayParams
	)
	if
		DoubleJumpLanding.isGroundedForLanding(session.humanoid, session.root, session.rayParams, landingCfg)
		or DoubleJumpLanding.shouldStartCancelLanding(
			session.humanoid,
			session.root,
			hit,
			session.rayParams,
			landingCfg,
			cancelCfg,
			cancelCfg.MinFallTime or 0.08
		)
	then
		-- Same landing phase as full ability hold: server keeps physics until settled.
		self:_setPhase(session, PHASE.LeapDown)
	else
		self:_setPhase(session, PHASE.CancelFall)
	end
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

function DoubleJumpService:_tickSession(session: AbilitySession, dt: number)
	local now = os.clock()
	local root = session.root
	local humanoid = session.humanoid

	if humanoid.Health <= 0 or not root.Parent or not session.character.Parent then
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
		local cfg = PhaseCfg.FlightTransit
		applySteerToFlightDirection(session, dt)

		local progress = math.clamp(phaseElapsed / cfg.Duration, 0, 1)
		local targetPitch = PoseCfg.TransitStartPitch
			+ (PoseCfg.TransitEndPitch - PoseCfg.TransitStartPitch) * progress
		local transitAlpha = math.min(1, PoseCfg.TransitPitchLerp * dt)
		session.currentPitch = session.currentPitch + (targetPitch - session.currentPitch) * transitAlpha

		local nudge = cfg.ForwardNudgeSpeed or 0
		local vel = if nudge > 0 then session.flightDirection * nudge else Vector3.zero
		applyFlightOrientation(session, vel)

		if phaseElapsed >= cfg.Duration then
			self:_setPhase(session, PHASE.AfterTransition)
		end
		return
	end

	if phase == PHASE.AfterTransition then
		local cfg = PhaseCfg.AfterTransition
		applySteerToFlightDirection(session, dt)
		local vel = computeSupermanVelocity(session, cfg.RiseSpeed, cfg.ForwardSpeed)
		lerpPitch(session, PoseCfg.FlightPitch, dt)
		applyFlightOrientation(session, vel)

		local heightGain = root.Position.Y - session.startPosition.Y
		if not session.afterTransitionComplete then
			if heightGain >= cfg.TargetHeightAboveStart or phaseElapsed >= cfg.MaxDuration then
				session.afterTransitionComplete = true
				-- #region agent log
				DebugLog.write("DoubleJumpService:AfterTransition", "after_transition_ended", {
					phaseElapsed = phaseElapsed,
					heightGain = heightGain,
					targetHeight = cfg.TargetHeightAboveStart,
					maxDuration = cfg.MaxDuration,
					grounded = isGrounded(humanoid),
				}, "E")
				-- #endregion
				self:_setPhase(session, PHASE.LeanUp)
			end
		end
		return
	end

	if phase == PHASE.LeanUp then
		local cfg = PhaseCfg.LeanUp
		local descentCfg = PhaseCfg.LeapDown
		local landingCfg = PhaseCfg.DownSupes
		local descentBlend = getDescentHorizontalBlend()

		root.AssemblyAngularVelocity = Vector3.zero
		applySteerToFlightDirection(session, dt)
		restoreUprightPose(root, session.flightDirection)

		local dist = flatDistance(session.startPosition, root.Position)
		local inDescent = dist >= cfg.ForwardDistance or phaseElapsed >= cfg.MaxDuration

		if not inDescent then
			applyVelocityOnly(root, session.flightDirection * cfg.ForwardSpeed)
			return
		end

		if not session.descentStartedAt then
			session.descentStartedAt = now
		end
		local descentElapsed = now - (session.descentStartedAt :: number)

		local hit = DoubleJumpLanding.raycastDownFromRoot(root, descentCfg.SurfaceRayLength, session.rayParams)
		local grounded = DoubleJumpLanding.isGroundedForLanding(humanoid, root, session.rayParams, landingCfg)
		local startLeapDown = DoubleJumpLanding.shouldStartLeapDown(
			humanoid,
			root,
			hit,
			descentCfg,
			landingCfg,
			descentElapsed
		)
		if startLeapDown then
			local effectiveHeight: number? = nil
			if hit then
				effectiveHeight = DoubleJumpLanding.getEffectiveHeightAbove(hit, root, humanoid, landingCfg)
			end
			if not session.debugLoggedLeapDownTrigger then
				session.debugLoggedLeapDownTrigger = true
				-- #region agent log
				DebugLog.write("DoubleJumpService:LeanUp", "should_start_leapdown", {
					descentElapsed = descentElapsed,
					effectiveHeight = effectiveHeight,
					triggerHeight = landingCfg.TriggerHeightAboveSurface,
					grounded = grounded,
					hasHit = hit ~= nil,
				}, "A")
				-- #endregion
			end
			self:_setPhase(session, PHASE.LeapDown)
			return
		end

		local vel: Vector3
		if hit then
			local heightAbove = root.Position.Y - hit.Position.Y
			local slowHeight = descentCfg.SlowDescentHeight or 12
			if heightAbove <= slowHeight then
				local t = math.clamp(heightAbove / slowHeight, 0.2, 1)
				vel = Vector3.new(0, -descentCfg.DescentSpeed * t, 0)
			else
				vel = Vector3.new(0, -descentCfg.DescentSpeed, 0)
			end
		else
			local approachSpeed = landingCfg.ApproachDescentSpeed or descentCfg.DescentSpeed
			vel = Vector3.new(0, -approachSpeed, 0)
		end

		applyVelocityOnly(root, blendHorizontalVelocity(session, vel, descentBlend))

		local maxDuration = landingCfg.MaxDuration or 2
		if descentElapsed >= maxDuration then
			self:_setPhase(session, PHASE.LeapDown)
		end
		return
	end

	if phase == PHASE.LeapDown then
		local cfg = PhaseCfg.DownSupes
		local landingLock = cfg.LandingLockDuration or 0.2
		local minGroundedPlay = cfg.MinGroundedPlayDuration or 0.4
		local settleDuration = cfg.SettleDuration or 0.15
		local endGroundedAfter = math.max(minGroundedPlay, settleDuration)
		local maxDuration = cfg.MaxDuration or 2.5
		local approachSpeed = cfg.ApproachDescentSpeed or 12
		local descentBlend = getDescentHorizontalBlend()

		root.AssemblyAngularVelocity = Vector3.zero

		local landingCfg = PhaseCfg.DownSupes
		local grounded = DoubleJumpLanding.isGroundedForLanding(humanoid, root, session.rayParams, landingCfg)
		if not grounded then
			session.groundedAt = nil
			session.landingControlReleased = false
			applySteerToFlightDirection(session, dt)
			restoreUprightPose(root, session.flightDirection)
			applyVelocityOnly(
				root,
				blendHorizontalVelocity(session, Vector3.new(0, -approachSpeed, 0), descentBlend)
			)
			return
		end

		if not session.leapDownFirstGroundedAt then
			session.leapDownFirstGroundedAt = now
			-- #region agent log
			DebugLog.write("DoubleJumpService:LeapDown", "leapdown_first_grounded", {
				phaseElapsed = phaseElapsed,
				rootY = root.Position.Y,
			}, "A")
			-- #endregion
		end
		if not session.groundedAt then
			session.groundedAt = now
		end

		local sinceFirstGround = now - (session.leapDownFirstGroundedAt :: number)
		humanoid:ChangeState(Enum.HumanoidStateType.Running)

		if sinceFirstGround < landingLock then
			applyVelocityOnly(root, Vector3.zero)
		elseif not session.landingControlReleased then
			session.landingControlReleased = true
			humanoid.AutoRotate = session.autoRotateWas
			pcall(function()
				root:SetNetworkOwner(session.player)
			end)
		end

		if sinceFirstGround >= endGroundedAfter then
			-- #region agent log
			DebugLog.write("DoubleJumpService:LeapDown", "leapdown_playthrough_complete", {
				phaseElapsed = phaseElapsed,
				sinceFirstGround = sinceFirstGround,
				endGroundedAfter = endGroundedAfter,
			}, "A")
			-- #endregion
			self:_endAbility(session.player)
			return
		end

		if phaseElapsed >= maxDuration then
			self:_endAbility(session.player)
		end
		return
	end

	if phase == PHASE.CancelFall then
		local cancelCfg = DjCfg.Cancel
		local landingCfg = PhaseCfg.DownSupes
		local cancelStarted = session.cancelFallStartedAt or now
		local fallElapsed = now - cancelStarted
		local approachSpeed = landingCfg.ApproachDescentSpeed or 12
		local descentBlend = getDescentHorizontalBlend() * 0.5

		humanoid.PlatformStand = false
		root.AssemblyAngularVelocity = Vector3.zero
		applySteerToFlightDirection(session, dt)
		restoreUprightPose(root, session.flightDirection)

		if not session.landingSignaled then
			local hit = DoubleJumpLanding.raycastDownFromRoot(
				root,
				cancelCfg.LandingRayLength or 250,
				session.rayParams
			)
			if
				DoubleJumpLanding.shouldStartCancelLanding(
					humanoid,
					root,
					hit,
					session.rayParams,
					landingCfg,
					cancelCfg,
					fallElapsed
				)
			then
				session.landingSignaled = true
				self:_setPhase(session, PHASE.LeapDown)
				return
			end

			applyVelocityOnly(
				root,
				blendHorizontalVelocity(session, Vector3.new(0, -approachSpeed, 0), descentBlend)
			)
		end

		if fallElapsed >= cancelCfg.MaxFallDuration then
			self:_setPhase(session, PHASE.LeapDown)
		end
		return
	end

	if phase == PHASE.CancelLanding then
		-- Legacy phase: use LeapDown landing physics (same as holding E through the jump).
		local landingCfg = PhaseCfg.DownSupes
		local landingLock = landingCfg.LandingLockDuration or 0.2
		local minGroundedPlay = landingCfg.MinGroundedPlayDuration or 0.4
		local settleDuration = landingCfg.SettleDuration or 0.15
		local endGroundedAfter = math.max(minGroundedPlay, settleDuration)
		local approachSpeed = landingCfg.ApproachDescentSpeed or 12
		local descentBlend = getDescentHorizontalBlend() * 0.5

		root.AssemblyAngularVelocity = Vector3.zero
		humanoid.PlatformStand = false

		local grounded = DoubleJumpLanding.isGroundedForLanding(humanoid, root, session.rayParams, landingCfg)
		if not grounded then
			session.groundedAt = nil
			session.landingControlReleased = false
			applySteerToFlightDirection(session, dt)
			restoreUprightPose(root, session.flightDirection)
			applyVelocityOnly(
				root,
				blendHorizontalVelocity(session, Vector3.new(0, -approachSpeed, 0), descentBlend)
			)
			return
		end

		if not session.leapDownFirstGroundedAt then
			session.leapDownFirstGroundedAt = now
		end
		if not session.groundedAt then
			session.groundedAt = now
		end

		local sinceFirstGround = now - (session.leapDownFirstGroundedAt :: number)
		humanoid:ChangeState(Enum.HumanoidStateType.Running)

		if sinceFirstGround < landingLock then
			applyVelocityOnly(root, Vector3.zero)
		elseif not session.landingControlReleased then
			session.landingControlReleased = true
			humanoid.AutoRotate = session.autoRotateWas
			pcall(function()
				root:SetNetworkOwner(session.player)
			end)
		end

		if sinceFirstGround >= endGroundedAfter then
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

	local startCFrame = root.CFrame
	local session: AbilitySession = {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		phase = PHASE.FlightTransit,
		holdingE = true,
		startPosition = root.Position,
		startCFrame = startCFrame,
		phaseStartedAt = os.clock(),
		abilityStartedAt = os.clock(),
		cancelFallStartedAt = nil,
		autoRotateWas = humanoid.AutoRotate,
		rayParams = rayParams,
		landingSignaled = false,
		diedConn = nil,
		flightDirection = flatUnit(startCFrame.LookVector),
		currentPitch = PoseCfg.TransitStartPitch,
		groundedAt = nil,
		leapDownFirstGroundedAt = nil,
		leapDownTouchdown = false,
		descentStartedAt = nil,
		debugLoggedLeapDownTrigger = false,
		afterTransitionComplete = false,
		clientSteerDirection = nil,
		landingControlReleased = false,
	}

	humanoid.AutoRotate = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	sessions[player] = session

	session.diedConn = humanoid.Died:Connect(function()
		self:_endAbility(player)
	end)

	player:SetAttribute(PHASE_ATTR, PHASE.FlightTransit)
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

function DoubleJumpService.Client:UpdateSteerInput(player: Player, direction: Vector3)
	local session = sessions[player]
	if not session then
		return
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude >= getSteerThreshold() then
		session.clientSteerDirection = flatUnit(flat)
	else
		session.clientSteerDirection = nil
	end
end

function DoubleJumpService.Client:SetHolding(player: Player, isHolding: boolean)
	local session = sessions[player]
	if not session then
		return
	end

	session.holdingE = isHolding

	if not isHolding then
		session.clientSteerDirection = nil
	end

	if not isHolding and canCancelOnRelease(session.phase) then
		if session.cancelFallStartedAt and session.phase == PHASE.LeapDown then
			return
		end
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

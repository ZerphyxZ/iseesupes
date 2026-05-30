--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DoubleJumpLanding = require(ReplicatedStorage.Shared.Utils.DoubleJumpLanding)
local DoubleJumpFlightPhysics = require(ReplicatedStorage.Shared.Utils.DoubleJumpFlightPhysics)
local DebugLog = require(ReplicatedStorage.Shared.Utils.DebugLog)
local LevelDesignTuning = require(ReplicatedStorage.Shared.Utils.LevelDesignTuning)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local ThrustConfigs = SpeedConfigs.Thrust

local Features = CharacterConfigs.Features
local DjCfg = CharacterConfigs.DoubleJump

type DjTuning = LevelDesignTuning.DoubleJumpTuning

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
local SJ_PHASE_ATTR = "SjAbilityPhase"

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
	lastFlatHeading: Vector3?,
	currentPitch: number,
	currentRoll: number,
	groundedAt: number?,
	leapDownFirstGroundedAt: number?,
	leapDownTouchdown: boolean,
	descentStartedAt: number?,
	debugLoggedLeapDownTrigger: boolean,
	afterTransitionComplete: boolean,
	clientSteerDirection: Vector3?,
	clientSteerAxis: number?,
	clientSteerPitchAxis: number?,
	landingControlReleased: boolean,
	tuning: DjTuning,
	tuningConns: { RBXScriptConnection },
	hardLandedAt: number?,
	flightBodyGyro: BodyGyro?,
	flightBodyVelocity: BodyVelocity?,
	platformStandWas: boolean?,
	thrustDepleted: boolean?,
	thrustEmptyAt: number?,
	flightFuelAtStart: number?,
	landingProbeAt: number?,
	landingProbe: DoubleJumpLanding.LandingProbe?,
	obstacleProbeAt: number?,
	obstacleBlocked: boolean?,
}

local HARD_LANDED_END_SECONDS = 1.5

local function clientOwnsFlightPhysics(): boolean
	local net = DjCfg.Network
	if net and net.ClientOwnsFlightPhysics == false then
		return false
	end
	return true
end

local function phaseUsesLandingProbe(phase: string): boolean
	return phase == PHASE.AfterTransition or phase == PHASE.LeanUp or phase == PHASE.LeapDown
end

local function getLandingProbeDistanceForPhase(session: AbilitySession, phase: string): number?
	local phaseCfg = session.tuning.Phases
	local landingCfg = phaseCfg.DownSupes
	if phase == PHASE.LeanUp then
		local descentCfg = phaseCfg.LeapDown
		local now = os.clock()
		local inDescent = (now - session.phaseStartedAt) >= ThrustConfigs.LeanUpSafetyMaxDuration
		if inDescent then
			return descentCfg.SurfaceRayLength
		end
		return DoubleJumpLanding.getGlideProbeDistance(session.humanoid, landingCfg)
	end
	if phase == PHASE.LeapDown then
		return phaseCfg.LeapDown.SurfaceRayLength or 250
	end
	return DoubleJumpLanding.getGlideProbeDistance(session.humanoid, landingCfg)
end

local function refreshSessionLandingProbe(session: AbilitySession, now: number): DoubleJumpLanding.LandingProbe
	local phaseCfg = session.tuning.Phases
	local landingCfg = phaseCfg.DownSupes
	local probeDistance = getLandingProbeDistanceForPhase(session, session.phase)
	local probe, cacheAt, obstacleAt, obstacleBlocked = DoubleJumpLanding.refreshLandingProbe(
		session.humanoid,
		session.root,
		session.rayParams,
		landingCfg,
		session.flightDirection,
		now,
		session.landingProbeAt,
		session.landingProbe,
		session.obstacleProbeAt,
		session.obstacleBlocked,
		probeDistance
	)
	session.landingProbe = probe
	session.landingProbeAt = cacheAt
	session.obstacleProbeAt = obstacleAt
	session.obstacleBlocked = obstacleBlocked
	return probe
end

-- Build-a-Plane style BodyMovers (deprecated but simple; same tuning as FlightPhysics).
local FLIGHT_GYRO_P = 6000
local FLIGHT_GYRO_D = 700
local FLIGHT_GYRO_MAX_TORQUE = Vector3.new(1e8, 1e8, 1e8)
local FLIGHT_GYRO_OFF = Vector3.zero
local FLIGHT_VEL_MAX_FORCE = Vector3.new(1e8, 1e8, 1e8)

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
local DataService: any = nil

local function refreshSessionTuning(session: AbilitySession)
	session.tuning = LevelDesignTuning.getDoubleJump(session.player)
end

local function bindTuningChangeListeners(session: AbilitySession)
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

local function disconnectTuningListeners(session: AbilitySession)
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

local function getOrientationHeading(session: AbilitySession): Vector3
	local flat = Vector3.new(session.flightDirection.X, 0, session.flightDirection.Z)
	if flat.Magnitude >= 0.01 then
		local heading = flat.Unit
		session.lastFlatHeading = heading
		return heading
	end
	if session.lastFlatHeading then
		return session.lastFlatHeading
	end
	local fallback = flatUnit(session.startCFrame.LookVector)
	session.lastFlatHeading = fallback
	return fallback
end

local function unit3D(vector: Vector3): Vector3
	if vector.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return vector.Unit
end

local function usesCameraPitchSteer(tuning: DjTuning): boolean
	return tuning.Steering.FollowCameraPitch ~= false
end

local function phaseUsesCameraPitchSteer(phase: string): boolean
	return phase == PHASE.AfterTransition or phase == PHASE.LeanUp
end

local function directionFromFlatAndPitchAxis(flatDir: Vector3, axis: number, maxPitchDeg: number): Vector3
	local flat = flatUnit(flatDir)
	local pitchRad = math.rad(maxPitchDeg) * math.clamp(axis, -1, 1)
	local cosPitch = math.cos(pitchRad)
	local sinPitch = math.sin(pitchRad)
	return unit3D(Vector3.new(flat.X * cosPitch, sinPitch, flat.Z * cosPitch))
end

local function clampSteerPitch(dir: Vector3, maxPitchDeg: number): Vector3
	local unit = unit3D(dir)
	local flat = Vector3.new(unit.X, 0, unit.Z)
	if flat.Magnitude < 0.01 then
		return unit
	end
	flat = flat.Unit
	local maxY = math.sin(math.rad(math.max(5, maxPitchDeg)))
	local y = math.clamp(unit.Y, -maxY, maxY)
	return unit3D(Vector3.new(flat.X, y, flat.Z))
end

local function normalizeFlightDirection(dir: Vector3, tuning: DjTuning, phase: string?): Vector3
	if usesCameraPitchSteer(tuning) and phase and phaseUsesCameraPitchSteer(phase) then
		return unit3D(dir)
	end
	return flatUnit(dir)
end

local function flatDistance(from: Vector3, to: Vector3): number
	local a = Vector3.new(from.X, 0, from.Z)
	local b = Vector3.new(to.X, 0, to.Z)
	return (b - a).Magnitude
end

local function raycastDown(origin: Vector3, length: number, params: RaycastParams): RaycastResult?
	return DoubleJumpLanding.raycastDown(origin, length, params)
end

local function getSteerThreshold(tuning: DjTuning): number
	local steerCfg = tuning.Steering
	local phaseCfg = tuning.Phases
	return steerCfg.SteerMoveThreshold
		or phaseCfg.AfterTransition.SteerMoveThreshold
		or CharacterConfigs.Locomotion.MoveThreshold
end

local function isSteeringEnabled(tuning: DjTuning): boolean
	return tuning.Steering.Enabled ~= false
end

local function getCancelFallSpeed(tuning: DjTuning): number
	local cancel = tuning.Cancel
	if typeof(cancel.FallSpeed) == "number" and cancel.FallSpeed > 0 then
		return cancel.FallSpeed
	end
	return tuning.Phases.LeapDown.DescentSpeed or 70
end

local function getDescentHorizontalBlend(tuning: DjTuning): number
	local steerCfg = tuning.Steering
	if typeof(steerCfg.DescentHorizontalBlend) == "number" then
		return steerCfg.DescentHorizontalBlend
	end
	return tuning.Phases.LeapDown.HorizontalLerp or 0.35
end

local function getSteerDirection(session: AbilitySession, tuning: DjTuning): Vector3
	local threshold = getSteerThreshold(tuning)
	local clientSteer = session.clientSteerDirection
	if clientSteer and clientSteer.Magnitude >= threshold then
		return normalizeFlightDirection(clientSteer, tuning, session.phase)
	end

	local move = session.humanoid.MoveDirection
	if move.Magnitude >= threshold then
		return normalizeFlightDirection(move, tuning, session.phase)
	end
	return normalizeFlightDirection(session.flightDirection, tuning, session.phase)
end

local function getFlightDirectionWithPitch(session: AbilitySession, tuning: DjTuning): Vector3
	local base = getSteerDirection(session, tuning)
	if not phaseUsesCameraPitchSteer(session.phase) then
		return base
	end

	local axis = session.clientSteerPitchAxis or 0
	if math.abs(axis) < 0.05 then
		return base
	end

	local maxPitch = tuning.Steering.MaxPitchDegrees or 45
	return directionFromFlatAndPitchAxis(base, axis, maxPitch)
end

local function applySteerToFlightDirection(session: AbilitySession, dt: number, tuning: DjTuning)
	if not isSteeringEnabled(tuning) then
		return
	end

	local target = getSteerDirection(session, tuning)
	local alpha = math.min(1, (tuning.Steering.DirectionLerp or 10) * dt)
	session.flightDirection = normalizeFlightDirection(session.flightDirection:Lerp(target, alpha), tuning, session.phase)
end

local function blendHorizontalVelocity(session: AbilitySession, baseVel: Vector3, horizontalScale: number, tuning: DjTuning): Vector3
	if horizontalScale <= 0 or not isSteeringEnabled(tuning) then
		return baseVel
	end

	local hSpeed = tuning.Steering.HorizontalSpeed or 45
	local flatDir = flatUnit(session.flightDirection)
	return baseVel + flatDir * hSpeed * horizontalScale
end

local function applyVelocityOnly(root: BasePart, velocity: Vector3)
	if clientOwnsFlightPhysics() then
		return
	end
	root.AssemblyLinearVelocity = velocity
end

local function destroyFlightMovers(session: AbilitySession)
	if session.flightBodyGyro then
		session.flightBodyGyro:Destroy()
		session.flightBodyGyro = nil
	end
	if session.flightBodyVelocity then
		session.flightBodyVelocity:Destroy()
		session.flightBodyVelocity = nil
	end
end

local function createFlightMovers(session: AbilitySession)
	destroyFlightMovers(session)

	local root = session.root
	-- Do NOT set PlatformStand — it replicates to the client and blocks Animator tracks.

	local bv = Instance.new("BodyVelocity")
	bv.Name = "DjFlightVelocity"
	bv.MaxForce = FLIGHT_VEL_MAX_FORCE
	bv.Velocity = Vector3.zero
	bv.Parent = root
	session.flightBodyVelocity = bv

	local bg = Instance.new("BodyGyro")
	bg.Name = "DjFlightGyro"
	bg.MaxTorque = FLIGHT_GYRO_OFF
	bg.P = FLIGHT_GYRO_P
	bg.D = FLIGHT_GYRO_D
	bg.CFrame = root.CFrame
	bg.Parent = root
	session.flightBodyGyro = bg

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function applySessionVelocity(session: AbilitySession, velocity: Vector3)
	local bv = session.flightBodyVelocity
	if bv and bv.Parent then
		bv.Velocity = velocity
	else
		applyVelocityOnly(session.root, velocity)
	end
end

local function restoreUprightPose(root: BasePart, flightDir: Vector3)
	if clientOwnsFlightPhysics() then
		return
	end
	DoubleJumpFlightPhysics.restoreUprightPose(root, flightDir)
end

local function syncSessionFlightDirectionFromRoot(session: AbilitySession)
	session.flightDirection = flatUnit(session.root.CFrame.LookVector)
	local flat = Vector3.new(session.flightDirection.X, 0, session.flightDirection.Z)
	if flat.Magnitude >= 0.01 then
		session.lastFlatHeading = flat.Unit
	end
end


local function setAutoRotateForPhase(session: AbilitySession, phase: string)
	if phase == PHASE.FlightTransit or phase == PHASE.AfterTransition or phase == PHASE.LeanUp then
		session.humanoid.AutoRotate = false
	else
		session.humanoid.AutoRotate = session.autoRotateWas
	end
end

local function finalizeCharacterControl(session: AbilitySession)
	local root = session.root
	local humanoid = session.humanoid

	destroyFlightMovers(session)

	if not clientOwnsFlightPhysics() then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		restoreUprightPose(root, session.flightDirection)
	end

	humanoid.AutoRotate = session.autoRotateWas
	humanoid.PlatformStand = false

	local landingCfg = session.tuning.Phases.DownSupes
	if DoubleJumpLanding.isOnWalkableGround(humanoid, root, session.rayParams, landingCfg) then
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
end

local function lerpRollToward(session: AbilitySession, targetRoll: number, dt: number, ratePerSec: number)
	local alpha = math.min(1, ratePerSec * dt)
	session.currentRoll = session.currentRoll + (targetRoll - session.currentRoll) * alpha
end

local function smoothstep01(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerpPitch(
	session: AbilitySession,
	targetPitch: number,
	dt: number,
	tuning: DjTuning,
	rateOverride: number?
)
	local rate = rateOverride or tuning.SupermanPose.PitchLerp or 10
	local alpha = math.min(1, rate * dt)
	local current = session.currentPitch or 0
	session.currentPitch = current + (targetPitch - current) * alpha
end

local function velocityAlongClimbAngle(flatDir: Vector3, climbDegrees: number, speed: number): Vector3
	local climbRad = math.rad(climbDegrees)
	local flat = flatUnit(flatDir)
	local dir = unit3D(flat * math.cos(climbRad) + Vector3.new(0, math.sin(climbRad), 0))
	return dir * speed
end

local function computeLaunchRiseVelocity(
	session: AbilitySession,
	cfg: any,
	tuning: DjTuning,
	phaseElapsed: number
): Vector3
	local poseCfg = tuning.SupermanPose
	local forwardSpeed = cfg.ForwardSpeed or 0
	local riseSpeed = cfg.RiseSpeed or 0
	local startClimb = poseCfg.LaunchClimbStartDegrees or 14
	local endClimb = poseCfg.LaunchClimbEndDegrees or 26
	local duration = cfg.MaxDuration or 1.1
	local t = smoothstep01(phaseElapsed / duration)
	local climbDeg = startClimb + (endClimb - startClimb) * t
	local speed = math.sqrt(forwardSpeed * forwardSpeed + riseSpeed * riseSpeed)
	return velocityAlongClimbAngle(session.flightDirection, climbDeg, speed)
end

local function updateBankRoll(session: AbilitySession, dt: number, tuning: DjTuning, enabled: boolean)
	local poseCfg = tuning.SupermanPose
	if not enabled or poseCfg.BankEnabled == false then
		lerpRollToward(session, 0, dt, poseCfg.BankReturnRate or 2)
		return
	end

	local steer = math.clamp(session.clientSteerAxis or 0, -1, 1)
	local maxBank = poseCfg.MaxBankDegrees or 40
	if math.abs(steer) > 0.05 then
		local target = steer * maxBank
		lerpRollToward(session, target, dt, poseCfg.BankFollowRate or 3)
	else
		lerpRollToward(session, 0, dt, poseCfg.BankReturnRate or 2)
	end
end

local function setFlightGyroEnabled(session: AbilitySession, enabled: boolean)
	local bg = session.flightBodyGyro
	if bg and bg.Parent then
		bg.MaxTorque = if enabled then FLIGHT_GYRO_MAX_TORQUE else FLIGHT_GYRO_OFF
	end
end

-- Velocity only — no root rotation (e.g. descent after movers destroyed).
local function applyFlightVelocityOnly(session: AbilitySession, velocity: Vector3?)
	setFlightGyroEnabled(session, false)
	if velocity then
		applySessionVelocity(session, velocity)
	end
end

local function buildFlightOrientationCFrame(
	pos: Vector3,
	heading: Vector3,
	rollDeg: number,
	pitchDeg: number?
): CFrame
	local flat = flatUnit(heading)
	local pitch = pitchDeg or 0
	if math.abs(pitch) > 0.01 then
		return CFrame.lookAt(pos, pos + flat) * CFrame.Angles(math.rad(pitch), 0, math.rad(rollDeg))
	end
	local _, yaw, _ = CFrame.lookAt(pos, pos + flat):ToEulerAnglesYXZ()
	return CFrame.new(pos) * CFrame.Angles(0, yaw, math.rad(rollDeg))
end

-- Yaw + optional forward pitch (launch) + bank roll. LeanUp glide keeps pitch at 0 (anim owns pose).
local function applyFlightYawRollAndVelocity(
	session: AbilitySession,
	heading: Vector3,
	rollDeg: number,
	velocity: Vector3?,
	pitchDeg: number?
)
	if clientOwnsFlightPhysics() then
		return
	end

	local root = session.root
	local bg = session.flightBodyGyro
	local pos = root.Position
	local targetCF = buildFlightOrientationCFrame(pos, heading, rollDeg, pitchDeg)

	if bg and bg.Parent then
		setFlightGyroEnabled(session, false)
		root.CFrame = targetCF
		root.AssemblyAngularVelocity = Vector3.zero
	else
		root.CFrame = targetCF
		root.AssemblyAngularVelocity = Vector3.zero
	end

	if velocity then
		applySessionVelocity(session, velocity)
	end
end

local function computeFlightVelocity(
	session: AbilitySession,
	riseSpeed: number,
	forwardSpeed: number,
	tuning: DjTuning
): Vector3
	local dir = normalizeFlightDirection(session.flightDirection, tuning, session.phase)
	if usesCameraPitchSteer(tuning) and phaseUsesCameraPitchSteer(session.phase) then
		local speed = math.sqrt(forwardSpeed * forwardSpeed + riseSpeed * riseSpeed)
		return dir * speed
	end
	return dir * forwardSpeed + Vector3.new(0, riseSpeed, 0)
end

local function applyDownSupesEntrySnap(session: AbilitySession, tuning: DjTuning)
	local downCfg = tuning.Phases.DownSupes
	local leapCfg = tuning.Phases.LeapDown
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

local function phaseRequiresHold(phase: string, tuning: DjTuning): boolean
	if phase == PHASE.AfterTransition then
		return tuning.Phases.AfterTransition.RequiresHold == true
	elseif phase == PHASE.LeanUp then
		return tuning.Phases.LeanUp.RequiresHold == true
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

local function phaseConsumesThrust(phase: string): boolean
	return phase == PHASE.FlightTransit or phase == PHASE.AfterTransition or phase == PHASE.LeanUp
end

function DoubleJumpService:_onThrustEmpty(session: AbilitySession)
	if session.thrustDepleted then
		return
	end

	session.thrustDepleted = true
	session.thrustEmptyAt = os.clock()

	if DataService then
		DataService:OnFlightDrained(session.player)
	end

	destroyFlightMovers(session)
	session.humanoid.PlatformStand = false

	if not clientOwnsFlightPhysics() then
		local fallSpeed = getCancelFallSpeed(session.tuning)
		applyVelocityOnly(session.root, Vector3.new(0, -fallSpeed, 0))
	end
end

function DoubleJumpService:_tickThrustDepleted(session: AbilitySession, tuning: DjTuning, now: number)
	local humanoid = session.humanoid
	local root = session.root

	if not isGrounded(humanoid) then
		local fallSpeed = getCancelFallSpeed(tuning)
		applyVelocityOnly(root, Vector3.new(0, -fallSpeed, 0))
		return
	end

	local emptyAt = session.thrustEmptyAt or now
	if now - emptyAt >= ThrustConfigs.EmptyDescentGrace then
		local player = session.player
		self:_endAbility(player)
		if DataService then
			DataService:TeleportToLobby(player)
		end
	end
end

function DoubleJumpService:_setPhase(session: AbilitySession, phase: string)
	refreshSessionTuning(session)
	local tuning = session.tuning
	local poseCfg = tuning.SupermanPose

	session.phase = phase
	session.phaseStartedAt = os.clock()
	session.landingProbe = nil
	session.landingProbeAt = nil
	if phase == PHASE.CancelFall then
		destroyFlightMovers(session)
		session.cancelFallStartedAt = os.clock()
		session.landingSignaled = false
		session.groundedAt = nil
		session.currentRoll = 0
		session.humanoid.PlatformStand = false
		restoreUprightPose(session.root, session.flightDirection)
		local fallSpeed = getCancelFallSpeed(tuning)
		applyVelocityOnly(session.root, Vector3.new(0, -fallSpeed, 0))
	elseif phase == PHASE.CancelLanding then
		destroyFlightMovers(session)
		session.groundedAt = nil
		session.currentRoll = 0
		session.humanoid.PlatformStand = false
		restoreUprightPose(session.root, session.flightDirection)
	elseif phase == PHASE.LeanUp then
		session.currentPitch = 0
		session.currentRoll = 0
		local heading = getOrientationHeading(session)
		session.flightDirection = heading
		session.lastFlatHeading = heading
		session.groundedAt = nil
		session.descentStartedAt = nil
		session.debugLoggedLeapDownTrigger = false
		applyFlightYawRollAndVelocity(session, heading, 0, nil)
	elseif phase == PHASE.LeapDown then
		destroyFlightMovers(session)
		session.currentPitch = poseCfg.UprightPitch
		session.currentRoll = 0
		session.flightDirection = flatUnit(session.flightDirection)
		session.groundedAt = nil
		session.leapDownFirstGroundedAt = nil
		session.landingControlReleased = false
		session.leapDownTouchdown = true
		session.humanoid.PlatformStand = false
		applyTouchdownUprightOnce(session)
	end
	setAutoRotateForPhase(session, phase)
	DebugLog.write("DoubleJumpService:_setPhase", "phase_changed", {
		phase = phase,
		player = session.player.Name,
		rootY = session.root.Position.Y,
		grounded = isGrounded(session.humanoid),
		platformStand = session.humanoid.PlatformStand,
	}, "A")
	session.player:SetAttribute(PHASE_ATTR, phase)
	self.Client.PhaseChanged:Fire(session.player, phase)
end

function DoubleJumpService:_endAbilityFromCollision(session: AbilitySession)
	destroyFlightMovers(session)
	session.humanoid.PlatformStand = false
	if not clientOwnsFlightPhysics() then
		session.root.AssemblyLinearVelocity = Vector3.zero
		session.root.AssemblyAngularVelocity = Vector3.zero
	end
	self:_endAbility(session.player)
end

function DoubleJumpService:_endAbility(player: Player)
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

	disconnectTuningListeners(session)

	pcall(function()
		finalizeCharacterControl(session)
	end)

	pcall(function()
		session.humanoid.AutoRotate = session.autoRotateWas
	end)
	pcall(function()
		session.humanoid.PlatformStand = false
	end)

	pcall(function()
		session.root:SetNetworkOwner(session.player)
	end)

	player:SetAttribute(PHASE_ATTR, nil)
	self.Client.AbilityEnded:Fire(player)
end

function DoubleJumpService:_transitionToCancelFall(session: AbilitySession)
	if session.phase == PHASE.CancelFall or session.phase == PHASE.CancelLanding then
		return
	end
	local tuning = session.tuning
	local phaseCfg = tuning.Phases

	if session.phase == PHASE.LeapDown then
		local landingCfg = phaseCfg.DownSupes
		local minPlay = landingCfg.MinGroundedPlayDuration or 1
		if not session.leapDownFirstGroundedAt then
			return
		end
		if os.clock() - session.leapDownFirstGroundedAt < minPlay then
			return
		end
	end
	local landingCfg = phaseCfg.DownSupes
	local cancelCfg = tuning.Cancel
	local hit = DoubleJumpLanding.raycastDownFromRoot(
		session.root,
		cancelCfg.LandingRayLength or 250,
		session.rayParams
	)
	if
		DoubleJumpLanding.isGroundedForLanding(
			session.humanoid,
			session.root,
			session.rayParams,
			landingCfg,
			session.flightDirection
		)
		or DoubleJumpLanding.shouldStartCancelLanding(
			session.humanoid,
			session.root,
			hit,
			session.rayParams,
			landingCfg,
			cancelCfg,
			cancelCfg.MinFallTime or 0.08,
			session.flightDirection
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

	if player:GetAttribute(SJ_PHASE_ATTR) then
		return false, "super_jump_active"
	end

	if humanoid.Health <= 0 then
		return false, "dead"
	end

	local tuning = LevelDesignTuning.getDoubleJump(player)
	local grounded = isGrounded(humanoid)
	if grounded and not tuning.Activation.AllowGrounded then
		return false, "grounded"
	end
	if not grounded and not tuning.Activation.AllowAirborne then
		return false, "airborne"
	end

	return true, nil
end

function DoubleJumpService:_tickSession(session: AbilitySession, dt: number)
	local tuning = session.tuning
	local phaseCfg = tuning.Phases
	local poseCfg = tuning.SupermanPose

	local now = os.clock()
	local root = session.root
	local humanoid = session.humanoid

	if humanoid.Health <= 0 or not root.Parent or not session.character.Parent then
		self:_endAbility(session.player)
		return
	end

	if clientOwnsFlightPhysics() then
		syncSessionFlightDirectionFromRoot(session)
	end

	local landingCfg = phaseCfg.DownSupes
	local probe: DoubleJumpLanding.LandingProbe? = nil
	if phaseUsesLandingProbe(session.phase) then
		probe = refreshSessionLandingProbe(session, now)
	end

	local onWalkableGround = if probe then probe.onWalkableGround
		else DoubleJumpLanding.isOnWalkableGround(humanoid, root, session.rayParams, landingCfg)

	-- Wall/obstacle: end E immediately (PlatformStand often keeps FloorMaterial = Air on walls).
	if probe then
		if not probe.isNearFloor and probe.obstacleBlocked then
			self:_endAbilityFromCollision(session)
			return
		end
	elseif
		session.phase == PHASE.AfterTransition
		or session.phase == PHASE.LeanUp
		or session.phase == PHASE.LeapDown
	then
		if
			DoubleJumpLanding.hasObstacleContact(
				humanoid,
				root,
				session.rayParams,
				landingCfg,
				session.flightDirection
			)
		then
			self:_endAbilityFromCollision(session)
			return
		end
	end

	-- Hard-grounded fail-safe: feet on walkable floor only (not "near landing" while still gliding).
	if onWalkableGround then
		session.hardLandedAt = session.hardLandedAt or now
		if
			session.phase ~= PHASE.FlightTransit
			and now - (session.hardLandedAt :: number) >= HARD_LANDED_END_SECONDS
		then
			self:_endAbility(session.player)
			return
		end
	else
		session.hardLandedAt = nil
	end

	local abilityCap = ThrustConfigs.GetAbilityTimeCap(session.flightFuelAtStart or 0, tuning.MaxAbilityDuration)
	if now - session.abilityStartedAt >= abilityCap then
		if session.phase ~= PHASE.CancelFall and session.phase ~= PHASE.CancelLanding then
			self:_transitionToCancelFall(session)
		end
	end

	local phase = session.phase
	local phaseElapsed = now - session.phaseStartedAt

	if phaseRequiresHold(phase, tuning) and not session.holdingE then
		self:_transitionToCancelFall(session)
		return
	end

	if session.thrustDepleted then
		self:_tickThrustDepleted(session, tuning, now)
		return
	end

	if phaseConsumesThrust(phase) and DataService then
		local drain = ThrustConfigs.DrainPerSecond * dt
		if not DataService:TryConsumeThrust(session.player, drain) then
			self:_onThrustEmpty(session)
			self:_tickThrustDepleted(session, tuning, now)
			return
		end
	end

	if phase == PHASE.FlightTransit then
		local cfg = phaseCfg.FlightTransit
		if not clientOwnsFlightPhysics() then
			applySteerToFlightDirection(session, dt, tuning)
		end

		local progress = if cfg.Duration > 0 then math.clamp(phaseElapsed / cfg.Duration, 0, 1) else 1
		local startPitch = poseCfg.TransitStartPitch or 0
		local endPitch = poseCfg.TransitEndPitch or -35
		local targetPitch = startPitch + (endPitch - startPitch) * smoothstep01(progress)
		lerpPitch(session, targetPitch, dt, tuning, poseCfg.TransitPitchLerp)

		local nudge = cfg.ForwardNudgeSpeed or 0
		local vel = Vector3.zero
		if nudge > 0 then
			vel = velocityAlongClimbAngle(
				session.flightDirection,
				poseCfg.TransitLaunchClimbDegrees or 10,
				nudge
			)
		end
		applyFlightYawRollAndVelocity(session, getOrientationHeading(session), 0, vel, session.currentPitch)

		if phaseElapsed >= cfg.Duration then
			self:_setPhase(session, PHASE.AfterTransition)
		end
		return
	end

	if phase == PHASE.AfterTransition then
		local cfg = phaseCfg.AfterTransition
		if not clientOwnsFlightPhysics() then
			applySteerToFlightDirection(session, dt, tuning)
		end

		local riseT = smoothstep01(phaseElapsed / (cfg.MaxDuration or 1.1))
		local transitEndPitch = poseCfg.TransitEndPitch or -35
		local launchBodyPitch = poseCfg.LaunchBodyPitch or -72
		local targetPitch = transitEndPitch + (launchBodyPitch - transitEndPitch) * riseT
		lerpPitch(session, targetPitch, dt, tuning, poseCfg.LaunchPitchLerp)

		local vel = computeLaunchRiseVelocity(session, cfg, tuning, phaseElapsed)
		local pitchBlend = poseCfg.CameraPitchVelocityBlend or 0.35
		local pitchAxis = session.clientSteerPitchAxis or 0
		if pitchBlend > 0 and math.abs(pitchAxis) >= 0.05 then
			local aim = getFlightDirectionWithPitch(session, tuning)
			vel = unit3D(vel.Unit:Lerp(aim, pitchBlend)) * vel.Magnitude
		end
		applyFlightYawRollAndVelocity(session, getOrientationHeading(session), 0, vel, session.currentPitch)

		local heightGain = root.Position.Y - session.startPosition.Y
		if not session.afterTransitionComplete then
			local ready = heightGain >= cfg.TargetHeightAboveStart or phaseElapsed >= cfg.MaxDuration
			local minElapsed = phaseElapsed >= (cfg.MinDuration or 0)
			if ready and minElapsed then
				session.afterTransitionComplete = true
				self:_setPhase(session, PHASE.LeanUp)
			end
		end
		return
	end

	if phase == PHASE.LeanUp then
		local cfg = phaseCfg.LeanUp
		local descentCfg = phaseCfg.LeapDown
		local landingCfg = phaseCfg.DownSupes
		local descentBlend = getDescentHorizontalBlend(tuning)

		if not clientOwnsFlightPhysics() then
			root.AssemblyAngularVelocity = Vector3.zero
			local fpState: DoubleJumpFlightPhysics.FlightState = {
				flightDirection = session.flightDirection,
				lastFlatHeading = session.lastFlatHeading,
				currentPitch = session.currentPitch,
				currentRoll = session.currentRoll,
				descentStartedAt = session.descentStartedAt,
				clientSteerAxis = session.clientSteerAxis,
				clientSteerPitchAxis = session.clientSteerPitchAxis,
				clientSteerDirection = session.clientSteerDirection,
			}
			DoubleJumpFlightPhysics.applyLeanUpHeadingSteer(
				fpState,
				dt,
				tuning,
				phase,
				session.clientSteerDirection
			)
			session.flightDirection = fpState.flightDirection
			session.lastFlatHeading = fpState.lastFlatHeading
		end

		-- Glide ends when thrust fuel hits 0 (_onThrustEmpty), not ForwardDistance / E_LeanDist.
		local maxPhaseTime = ThrustConfigs.LeanUpSafetyMaxDuration
		local inDescent = phaseElapsed >= maxPhaseTime

		if not inDescent then
			if probe and DoubleJumpLanding.shouldApproachLandFromGlide(probe) then
				self:_setPhase(session, PHASE.LeapDown)
				return
			end

			local flightDir = getFlightDirectionWithPitch(session, tuning)
			local vel = flightDir * cfg.ForwardSpeed
			if not clientOwnsFlightPhysics() then
				local fpState: DoubleJumpFlightPhysics.FlightState = {
					flightDirection = session.flightDirection,
					lastFlatHeading = session.lastFlatHeading,
					currentPitch = session.currentPitch,
					currentRoll = session.currentRoll,
					descentStartedAt = session.descentStartedAt,
					clientSteerAxis = session.clientSteerAxis,
					clientSteerPitchAxis = session.clientSteerPitchAxis,
					clientSteerDirection = session.clientSteerDirection,
				}
				vel = DoubleJumpFlightPhysics.applyKeyboardStrafeVelocity(fpState, vel, tuning)
			end
			updateBankRoll(session, dt, tuning, true)
			applyFlightYawRollAndVelocity(
				session,
				getOrientationHeading(session),
				session.currentRoll,
				vel
			)
			return
		end

		if session.flightBodyGyro then
			destroyFlightMovers(session)
			session.humanoid.PlatformStand = false
		end
		session.currentRoll = 0
		restoreUprightPose(root, session.flightDirection)

		if not session.descentStartedAt then
			session.descentStartedAt = now
		end
		local descentElapsed = now - (session.descentStartedAt :: number)

		local walkableHit = if probe and probe.walkableHit then probe.walkableHit else nil
		if not walkableHit then
			local hit = DoubleJumpLanding.raycastDownFromRoot(root, descentCfg.SurfaceRayLength, session.rayParams)
			walkableHit = if hit and DoubleJumpLanding.isWalkableHit(hit, landingCfg) then hit else nil
		end
		local startLeapDown = DoubleJumpLanding.shouldStartLeapDown(
			humanoid,
			root,
			walkableHit,
			descentCfg,
			landingCfg,
			descentElapsed,
			session.rayParams,
			session.flightDirection,
			probe
		)
		if startLeapDown then
			self:_setPhase(session, PHASE.LeapDown)
			return
		end

		local vel: Vector3
		if walkableHit then
			local heightAbove = root.Position.Y - walkableHit.Position.Y
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

		applyVelocityOnly(root, blendHorizontalVelocity(session, vel, descentBlend, tuning))

		local maxDuration = landingCfg.MaxDuration or 2
		if descentElapsed >= maxDuration then
			self:_setPhase(session, PHASE.LeapDown)
		end
		return
	end

	if phase == PHASE.LeapDown then
		local cfg = phaseCfg.DownSupes
		local landingLock = cfg.LandingLockDuration or 0.2
		local minGroundedPlay = cfg.MinGroundedPlayDuration or 0.4
		local settleDuration = cfg.SettleDuration or 0.15
		local endGroundedAfter = math.max(minGroundedPlay, settleDuration)
		local maxDuration = cfg.MaxDuration or 2.5
		local approachSpeed = cfg.ApproachDescentSpeed or 12
		local descentBlend = getDescentHorizontalBlend(tuning)

		root.AssemblyAngularVelocity = Vector3.zero

		local landingCfg = phaseCfg.DownSupes
		local grounded = if probe
			then probe.isNearFloor or probe.onWalkableGround
			else DoubleJumpLanding.isGroundedForLanding(
				humanoid,
				root,
				session.rayParams,
				landingCfg,
				session.flightDirection
			)
		if not grounded then
			session.groundedAt = nil
			session.landingControlReleased = false
			restoreUprightPose(root, session.flightDirection)

			local fallSpeed = getCancelFallSpeed(tuning)
			local walkableHit = if probe and probe.walkableHit then probe.walkableHit else nil
			if not walkableHit then
				local hit = DoubleJumpLanding.raycastDownFromRoot(
					root,
					phaseCfg.LeapDown.SurfaceRayLength or 250,
					session.rayParams
				)
				walkableHit = if hit and DoubleJumpLanding.isWalkableHit(hit, landingCfg) then hit else nil
			end
			if walkableHit then
				local effectiveHeight = DoubleJumpLanding.getEffectiveHeightAbove(
					walkableHit,
					root,
					humanoid,
					landingCfg
				)
				local softHeight = (landingCfg.TriggerHeightAboveSurface or 6) + 2
				if effectiveHeight <= softHeight then
					fallSpeed = approachSpeed
				end
			end

			applyVelocityOnly(root, Vector3.new(0, -fallSpeed, 0))
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
			return
		end

		if phaseElapsed >= maxDuration then
			self:_endAbility(session.player)
			return
		end

		return
	end

	if phase == PHASE.CancelFall then
		local cancelCfg = tuning.Cancel
		local landingCfg = phaseCfg.DownSupes
		local cancelStarted = session.cancelFallStartedAt or now
		local fallElapsed = now - cancelStarted
		local fallSpeed = getCancelFallSpeed(tuning)

		humanoid.PlatformStand = false
		root.AssemblyAngularVelocity = Vector3.zero
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
					if hit and DoubleJumpLanding.isWalkableHit(hit, landingCfg) then hit else nil,
					session.rayParams,
					landingCfg,
					cancelCfg,
					fallElapsed,
					session.flightDirection
				)
			then
				session.landingSignaled = true
				self:_setPhase(session, PHASE.LeapDown)
				return
			end

			applyVelocityOnly(root, Vector3.new(0, -fallSpeed, 0))
		end

		if fallElapsed >= cancelCfg.MaxFallDuration then
			self:_setPhase(session, PHASE.LeapDown)
		end
		return
	end

	if phase == PHASE.CancelLanding then
		-- Legacy phase: use LeapDown landing physics (same as holding E through the jump).
		local landingCfg = phaseCfg.DownSupes
		local landingLock = landingCfg.LandingLockDuration or 0.2
		local minGroundedPlay = landingCfg.MinGroundedPlayDuration or 0.4
		local settleDuration = landingCfg.SettleDuration or 0.15
		local endGroundedAfter = math.max(minGroundedPlay, settleDuration)
		local fallSpeed = getCancelFallSpeed(tuning)

		root.AssemblyAngularVelocity = Vector3.zero
		humanoid.PlatformStand = false

		local grounded = DoubleJumpLanding.isGroundedForLanding(
			humanoid,
			root,
			session.rayParams,
			landingCfg,
			session.flightDirection
		)
		if not grounded then
			session.groundedAt = nil
			session.landingControlReleased = false
			restoreUprightPose(root, session.flightDirection)
			applyVelocityOnly(root, Vector3.new(0, -fallSpeed, 0))
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

	if not DataService or not DataService:CanStartFlight(player) then
		return false, "no_thrust"
	end

	local tuning = LevelDesignTuning.getDoubleJump(player)
	local poseCfg = tuning.SupermanPose

	cooldownEndsAt[player] = os.clock() + tuning.Cooldown

	if RunService:IsStudio() then
		print("[iseesupes] E ability using server tuning:", LevelDesignTuning.formatActiveTuning(player))
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local startCFrame = root.CFrame
	local fuelAtStart = 0
	if DataService then
		fuelAtStart = DataService:GetFuel(player)
	end

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
		lastFlatHeading = flatUnit(startCFrame.LookVector),
		currentPitch = poseCfg.TransitStartPitch,
		currentRoll = 0,
		groundedAt = nil,
		leapDownFirstGroundedAt = nil,
		leapDownTouchdown = false,
		descentStartedAt = nil,
		debugLoggedLeapDownTrigger = false,
		afterTransitionComplete = false,
		clientSteerDirection = nil,
		clientSteerAxis = 0,
		clientSteerPitchAxis = 0,
		landingControlReleased = false,
		tuning = tuning,
		tuningConns = {},
		hardLandedAt = nil,
		flightBodyGyro = nil,
		flightBodyVelocity = nil,
		platformStandWas = nil,
		thrustDepleted = false,
		thrustEmptyAt = nil,
		flightFuelAtStart = fuelAtStart,
	}

	humanoid.AutoRotate = false
	pcall(function()
		if clientOwnsFlightPhysics() then
			root:SetNetworkOwner(player)
		else
			root:SetNetworkOwner(nil)
		end
	end)
	sessions[player] = session
	bindTuningChangeListeners(session)
	if not clientOwnsFlightPhysics() then
		local moversOk, moversErr = pcall(function()
			createFlightMovers(session)
		end)
		if not moversOk then
			warn("[iseesupes] DoubleJump createFlightMovers failed:", moversErr)
		end
	end

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

function DoubleJumpService.Client:UpdateSteerState(
	player: Player,
	direction: Vector3?,
	axis: number,
	pitchAxis: number
)
	local session = sessions[player]
	if not session then
		return
	end

	session.clientSteerAxis = math.clamp(axis, -1, 1)
	session.clientSteerPitchAxis = math.clamp(pitchAxis, -1, 1)

	local tuning = session.tuning
	local threshold = getSteerThreshold(tuning)
	if not direction or direction.Magnitude < threshold then
		session.clientSteerDirection = nil
		return
	end

	local steer = unit3D(direction)
	if usesCameraPitchSteer(tuning) and phaseUsesCameraPitchSteer(session.phase) then
		steer = clampSteerPitch(steer, tuning.Steering.MaxPitchDegrees or 80)
	else
		steer = flatUnit(steer)
	end
	session.clientSteerDirection = steer
end

function DoubleJumpService.Client:UpdateSteerInput(player: Player, direction: Vector3)
	local session = sessions[player]
	if not session then
		return
	end
	DoubleJumpService.Client:UpdateSteerState(
		player,
		direction,
		session.clientSteerAxis or 0,
		session.clientSteerPitchAxis or 0
	)
end

function DoubleJumpService.Client:UpdateSteerAxis(player: Player, axis: number)
	local session = sessions[player]
	if not session then
		return
	end
	DoubleJumpService.Client:UpdateSteerState(
		player,
		session.clientSteerDirection,
		axis,
		session.clientSteerPitchAxis or 0
	)
end

function DoubleJumpService.Client:UpdateSteerPitchAxis(player: Player, axis: number)
	local session = sessions[player]
	if not session then
		return
	end
	DoubleJumpService.Client:UpdateSteerState(
		player,
		session.clientSteerDirection,
		session.clientSteerAxis or 0,
		axis
	)
end

function DoubleJumpService.Client:SetHolding(player: Player, isHolding: boolean)
	local session = sessions[player]
	if not session then
		return
	end

	session.holdingE = isHolding

	if not isHolding then
		session.clientSteerDirection = nil
		session.clientSteerAxis = 0
		session.clientSteerPitchAxis = 0
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
	DataService = Knit.GetService("DataService")

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

	local function onPlayerCharacterAdded(player: Player)
		DoubleJumpService:_endAbility(player)
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

	print("[iseesupes] DoubleJumpService ready.")
end

return DoubleJumpService

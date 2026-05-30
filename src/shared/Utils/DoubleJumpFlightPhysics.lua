--!strict

-- Shared E-flight movement/orientation math (client network owner applies physics locally).

local CharacterConfigs = require(script.Parent.Parent.Configs.CharacterConfigs)
local DoubleJumpLanding = require(script.Parent.DoubleJumpLanding)
local SpeedConfigs = require(script.Parent.Parent.Configs.SpeedConfigs)
local ThrustConfigs = SpeedConfigs.Thrust

type DjTuning = any

export type FlightState = {
	flightDirection: Vector3,
	lastFlatHeading: Vector3?,
	currentPitch: number,
	currentRoll: number,
	descentStartedAt: number?,
	clientSteerAxis: number,
	clientSteerPitchAxis: number,
	clientSteerDirection: Vector3?,
}

export type TickContext = {
	phase: string,
	phaseElapsed: number,
	phaseStartedAt: number,
	startPosition: Vector3,
	rayParams: RaycastParams,
	humanoid: Humanoid,
	steerDirection: Vector3?,
}

local PHASE = {
	FlightTransit = "FlightTransit",
	AfterTransition = "AfterTransition",
	LeanUp = "LeanUp",
	LeapDown = "LeapDown",
	DownSupes = "DownSupes",
	CancelFall = "CancelFall",
	CancelLanding = "CancelLanding",
}

local DoubleJumpFlightPhysics = {
	PHASE = PHASE,
}

local function flatUnit(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function DoubleJumpFlightPhysics.flatUnit(vector: Vector3): Vector3
	return flatUnit(vector)
end

local function unit3D(vector: Vector3): Vector3
	if vector.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return vector.Unit
end

function DoubleJumpFlightPhysics.unit3D(vector: Vector3): Vector3
	return unit3D(vector)
end

local function smoothstep01(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

function DoubleJumpFlightPhysics.smoothstep01(t: number): number
	return smoothstep01(t)
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

function DoubleJumpFlightPhysics.clampSteerPitch(dir: Vector3, maxPitchDeg: number): Vector3
	local u = unit3D(dir)
	local flat = Vector3.new(u.X, 0, u.Z)
	if flat.Magnitude < 0.01 then
		return u
	end
	flat = flat.Unit
	local maxY = math.sin(math.rad(math.max(5, maxPitchDeg)))
	local y = math.clamp(u.Y, -maxY, maxY)
	return unit3D(Vector3.new(flat.X, y, flat.Z))
end

function DoubleJumpFlightPhysics.normalizeFlightDirection(dir: Vector3, tuning: DjTuning, phase: string?): Vector3
	if usesCameraPitchSteer(tuning) and phase and phaseUsesCameraPitchSteer(phase) then
		return unit3D(dir)
	end
	return flatUnit(dir)
end

function DoubleJumpFlightPhysics.getOrientationHeading(state: FlightState): Vector3
	local flat = Vector3.new(state.flightDirection.X, 0, state.flightDirection.Z)
	if flat.Magnitude >= 0.01 then
		local heading = flat.Unit
		state.lastFlatHeading = heading
		return heading
	end
	if state.lastFlatHeading then
		return state.lastFlatHeading
	end
	return Vector3.new(0, 0, -1)
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

function DoubleJumpFlightPhysics.getCancelFallSpeed(tuning: DjTuning): number
	local cancel = tuning.Cancel
	if typeof(cancel.FallSpeed) == "number" and cancel.FallSpeed > 0 then
		return cancel.FallSpeed
	end
	return tuning.Phases.LeapDown.DescentSpeed or 70
end

function DoubleJumpFlightPhysics.getDescentHorizontalBlend(tuning: DjTuning): number
	local steerCfg = tuning.Steering
	if typeof(steerCfg.DescentHorizontalBlend) == "number" then
		return steerCfg.DescentHorizontalBlend
	end
	return tuning.Phases.LeapDown.HorizontalLerp or 0.35
end

local function getSteerDirection(state: FlightState, tuning: DjTuning, phase: string, steerDirection: Vector3?): Vector3
	local threshold = getSteerThreshold(tuning)
	local clientSteer = steerDirection or state.clientSteerDirection
	if clientSteer and clientSteer.Magnitude >= threshold then
		return DoubleJumpFlightPhysics.normalizeFlightDirection(clientSteer, tuning, phase)
	end
	return DoubleJumpFlightPhysics.normalizeFlightDirection(state.flightDirection, tuning, phase)
end

function DoubleJumpFlightPhysics.getFlightDirectionWithPitch(
	state: FlightState,
	tuning: DjTuning,
	phase: string,
	steerDirection: Vector3?
): Vector3
	local base = getSteerDirection(state, tuning, phase, steerDirection)
	if not phaseUsesCameraPitchSteer(phase) then
		return base
	end

	local axis = state.clientSteerPitchAxis or 0
	if math.abs(axis) < 0.05 then
		return base
	end

	local maxPitch = tuning.Steering.MaxPitchDegrees or 45
	return directionFromFlatAndPitchAxis(base, axis, maxPitch)
end

function DoubleJumpFlightPhysics.applySteerToFlightDirection(
	state: FlightState,
	dt: number,
	tuning: DjTuning,
	phase: string,
	steerDirection: Vector3?
)
	if not isSteeringEnabled(tuning) then
		return
	end

	local target = getSteerDirection(state, tuning, phase, steerDirection)
	local alpha = math.min(1, (tuning.Steering.DirectionLerp or 10) * dt)
	state.flightDirection =
		DoubleJumpFlightPhysics.normalizeFlightDirection(state.flightDirection:Lerp(target, alpha), tuning, phase)
end

local function rotateFlatY(flatDir: Vector3, radians: number): Vector3
	local c = math.cos(radians)
	local s = math.sin(radians)
	local x, z = flatDir.X, flatDir.Z
	return Vector3.new(x * c - z * s, 0, x * s + z * c)
end

function DoubleJumpFlightPhysics.usesKeyboardBankOnlySteer(tuning: DjTuning, phase: string): boolean
	if phase ~= PHASE.LeanUp then
		return false
	end
	local steerCfg = tuning.Steering
	local phases = steerCfg.KeyboardBankOnlyPhases
	if typeof(phases) == "table" and phases.LeanUp == true then
		return true
	end
	return steerCfg.UseSlowKeyboardYawOnLeanUp == true
end

function DoubleJumpFlightPhysics.isLateralKeyboardSteer(
	state: FlightState,
	steerDirection: Vector3?,
	tuning: DjTuning
): boolean
	local axis = math.clamp(state.clientSteerAxis or 0, -1, 1)
	if math.abs(axis) < 0.01 then
		return false
	end
	-- Forward / camera steer (W or mouse) keeps fast DirectionLerp; A/D alone uses slow axis yaw.
	local threshold = getSteerThreshold(tuning)
	if not steerDirection then
		return true
	end
	return steerDirection.Magnitude < threshold
end

function DoubleJumpFlightPhysics.applyKeyboardYawFromAxis(
	state: FlightState,
	dt: number,
	tuning: DjTuning,
	phase: string
)
	if not isSteeringEnabled(tuning) then
		return
	end

	local axis = math.clamp(state.clientSteerAxis or 0, -1, 1)
	if math.abs(axis) < 0.01 then
		return
	end

	local yawRate = tuning.Steering.KeyboardYawDegreesPerSecond or 115
	-- Negative: A (+axis) yaws left, D (-axis) yaws right (camera-relative).
	local radians = math.rad(-yawRate * axis * dt)
	local flat = Vector3.new(state.flightDirection.X, 0, state.flightDirection.Z)
	if flat.Magnitude < 0.01 then
		return
	end

	local rotated = rotateFlatY(flat.Unit, radians)
	state.flightDirection = DoubleJumpFlightPhysics.normalizeFlightDirection(
		Vector3.new(rotated.X, state.flightDirection.Y, rotated.Z),
		tuning,
		phase
	)
	state.lastFlatHeading = Vector3.new(rotated.X, 0, rotated.Z).Unit
end

function DoubleJumpFlightPhysics.applyKeyboardStrafeVelocity(
	state: FlightState,
	velocity: Vector3,
	tuning: DjTuning
): Vector3
	local axis = math.clamp(state.clientSteerAxis or 0, -1, 1)
	if math.abs(axis) < 0.01 then
		return velocity
	end

	local strafeSpeed = tuning.Steering.KeyboardStrafeSpeed or 58
	local camera = workspace.CurrentCamera
	if camera then
		local camRight = camera.CFrame.RightVector
		local flatRight = Vector3.new(camRight.X, 0, camRight.Z)
		if flatRight.Magnitude >= 0.01 then
			-- A (+axis) strafes camera-left; D (-axis) camera-right.
			return velocity - flatRight.Unit * axis * strafeSpeed
		end
	end

	local heading = DoubleJumpFlightPhysics.getOrientationHeading(state)
	local right = Vector3.new(-heading.Z, 0, heading.X)
	return velocity - right * axis * strafeSpeed
end

function DoubleJumpFlightPhysics.applyLeanUpHeadingSteer(
	state: FlightState,
	dt: number,
	tuning: DjTuning,
	phase: string,
	steerDirection: Vector3?
)
	local axis = math.clamp(state.clientSteerAxis or 0, -1, 1)
	local keyboardActive = DoubleJumpFlightPhysics.usesKeyboardBankOnlySteer(tuning, phase) and math.abs(axis) > 0.01

	if keyboardActive then
		-- A/D only: continuous yaw from hold time; do not lerp heading toward camera.
		DoubleJumpFlightPhysics.applyKeyboardYawFromAxis(state, dt, tuning, phase)
		return
	end

	local threshold = getSteerThreshold(tuning)
	if steerDirection and steerDirection.Magnitude >= threshold then
		DoubleJumpFlightPhysics.applySteerToFlightDirection(state, dt, tuning, phase, steerDirection)
	end
end

function DoubleJumpFlightPhysics.lerpRollToward(state: FlightState, targetRoll: number, dt: number, ratePerSec: number)
	local alpha = math.min(1, ratePerSec * dt)
	state.currentRoll = state.currentRoll + (targetRoll - state.currentRoll) * alpha
end

function DoubleJumpFlightPhysics.lerpPitch(
	state: FlightState,
	targetPitch: number,
	dt: number,
	tuning: DjTuning,
	rateOverride: number?
)
	local rate = rateOverride or tuning.SupermanPose.PitchLerp or 10
	local alpha = math.min(1, rate * dt)
	state.currentPitch = state.currentPitch + (targetPitch - state.currentPitch) * alpha
end

function DoubleJumpFlightPhysics.velocityAlongClimbAngle(flatDir: Vector3, climbDegrees: number, speed: number): Vector3
	local climbRad = math.rad(climbDegrees)
	local flat = flatUnit(flatDir)
	local dir = unit3D(flat * math.cos(climbRad) + Vector3.new(0, math.sin(climbRad), 0))
	return dir * speed
end

function DoubleJumpFlightPhysics.computeLaunchRiseVelocity(
	state: FlightState,
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
	return DoubleJumpFlightPhysics.velocityAlongClimbAngle(state.flightDirection, climbDeg, speed)
end

function DoubleJumpFlightPhysics.updateBankRoll(state: FlightState, dt: number, tuning: DjTuning, enabled: boolean)
	local poseCfg = tuning.SupermanPose
	if not enabled or poseCfg.BankEnabled == false then
		DoubleJumpFlightPhysics.lerpRollToward(state, 0, dt, poseCfg.BankReturnRate or 2)
		return
	end

	local steer = math.clamp(state.clientSteerAxis or 0, -1, 1)
	local maxBank = poseCfg.MaxBankDegrees or 55
	if math.abs(steer) > 0.01 then
		local target = steer * maxBank
		DoubleJumpFlightPhysics.lerpRollToward(state, target, dt, poseCfg.BankFollowRate or 6)
	else
		DoubleJumpFlightPhysics.lerpRollToward(state, 0, dt, poseCfg.BankReturnRate or 2)
	end
end

function DoubleJumpFlightPhysics.buildFlightOrientationCFrame(
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

function DoubleJumpFlightPhysics.applyFlightYawRollAndVelocity(
	root: BasePart,
	state: FlightState,
	heading: Vector3,
	rollDeg: number,
	velocity: Vector3?,
	pitchDeg: number?
)
	local pos = root.Position
	local targetCF = DoubleJumpFlightPhysics.buildFlightOrientationCFrame(pos, heading, rollDeg, pitchDeg)
	root.CFrame = targetCF
	root.AssemblyAngularVelocity = Vector3.zero
	if velocity then
		root.AssemblyLinearVelocity = velocity
	end
end

function DoubleJumpFlightPhysics.restoreUprightPose(root: BasePart, flightDir: Vector3)
	local flat = flatUnit(flightDir)
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + flat)
	root.AssemblyAngularVelocity = Vector3.zero
end

function DoubleJumpFlightPhysics.applyVelocityOnly(root: BasePart, velocity: Vector3)
	root.AssemblyLinearVelocity = velocity
end

function DoubleJumpFlightPhysics.blendHorizontalVelocity(
	state: FlightState,
	baseVel: Vector3,
	horizontalScale: number,
	tuning: DjTuning
): Vector3
	if horizontalScale <= 0 or not isSteeringEnabled(tuning) then
		return baseVel
	end

	local hSpeed = tuning.Steering.HorizontalSpeed or 45
	local flatDir = flatUnit(state.flightDirection)
	return baseVel + flatDir * hSpeed * horizontalScale
end

function DoubleJumpFlightPhysics.syncFlightDirectionFromRoot(state: FlightState, root: BasePart)
	state.flightDirection = flatUnit(root.CFrame.LookVector)
	local flat = Vector3.new(state.flightDirection.X, 0, state.flightDirection.Z)
	if flat.Magnitude >= 0.01 then
		state.lastFlatHeading = flat.Unit
	end
end

function DoubleJumpFlightPhysics.tickPhase(
	root: BasePart,
	state: FlightState,
	ctx: TickContext,
	dt: number,
	tuning: DjTuning,
	opts: {
		thrustDepleted: boolean?,
	}?
)
	local phase = ctx.phase
	local phaseElapsed = ctx.phaseElapsed
	local phaseCfg = tuning.Phases
	local poseCfg = tuning.SupermanPose
	local humanoid = ctx.humanoid
	local rayParams = ctx.rayParams
	local steerDirection = ctx.steerDirection

	if opts and opts.thrustDepleted then
		local fallSpeed = DoubleJumpFlightPhysics.getCancelFallSpeed(tuning)
		DoubleJumpFlightPhysics.restoreUprightPose(root, state.flightDirection)
		DoubleJumpFlightPhysics.applyVelocityOnly(root, Vector3.new(0, -fallSpeed, 0))
		return
	end

	if phase == PHASE.FlightTransit then
		local cfg = phaseCfg.FlightTransit
		DoubleJumpFlightPhysics.applySteerToFlightDirection(state, dt, tuning, phase, steerDirection)

		local progress = if cfg.Duration > 0 then math.clamp(phaseElapsed / cfg.Duration, 0, 1) else 1
		local startPitch = poseCfg.TransitStartPitch or 0
		local endPitch = poseCfg.TransitEndPitch or -35
		local targetPitch = startPitch + (endPitch - startPitch) * smoothstep01(progress)
		DoubleJumpFlightPhysics.lerpPitch(state, targetPitch, dt, tuning, poseCfg.TransitPitchLerp)

		local nudge = cfg.ForwardNudgeSpeed or 0
		local vel = Vector3.zero
		if nudge > 0 then
			vel = DoubleJumpFlightPhysics.velocityAlongClimbAngle(
				state.flightDirection,
				poseCfg.TransitLaunchClimbDegrees or 10,
				nudge
			)
		end
		DoubleJumpFlightPhysics.applyFlightYawRollAndVelocity(
			root,
			state,
			DoubleJumpFlightPhysics.getOrientationHeading(state),
			0,
			vel,
			state.currentPitch
		)
		return
	end

	if phase == PHASE.AfterTransition then
		local cfg = phaseCfg.AfterTransition
		DoubleJumpFlightPhysics.applySteerToFlightDirection(state, dt, tuning, phase, steerDirection)

		local riseT = smoothstep01(phaseElapsed / (cfg.MaxDuration or 1.1))
		local transitEndPitch = poseCfg.TransitEndPitch or -35
		local launchBodyPitch = poseCfg.LaunchBodyPitch or -72
		local targetPitch = transitEndPitch + (launchBodyPitch - transitEndPitch) * riseT
		DoubleJumpFlightPhysics.lerpPitch(state, targetPitch, dt, tuning, poseCfg.LaunchPitchLerp)

		local vel = DoubleJumpFlightPhysics.computeLaunchRiseVelocity(state, cfg, tuning, phaseElapsed)
		local pitchBlend = poseCfg.CameraPitchVelocityBlend or 0.35
		local pitchAxis = state.clientSteerPitchAxis or 0
		if pitchBlend > 0 and math.abs(pitchAxis) >= 0.05 then
			local aim = DoubleJumpFlightPhysics.getFlightDirectionWithPitch(state, tuning, phase, steerDirection)
			vel = unit3D(vel.Unit:Lerp(aim, pitchBlend)) * vel.Magnitude
		end
		DoubleJumpFlightPhysics.applyFlightYawRollAndVelocity(
			root,
			state,
			DoubleJumpFlightPhysics.getOrientationHeading(state),
			0,
			vel,
			state.currentPitch
		)
		return
	end

	if phase == PHASE.LeanUp then
		local cfg = phaseCfg.LeanUp
		local descentCfg = phaseCfg.LeapDown
		local landingCfg = phaseCfg.DownSupes
		local descentBlend = DoubleJumpFlightPhysics.getDescentHorizontalBlend(tuning)

		root.AssemblyAngularVelocity = Vector3.zero
		DoubleJumpFlightPhysics.applyLeanUpHeadingSteer(state, dt, tuning, phase, steerDirection)

		local maxPhaseTime = ThrustConfigs.LeanUpSafetyMaxDuration
		local inDescent = phaseElapsed >= maxPhaseTime

		if not inDescent then
			local flightDir = DoubleJumpFlightPhysics.getFlightDirectionWithPitch(state, tuning, phase, steerDirection)
			local vel = flightDir * cfg.ForwardSpeed
			vel = DoubleJumpFlightPhysics.applyKeyboardStrafeVelocity(state, vel, tuning)
			DoubleJumpFlightPhysics.updateBankRoll(state, dt, tuning, true)
			DoubleJumpFlightPhysics.applyFlightYawRollAndVelocity(
				root,
				state,
				DoubleJumpFlightPhysics.getOrientationHeading(state),
				state.currentRoll,
				vel
			)
			return
		end

		state.currentRoll = 0
		DoubleJumpFlightPhysics.restoreUprightPose(root, state.flightDirection)

		if not state.descentStartedAt then
			state.descentStartedAt = os.clock()
		end
		local descentElapsed = os.clock() - (state.descentStartedAt :: number)

		local walkableHit: RaycastResult? = nil
		local hit = DoubleJumpLanding.raycastDownFromRoot(root, descentCfg.SurfaceRayLength, rayParams)
		if hit and DoubleJumpLanding.isWalkableHit(hit, landingCfg) then
			walkableHit = hit
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

		DoubleJumpFlightPhysics.applyVelocityOnly(
			root,
			DoubleJumpFlightPhysics.blendHorizontalVelocity(state, vel, descentBlend, tuning)
		)
		return
	end

	if phase == PHASE.LeapDown then
		local landingCfg = phaseCfg.DownSupes
		local approachSpeed = landingCfg.ApproachDescentSpeed or 12
		local descentBlend = DoubleJumpFlightPhysics.getDescentHorizontalBlend(tuning)

		root.AssemblyAngularVelocity = Vector3.zero

		local grounded =
			DoubleJumpLanding.isGroundedForLanding(humanoid, root, rayParams, landingCfg, state.flightDirection)
		if not grounded then
			local fallSpeed = DoubleJumpFlightPhysics.getCancelFallSpeed(tuning)
			DoubleJumpFlightPhysics.restoreUprightPose(root, state.flightDirection)

			local walkableHit: RaycastResult? = nil
			local hit =
				DoubleJumpLanding.raycastDownFromRoot(root, phaseCfg.LeapDown.SurfaceRayLength or 250, rayParams)
			if hit and DoubleJumpLanding.isWalkableHit(hit, landingCfg) then
				walkableHit = hit
			end
			if walkableHit then
				local effectiveHeight =
					DoubleJumpLanding.getEffectiveHeightAbove(walkableHit, root, humanoid, landingCfg)
				local softHeight = (landingCfg.TriggerHeightAboveSurface or 6) + 2
				if effectiveHeight <= softHeight then
					fallSpeed = approachSpeed
				end
			end

			DoubleJumpFlightPhysics.applyVelocityOnly(root, Vector3.new(0, -fallSpeed, 0))
			return
		end

		DoubleJumpFlightPhysics.applyVelocityOnly(root, Vector3.zero)
		return
	end

	if phase == PHASE.CancelFall then
		local cancelCfg = tuning.Cancel
		local landingCfg = phaseCfg.DownSupes
		local fallSpeed = DoubleJumpFlightPhysics.getCancelFallSpeed(tuning)

		root.AssemblyAngularVelocity = Vector3.zero
		DoubleJumpFlightPhysics.restoreUprightPose(root, state.flightDirection)
		DoubleJumpFlightPhysics.applyVelocityOnly(root, Vector3.new(0, -fallSpeed, 0))
		return
	end

	if phase == PHASE.CancelLanding then
		local landingCfg = phaseCfg.DownSupes
		local fallSpeed = DoubleJumpFlightPhysics.getCancelFallSpeed(tuning)

		root.AssemblyAngularVelocity = Vector3.zero
		local grounded =
			DoubleJumpLanding.isGroundedForLanding(humanoid, root, rayParams, landingCfg, state.flightDirection)
		if not grounded then
			DoubleJumpFlightPhysics.restoreUprightPose(root, state.flightDirection)
			DoubleJumpFlightPhysics.applyVelocityOnly(root, Vector3.new(0, -fallSpeed, 0))
		else
			DoubleJumpFlightPhysics.applyVelocityOnly(root, Vector3.zero)
		end
	end
end

return DoubleJumpFlightPhysics

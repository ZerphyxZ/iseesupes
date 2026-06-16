--!strict

-- Shared landing helpers: walkable floor vs wall/obstacle contact.

local StageCheckpointWorld = require(script.Parent.StageCheckpointWorld)

local DoubleJumpLanding = {}

local DEFAULT_WALKABLE_NORMAL_MIN_Y = 0.6
local DEFAULT_GROUND_PROBE_DISTANCE = 8
local DEFAULT_CLEARANCE_TOLERANCE = 0.35
local DEFAULT_AIRBORNE_PROBE_DISTANCE = 64
local DEFAULT_OBSTACLE_PROBE_DISTANCE = 4
local DEFAULT_WALL_PROBE_DISTANCE = 5
local DEFAULT_LANDING_PROBE_INTERVAL = 0.12
local DEFAULT_OBSTACLE_PROBE_INTERVAL = 0.15

export type LandingProbe = {
	walkableHit: RaycastResult?,
	effectiveHeight: number?,
	isNearFloor: boolean,
	onWalkableGround: boolean,
	obstacleBlocked: boolean,
}

export type FlightProbeOptions = {
	--- Stage gate folder — excluded from wall/obstacle cardinal rays (glass is not a crash wall).
	ignoreWallProbeHitsIn: Instance?,
	--- Skip walkable hits (e.g. checkpoint Spawn pads while Superman gliding).
	ignoreWalkableInstance: ((Instance) -> boolean)?,
}

local function shouldIgnoreWalkableHit(hit: RaycastResult, options: FlightProbeOptions?): boolean
	if not options or not options.ignoreWalkableInstance then
		return false
	end
	return options.ignoreWalkableInstance(hit.Instance)
end

local function buildWallRayParams(baseParams: RaycastParams, options: FlightProbeOptions?): RaycastParams
	if not options or not options.ignoreWallProbeHitsIn then
		return baseParams
	end

	local excludes: { Instance } = {}
	for _, inst in baseParams.FilterDescendantsInstances do
		table.insert(excludes, inst)
	end
	table.insert(excludes, options.ignoreWallProbeHitsIn)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludes
	return params
end

local function isIgnorableFlightObstacleHit(hit: RaycastResult): boolean
	return StageCheckpointWorld.isCheckpointHit(hit.Instance)
end

function DoubleJumpLanding.isGrounded(humanoid: Humanoid): boolean
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

function DoubleJumpLanding.isWalkableHit(hit: RaycastResult, landingCfg: { [string]: any }): boolean
	local minY = landingCfg.WalkableNormalMinY
	if typeof(minY) ~= "number" then
		minY = DEFAULT_WALKABLE_NORMAL_MIN_Y
	end
	return hit.Normal.Y >= minY
end

function DoubleJumpLanding.raycastDown(
	origin: Vector3,
	length: number,
	params: RaycastParams
): RaycastResult?
	return workspace:Raycast(origin, Vector3.new(0, -length, 0), params)
end

function DoubleJumpLanding.raycastDownFromRoot(
	root: BasePart,
	length: number,
	params: RaycastParams
): RaycastResult?
	local origin = root.Position + Vector3.new(0, 2, 0)
	return DoubleJumpLanding.raycastDown(origin, length + 2, params)
end

function DoubleJumpLanding.getRootHeightOffset(humanoid: Humanoid, downSupesCfg: { [string]: any }): number
	local offset = downSupesCfg.RootHeightOffset
	if typeof(offset) == "number" then
		return offset
	end
	return humanoid.HipHeight
end

function DoubleJumpLanding.getMaxNearGroundClearance(humanoid: Humanoid, landingCfg: { [string]: any }): number
	local tolerance = landingCfg.GroundClearanceTolerance
	if typeof(tolerance) ~= "number" then
		tolerance = DEFAULT_CLEARANCE_TOLERANCE
	end
	return DoubleJumpLanding.getRootHeightOffset(humanoid, landingCfg) + tolerance
end

function DoubleJumpLanding.getFlightNearGroundHeight(landingCfg: { [string]: any }): number
	local height = landingCfg.FlightNearGroundHeight
	if typeof(height) == "number" and height > 0 then
		return height
	end
	return 1.25
end

function DoubleJumpLanding.getWalkableGroundHit(
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	probeDistance: number?,
	options: FlightProbeOptions?
): RaycastResult?
	local distance = probeDistance
	if typeof(distance) ~= "number" or distance <= 0 then
		distance = landingCfg.GroundProbeDistance
	end
	if typeof(distance) ~= "number" or distance <= 0 then
		distance = DEFAULT_GROUND_PROBE_DISTANCE
	end

	local hit = DoubleJumpLanding.raycastDownFromRoot(root, distance, rayParams)
	if hit and DoubleJumpLanding.isWalkableHit(hit, landingCfg) then
		if shouldIgnoreWalkableHit(hit, options) then
			return nil
		end
		return hit
	end
	return nil
end

function DoubleJumpLanding.isOnWalkableGround(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	options: FlightProbeOptions?
): boolean
	local hit = DoubleJumpLanding.getWalkableGroundHit(root, rayParams, landingCfg, nil, options)
	if not hit then
		return false
	end

	local clearance = root.Position.Y - hit.Position.Y
	return clearance <= DoubleJumpLanding.getMaxNearGroundClearance(humanoid, landingCfg)
end

local function getWallProbeDistance(landingCfg: { [string]: any }): number
	local distance = landingCfg.WallProbeDistance
	if typeof(distance) ~= "number" or distance <= 0 then
		distance = DEFAULT_WALL_PROBE_DISTANCE
	end
	return distance
end

local function rayHitsNonWalkableObstacle(
	origin: Vector3,
	direction: Vector3,
	distance: number,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	options: FlightProbeOptions?
): boolean
	if direction.Magnitude < 0.01 then
		return false
	end
	local params = buildWallRayParams(rayParams, options)
	local hit = workspace:Raycast(origin, direction.Unit * distance, params)
	return hit ~= nil and not DoubleJumpLanding.isWalkableHit(hit, landingCfg)
end

-- Walls/ceilings nearby (works with PlatformStand when FloorMaterial stays Air).
function DoubleJumpLanding.isBlockedByNearbyObstacle(
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	moveDir: Vector3?,
	options: FlightProbeOptions?
): boolean
	local distance = getWallProbeDistance(landingCfg)
	local origin = root.Position + Vector3.new(0, 1, 0)

	local cardinals = {
		root.CFrame.RightVector,
		-root.CFrame.RightVector,
		root.CFrame.LookVector,
		-root.CFrame.LookVector,
	}
	for _, dir in cardinals do
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if rayHitsNonWalkableObstacle(origin, flat, distance, rayParams, landingCfg, options) then
			return true
		end
	end

	local forward = moveDir
	if forward and forward.Magnitude > 0.01 then
		local flatMove = Vector3.new(forward.X, 0, forward.Z)
		if rayHitsNonWalkableObstacle(origin, flatMove, distance + 1, rayParams, landingCfg, options) then
			return true
		end
	end

	local vel = root.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	if flatVel.Magnitude > 8 then
		if rayHitsNonWalkableObstacle(origin, flatVel, distance + 1, rayParams, landingCfg, options) then
			return true
		end
	end

	return false
end

function DoubleJumpLanding.getLandingProbeInterval(landingCfg: { [string]: any }): number
	local interval = landingCfg.LandingProbeInterval
	if typeof(interval) == "number" and interval > 0 then
		return interval
	end
	return DEFAULT_LANDING_PROBE_INTERVAL
end

function DoubleJumpLanding.getObstacleProbeInterval(landingCfg: { [string]: any }): number
	local interval = landingCfg.ObstacleProbeInterval
	if typeof(interval) == "number" and interval > 0 then
		return interval
	end
	return DEFAULT_OBSTACLE_PROBE_INTERVAL
end

-- Short down-ray for glide: enough for E_LandHt without full AirborneProbeDistance every frame.
function DoubleJumpLanding.getGlideProbeDistance(humanoid: Humanoid, landingCfg: { [string]: any }): number
	local flightNear = DoubleJumpLanding.getFlightNearGroundHeight(landingCfg)
	local hip = DoubleJumpLanding.getRootHeightOffset(humanoid, landingCfg)
	local tolerance = landingCfg.GroundClearanceTolerance
	if typeof(tolerance) ~= "number" then
		tolerance = DEFAULT_CLEARANCE_TOLERANCE
	end
	local shortProbe = flightNear + hip + tolerance + 2

	local airProbe = landingCfg.AirborneProbeDistance
	if typeof(airProbe) ~= "number" or airProbe <= 0 then
		airProbe = DEFAULT_AIRBORNE_PROBE_DISTANCE
	end
	return math.min(airProbe, shortProbe)
end

local function computeObstacleBlocked(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	moveDir: Vector3?,
	probe: LandingProbe,
	options: FlightProbeOptions?
): boolean
	if DoubleJumpLanding.isBlockedByNearbyObstacle(root, rayParams, landingCfg, moveDir, options) then
		return true
	end

	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	if probe.onWalkableGround or probe.isNearFloor then
		return false
	end

	local obstacleProbe = landingCfg.ObstacleProbeDistance
	if typeof(obstacleProbe) ~= "number" or obstacleProbe <= 0 then
		obstacleProbe = DEFAULT_OBSTACLE_PROBE_DISTANCE
	end
	local nearHit = DoubleJumpLanding.raycastDownFromRoot(root, obstacleProbe, rayParams)
	if nearHit and not DoubleJumpLanding.isWalkableHit(nearHit, landingCfg) then
		if not isIgnorableFlightObstacleHit(nearHit) then
			local clearance = root.Position.Y - nearHit.Position.Y
			if clearance <= DoubleJumpLanding.getMaxNearGroundClearance(humanoid, landingCfg) then
				return true
			end
		end
	end

	return false
end

local function buildLandingProbeGround(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	probeDistance: number?,
	options: FlightProbeOptions?
): LandingProbe
	local distance = probeDistance
	if typeof(distance) ~= "number" or distance <= 0 then
		distance = DoubleJumpLanding.getGlideProbeDistance(humanoid, landingCfg)
	end

	local walkableHit = DoubleJumpLanding.getWalkableGroundHit(root, rayParams, landingCfg, distance, options)
	local flightNearGround = DoubleJumpLanding.getFlightNearGroundHeight(landingCfg)
	local onWalkableGround = false
	local isNearFloor = false
	local effectiveHeight: number? = nil

	if walkableHit then
		effectiveHeight = DoubleJumpLanding.getEffectiveHeightAbove(walkableHit, root, humanoid, landingCfg)
		local clearance = root.Position.Y - walkableHit.Position.Y
		onWalkableGround = clearance <= DoubleJumpLanding.getMaxNearGroundClearance(humanoid, landingCfg)
		isNearFloor = onWalkableGround or (effectiveHeight :: number) <= flightNearGround
	end

	return {
		walkableHit = walkableHit,
		effectiveHeight = effectiveHeight,
		isNearFloor = isNearFloor,
		onWalkableGround = onWalkableGround,
		obstacleBlocked = false,
	}
end

function DoubleJumpLanding.buildLandingProbe(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	moveDir: Vector3?,
	probeDistance: number?,
	options: FlightProbeOptions?
): LandingProbe
	local probe = buildLandingProbeGround(humanoid, root, rayParams, landingCfg, probeDistance, options)
	probe.obstacleBlocked = computeObstacleBlocked(humanoid, root, rayParams, landingCfg, moveDir, probe, options)
	return probe
end

function DoubleJumpLanding.refreshLandingProbe(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	moveDir: Vector3?,
	now: number,
	cacheAt: number?,
	cachedProbe: LandingProbe?,
	obstacleAt: number?,
	obstacleBlocked: boolean?,
	probeDistance: number?,
	options: FlightProbeOptions?
): (LandingProbe, number, number, boolean)
	local groundInterval = DoubleJumpLanding.getLandingProbeInterval(landingCfg)
	local obstacleInterval = DoubleJumpLanding.getObstacleProbeInterval(landingCfg)

	local refreshGround = not cachedProbe or not cacheAt or (now - cacheAt) >= groundInterval
	local refreshObstacle = not obstacleAt or (now - obstacleAt) >= obstacleInterval

	local function withObstacle(groundProbe: LandingProbe, blocked: boolean): LandingProbe
		return {
			walkableHit = groundProbe.walkableHit,
			effectiveHeight = groundProbe.effectiveHeight,
			isNearFloor = groundProbe.isNearFloor,
			onWalkableGround = groundProbe.onWalkableGround,
			obstacleBlocked = blocked,
		}
	end

	if not refreshGround and cachedProbe then
		if refreshObstacle then
			local blocked = computeObstacleBlocked(humanoid, root, rayParams, landingCfg, moveDir, cachedProbe, options)
			return withObstacle(cachedProbe, blocked), cacheAt :: number, now, blocked
		end
		return cachedProbe, cacheAt :: number, obstacleAt :: number, obstacleBlocked or cachedProbe.obstacleBlocked
	end

	local groundProbe = buildLandingProbeGround(humanoid, root, rayParams, landingCfg, probeDistance, options)
	if refreshObstacle then
		local blocked = computeObstacleBlocked(humanoid, root, rayParams, landingCfg, moveDir, groundProbe, options)
		return withObstacle(groundProbe, blocked), now, now, blocked
	end

	local blocked = if typeof(obstacleBlocked) == "boolean" then obstacleBlocked else false
	return withObstacle(groundProbe, blocked), now, obstacleAt or now, blocked
end

function DoubleJumpLanding.shouldApproachLandFromGlide(probe: LandingProbe): boolean
	return probe.isNearFloor and not probe.obstacleBlocked
end

function DoubleJumpLanding.isNearWalkableSurface(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	moveDir: Vector3?,
	options: FlightProbeOptions?
): boolean
	if DoubleJumpLanding.isBlockedByNearbyObstacle(root, rayParams, landingCfg, moveDir, options) then
		return false
	end

	if DoubleJumpLanding.isOnWalkableGround(humanoid, root, rayParams, landingCfg, options) then
		return true
	end

	local probe = landingCfg.AirborneProbeDistance
	if typeof(probe) ~= "number" or probe <= 0 then
		probe = DEFAULT_AIRBORNE_PROBE_DISTANCE
	end

	local hit = DoubleJumpLanding.getWalkableGroundHit(root, rayParams, landingCfg, probe, options)
	if not hit then
		return false
	end

	local effectiveHeight = DoubleJumpLanding.getEffectiveHeightAbove(hit, root, humanoid, landingCfg)
	return effectiveHeight <= DoubleJumpLanding.getFlightNearGroundHeight(landingCfg)
end

function DoubleJumpLanding.hasObstacleContact(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	moveDir: Vector3?,
	options: FlightProbeOptions?
): boolean
	if DoubleJumpLanding.isBlockedByNearbyObstacle(root, rayParams, landingCfg, moveDir, options) then
		return true
	end

	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	if DoubleJumpLanding.isOnWalkableGround(humanoid, root, rayParams, landingCfg, options) then
		return false
	end

	local airProbe = landingCfg.AirborneProbeDistance
	if typeof(airProbe) ~= "number" or airProbe <= 0 then
		airProbe = DEFAULT_AIRBORNE_PROBE_DISTANCE
	end
	local farHit = DoubleJumpLanding.getWalkableGroundHit(root, rayParams, landingCfg, airProbe, options)
	if farHit then
		local clearance = root.Position.Y - farHit.Position.Y
		if clearance > DoubleJumpLanding.getMaxNearGroundClearance(humanoid, landingCfg) then
			return false
		end
	end

	local obstacleProbe = landingCfg.ObstacleProbeDistance
	if typeof(obstacleProbe) ~= "number" or obstacleProbe <= 0 then
		obstacleProbe = DEFAULT_OBSTACLE_PROBE_DISTANCE
	end
	local nearHit = DoubleJumpLanding.raycastDownFromRoot(root, obstacleProbe, rayParams)
	if nearHit and not DoubleJumpLanding.isWalkableHit(nearHit, landingCfg) then
		if not isIgnorableFlightObstacleHit(nearHit) then
			local clearance = root.Position.Y - nearHit.Position.Y
			if clearance <= DoubleJumpLanding.getMaxNearGroundClearance(humanoid, landingCfg) then
				return true
			end
		end
	end

	return false
end

function DoubleJumpLanding.isGroundedForLanding(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	moveDir: Vector3?,
	options: FlightProbeOptions?
): boolean
	return DoubleJumpLanding.isNearWalkableSurface(humanoid, root, rayParams, landingCfg, moveDir, options)
end

function DoubleJumpLanding.getEffectiveHeightAbove(
	hit: RaycastResult,
	root: BasePart,
	humanoid: Humanoid,
	downSupesCfg: { [string]: any }
): number
	local heightAbove = root.Position.Y - hit.Position.Y
	return heightAbove - DoubleJumpLanding.getRootHeightOffset(humanoid, downSupesCfg)
end

function DoubleJumpLanding.shouldStartLeapDown(
	humanoid: Humanoid,
	root: BasePart,
	hit: RaycastResult?,
	descentCfg: { [string]: any },
	landingCfg: { [string]: any },
	phaseElapsed: number,
	rayParams: RaycastParams?,
	moveDir: Vector3?,
	probe: LandingProbe?
): boolean
	local minDescent = descentCfg.MinDuration or 0.15
	if phaseElapsed < minDescent then
		return false
	end

	if probe then
		if probe.obstacleBlocked then
			return false
		end
		if probe.isNearFloor then
			return true
		end
		hit = probe.walkableHit
	end

	if rayParams and moveDir and DoubleJumpLanding.isBlockedByNearbyObstacle(root, rayParams, landingCfg, moveDir, nil) then
		return false
	end

	if not probe and rayParams and DoubleJumpLanding.isNearWalkableSurface(humanoid, root, rayParams, landingCfg, moveDir, nil) then
		return true
	end

	if not hit or not DoubleJumpLanding.isWalkableHit(hit, landingCfg) then
		return false
	end

	local effectiveHeight = if probe and probe.effectiveHeight
		then probe.effectiveHeight
		else DoubleJumpLanding.getEffectiveHeightAbove(hit, root, humanoid, landingCfg)
	local triggerHeight = landingCfg.TriggerHeightAboveSurface or 6
	return (effectiveHeight :: number) <= triggerHeight
end

function DoubleJumpLanding.shouldStartCancelLanding(
	humanoid: Humanoid,
	root: BasePart,
	hit: RaycastResult?,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	cancelCfg: { [string]: any },
	phaseElapsed: number,
	moveDir: Vector3?
): boolean
	local minFall = cancelCfg.MinFallTime or 0.08
	if phaseElapsed < minFall then
		return false
	end

	if DoubleJumpLanding.isNearWalkableSurface(humanoid, root, rayParams, landingCfg, moveDir, nil) then
		return true
	end

	if hit and DoubleJumpLanding.isWalkableHit(hit, landingCfg) then
		local effectiveHeight = DoubleJumpLanding.getEffectiveHeightAbove(hit, root, humanoid, landingCfg)
		local triggerHeight = cancelCfg.LandingTriggerHeight or landingCfg.TriggerHeightAboveSurface or 8
		return effectiveHeight <= triggerHeight
	end

	return false
end

return DoubleJumpLanding

--!strict

-- Shared landing helpers: DownSupes on descent; LeapDown starts a few studs above ground.

local DoubleJumpLanding = {}

function DoubleJumpLanding.isGrounded(humanoid: Humanoid): boolean
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

function DoubleJumpLanding.isGroundedForLanding(
	humanoid: Humanoid,
	root: BasePart,
	rayParams: RaycastParams,
	landingCfg: { [string]: any }
): boolean
	if DoubleJumpLanding.isGrounded(humanoid) then
		return true
	end

	local hit = DoubleJumpLanding.raycastDownFromRoot(root, 8, rayParams)
	if not hit then
		return false
	end

	local clearance = root.Position.Y - hit.Position.Y
	local maxClearance = DoubleJumpLanding.getRootHeightOffset(humanoid, landingCfg) + 1.25
	return clearance <= maxClearance
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

function DoubleJumpLanding.getEffectiveHeightAbove(
	hit: RaycastResult,
	root: BasePart,
	humanoid: Humanoid,
	downSupesCfg: { [string]: any }
): number
	local heightAbove = root.Position.Y - hit.Position.Y
	return heightAbove - DoubleJumpLanding.getRootHeightOffset(humanoid, downSupesCfg)
end

-- Start LeapDown a few studs above ground (before feet touch) so the landing anim plays upright.
function DoubleJumpLanding.shouldStartLeapDown(
	humanoid: Humanoid,
	root: BasePart,
	hit: RaycastResult?,
	descentCfg: { [string]: any },
	landingCfg: { [string]: any },
	phaseElapsed: number
): boolean
	local minDescent = descentCfg.MinDuration or 0.15
	if phaseElapsed < minDescent then
		return false
	end

	if DoubleJumpLanding.isGrounded(humanoid) then
		return true
	end

	if not hit then
		return false
	end

	local effectiveHeight = DoubleJumpLanding.getEffectiveHeightAbove(hit, root, humanoid, landingCfg)
	local triggerHeight = landingCfg.TriggerHeightAboveSurface or 6
	return effectiveHeight <= triggerHeight
end

-- Cancel (release E): switch from Fall to LeapDown/Landing when close to or on ground.
function DoubleJumpLanding.shouldStartCancelLanding(
	humanoid: Humanoid,
	root: BasePart,
	hit: RaycastResult?,
	rayParams: RaycastParams,
	landingCfg: { [string]: any },
	cancelCfg: { [string]: any },
	phaseElapsed: number
): boolean
	local minFall = cancelCfg.MinFallTime or 0.08
	if phaseElapsed < minFall then
		return false
	end

	if DoubleJumpLanding.isGrounded(humanoid) then
		return true
	end

	if DoubleJumpLanding.isGroundedForLanding(humanoid, root, rayParams, landingCfg) then
		return true
	end

	if not hit then
		return false
	end

	local effectiveHeight = DoubleJumpLanding.getEffectiveHeightAbove(hit, root, humanoid, landingCfg)
	local triggerHeight = cancelCfg.LandingTriggerHeight or landingCfg.TriggerHeightAboveSurface or 8
	return effectiveHeight <= triggerHeight
end

return DoubleJumpLanding

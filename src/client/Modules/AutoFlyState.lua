--!strict

-- Shared auto-fly steer override (read by DoubleJumpController, set by AutoFlyController).

local AutoFlyState = {}

local steerOverride: Vector3? = nil

function AutoFlyState.setSteerOverride(direction: Vector3?)
	if direction and direction.Magnitude > 0.001 then
		steerOverride = direction.Unit
	else
		steerOverride = nil
	end
end

function AutoFlyState.getSteerOverride(): Vector3?
	return steerOverride
end

function AutoFlyState.isSteeringLocked(): boolean
	return steerOverride ~= nil
end

function AutoFlyState.clear()
	steerOverride = nil
end

return AutoFlyState

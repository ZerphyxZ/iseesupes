--!strict

-- Helpers for when Roblox engine locomotion (climb, swim) should take over from custom anims/jumps.

local HumanoidLocomotion = {}

function HumanoidLocomotion.getState(humanoid: Humanoid): Enum.HumanoidStateType?
	local ok, state = pcall(function()
		return humanoid:GetState()
	end)
	if ok then
		return state
	end
	return nil
end

function HumanoidLocomotion.usesEngineLocomotion(humanoid: Humanoid): boolean
	local state = HumanoidLocomotion.getState(humanoid)
	if state == Enum.HumanoidStateType.Climbing then
		return true
	end
	if state == Enum.HumanoidStateType.Swimming then
		return true
	end
	return false
end

function HumanoidLocomotion.ensureClimbControl(humanoid: Humanoid)
	if HumanoidLocomotion.getState(humanoid) ~= Enum.HumanoidStateType.Climbing then
		return
	end
	if humanoid.PlatformStand then
		humanoid.PlatformStand = false
	end
	if not humanoid.AutoRotate then
		humanoid.AutoRotate = true
	end
end

return HumanoidLocomotion

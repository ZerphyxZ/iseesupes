--!strict

-- Speed progression (XP), level thresholds, swim/walk display speed, rebirth boost.

local SpeedConfigs = {
	StudsRequired = 8,
	BaseXpCost = 10,
	CostMultiplier = 1.5,
	BaseWalkSpeed = 8,
	SpeedPerLevel = 2,
	RebirthPercentPerStep = 50,
	SpeedGainPerStudBatch = 1,
	AddSpeedMinInterval = 0.05,
	SwimSpeedAttribute = "SwimSpeed",
}

function SpeedConfigs.GetExperienceForLevel(level: number): number
	if level <= 1 then
		return 0
	end
	local total = 0
	for i = 1, level - 1 do
		total += math.floor(SpeedConfigs.BaseXpCost * (SpeedConfigs.CostMultiplier ^ (i - 1)))
	end
	return total
end

function SpeedConfigs.GetXpNeededForLevel(level: number): number
	return SpeedConfigs.GetExperienceForLevel(level + 1) - SpeedConfigs.GetExperienceForLevel(level)
end

function SpeedConfigs.GetLevelFromSpeed(speed: number): number
	local level = 1
	while speed >= SpeedConfigs.GetExperienceForLevel(level + 1) do
		level += 1
	end
	return level
end

function SpeedConfigs.GetSpeedFromLevel(level: number): number
	local lvl = math.max(1, math.floor(level))
	return SpeedConfigs.BaseWalkSpeed + (lvl - 1) * SpeedConfigs.SpeedPerLevel
end

-- Alias used by HUD swim cap
function SpeedConfigs.GetMaxSpeed(level: number): number
	return SpeedConfigs.GetSpeedFromLevel(level)
end

function SpeedConfigs.GetRebirthBoostPercent(rebirths: number): number
	return rebirths * SpeedConfigs.RebirthPercentPerStep
end

function SpeedConfigs.GetRebirthGainMultiplier(rebirths: number): number
	return 1 + (rebirths * SpeedConfigs.RebirthPercentPerStep) / 100
end

function SpeedConfigs.SyncLevelFromSpeed(data: any): (number, number)
	local speed = 0
	if type(data.Speed) == "number" then
		speed = data.Speed
	end
	local oldLevel = 1
	if type(data.Level) == "number" then
		oldLevel = data.Level
	end
	local newLevel = SpeedConfigs.GetLevelFromSpeed(speed)
	data.Level = newLevel
	return oldLevel, newLevel
end

return SpeedConfigs

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

-- Thrust flight fuel (lives here so one synced module is enough; ThrustConfigs.lua re-exports this).
local Thrust = {
	BaseMaxFuel = 75,
	DrainPerSecond = 10,
	TreadmillRefillPerTick = 3,
	MinFuelToStartFlight = 5,
	EmptyDescentGrace = 0.6,
	SpeedPointsToMaxFuelBonus = 1,
	MaxFuelBonusFromProducts = 0,
	ReplicateMinInterval = 0.25,
	LeanUpSafetyMaxDuration = 45,
}

function Thrust.GetAbilityTimeCap(fuelAtStart: number, tuningMax: number): number
	local drain = Thrust.DrainPerSecond
	if drain <= 0 then
		return tuningMax
	end
	local fuelSeconds = fuelAtStart / drain
	return math.max(tuningMax, fuelSeconds + 5)
end

function Thrust.EnsureFuelDefaults(data: any)
	if typeof(data.ThrustMax) ~= "number" or data.ThrustMax <= 0 then
		data.ThrustMax = Thrust.BaseMaxFuel
	end
	if typeof(data.ThrustCurrent) ~= "number" then
		data.ThrustCurrent = data.ThrustMax
	end
	data.ThrustCurrent = math.clamp(data.ThrustCurrent, 0, data.ThrustMax)
end

function Thrust.MigrateProfile(data: any)
	Thrust.EnsureFuelDefaults(data)

	local legacyPoints = data.SpeedPoints
	if typeof(legacyPoints) == "number" and legacyPoints > 0 then
		data.ThrustMax += math.floor(legacyPoints * Thrust.SpeedPointsToMaxFuelBonus)
		data.SpeedPoints = 0
		data.ThrustCurrent = math.min(data.ThrustCurrent, data.ThrustMax)
	end
end

function Thrust.RefillToMax(data: any)
	Thrust.EnsureFuelDefaults(data)
	data.ThrustCurrent = data.ThrustMax
end

SpeedConfigs.Thrust = Thrust

return SpeedConfigs

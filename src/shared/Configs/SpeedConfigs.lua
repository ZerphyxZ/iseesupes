--!strict

-- Speed progression (XP), level thresholds, swim/walk display speed, rebirth boost.

local SpeedConfigs = {
	StudsRequired = 8,
	BaseXpCost = 300,
	CostMultiplier = 1.3,
	BaseWalkSpeed = 8,
	SpeedPerLevel = 3,
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
-- BaseMaxFuel = 60 → ~374 studs per charge (new players reach Stage 2, not Stage 3 in one shot).
-- PassiveRefillRate = 6 → 10s from empty to full; prevents chain-flying across stages.
-- MinFuelToStartFlight = 15 → must wait ~2.5s on ground before flying again.
local Thrust = {
	BaseMaxFuel = 60,
	DrainPerSecond = 10,
	TreadmillRefillPerTick = 0,
	PassiveRefillRate = 6,
	MinFuelToStartFlight = 15,
	EmptyDescentGrace = 0.6,
	SpeedPointsToMaxFuelBonus = 1,
	MaxFuelBonusFromProducts = 0,
	ReplicateMinInterval = 0.25,
	LeanUpSafetyMaxDuration = 45,
	-- Player attribute (Properties panel) to set max thrust fuel directly. 0 = use BaseMaxFuel.
	PowerAttribute = "ThrustPower",
	DefaultPower = 0,
	--- DjAbilityPhase values that block passive refill (in-air thrust use only).
	PassiveRefillBlockPhases = {
		FlightTransit = true,
		AfterTransition = true,
		LeanUp = true,
	},
}

function Thrust.BlocksPassiveRefill(djPhase: any): boolean
	if djPhase == nil or djPhase == "" then
		return false
	end
	if typeof(djPhase) ~= "string" then
		return true
	end
	return Thrust.PassiveRefillBlockPhases[djPhase] == true
end

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

-- Apply the ThrustPower attribute value as the player's max fuel.
-- power > 0 sets ThrustMax to that value; power <= 0 (or nil) resets to BaseMaxFuel.
-- refill = true tops current fuel up to the new max (used on set / respawn).
function Thrust.ApplyPower(data: any, power: number?, refill: boolean?): boolean
	Thrust.EnsureFuelDefaults(data)

	local targetMax: number
	if typeof(power) == "number" and power > 0 then
		targetMax = power
	else
		targetMax = Thrust.BaseMaxFuel
	end

	local changed = data.ThrustMax ~= targetMax
	data.ThrustMax = targetMax
	if refill then
		data.ThrustCurrent = targetMax
	else
		data.ThrustCurrent = math.clamp(data.ThrustCurrent, 0, targetMax)
	end
	return changed
end

SpeedConfigs.Thrust = Thrust

return SpeedConfigs

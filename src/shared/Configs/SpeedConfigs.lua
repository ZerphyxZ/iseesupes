--!strict

-- Speed progression (XP), level thresholds, swim/walk display speed, rebirth boost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

local FLIGHT_SCALE_FULL_AT_LEVEL = 4
local WALK_AT_FLIGHT_REF = 8 + (FLIGHT_SCALE_FULL_AT_LEVEL - 1) * 3
local LEGACY_AFTER_FORWARD = CharacterConfigs.DoubleJump.Phases.AfterTransition.ForwardSpeed

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
	--- Icon on the +Speed burst when walking / gaining speed (EffectsSystem).
	SpeedGainPopupImage = "rbxassetid://79786696302749",
	--- Icon on the +Thrust burst when thrust refills (EffectsSystem).
	ThrustGainPopupImage = "rbxassetid://109635513870423",
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

-- E-ability horizontal flight scales with Speed level (walk-linked); thrust fuel unchanged.
SpeedConfigs.Flight = {
	MinWalkMultiplier = 1.15,
	MaxWalkMultiplier = (LEGACY_AFTER_FORWARD / WALK_AT_FLIGHT_REF) * 1.12,
	ScaleFullAtLevel = FLIGHT_SCALE_FULL_AT_LEVEL,
	ReferenceAfterForward = LEGACY_AFTER_FORWARD,
	--- Extra horizontal flight feel (1 = plan baseline). Tune here after playtest.
	SpeedBoost = 1.08,
}

function SpeedConfigs.GetFlightWalkMultiplier(level: number): number
	local cfg = SpeedConfigs.Flight
	local lvl = math.max(1, math.floor(level))
	local t = 1
	if cfg.ScaleFullAtLevel > 1 then
		t = math.clamp((lvl - 1) / (cfg.ScaleFullAtLevel - 1), 0, 1)
	end
	return cfg.MinWalkMultiplier + (cfg.MaxWalkMultiplier - cfg.MinWalkMultiplier) * t
end

function SpeedConfigs.GetFlightForwardSpeed(level: number): number
	local cfg = SpeedConfigs.Flight
	local boost = if typeof(cfg.SpeedBoost) == "number" and cfg.SpeedBoost > 0 then cfg.SpeedBoost else 1
	return SpeedConfigs.GetSpeedFromLevel(level) * SpeedConfigs.GetFlightWalkMultiplier(level) * boost
end

function SpeedConfigs.GetPlayerLevel(player: Player): number
	local folder = player:FindFirstChild("leaderstats")
	if folder and folder:IsA("Folder") then
		local levelValue = folder:FindFirstChild("Level")
		if levelValue and levelValue:IsA("IntValue") then
			return math.max(1, levelValue.Value)
		end
	end
	return 1
end

function SpeedConfigs.ApplyFlightScalingToDoubleJump(tuning: any, level: number): any
	local phases = tuning.Phases
	if not phases or not phases.AfterTransition then
		return tuning
	end

	local resolvedForward = phases.AfterTransition.ForwardSpeed
	if typeof(resolvedForward) ~= "number" or resolvedForward <= 0.01 then
		return tuning
	end

	local targetForward = SpeedConfigs.GetFlightForwardSpeed(level)
	local scale = targetForward / resolvedForward

	phases.AfterTransition.ForwardSpeed = resolvedForward * scale
	phases.LeanUp.ForwardSpeed = (phases.LeanUp.ForwardSpeed or resolvedForward) * scale

	local transit = phases.FlightTransit
	if transit and typeof(transit.ForwardNudgeSpeed) == "number" then
		transit.ForwardNudgeSpeed = transit.ForwardNudgeSpeed * scale
	end

	local steering = tuning.Steering
	if steering then
		if typeof(steering.HorizontalSpeed) == "number" then
			steering.HorizontalSpeed = steering.HorizontalSpeed * scale
		end
		local strafe = steering.KeyboardStrafeSpeed
		if typeof(strafe) ~= "number" then
			strafe = CharacterConfigs.DoubleJump.Steering.KeyboardStrafeSpeed or 58
		end
		steering.KeyboardStrafeSpeed = strafe * scale
		-- Match yaw / camera-follow rates to forward speed so turn radius stays controllable.
		if typeof(steering.DirectionLerp) == "number" then
			steering.DirectionLerp = steering.DirectionLerp * scale
		end
		if typeof(steering.KeyboardYawDegreesPerSecond) == "number" then
			steering.KeyboardYawDegreesPerSecond = steering.KeyboardYawDegreesPerSecond * scale
		end
		for _, key in {
			"SteerSmoothRate",
			"CameraSteerSmoothRate",
			"SteerAxisSmoothRate",
			"KeyboardAxisSmoothRateLeanUp",
		} do
			local rate = steering[key]
			if typeof(rate) == "number" then
				steering[key] = rate * scale
			end
		end
	end

	local pose = tuning.SupermanPose
	if pose and typeof(pose.BankFollowRate) == "number" then
		pose.BankFollowRate = pose.BankFollowRate * math.sqrt(scale)
	end

	return tuning
end

-- Thrust = flight bar (SupesMobile). Refills on the ground; drains while flying.
-- Solar energy (heat vision) lives in HeatVisionConfigs.SolarEnergy — separate profile fields.
local Thrust = {
	BaseMaxFuel = 60,
	DrainPerSecond = 10,
	TreadmillRefillPerTick = 0,
	PassiveRefillRate = 7,
	FlightRefillRate = 0,
	MinFuelToStartFlight = 15,
	EmptyDescentGrace = 0.6,
	SpeedPointsToMaxFuelBonus = 1,
	MaxFuelBonusFromProducts = 0,
	ReplicateMinInterval = 0.25,
	LeanUpSafetyMaxDuration = 45,
	-- Player attribute (Properties panel) to set max thrust fuel directly. 0 = use BaseMaxFuel.
	PowerAttribute = "ThrustPower",
	DefaultPower = 0,
	--- Phases where thrust refills (in-air flight only).
	FlightRefillPhases = {
		FlightTransit = true,
		AfterTransition = true,
		LeanUp = true,
	},
	SuperJumpRefillPhases = {
		LeanUp = true,
		LeapDown = true,
	},
}

function Thrust.GetEffectiveMinFuelToStart(thrustMax: number): number
	if typeof(thrustMax) ~= "number" or thrustMax <= 0 then
		return Thrust.MinFuelToStartFlight
	end
	return math.min(Thrust.MinFuelToStartFlight, thrustMax)
end

function Thrust.IsInFlightRefillPhase(djPhase: any, sjPhase: any): boolean
	if typeof(sjPhase) == "string" and sjPhase ~= "" then
		return Thrust.SuperJumpRefillPhases[sjPhase] == true
	end
	if djPhase == nil or djPhase == "" then
		return false
	end
	if typeof(djPhase) ~= "string" then
		return false
	end
	return Thrust.FlightRefillPhases[djPhase] == true
end

--- @deprecated use IsInFlightRefillPhase — kept for any external callers
function Thrust.BlocksPassiveRefill(djPhase: any): boolean
	return Thrust.IsInFlightRefillPhase(djPhase, nil)
end

function Thrust.GetNetDrainPerSecond(): number
	return math.max(Thrust.DrainPerSecond, 0.01)
end

function Thrust.GetAbilityTimeCap(fuelAtStart: number, tuningMax: number): number
	local netDrain = Thrust.GetNetDrainPerSecond()
	if netDrain <= 0 then
		return tuningMax
	end
	local fuelSeconds = fuelAtStart / netDrain
	return math.max(tuningMax, fuelSeconds + 2)
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

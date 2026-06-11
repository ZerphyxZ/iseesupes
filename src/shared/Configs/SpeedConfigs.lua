--!strict

-- Speed progression (XP), level thresholds, swim/walk display speed, rebirth boost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

local LEGACY_AFTER_FORWARD = CharacterConfigs.DoubleJump.Phases.AfterTransition.ForwardSpeed

local SpeedConfigs = {
	StudsRequired = 8,
	BaseXpCost = 300,
	CostMultiplier = 1.3,
	--- After this level, per-level XP cost grows by SoftCostMultiplier instead of
	--- CostMultiplier. Stage gates end at L25; without this bend 1.3^N makes
	--- L46 cost ~40M XP for one level and the late flight curve unreachable.
	SoftCapLevel = 25,
	SoftCostMultiplier = 1.1,
	BaseWalkSpeed = 8,
	RebirthPercentPerStep = 50,
	SpeedGainPerStudBatch = 1,
	AddSpeedMinInterval = 0.05,
	--- Anti-teleport cap on per-frame distance counted for Speed XP (SpeedController).
	--- Must stay above max flight speed / 60fps (450/60 = 7.5) or flight XP stops at high level.
	MaxCountedStudsPerFrame = 12,
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
	local step = SpeedConfigs.BaseXpCost
	for i = 1, level - 1 do
		if i > 1 then
			local mult = if i <= SpeedConfigs.SoftCapLevel - 1
				then SpeedConfigs.CostMultiplier
				else SpeedConfigs.SoftCostMultiplier
			step *= mult
		end
		total += math.floor(step)
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

-- ──────────────────────────────────────────────────────────────────
-- Level → speed curves (piecewise-linear anchors).
-- Design: low, learnable speed while players discover the map; crazy speed
-- arrives gradually at high levels. Tune by editing anchor rows only.
-- ──────────────────────────────────────────────────────────────────

export type CurveAnchor = { level: number, value: number }

--- Walk / swim speed (Humanoid.WalkSpeed). Old formula (8 + 3/level) hit 59 at
--- L18 — uncontrollable on obstacles. Slow growth, soft-capped late.
SpeedConfigs.WalkSpeedCurve = {
	{ level = 1, value = 8 },
	{ level = 3, value = 11 },
	{ level = 5, value = 14 },
	{ level = 8, value = 18 },
	{ level = 12, value = 23 },
	{ level = 16, value = 27 },
	{ level = 20, value = 31 },
	{ level = 25, value = 35 },
	{ level = 32, value = 40 },
	{ level = 40, value = 46 },
	{ level = 50, value = 52 },
	{ level = 60, value = 58 },
	{ level = 80, value = 67 },
	{ level = 100, value = 75 },
} :: { CurveAnchor }

--- E-flight forward speed (studs/s). Old formula reached its full 4.48x walk
--- multiplier at L4 and gave ~285 studs/s at L18. New curve: learn the map
--- early, earn crazy speed late. Flat beyond the last anchor.
SpeedConfigs.FlightSpeedCurve = {
	{ level = 1, value = 50 },
	{ level = 3, value = 62 },
	{ level = 5, value = 75 },
	{ level = 8, value = 88 },
	{ level = 12, value = 102 },
	{ level = 16, value = 115 },
	{ level = 20, value = 130 },
	{ level = 25, value = 150 },
	{ level = 32, value = 180 },
	{ level = 40, value = 215 },
	{ level = 50, value = 260 },
	{ level = 65, value = 320 },
	{ level = 80, value = 380 },
	{ level = 100, value = 450 },
} :: { CurveAnchor }

local function evalLevelCurve(curve: { CurveAnchor }, level: number): number
	local lvl = math.max(1, math.floor(level))
	local first = curve[1]
	if lvl <= first.level then
		return first.value
	end
	for i = 2, #curve do
		local a = curve[i - 1]
		local b = curve[i]
		if lvl <= b.level then
			local t = (lvl - a.level) / (b.level - a.level)
			return a.value + (b.value - a.value) * t
		end
	end
	return curve[#curve].value
end

function SpeedConfigs.GetSpeedFromLevel(level: number): number
	return evalLevelCurve(SpeedConfigs.WalkSpeedCurve, level)
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

-- E-ability horizontal flight follows FlightSpeedCurve (no longer walk-linked);
-- steering / yaw rates still scale with the resulting speed in ApplyFlightScalingToDoubleJump.
SpeedConfigs.Flight = {
	ReferenceAfterForward = LEGACY_AFTER_FORWARD,
	--- Global flight feel multiplier on top of FlightSpeedCurve (1 = curve as authored).
	SpeedBoost = 1,
}

--- Compat: flight-to-walk ratio now derived from the two curves.
function SpeedConfigs.GetFlightWalkMultiplier(level: number): number
	local walk = SpeedConfigs.GetSpeedFromLevel(level)
	if walk <= 0 then
		return 1
	end
	return SpeedConfigs.GetFlightForwardSpeed(level) / walk
end

function SpeedConfigs.GetFlightForwardSpeed(level: number): number
	local cfg = SpeedConfigs.Flight
	local boost = if typeof(cfg.SpeedBoost) == "number" and cfg.SpeedBoost > 0 then cfg.SpeedBoost else 1
	return evalLevelCurve(SpeedConfigs.FlightSpeedCurve, level) * boost
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
	--- Drain per second at L1 flight speed. Actual drain RISES with flight speed
	--- (see GetFlightDrainPerSecond) so faster flight burns hotter — one tank
	--- should never comfortably cover a full stage without thrust upgrades.
	DrainPerSecond = 10,
	--- Drain grows with (flightSpeed / L1 flightSpeed)^exponent. 0 = flat drain,
	--- 1 = constant studs-per-fuel. 0.6 keeps range growing slowly with level
	--- while time-per-tank shrinks → permanent "need more thrust" pressure.
	DrainSpeedExponent = 0.6,
	TreadmillRefillPerTick = 0,
	--- Ground refill floor (per second). Intentionally flat across levels —
	--- leveling speed must NOT erase thrust anxiety.
	PassiveRefillRate = 7,
	--- Bigger tanks refill proportionally (rate = max(floor, ThrustMax * this)),
	--- so a full refill converges to ~20s regardless of upgrades.
	PassiveRefillPercentOfMax = 0.05,
	FlightRefillRate = 0,
	MinFuelToStartFlight = 15,
	EmptyDescentGrace = 0.6,
	SpeedPointsToMaxFuelBonus = 1,
	MaxFuelBonusFromProducts = 0,
	ReplicateMinInterval = 0.25,
	-- Safety net only; upgraded tanks can glide ~50s+, fuel is the real limiter.
	LeanUpSafetyMaxDuration = 90,
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

-- ──────────────────────────────────────────────────────────────────
-- Speed-Scaling System
-- Higher Speed level → shorter cooldowns and faster flight, but ALSO faster
-- thrust drain. Refill stays flat per level. Net effect: speed is the grind,
-- thrust upgrades are the permanent chase ("always more thrust").
-- ──────────────────────────────────────────────────────────────────

--- Generic cooldown reducer. Returns base cooldown minus (level-1)*reduction,
--- clamped between minCD and base.
function SpeedConfigs.ScaledCooldown(base: number, level: number, reductionPerLevel: number, minCD: number): number
	local lvl = math.max(1, math.floor(level))
	return math.clamp(base - (lvl - 1) * reductionPerLevel, minCD, base)
end

--- Double-jump / flight cooldown: 5.0s at L1 → 0.8s at L85+.
function SpeedConfigs.GetDoubleJumpCooldown(level: number): number
	return SpeedConfigs.ScaledCooldown(5.0, level, 0.05, 0.8)
end

--- Long-jump cooldown: 1.0s at L1 → 0.2s at L41+.
function SpeedConfigs.GetLongJumpCooldown(level: number): number
	return SpeedConfigs.ScaledCooldown(1.0, level, 0.02, 0.2)
end

--- Super-jump cooldown: 1.5s at L1 → 0.4s at L74+.
function SpeedConfigs.GetSuperJumpCooldown(level: number): number
	return SpeedConfigs.ScaledCooldown(1.5, level, 0.015, 0.4)
end

--- Heat-vision / laser-beam post-depletion cooldown: 2.5s at L1 → 0.3s at L111+.
function SpeedConfigs.GetHeatVisionCooldown(level: number): number
	return SpeedConfigs.ScaledCooldown(2.5, level, 0.02, 0.3)
end

--- Thrust drain per second while flying. Scales UP with flight speed:
--- drain = DrainPerSecond * (flightSpeed / L1 flightSpeed)^DrainSpeedExponent.
--- L1 = 10/s (6.0s tank), L12 ≈ 15.3/s (3.9s), L25 ≈ 19.3/s (3.1s),
--- L100 ≈ 37/s — a base 60 tank always feels too small. That is the point.
function SpeedConfigs.GetFlightDrainPerSecond(level: number): number
	local baseSpeed = evalLevelCurve(SpeedConfigs.FlightSpeedCurve, 1)
	local speed = SpeedConfigs.GetFlightForwardSpeed(level)
	if baseSpeed <= 0 or speed <= 0 then
		return Thrust.DrainPerSecond
	end
	local exponent = Thrust.DrainSpeedExponent
	if typeof(exponent) ~= "number" or exponent < 0 then
		exponent = 0
	end
	return Thrust.DrainPerSecond * (speed / baseSpeed) ^ exponent
end

--- Passive thrust refill rate (on the ground, not flying). Flat per level —
--- only a bigger tank (thrust upgrades) speeds up the absolute refill.
function SpeedConfigs.GetPassiveRefillRate(level: number, thrustMax: number?): number
	local floorRate = Thrust.PassiveRefillRate
	local max = if typeof(thrustMax) == "number" and thrustMax > 0 then thrustMax else Thrust.BaseMaxFuel
	local pct = Thrust.PassiveRefillPercentOfMax
	if typeof(pct) ~= "number" or pct <= 0 then
		return floorRate
	end
	return math.max(floorRate, max * pct)
end

return SpeedConfigs

-- Lune script: compile-checks edited files and simulates the new balance curves.
-- Run: lune run scripts/validate-balance.luau (from repo root)

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function compileCheck(path: string)
	local src = fs.readFile(path)
	-- luau.load compiles immediately; syntax errors throw here.
	local ok, err = pcall(function()
		return luau.load(src, { debugName = path })
	end)
	if not ok then
		error("SYNTAX ERROR in " .. path .. ": " .. tostring(err))
	end
	print("compile OK  " .. path)
end

-- 1) Pure syntax checks on every edited file
local edited = {
	"src/shared/Configs/SpeedConfigs.lua",
	"src/shared/Configs/ThrustUpgradeConfigs.lua",
	"src/shared/Configs/StageCheckpointConfigs.lua",
	"src/shared/Configs/RebirthConfigs.lua",
	"src/server/GameServices/DoubleJumpService.lua",
	"src/server/GameServices/HeatVisionService.lua",
	"src/server/GameServices/RebirthService.lua",
	"src/server/GameServices/ThrustUpgradeService.lua",
	"src/server/GameServices/TreadmillService.lua",
	"src/server/GameServices/GiveWinsService.lua",
	"src/server/GameServices/HealthRedService.lua",
	"src/shared/Configs/FunnelAnalyticsConfigs.lua",
	"src/shared/Configs/HealthRedConfigs.lua",
	"src/shared/Configs/CharacterConfigs.lua",
	"src/shared/Utils/StageCheckpointWorld.lua",
	"src/client/GameControllers/Character/LongJumpController.lua",
	"src/client/GameControllers/HUD/JumpCounterController.lua",
	"src/server/GlobalServices/DataService.lua",
	"src/client/GameControllers/Speed/SpeedController.lua",
	"src/client/GameControllers/Rebirth/RebirthController.lua",
	"src/shared/Configs/PlaytimeRewardConfigs.lua",
	"src/server/GameServices/PlaytimeRewardService.lua",
	"src/client/GameControllers/PlaytimeReward/PlaytimeRewardController.lua",
	"src/client/GameControllers/HUD/WinCelebrationController.lua",
	"src/client/GameControllers/Character/CharacterController.lua",
	"src/server/GameServices/LoginRewardService.lua",
	"src/client/GameControllers/LoginReward/LoginRewardController.lua",
	"src/shared/Configs/LoginRewardConfigs.lua",
	"src/shared/Utils/ToggleFlyZone.lua",
	"src/shared/Configs/AutoFlyConfigs.lua",
	"src/client/GameControllers/HUD/AutoFlyController.lua",
	"src/shared/Configs/QuestConfigs.lua",
	"src/server/GameServices/QuestService.lua",
	"src/client/GameControllers/Quest/QuestController.lua",
	"src/shared/Utils/ProfileTemplate.lua",
	"src/client/GameControllers/Performance/LowEndWorldController.lua",
	"src/server/GameServices/StageCheckpointService.lua",
	"src/client/GameControllers/HUD/ThrustMobileBarController.lua",
	"src/client/GameControllers/HUD/ToggleFlyHintController.lua",
	"src/client/GameControllers/Character/SuperJumpController.lua",
	"src/server/GameServices/LeaderboardService.lua",
	"src/client/GameControllers/HUD/NotificationController.lua",
}
for _, path in edited do
	compileCheck(path)
end

-- 2) Execute SpeedConfigs with stubbed Roblox globals
local characterConfigsStub = {
	DoubleJump = {
		Phases = { AfterTransition = { ForwardSpeed = 68 } },
		Steering = { KeyboardStrafeSpeed = 58 },
	},
}

local env = {
	game = {
		GetService = function(_self, _name)
			return { Shared = { Configs = { CharacterConfigs = "stub" } } }
		end,
	},
	require = function(_target)
		return characterConfigsStub
	end,
}

local loadCfg = luau.load(fs.readFile("src/shared/Configs/SpeedConfigs.lua"), {
	debugName = "SpeedConfigs",
	environment = env,
	injectGlobals = true,
})
local SpeedConfigs = loadCfg()
local Thrust = SpeedConfigs.Thrust

local loadUpg = luau.load(fs.readFile("src/shared/Configs/ThrustUpgradeConfigs.lua"), {
	debugName = "ThrustUpgradeConfigs",
	environment = env,
	injectGlobals = true,
})
local ThrustUpgradeConfigs = loadUpg()

-- 3) Simulation: per-level table
print("")
print("LVL | walk | flight | drain/s | tank(base)s | studs/tank | refillBase | refill w/all packs")
local function row(level: number)
	local walk = SpeedConfigs.GetSpeedFromLevel(level)
	local flight = SpeedConfigs.GetFlightForwardSpeed(level)
	local drain = SpeedConfigs.GetFlightDrainPerSecond(level)
	local tankS = Thrust.BaseMaxFuel / drain
	local studs = flight * tankS
	local maxAll = Thrust.BaseMaxFuel
		+ ThrustUpgradeConfigs.Tiers[1].FuelBonus
		+ ThrustUpgradeConfigs.Tiers[2].FuelBonus
		+ ThrustUpgradeConfigs.Tiers[3].FuelBonus
	print(
		string.format(
			"%3d | %4.1f | %6.1f | %7.2f | %9.2f | %10.0f | %8.2f | %8.2f",
			level,
			walk,
			flight,
			drain,
			tankS,
			studs,
			SpeedConfigs.GetPassiveRefillRate(level, Thrust.BaseMaxFuel),
			SpeedConfigs.GetPassiveRefillRate(level, maxAll)
		)
	)
end
for _, level in { 1, 3, 5, 8, 10, 12, 15, 18, 20, 25, 32, 40, 50, 65, 80, 100, 120 } do
	row(level)
end

-- 4) Stage coverage: entry level, expected gear (packs owned), tank coverage %
print("")
print("STAGE | length | entryLvl | flight | no-pack tank %% | geared tank %%")
local stages = {
	{ n = 1, len = 640, lvl = 1, packs = 0 },
	{ n = 2, len = 645, lvl = 3, packs = 0 },
	{ n = 3, len = 793, lvl = 6, packs = 1 },
	{ n = 4, len = 1409, lvl = 9, packs = 1 },
	{ n = 5, len = 953, lvl = 12, packs = 2 },
	{ n = 6, len = 2411, lvl = 15, packs = 2 },
	{ n = 7, len = 1871, lvl = 17, packs = 3 },
	{ n = 8, len = 1180, lvl = 22, packs = 3 },
	{ n = 9, len = 1479, lvl = 25, packs = 3 },
}
local cumulativeBonus = { 0, 0, 0 }
cumulativeBonus[1] = ThrustUpgradeConfigs.Tiers[1].FuelBonus
cumulativeBonus[2] = cumulativeBonus[1] + ThrustUpgradeConfigs.Tiers[2].FuelBonus
cumulativeBonus[3] = cumulativeBonus[2] + ThrustUpgradeConfigs.Tiers[3].FuelBonus

for _, s in stages do
	local flight = SpeedConfigs.GetFlightForwardSpeed(s.lvl)
	local drain = SpeedConfigs.GetFlightDrainPerSecond(s.lvl)
	local baseStuds = flight * (Thrust.BaseMaxFuel / drain)
	local gearFuel = Thrust.BaseMaxFuel + (s.packs > 0 and cumulativeBonus[s.packs] or 0)
	local gearStuds = flight * (gearFuel / drain)
	print(
		string.format(
			"  S%d  | %5d  |  L%-3d   | %6.1f | %8.0f%%      | %8.0f%%",
			s.n,
			s.len,
			s.lvl,
			flight,
			100 * baseStuds / s.len,
			100 * gearStuds / s.len
		)
	)
end

-- 5) Design assertions
local f18 = SpeedConfigs.GetFlightForwardSpeed(18)
assert(f18 >= 105 and f18 <= 140, "L18 flight should be controllable (105-140), got " .. f18)
assert(SpeedConfigs.GetFlightForwardSpeed(1) >= 45, "L1 flight too slow")
assert(SpeedConfigs.GetFlightForwardSpeed(100) <= 115, "flight is capped ~110 for stage control")

local prevDrain = 0
local prevFlight = 0
local prevWalk = 0
for level = 1, 120 do
	local d = SpeedConfigs.GetFlightDrainPerSecond(level)
	local f = SpeedConfigs.GetFlightForwardSpeed(level)
	local w = SpeedConfigs.GetSpeedFromLevel(level)
	assert(d >= prevDrain - 1e-9, "drain must never decrease with level (L" .. level .. ")")
	assert(f >= prevFlight - 1e-9, "flight speed must never decrease (L" .. level .. ")")
	assert(w >= prevWalk - 1e-9, "walk speed must never decrease (L" .. level .. ")")
	prevDrain, prevFlight, prevWalk = d, f, w
end

-- Coverage invariant: a base tank must not trivially fly a WHOLE stage nonstop.
-- Threshold relaxed 0.80 → 0.90 for the walk/jump + discrete-ToggleFly-hop design
-- (flight is no longer how you cross a whole stage; the base 100 tank intentionally
-- covers the short early stages and the ≤90-fuel worst hop — see Thrust.BaseMaxFuel).
for _, s in stages do
	local flight = SpeedConfigs.GetFlightForwardSpeed(s.lvl)
	local drain = SpeedConfigs.GetFlightDrainPerSecond(s.lvl)
	local coverage = flight * (Thrust.BaseMaxFuel / drain) / s.len
	assert(coverage < 0.90, "S" .. s.n .. " base-tank coverage too high: " .. coverage)
end
-- Base tank must cover the longest ToggleFly hop (~90 fuel, Stage 6 choiceRoom) so
-- Stages 5-6 clear without thrust packs — the whole point of the 60→100 base bump.
assert(Thrust.BaseMaxFuel >= 90, "base tank must cover the longest ToggleFly hop (~90 fuel)")

-- Seconds-per-tank (base 60) must shrink with level → upgrades always wanted
local t1 = Thrust.BaseMaxFuel / SpeedConfigs.GetFlightDrainPerSecond(1)
local t25 = Thrust.BaseMaxFuel / SpeedConfigs.GetFlightDrainPerSecond(25)
local t100 = Thrust.BaseMaxFuel / SpeedConfigs.GetFlightDrainPerSecond(100)
assert(t25 < t1 and t100 <= t25, "time-per-tank must shrink early then flatten (flight capped)")

-- XP anti-teleport headroom: max flight speed per frame at 60fps must fit cap
local maxFlight = SpeedConfigs.GetFlightForwardSpeed(200)
assert(maxFlight / 60 < SpeedConfigs.MaxCountedStudsPerFrame, "MaxCountedStudsPerFrame too low for top flight speed")

-- Refill: flat at base tank, proportional for big tanks
assert(SpeedConfigs.GetPassiveRefillRate(1, 60) == 10, "base refill should be 10/s")
assert(SpeedConfigs.GetPassiveRefillRate(50, 60) == 10, "refill must not scale with level")
assert(SpeedConfigs.GetPassiveRefillRate(1, 400) == 20, "big tank refill should be proportional")

-- StudsRequired curve: early earns faster (smaller threshold), late earns slower (larger threshold)
assert(SpeedConfigs.GetStudsRequired(1) < SpeedConfigs.GetStudsRequired(50),
	"early stud threshold must be lower than late (fast early / slow late)")
assert(SpeedConfigs.GetStudsRequired(1) >= 1, "stud threshold must be at least 1")

-- Jump XP boost: must be a multiplier ≥ 1 (1 = no boost, 2 = double while airborne from jump)
local jumpBoost = SpeedConfigs.JumpXpBoost or 1
assert(type(jumpBoost) == "number" and jumpBoost >= 1, "JumpXpBoost must be a number >= 1")

-- 6) XP pacing with post-L25 soft cap
local loadRebirth = luau.load(fs.readFile("src/shared/Configs/RebirthConfigs.lua"), {
	debugName = "RebirthConfigs",
	environment = env,
	injectGlobals = true,
})
local RebirthConfigs = loadRebirth()

print("")
print("XP pacing (Void treadmill 250 XP/s base; movement adds up to ~20/s):")
print("LVL | step cost | total XP | hrs@250xp/s r0 | hrs r5 (x3.5) | flight")
local prevTotal = 0
for _, lvl in { 25, 30, 40, 50, 75, 100 } do
	local total = SpeedConfigs.GetExperienceForLevel(lvl)
	local step = SpeedConfigs.GetXpNeededForLevel(lvl)
	print(
		string.format(
			"%3d | %9s | %8s | %8.1f       | %8.1f      | %5.0f",
			lvl,
			tostring(math.floor(step / 1000)) .. "k",
			tostring(math.floor(total / 1000)) .. "k",
			total / 250 / 3600,
			total / (250 * RebirthConfigs.GetSpeedMultiplier(5)) / 3600,
			SpeedConfigs.GetFlightForwardSpeed(lvl)
		)
	)
	prevTotal = total
end

-- Gates (≤L25) must be unaffected by the soft cap
local totalL25 = SpeedConfigs.GetExperienceForLevel(25)
assert(totalL25 > 535000 and totalL25 < 550000, "L25 total XP moved — gates would shift: " .. totalL25)
-- Soft cap engaged: L26 step grows by 1.1, not 1.3
local step25 = SpeedConfigs.GetXpNeededForLevel(25)
local step26 = SpeedConfigs.GetXpNeededForLevel(26)
assert(step26 < step25 * 1.15, "soft cap not applied after L25")
-- Reachability: L50 under 100M total (was ~970M with 1.3^N)
assert(SpeedConfigs.GetExperienceForLevel(50) < 100_000_000, "L50 still unreachable")

-- Rebirth perks
assert(RebirthConfigs.GetThrustBonus(0) == 0, "rebirth 0 should grant no thrust")
assert(RebirthConfigs.GetThrustBonus(5) == 5 * RebirthConfigs.ThrustBonusPerRebirth, "thrust bonus math")
assert(RebirthConfigs.GetSpeedMultiplier(2) == 2, "2 rebirths should double gain")
-- Rebirth wins multiplier (drives the win grind now that every stage is reachable)
assert(RebirthConfigs.GetWinsMultiplier(0) == 1, "rebirth 0 should not multiply wins")
assert(math.abs(RebirthConfigs.GetWinsMultiplier(10) - 2) < 1e-9, "10 rebirths should ~double wins")

print("")
print("ALL BALANCE ASSERTIONS PASSED")

-- Lune script: models the WIN economy (wins/hour, hours-to-unlock cosmetics, rebirth).
-- Companion to validate-balance.luau (which covers speed/thrust/XP curves).
-- Run: lune run scripts/validate-economy.luau (from repo root)
--
-- WHY THIS EXISTS: after removing the speed-gate, thrust-requirement, and
-- death->lobby loop, EVERY player can now reach the deepest stage-end button.
-- Claiming any button teleports you to the lobby (GiveWinsService), so a run =
-- "traverse to the deepest button you can reach, claim it, repeat". The economy
-- ceiling is therefore (deepest button value) / (run time). This sim prices that
-- out for current vs proposed numbers so we tune from a table, not vibes.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

-- Load the REAL walk-speed curve from SpeedConfigs (stays in sync with the game).
local characterConfigsStub = {
	DoubleJump = {
		Phases = { AfterTransition = { ForwardSpeed = 68 } },
		Steering = { KeyboardStrafeSpeed = 58 },
	},
}
local env = {
	game = { GetService = function() return { Shared = { Configs = { CharacterConfigs = "stub" } } } end },
	require = function() return characterConfigsStub end,
}
local SpeedConfigs = luau.load(fs.readFile("src/shared/Configs/SpeedConfigs.lua"), {
	debugName = "SpeedConfigs",
	environment = env,
	injectGlobals = true,
})()

----------------------------------------------------------------------
-- INPUTS
----------------------------------------------------------------------

-- Stage gate->gate lengths (studs), from the measured map (see balance memory).
-- A "full run" to the deepest claimable button (end of S8 = Button9) traverses S1..S8.
local STAGE_LEN = { 640, 645, 793, 1409, 953, 2411, 1871, 1180, 1479 }
local function studsToStageEnd(stage: number): number
	local sum = 0
	for i = 1, stage do
		sum += STAGE_LEN[i]
	end
	return sum
end
local DEEPEST_STAGE = 8 -- Button9 sits at end of S8; S9 is the win room (no button payout)

-- Per-run friction: obby platforming, jumps, mistakes, and re-routing make a run
-- take longer than raw (distance / walkSpeed). Plus a flat per-run overhead for the
-- 1.5s win celebration + teleport + respawn + re-accelerate.
local FRICTION = 2.2
local OVERHEAD = 6

-- Button payouts by STAGE (assumed LIVE map-attribute values, post-2026-06-14 3x;
-- confirm against the boot log "GiveWins: button->stage map" if these drift).
-- Only the deepest (S8) sets the farm ceiling; earlier ones are onboarding feel.
local BUTTONS_CURRENT = { 5, 15, 50, 120, 200, 450, 900, 1500 } -- S1..S8

-- Cosmetic SINKS (win costs), from the configs.
local SUITS_CURRENT = { 5, 30, 75, 150, 350, 750, 1500, 3000, 6000, 12000, 25000, 60000 }
local TRAILS_CURRENT = { 150, 1500, 2500, 4000 }
local THRUST_CURRENT = { 100, 300, 1000 }

-- ---- PROPOSED ----
-- Trim only the deepest button (reaching it is no longer a feat); keep the
-- onboarding buttons juicy. Stretch the TOP of the cosmetic ladder so the chase
-- lengthens WITHOUT shrinking any single celebration. Rebirth gains a wins
-- multiplier so it accelerates the (now longer) grind.
local BUTTONS_PROPOSED = { 5, 15, 50, 120, 200, 400, 700, 1000 } -- S6/S7/S8 trimmed
local SUITS_PROPOSED = { 5, 30, 75, 150, 400, 900, 2000, 4500, 10000, 22000, 50000, 110000 }
local TRAILS_PROPOSED = { 150, 2000, 4000, 8000 }
local THRUST_PROPOSED = { 100, 300, 1000 } -- unchanged (also Robux products)

-- Rebirth wins multiplier (proposed): +10% wins per rebirth.
local REBIRTH_WINS_MULT_ADD = 0.10

----------------------------------------------------------------------
-- MODEL
----------------------------------------------------------------------

local function sum(t: { number }): number
	local s = 0
	for _, v in t do
		s += v
	end
	return s
end

local function runSeconds(level: number, stage: number): number
	local walk = SpeedConfigs.GetSpeedFromLevel(level)
	return (studsToStageEnd(stage) / walk) * FRICTION + OVERHEAD
end

-- Wins/hour for a player who reliably reaches `stage` and farms its button.
local function winsPerHour(level: number, stage: number, buttonValue: number, winsMult: number): number
	return buttonValue * winsMult / runSeconds(level, stage) * 3600
end

local function hrs(cost: number, wph: number): number
	return cost / wph
end

----------------------------------------------------------------------
-- REPORT
----------------------------------------------------------------------

print("WIN ECONOMY MODEL  (friction x" .. FRICTION .. ", +" .. OVERHEAD .. "s/run overhead)")
print("Loop: run to deepest reachable button -> claim -> teleport to lobby -> repeat.")
print("")

-- Player tiers: everyone can now reach S8; only their walk speed (level) differs.
local TIERS = {
	{ name = "newbie L8 (S3 only)", level = 8, stage = 3 },
	{ name = "low    L12 (full)  ", level = 12, stage = DEEPEST_STAGE },
	{ name = "mid    L20 (full)  ", level = 20, stage = DEEPEST_STAGE },
	{ name = "mid    L25 (full)  ", level = 25, stage = DEEPEST_STAGE },
	{ name = "high   L50 (full)  ", level = 50, stage = DEEPEST_STAGE },
	{ name = "max    L100 (full) ", level = 100, stage = DEEPEST_STAGE },
}

local function buttonForStage(buttons: { number }, stage: number): number
	return buttons[stage]
end

local function tierTable(label: string, buttons: { number }, suits: { number }, trails: { number }, thrust: { number })
	local topSuit = suits[#suits]
	local allCosmetics = sum(suits) + sum(trails) + sum(thrust)
	print("== " .. label .. " ==")
	print("  top suit = " .. topSuit .. " wins | ALL cosmetics = " .. allCosmetics .. " wins")
	print("  player                | run(s) | wins/run |  wins/hr | hrs->topSuit | hrs->ALL")
	for _, t in TIERS do
		local btn = buttonForStage(buttons, t.stage)
		local rs = runSeconds(t.level, t.stage)
		local wph = winsPerHour(t.level, t.stage, btn, 1)
		print(string.format(
			"  %-21s | %5.0f  | %8d | %8.0f | %11.1f | %8.1f",
			t.name, rs, btn, wph, hrs(topSuit, wph), hrs(allCosmetics, wph)
		))
	end
	print("")
end

tierTable("CURRENT", BUTTONS_CURRENT, SUITS_CURRENT, TRAILS_CURRENT, THRUST_CURRENT)
tierTable("PROPOSED", BUTTONS_PROPOSED, SUITS_PROPOSED, TRAILS_PROPOSED, THRUST_PROPOSED)

-- Suit ladder side by side (what each unlock costs + cumulative).
print("== SUIT LADDER (cost / cumulative) ==")
print("  #  |  current cost  cum   |  proposed cost  cum")
local curCum, propCum = 0, 0
for i = 1, #SUITS_CURRENT do
	curCum += SUITS_CURRENT[i]
	propCum += SUITS_PROPOSED[i]
	print(string.format("  %2d | %9d %9d  | %9d %9d", i, SUITS_CURRENT[i], curCum, SUITS_PROPOSED[i], propCum))
end
print("")

-- Rebirth: the wins multiplier makes rebirth accelerate the win grind directly.
-- (It ALSO raises XP gain -> faster leveling -> faster walk -> shorter runs; that
-- compounding is shown qualitatively, the table isolates the direct wins mult.)
print("== REBIRTH wins multiplier (proposed +" .. (REBIRTH_WINS_MULT_ADD * 100) .. "%/rebirth) ==")
print("  modeled at L25, full S8 run, PROPOSED button (" .. BUTTONS_PROPOSED[DEEPEST_STAGE] .. ")")
print("  rebirths | wins mult | wins/hr | hrs->topSuit(110k) | hrs->ALL")
local propAll = sum(SUITS_PROPOSED) + sum(TRAILS_PROPOSED) + sum(THRUST_PROPOSED)
local propTop = SUITS_PROPOSED[#SUITS_PROPOSED]
for _, rb in { 0, 1, 3, 6, 10 } do
	local mult = 1 + rb * REBIRTH_WINS_MULT_ADD
	local wph = winsPerHour(25, DEEPEST_STAGE, BUTTONS_PROPOSED[DEEPEST_STAGE], mult)
	print(string.format("  %8d | %8.2fx | %7.0f | %18.1f | %8.1f", rb, mult, wph, hrs(propTop, wph), hrs(propAll, wph)))
end
print("")

----------------------------------------------------------------------
-- ASSERTIONS (design intent)
----------------------------------------------------------------------

-- The whole point: the deepest button is the ceiling. Confirm a mid player on the
-- CURRENT numbers clears ALL cosmetics fast enough to be a problem (< ~6h), and the
-- PROPOSED numbers push it into a "long chase" band (top suit many hours).
local midWphCur = winsPerHour(25, DEEPEST_STAGE, BUTTONS_CURRENT[DEEPEST_STAGE], 1)
local midWphProp = winsPerHour(25, DEEPEST_STAGE, BUTTONS_PROPOSED[DEEPEST_STAGE], 1)
local allCur = sum(SUITS_CURRENT) + sum(TRAILS_CURRENT) + sum(THRUST_CURRENT)
local allProp = sum(SUITS_PROPOSED) + sum(TRAILS_PROPOSED) + sum(THRUST_PROPOSED)

assert(hrs(allCur, midWphCur) < 6, "sanity: current all-cosmetics should be the <6h problem we're fixing")
assert(hrs(allProp, midWphProp) > hrs(allCur, midWphCur) * 1.6, "proposed should lengthen the chase >1.6x")
assert(SUITS_PROPOSED[1] == SUITS_CURRENT[1], "first suit must stay cheap (onboarding dopamine)")
assert(BUTTONS_PROPOSED[1] == BUTTONS_CURRENT[1] and BUTTONS_PROPOSED[2] == BUTTONS_CURRENT[2],
	"early buttons must stay juicy (38.6% quit before first win)")

-- Proposed numbers must stay monotonic (each tier costs more than the last).
for _, ladder in { SUITS_PROPOSED, BUTTONS_PROPOSED, TRAILS_PROPOSED } do
	for i = 2, #ladder do
		assert(ladder[i] >= ladder[i - 1], "ladder must be monotonic")
	end
end

print("ALL ECONOMY ASSERTIONS PASSED")

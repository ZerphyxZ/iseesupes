--!strict

-- Endless rolling quests: 3 always-live quest slots, each on its own ESCALATING ladder.
-- Finishing a quest advances that slot to the next (bigger) tier, so there is ALWAYS a next
-- goal — the on-screen tracker never goes empty and the session keeps extending. Designed to
-- raise average session time from ~5 min toward 10-12 min (see plan).
--
-- Every quest is either a profile-COUNTER DELTA (EarnWins → data.Wins, EarnSpeed → data.Speed)
-- or session minutes (PlayTime), so QuestService computes progress with ZERO hooks into other
-- services and is fully server-authoritative (a client can't fake a profile counter).
--
-- All three slot types are completable by simply STAYING in the session — no skill wall can
-- block a reward, which is exactly what we optimise for. XP rewards are a PERCENT of the
-- player's current level step (stay meaningful at any level), like Login/Playtime rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local LoginRewardConfigs = require(ReplicatedStorage.Shared.Configs.LoginRewardConfigs)
local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)

-- Single-source the CURRENT canonical icons so they can never go stale: Wins = the main HUD
-- trophy (HudConfigs.WinCollectEffect.IconImage), Speed = the +Speed burst icon (SpeedConfigs).
-- The old reward-popup ids in Login/Playtime configs (Speed=111493420189104, Wins=126127674350677)
-- were superseded — don't copy those. Gift has no newer canonical source, so keep it inline.
local ICON_WINS = (HudConfigs.WinCollectEffect and HudConfigs.WinCollectEffect.IconImage)
	or "rbxassetid://137378104956269"
local ICON_SPEED = SpeedConfigs.SpeedGainPopupImage or "rbxassetid://130009821689663"
local ICON_GIFT = "rbxassetid://80861029762439"

export type Reward = {
	--- "Wins" | "Speed" | "Boost"
	Type: string,
	--- Wins: flat amount. Speed: uses XpPercentOfStep. Boost: uses DurationSeconds.
	Amount: number?,
	XpPercentOfStep: number?,
	DurationSeconds: number?,
}

local QuestConfigs = {}

--- Quests appear only after the tutorial (same gate as playtime/login rewards).
QuestConfigs.MinTutorialStep = 6
--- Server re-check / replicate cadence (seconds). The client computes live progress from
--- replicated baselines between pushes, so this can be coarse.
QuestConfigs.HeartbeatSeconds = 5

--- Daily "quests completed today" mega-reward (a come-back-tomorrow hook layered on the endless
--- chain). Granted once when QuestDayCount reaches DailyGoal; resets at the day boundary.
QuestConfigs.DailyGoal = 5
QuestConfigs.DailyMegaWins = 150
QuestConfigs.DailyMegaBoostSeconds = 90

--- The three always-live slots, each fixed to one ladder type.
QuestConfigs.Slots = { "EarnWins", "EarnSpeed", "PlayTime" } :: { string }
QuestConfigs.SlotCount = 3

-- ── Per-type ladders (tune here) ───────────────────────────────────────────────
-- target(tier) and reward(tier) are derived from these. EarnWins/EarnSpeed grow
-- multiplicatively (the grind lengthens each tier); PlayTime grows additively and caps so
-- it stays "play another N minutes" rather than ballooning.
type TypeSpec = {
	Counter: string, -- profile field for delta, or "PlayMinutes" (session minutes)
	Icon: string,
	--- Target curve
	BaseTarget: number,
	TargetGrowth: number?, -- multiplicative (EarnWins/EarnSpeed)
	TargetAddStep: number?, -- additive per tier (PlayTime)
	TargetCap: number,
	--- Reward curve. RewardType is CROSS-AXIS — never the same currency the quest measures:
	--- EarnWins → Speed, EarnSpeed → Wins, PlayTime → Boost. (Paying back the currency you grind
	--- feels pointless; cross-axis means every quest advances a different goal.)
	RewardType: string, -- "Wins" | "Speed" | "Boost"
	RewardBase: number?, -- Wins: base amount
	RewardGrowth: number?, -- Wins: per-tier multiplier
	RewardCap: number?, -- Wins: max amount
	RewardXpPercent: number?, -- Speed: base % of level step
	RewardXpPercentPerTier: number?, -- Speed: % added per tier
	RewardXpPercentCap: number?, -- Speed: max %
	RewardBoostSeconds: number?, -- Boost: duration
}

local TYPES: { [string]: TypeSpec } = {
	-- Grinding Wins (cosmetic currency) → rewards SPEED XP (a leveling boost). Cross-axis.
	EarnWins = {
		Counter = "Wins",
		Icon = ICON_WINS,
		BaseTarget = 15,
		TargetGrowth = 1.6,
		TargetCap = 4000,
		RewardType = "Speed",
		RewardXpPercent = 25, -- % of the current level step, grows per tier
		RewardXpPercentPerTier = 3,
		RewardXpPercentCap = 50,
	},
	-- Grinding Speed (leveling) → rewards WINS (cosmetic currency). Cross-axis.
	EarnSpeed = {
		Counter = "Speed",
		Icon = ICON_SPEED,
		BaseTarget = 2500,
		TargetGrowth = 1.7,
		TargetCap = 250000,
		RewardType = "Wins",
		RewardBase = 20,
		RewardGrowth = 1.4,
		RewardCap = 150,
	},
	-- Time invested → rewards WINS (permanent progress that banks toward cosmetics — a far stronger
	-- "keep playing" hook than a temporary boost, which only helped during flight and was half dead
	-- code anyway). The quest measures minutes, so paying Wins stays cross-axis.
	PlayTime = {
		Counter = "PlayMinutes",
		Icon = ICON_GIFT,
		BaseTarget = 6,
		TargetAddStep = 3,
		TargetCap = 20,
		RewardType = "Wins",
		RewardBase = 20,
		RewardGrowth = 1.4,
		RewardCap = 120,
	},
}

local function roundNice(n: number): number
	if n >= 1000 then
		return math.floor(n / 500 + 0.5) * 500
	elseif n >= 100 then
		return math.floor(n / 10 + 0.5) * 10
	elseif n >= 20 then
		return math.floor(n / 5 + 0.5) * 5
	end
	return math.max(1, math.floor(n + 0.5))
end

--- The profile/session counter field this quest type tracks ("Wins" / "Speed" / "PlayMinutes").
function QuestConfigs.GetCounter(questType: string): string
	local t = TYPES[questType]
	return if t then t.Counter else "PlayMinutes"
end

function QuestConfigs.GetIcon(questType: string): string
	local t = TYPES[questType]
	return if t then t.Icon else ICON_GIFT
end

--- Target value to finish the quest at this tier (tier is 1-based).
function QuestConfigs.GetTarget(questType: string, tier: number): number
	local t = TYPES[questType]
	if not t then
		return 1
	end
	tier = math.max(1, math.floor(tier))
	if typeof(t.TargetAddStep) == "number" then
		return math.min(t.TargetCap, t.BaseTarget + (tier - 1) * (t.TargetAddStep :: number))
	end
	local growth = if typeof(t.TargetGrowth) == "number" then t.TargetGrowth else 1.6
	return math.min(t.TargetCap, roundNice(t.BaseTarget * growth ^ (tier - 1)))
end

--- Reward granted on claiming this tier.
function QuestConfigs.GetReward(questType: string, tier: number): Reward
	local t = TYPES[questType]
	if not t then
		return { Type = "Wins", Amount = 5 }
	end
	tier = math.max(1, math.floor(tier))
	if t.RewardType == "Speed" then
		local pct = if typeof(t.RewardXpPercent) == "number" then t.RewardXpPercent else 25
		if typeof(t.RewardXpPercentPerTier) == "number" then
			pct += (tier - 1) * (t.RewardXpPercentPerTier :: number)
		end
		if typeof(t.RewardXpPercentCap) == "number" then
			pct = math.min(pct, t.RewardXpPercentCap :: number)
		end
		return { Type = "Speed", XpPercentOfStep = pct }
	elseif t.RewardType == "Boost" then
		return {
			Type = "Boost",
			DurationSeconds = if typeof(t.RewardBoostSeconds) == "number" then t.RewardBoostSeconds else 90,
		}
	end
	local base = if typeof(t.RewardBase) == "number" then t.RewardBase else 10
	local growth = if typeof(t.RewardGrowth) == "number" then t.RewardGrowth else 1.4
	local cap = if typeof(t.RewardCap) == "number" then t.RewardCap else math.huge
	return { Type = "Wins", Amount = math.min(cap, roundNice(base * growth ^ (tier - 1))) }
end

--- Speed XP amount for a Speed reward at the given level (percent of that level's step).
function QuestConfigs.GetSpeedXp(reward: Reward, level: number): number
	if typeof(reward.XpPercentOfStep) ~= "number" then
		return 0
	end
	local step = SpeedConfigs.GetXpNeededForLevel(math.max(1, math.floor(level)))
	return math.max(1, math.floor(step * (reward.XpPercentOfStep :: number) / 100))
end

--- Player-facing quest title, e.g. "Earn 40 Wins" / "Earn 12K Speed" / "Play 9 Minutes".
function QuestConfigs.GetLabel(questType: string, tier: number): string
	local target = QuestConfigs.GetTarget(questType, tier)
	if questType == "PlayTime" then
		return string.format("Play %d Minutes", target)
	elseif questType == "EarnSpeed" then
		return "Earn " .. NumberFormatter.Format(target) .. " Speed"
	end
	return "Earn " .. NumberFormatter.Format(target) .. " Wins"
end

--- Short reward label for the board, e.g. "+25 Wins" / "+360 Speed" / "90s 2x Boost".
--- Pass `level` to show the actual Speed XP amount (Speed rewards are a % of that level's step).
function QuestConfigs.GetRewardLabel(questType: string, tier: number, level: number?): string
	local r = QuestConfigs.GetReward(questType, tier)
	if r.Type == "Wins" then
		return "+" .. NumberFormatter.Format(r.Amount or 0) .. " Wins"
	elseif r.Type == "Speed" then
		if typeof(level) == "number" then
			return "+" .. NumberFormatter.Format(QuestConfigs.GetSpeedXp(r, level)) .. " Speed"
		end
		return "Speed XP"
	elseif r.Type == "Boost" then
		return string.format("%ds 2x Boost", r.DurationSeconds or 90)
	end
	return "Reward"
end

--- The slot type for slot index 1..SlotCount.
function QuestConfigs.GetSlotType(slotIndex: number): string
	return QuestConfigs.Slots[slotIndex] or "PlayTime"
end

--- Day number for the daily counter (shared with the login-streak boundary).
function QuestConfigs.GetDayNumber(unixTime: number): number
	return LoginRewardConfigs.GetDayNumber(unixTime)
end

return QuestConfigs

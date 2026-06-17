--!strict

-- Daily login streak (7-day cycle) + offline "welcome back" rewards.
-- XP rewards are a PERCENT of the player's current level step cost, so they
-- stay meaningful at every level instead of becoming dust (fixed amounts die
-- past L20 because step costs grow 1.3x/level to L25, then 1.1x).
-- UI: GUI.Frames.DailyStreak / GUI.Frames.OfflineReward (built in Studio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

export type StreakDayReward = {
	XpPercentOfStep: number,
	Wins: number,
	--- Icon asset shown on the day card (same set the Rewards frame uses).
	Icon: string,
}

export type StreakState = {
	canClaim: boolean,
	--- Day card (1..7) the player can claim now, or last claimed when canClaim=false.
	dayInCycle: number,
	totalStreak: number,
	--- True when a missed day reset the cycle back to day 1.
	resetHappened: boolean,
}

local ICON_SPEED = "rbxassetid://111493420189104"
local ICON_WINS = "rbxassetid://126127674350677"
local ICON_GIFT = "rbxassetid://80861029762439"

local LoginRewardConfigs = {
	SecondsPerDay = 86400,
	--- Shift streak day rollover from UTC midnight (e.g. -18000 = US Eastern midnight).
	DayBoundaryUtcOffsetSeconds = -18000,

	StreakDays = {
		[1] = { XpPercentOfStep = 15, Wins = 0, Icon = ICON_SPEED },
		[2] = { XpPercentOfStep = 20, Wins = 2, Icon = ICON_SPEED },
		[3] = { XpPercentOfStep = 30, Wins = 5, Icon = ICON_WINS },
		[4] = { XpPercentOfStep = 40, Wins = 8, Icon = ICON_SPEED },
		[5] = { XpPercentOfStep = 55, Wins = 12, Icon = ICON_WINS },
		[6] = { XpPercentOfStep = 75, Wins = 18, Icon = ICON_SPEED },
		[7] = { XpPercentOfStep = 120, Wins = 30, Icon = ICON_GIFT },
	} :: { [number]: StreakDayReward },

	Offline = {
		--- Below this the popup is skipped entirely (also kills rejoin farming —
		--- LastSeenAt refreshes every 60s while online).
		MinAwayMinutes = 10,
		MaxHours = 8,
		--- VIP gamepass owners accrue offline XP for up to this many hours instead.
		VipMaxHours = 16,
		--- XP per offline hour as percent of current level step (8h cap = 48%).
		XpPercentOfStepPerHour = 6,
	},

	--- Periodic LastSeenAt heartbeat + streak re-check (crossing midnight mid-session).
	HeartbeatSeconds = 60,
	StreakRecheckSeconds = 300,

	UI = {
		StreakFrameName = "DailyStreak",
		OfflineFrameName = "OfflineReward",
		--- Hold auto-popups until the tutorial is complete (TutorialStep).
		MinTutorialStep = 6,
		--- Seconds after join before auto-showing popups (spawn intro settles).
		AutoShowDelay = 4,
		--- HUD gift button under GUI.HUD (opens DailyStreak when claimable).
		HudButtonPath = { "Left", "DailyStreak" },
	},
}

function LoginRewardConfigs.GetDayNumber(unixTime: number): number
	local offset = LoginRewardConfigs.DayBoundaryUtcOffsetSeconds
	if typeof(offset) ~= "number" then
		offset = 0
	end
	return math.floor((unixTime + offset) / LoginRewardConfigs.SecondsPerDay)
end

function LoginRewardConfigs.GetStreakDayReward(dayInCycle: number): StreakDayReward
	local idx = math.clamp(math.floor(dayInCycle), 1, 7)
	return LoginRewardConfigs.StreakDays[idx]
end

--- XP amount for a streak day at the given level (percent of that level's step).
function LoginRewardConfigs.GetStreakXp(dayInCycle: number, level: number): number
	local reward = LoginRewardConfigs.GetStreakDayReward(dayInCycle)
	local step = SpeedConfigs.GetXpNeededForLevel(math.max(1, math.floor(level)))
	return math.max(1, math.floor(step * reward.XpPercentOfStep / 100))
end

--- Reads profile fields and decides where the streak stands right now.
function LoginRewardConfigs.EvaluateStreak(data: any, now: number): StreakState
	local lastClaimDay = if type(data.StreakLastClaimDay) == "number" then data.StreakLastClaimDay else 0
	local streakDay = if type(data.StreakDay) == "number" then data.StreakDay else 0
	local totalStreak = if type(data.StreakTotal) == "number" then data.StreakTotal else 0
	local today = LoginRewardConfigs.GetDayNumber(now)

	if lastClaimDay <= 0 or streakDay <= 0 then
		return { canClaim = true, dayInCycle = 1, totalStreak = 0, resetHappened = false }
	end
	if today == lastClaimDay then
		return { canClaim = false, dayInCycle = streakDay, totalStreak = totalStreak, resetHappened = false }
	end
	if today == lastClaimDay + 1 then
		return {
			canClaim = true,
			dayInCycle = (streakDay % 7) + 1,
			totalStreak = totalStreak,
			resetHappened = false,
		}
	end
	-- Missed at least one full day: cycle restarts.
	return { canClaim = true, dayInCycle = 1, totalStreak = 0, resetHappened = true }
end

--- Offline XP for `awaySeconds` away at `level`. 0 when below the minimum.
--- maxHoursOverride: VIP cap (LoginRewardService passes Offline.VipMaxHours).
function LoginRewardConfigs.ComputeOfflineXp(level: number, awaySeconds: number, maxHoursOverride: number?): number
	local offline = LoginRewardConfigs.Offline
	if awaySeconds < offline.MinAwayMinutes * 60 then
		return 0
	end
	local maxHours = if typeof(maxHoursOverride) == "number" and maxHoursOverride > 0
		then maxHoursOverride
		else offline.MaxHours
	local hours = math.min(awaySeconds / 3600, maxHours)
	local step = SpeedConfigs.GetXpNeededForLevel(math.max(1, math.floor(level)))
	return math.floor(step * offline.XpPercentOfStepPerHour / 100 * hours)
end

function LoginRewardConfigs.FormatAway(awaySeconds: number): string
	local hours = math.floor(awaySeconds / 3600)
	local minutes = math.floor((awaySeconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end
	return string.format("%dm", math.max(1, minutes))
end

return LoginRewardConfigs

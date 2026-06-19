--!strict

-- In-session PLAYTIME rewards: claimable milestones at minutes spent IN the current
-- session, reset every session. The in-session mirror of the offline reward — built to
-- raise session time by always dangling a "next reward coming, stay a bit longer" hook.
-- Speed XP rewards are a PERCENT of the player's current level step (stay meaningful at
-- any level), exactly like LoginRewardConfigs.GetStreakXp.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

export type Milestone = {
	Minutes: number,
	--- "Wins" | "Speed" | "ThrustRunBonus" | "Boost".
	Type: string,
	--- Wins / Thrust: flat amount. Speed: uses XpPercentOfStep. Boost: uses DurationSeconds.
	Amount: number?,
	XpPercentOfStep: number?,
	DurationSeconds: number?,
	--- Short label for the popup, e.g. "+15 Wins".
	Label: string,
	--- Optional toast copy; falls back to Label.
	ToastLabel: string?,
	Icon: string,
}

-- Reuse the same icon set the daily-streak / rewards frames use.
local ICON_SPEED = "rbxassetid://111493420189104"
local ICON_WINS = "rbxassetid://126127674350677"
local ICON_GIFT = "rbxassetid://80861029762439"

local PlaytimeRewardConfigs = {
	--- How often the server re-checks whether a new milestone became claimable.
	HeartbeatSeconds = 15,

	UI = {
		--- Hold rewards until the tutorial is complete (TutorialStep).
		MinTutorialStep = 6,
		AutoShowDelay = 4,
		--- Countdown pill hidden — reward popup is the surprise.
		ShowCountdownPill = false,
	},

	--- Ascending by Minutes. Generous early to hook before the ~4-min average session.
	Milestones = {
		[1] = { Minutes = 2, Type = "Wins", Amount = 15, Label = "+15 Wins", Icon = ICON_WINS },
		[2] = { Minutes = 5, Type = "Speed", XpPercentOfStep = 25, Label = "Speed Boost", Icon = ICON_SPEED },
		[3] = {
			Minutes = 10,
			Type = "ThrustRunBonus",
			Amount = 35,
			Label = "+35 Thrust (One Run)",
			ToastLabel = "+35 Thrust for your next flight",
			Icon = ICON_SPEED,
		},
		[4] = { Minutes = 15, Type = "Wins", Amount = 50, Label = "+50 Wins", Icon = ICON_WINS },
		[5] = { Minutes = 20, Type = "Boost", DurationSeconds = 90, Label = "90s Power Boost", Icon = ICON_GIFT },
	} :: { [number]: Milestone },
}

function PlaytimeRewardConfigs.GetMilestone(index: number): Milestone?
	return PlaytimeRewardConfigs.Milestones[index]
end

function PlaytimeRewardConfigs.Count(): number
	return #PlaytimeRewardConfigs.Milestones
end

--- Speed XP for a milestone at the given level (percent of that level's step).
function PlaytimeRewardConfigs.GetSpeedXp(index: number, level: number): number
	local m = PlaytimeRewardConfigs.Milestones[index]
	if not m or type(m.XpPercentOfStep) ~= "number" then
		return 0
	end
	local step = SpeedConfigs.GetXpNeededForLevel(math.max(1, math.floor(level)))
	return math.max(1, math.floor(step * m.XpPercentOfStep / 100))
end

--- The lowest reached-and-unclaimed milestone, or nil. (Claim in order.)
function PlaytimeRewardConfigs.GetClaimableIndex(elapsedSeconds: number, claimed: { [number]: boolean }): number?
	for index = 1, #PlaytimeRewardConfigs.Milestones do
		local m = PlaytimeRewardConfigs.Milestones[index]
		if elapsedSeconds >= m.Minutes * 60 and not claimed[index] then
			return index
		end
	end
	return nil
end

--- The next un-reached milestone (for the "next reward in …" countdown), or nil.
function PlaytimeRewardConfigs.GetNextMilestone(elapsedSeconds: number): (number?, Milestone?)
	for index = 1, #PlaytimeRewardConfigs.Milestones do
		local m = PlaytimeRewardConfigs.Milestones[index]
		if elapsedSeconds < m.Minutes * 60 then
			return index, m
		end
	end
	return nil, nil
end

return PlaytimeRewardConfigs

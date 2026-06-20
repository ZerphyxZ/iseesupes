--!strict

-- Endless rolling quests. 3 always-live quest slots, each on its own escalating ladder
-- (QuestConfigs). Progress is a server-authoritative COUNTER DELTA: EarnWins → profile.Wins,
-- EarnSpeed → profile.Speed, PlayTime → in-session minutes (an os.clock() delta in a server-only
-- table, immune to client clock spoofing). Each slot stores { type, tier, baseline } in the
-- profile; claiming a completed quest grants the tier reward then ADVANCES the slot to the next
-- tier and re-baselines it, so a new (bigger) goal appears at once and the chain never ends.
-- Grants reuse DataService / BoostService. Mirrors PlaytimeRewardService / LoginRewardService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local QuestConfigs = require(ReplicatedStorage.Shared.Configs.QuestConfigs)
local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local DataService: any = nil
local BoostService: any = nil

local QuestService = Knit.CreateService({
	Name = "QuestService",
	Client = {
		--- (state) pushed when slots/tiers/daily-count change so the tracker + board refresh.
		StateChanged = Knit.CreateSignal(),
		--- (slotIndex, rewardLabel, nextLabel) on a successful claim so the client toasts.
		QuestClaimed = Knit.CreateSignal(),
		--- (winsAmount, boostSeconds) when the daily completion goal is hit.
		DailyGoalReached = Knit.CreateSignal(),
	},
})

--- os.clock() when the in-session PlayTime timer started; nil until tutorial is complete.
local sessionStartClock: { [Player]: number? } = {}

local function minTutorialStep(): number
	if typeof(QuestConfigs.MinTutorialStep) == "number" then
		return QuestConfigs.MinTutorialStep
	end
	return TutorialConfigs.Step.Complete
end

local function isQuestActive(data: any): boolean
	if not data then
		return false
	end
	local step = if type(data.TutorialStep) == "number" then math.floor(data.TutorialStep) else 1
	return step >= minTutorialStep()
end

local function sessionMinutes(player: Player): number
	local start = sessionStartClock[player]
	if not start then
		return 0
	end
	return (os.clock() - start) / 60
end

--- Current value of the counter a quest type tracks (profile field, or session minutes).
local function counterValue(data: any, questType: string, minutes: number): number
	if questType == "PlayTime" then
		return minutes
	end
	local v = data[QuestConfigs.GetCounter(questType)]
	return if type(v) == "number" then v else 0
end

-- ── Slot lifecycle ──────────────────────────────────────────────────────────────

--- Create any missing/mismatched slots. Fresh slots baseline off the CURRENT counter so the
--- quest measures earnings from now. (Existing EarnWins/EarnSpeed baselines persist across
--- sessions — those counters only go up — so the chain carries over; PlayTime is re-based once
--- per session in tryStartSessionClock since session minutes reset each session.)
local function ensureSlots(player: Player, data: any)
	if typeof(data.QuestSlots) ~= "table" then
		data.QuestSlots = {}
	end
	local minutes = sessionMinutes(player)
	for i = 1, QuestConfigs.SlotCount do
		local questType = QuestConfigs.GetSlotType(i)
		local slot = data.QuestSlots[i]
		if typeof(slot) ~= "table" or slot.type ~= questType or type(slot.tier) ~= "number" then
			data.QuestSlots[i] = {
				type = questType,
				tier = 1,
				baseline = counterValue(data, questType, minutes),
			}
		end
	end
end

local function tryStartSessionClock(player: Player, data: any)
	if sessionStartClock[player] ~= nil then
		return
	end
	if not isQuestActive(data) then
		return
	end
	sessionStartClock[player] = os.clock()
	-- One-time per session: PlayTime is measured in session minutes (which reset each session),
	-- so re-base any PlayTime slot to "now" (0 min) — i.e. "play <target> more minutes".
	if typeof(data.QuestSlots) == "table" then
		for _, slot in data.QuestSlots do
			if typeof(slot) == "table" and slot.type == "PlayTime" then
				slot.baseline = 0
			end
		end
	end
end

-- ── Daily completion counter ──────────────────────────────────────────────────────

local function checkDailyReset(data: any)
	local today = QuestConfigs.GetDayNumber(os.time())
	if data.QuestDay ~= today then
		data.QuestDay = today
		data.QuestDayCount = 0
		data.QuestDailyClaimed = false
	end
end

-- ── Replicated state ──────────────────────────────────────────────────────────────

local function buildQuestView(slotIndex: number, slot: any, data: any, minutes: number): any
	local questType = slot.type
	local tier = math.max(1, math.floor(slot.tier))
	local target = QuestConfigs.GetTarget(questType, tier)
	local baseline = if type(slot.baseline) == "number" then slot.baseline else 0
	local progress = math.clamp(counterValue(data, questType, minutes) - baseline, 0, target)
	return {
		slot = slotIndex,
		questType = questType,
		tier = tier,
		target = target,
		baseline = baseline,
		counter = QuestConfigs.GetCounter(questType),
		progress = math.floor(progress),
		complete = progress >= target,
		label = QuestConfigs.GetLabel(questType, tier),
		rewardLabel = QuestConfigs.GetRewardLabel(questType, tier, if type(data.Level) == "number" then data.Level else 1),
		icon = QuestConfigs.GetIcon(questType),
	}
end

local function buildClientState(player: Player): any
	local data = DataService:GetData(player)
	if not data or not isQuestActive(data) then
		return { active = false, quests = {} }
	end
	local minutes = sessionMinutes(player)
	local quests = {}
	for i = 1, QuestConfigs.SlotCount do
		local slot = data.QuestSlots and data.QuestSlots[i]
		if typeof(slot) == "table" then
			quests[i] = buildQuestView(i, slot, data, minutes)
		end
	end
	return {
		active = true,
		quests = quests,
		dayCount = if type(data.QuestDayCount) == "number" then data.QuestDayCount else 0,
		dailyGoal = QuestConfigs.DailyGoal,
		sessionMinutes = math.floor(minutes),
	}
end

local function pushState(player: Player)
	QuestService.Client.StateChanged:Fire(player, buildClientState(player))
end

-- ── Grants ────────────────────────────────────────────────────────────────────────

local function grantReward(player: Player, data: any, questType: string, tier: number): string
	local reward = QuestConfigs.GetReward(questType, tier)
	if reward.Type == "Wins" then
		DataService:AddWins(player, reward.Amount or 0)
	elseif reward.Type == "Speed" then
		local level = if type(data.Level) == "number" then data.Level else 1
		local xp = QuestConfigs.GetSpeedXp(reward, level)
		if type(data.Speed) ~= "number" then
			data.Speed = 0
		end
		data.Speed += xp
		SpeedConfigs.SyncLevelFromSpeed(data)
		DataService:Replicate(player)
		DataService:NotifyLeaderboards(player, { "Speed" })
	elseif reward.Type == "Boost" then
		if BoostService then
			BoostService:GrantBoost(player)
			local dur = if typeof(reward.DurationSeconds) == "number" then reward.DurationSeconds else 90
			task.delay(dur, function()
				if player.Parent == Players and BoostService then
					BoostService:ClearBoost(player)
				end
			end)
		end
	end
	local level = if type(data.Level) == "number" then data.Level else 1
	return QuestConfigs.GetRewardLabel(questType, tier, level)
end

local function grantDailyMega(player: Player)
	local wins = QuestConfigs.DailyMegaWins or 0
	if wins > 0 then
		DataService:AddWins(player, wins)
	end
	local boostSeconds = QuestConfigs.DailyMegaBoostSeconds or 0
	if boostSeconds > 0 and BoostService then
		BoostService:GrantBoost(player)
		task.delay(boostSeconds, function()
			if player.Parent == Players and BoostService then
				BoostService:ClearBoost(player)
			end
		end)
	end
	QuestService.Client.DailyGoalReached:Fire(player, wins, boostSeconds)
end

-- ── Client API ──────────────────────────────────────────────────────────────────

function QuestService.Client:GetState(player: Player): any
	return buildClientState(player)
end

function QuestService.Client:ClaimQuest(player: Player, slotIndex: number): boolean
	if type(slotIndex) ~= "number" then
		return false
	end
	slotIndex = math.floor(slotIndex)
	local data = DataService:GetData(player)
	if not data or not isQuestActive(data) then
		return false
	end
	local slot = data.QuestSlots and data.QuestSlots[slotIndex]
	if typeof(slot) ~= "table" then
		return false
	end

	local questType = slot.type
	local tier = math.max(1, math.floor(slot.tier))
	local minutes = sessionMinutes(player)
	local target = QuestConfigs.GetTarget(questType, tier)
	local baseline = if type(slot.baseline) == "number" then slot.baseline else 0
	-- Server-recomputed progress; the client never supplies it.
	if counterValue(data, questType, minutes) - baseline < target then
		return false
	end

	local rewardLabel = grantReward(player, data, questType, tier)

	-- Advance the slot to the next tier and re-baseline off the CURRENT counter (read AFTER the
	-- grant, so a Wins/Speed reward doesn't count toward the next quest). PlayTime re-bases to
	-- the current session minute.
	slot.tier = tier + 1
	slot.baseline = counterValue(data, questType, sessionMinutes(player))
	local nextLabel = QuestConfigs.GetLabel(questType, slot.tier)

	-- Daily completion counter → mega-reward once per day.
	checkDailyReset(data)
	data.QuestDayCount = (if type(data.QuestDayCount) == "number" then data.QuestDayCount else 0) + 1
	if data.QuestDayCount >= QuestConfigs.DailyGoal and not data.QuestDailyClaimed then
		data.QuestDailyClaimed = true
		grantDailyMega(player)
	end

	DataService:ForceSave(player)
	QuestService.Client.QuestClaimed:Fire(player, slotIndex, rewardLabel, nextLabel)
	pushState(player)
	StudioLog.print("Gameplay", "[iseesupes] QuestService: claim", player.Name, "slot", slotIndex, questType, "t" .. tier, rewardLabel)
	return true
end

-- ── Player lifecycle ──────────────────────────────────────────────────────────────

local function waitForData(player: Player, timeout: number): any?
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local data = DataService:GetData(player)
		if data then
			return data
		end
		if player.Parent ~= Players then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

local function onPlayerAdded(player: Player)
	task.spawn(function()
		local data = waitForData(player, 30)
		if not data then
			return
		end
		checkDailyReset(data)
		tryStartSessionClock(player, data)
		ensureSlots(player, data)
		pushState(player)

		while player.Parent == Players do
			task.wait(QuestConfigs.HeartbeatSeconds)
			if player.Parent ~= Players then
				break
			end
			local started = sessionStartClock[player] ~= nil
			tryStartSessionClock(player, data)
			ensureSlots(player, data)
			checkDailyReset(data)
			-- Push so the board/tracker stay live and the CLAIM lights up server-side too
			-- (the client also computes progress locally from the replicated baselines).
			pushState(player)
			if not started and sessionStartClock[player] ~= nil then
				-- clock just started this iteration; state already pushed above.
			end
		end
	end)
end

local function onPlayerRemoving(player: Player)
	sessionStartClock[player] = nil
end

function QuestService:KnitStart()
	DataService = Knit.GetService("DataService")
	pcall(function()
		BoostService = Knit.GetService("BoostService")
	end)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	StudioLog.ready("QuestService")
end

return QuestService

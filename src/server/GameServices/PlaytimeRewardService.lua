--!strict

-- In-session playtime rewards. Server-authoritative: elapsed time is an os.clock()
-- delta held in a server-only table (immune to client clock spoofing), and the claimed
-- set lives in memory — both cleared on PlayerRemoving, so every session starts fresh
-- and there's nothing to farm by rejoining (leaving forfeits progress to the next
-- milestone). Grants reuse DataService / BoostService. Mirrors LoginRewardService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local PlaytimeRewardConfigs = require(ReplicatedStorage.Shared.Configs.PlaytimeRewardConfigs)
local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local DataService: any = nil
local BoostService: any = nil

local PlaytimeRewardService = Knit.CreateService({
	Name = "PlaytimeRewardService",
	Client = {
		--- (state) pushed when elapsed time or the claimed set changes.
		StateChanged = Knit.CreateSignal(),
		--- (index: number, label: string) fired on a successful claim so the client toasts.
		RewardClaimed = Knit.CreateSignal(),
	},
})

--- os.clock() when the in-session timer started; nil until tutorial is complete.
local sessionStartClock: { [Player]: number? } = {}
local claimedThisSession: { [Player]: { [number]: boolean } } = {}

local function minTutorialStepForPlaytime(): number
	local ui = PlaytimeRewardConfigs.UI
	if ui and typeof(ui.MinTutorialStep) == "number" then
		return ui.MinTutorialStep
	end
	return TutorialConfigs.Step.Complete
end

local function isPlaytimeTimerActive(player: Player): boolean
	local data = DataService:GetData(player)
	if not data then
		return false
	end
	local step = if type(data.TutorialStep) == "number" then math.floor(data.TutorialStep) else 1
	return step >= minTutorialStepForPlaytime()
end

local function elapsedSeconds(player: Player): number
	local start = sessionStartClock[player]
	if not start then
		return 0
	end
	return os.clock() - start
end

local function buildClientState(player: Player): any
	local elapsed = elapsedSeconds(player)
	local claimed = claimedThisSession[player] or {}
	local nextIndex, nextM = PlaytimeRewardConfigs.GetNextMilestone(elapsed)
	local claimedCopy: { [number]: boolean } = {}
	for index, v in claimed do
		claimedCopy[index] = v
	end
	return {
		elapsedSeconds = math.floor(elapsed),
		claimableIndex = PlaytimeRewardConfigs.GetClaimableIndex(elapsed, claimed),
		nextIndex = nextIndex,
		nextSeconds = if nextM then nextM.Minutes * 60 else nil,
		claimed = claimedCopy,
	}
end

local function pushState(player: Player)
	PlaytimeRewardService.Client.StateChanged:Fire(player, buildClientState(player))
end

local function tryStartSessionClock(player: Player)
	if sessionStartClock[player] ~= nil then
		return
	end
	if not isPlaytimeTimerActive(player) then
		return
	end
	sessionStartClock[player] = os.clock()
	pushState(player)
end

local function dispatchGrant(player: Player, data: any, index: number): string
	local m = PlaytimeRewardConfigs.GetMilestone(index)
	if not m then
		return ""
	end
	if m.Type == "Wins" then
		DataService:AddWins(player, m.Amount or 0)
		DataService:ForceSave(player)
	elseif m.Type == "Speed" then
		local level = if type(data.Level) == "number" then data.Level else 1
		local xp = PlaytimeRewardConfigs.GetSpeedXp(index, level)
		if type(data.Speed) ~= "number" then
			data.Speed = 0
		end
		data.Speed += xp
		SpeedConfigs.SyncLevelFromSpeed(data)
		DataService:Replicate(player)
		DataService:NotifyLeaderboards(player, { "Speed" })
		DataService:ForceSave(player)
	elseif m.Type == "Thrust" then
		DataService:AddFuel(player, m.Amount or 0)
	elseif m.Type == "Boost" then
		if BoostService then
			BoostService:GrantBoost(player)
			local duration = m.DurationSeconds or 60
			task.delay(duration, function()
				if player.Parent == Players and BoostService then
					BoostService:ClearBoost(player)
				end
			end)
		end
	end
	return m.Label
end

function PlaytimeRewardService.Client:GetState(player: Player): any
	return buildClientState(player)
end

function PlaytimeRewardService.Client:ClaimMilestone(player: Player, index: number): boolean
	if type(index) ~= "number" then
		return false
	end
	local data = DataService:GetData(player)
	if not data then
		return false
	end
	local m = PlaytimeRewardConfigs.GetMilestone(index)
	if not m then
		return false
	end

	local claimed = claimedThisSession[player]
	if not claimed then
		claimed = {}
		claimedThisSession[player] = claimed
	end
	if claimed[index] then
		return false
	end
	if sessionStartClock[player] == nil or not isPlaytimeTimerActive(player) then
		return false
	end
	-- Server-recomputed elapsed; client-supplied time is never trusted.
	if elapsedSeconds(player) < m.Minutes * 60 then
		return false
	end

	claimed[index] = true
	local label = dispatchGrant(player, data, index)
	PlaytimeRewardService.Client.RewardClaimed:Fire(player, index, label)
	pushState(player)
	StudioLog.print("Gameplay", "[iseesupes] PlaytimeRewardService: claim", player.Name, "milestone", index, label)
	return true
end

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
		claimedThisSession[player] = {}
		tryStartSessionClock(player)
		pushState(player)

		-- Re-push when a new milestone crosses into claimable so the HUD pip lights up
		-- without the panel being open.
		local lastClaimable: number? = nil
		while player.Parent == Players do
			task.wait(PlaytimeRewardConfigs.HeartbeatSeconds)
			if player.Parent ~= Players then
				break
			end
			tryStartSessionClock(player)
			local claimableIndex =
				PlaytimeRewardConfigs.GetClaimableIndex(elapsedSeconds(player), claimedThisSession[player] or {})
			if claimableIndex ~= lastClaimable then
				lastClaimable = claimableIndex
				pushState(player)
			end
		end
	end)
end

local function onPlayerRemoving(player: Player)
	-- The entire session reset: nothing persisted, so a fresh join starts at zero.
	sessionStartClock[player] = nil
	claimedThisSession[player] = nil
end

function PlaytimeRewardService:KnitStart()
	DataService = Knit.GetService("DataService")
	pcall(function()
		BoostService = Knit.GetService("BoostService")
	end)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	StudioLog.ready("PlaytimeRewardService")
end

return PlaytimeRewardService

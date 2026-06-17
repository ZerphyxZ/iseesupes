--!strict

-- Daily login streak + offline rewards. All amounts computed server-side from
-- LoginRewardConfigs; client only asks to claim. LastSeenAt heartbeats every
-- 60s so offline time survives crashes, and a 5-min loop re-evaluates the
-- streak when a session crosses midnight UTC.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local LoginRewardConfigs = require(ReplicatedStorage.Shared.Configs.LoginRewardConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local DataService: any = nil
local MonetizationService: any = nil

local LoginRewardService = Knit.CreateService({
	Name = "LoginRewardService",
	Client = {
		--- (state: {canClaim, dayInCycle, totalStreak, offlineXp, awaySeconds})
		StateChanged = Knit.CreateSignal(),
	},
})

--- Pending offline XP per session; computed once from the profile on join.
local pendingOffline: { [Player]: { xp: number, awaySeconds: number } } = {}

local function buildClientState(player: Player, data: any): any
	local streak = LoginRewardConfigs.EvaluateStreak(data, os.time())
	local offline = pendingOffline[player]
	local level = if type(data.Level) == "number" then data.Level else 1
	return {
		canClaim = streak.canClaim,
		dayInCycle = streak.dayInCycle,
		totalStreak = streak.totalStreak,
		resetHappened = streak.resetHappened,
		xpForDay = LoginRewardConfigs.GetStreakXp(streak.dayInCycle, level),
		offlineXp = if offline then offline.xp else 0,
		awaySeconds = if offline then offline.awaySeconds else 0,
	}
end

local function pushState(player: Player)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	LoginRewardService.Client.StateChanged:Fire(player, buildClientState(player, data))
end

local function grantSpeedXp(player: Player, data: any, amount: number)
	if type(data.Speed) ~= "number" then
		data.Speed = 0
	end
	data.Speed += amount
	SpeedConfigs.SyncLevelFromSpeed(data)
	DataService:Replicate(player)
	DataService:NotifyLeaderboards(player, { "Speed" })
end

function LoginRewardService:PushStateServer(player: Player)
	pushState(player)
end

function LoginRewardService.Client:GetState(player: Player): any?
	local data = DataService:GetData(player)
	if not data then
		return nil
	end
	return buildClientState(player, data)
end

function LoginRewardService.Client:ClaimStreak(player: Player): boolean
	local data = DataService:GetData(player)
	if not data then
		return false
	end

	local now = os.time()
	local streak = LoginRewardConfigs.EvaluateStreak(data, now)
	if not streak.canClaim then
		return false
	end

	local level = if type(data.Level) == "number" then data.Level else 1
	local xp = LoginRewardConfigs.GetStreakXp(streak.dayInCycle, level)
	local reward = LoginRewardConfigs.GetStreakDayReward(streak.dayInCycle)

	data.StreakDay = streak.dayInCycle
	data.StreakLastClaimDay = LoginRewardConfigs.GetDayNumber(now)
	data.StreakTotal = streak.totalStreak + 1

	grantSpeedXp(player, data, xp)
	if reward.Wins > 0 then
		DataService:AddWins(player, reward.Wins)
	end
	DataService:ForceSave(player)

	StudioLog.print(
		"Gameplay",
		"[iseesupes] LoginRewardService: streak claim",
		player.Name,
		"day",
		streak.dayInCycle,
		"xp",
		xp,
		"wins",
		reward.Wins,
		"total",
		data.StreakTotal
	)
	pushState(player)
	return true
end

function LoginRewardService.Client:ClaimOffline(player: Player): boolean
	local pending = pendingOffline[player]
	if not pending or pending.xp <= 0 then
		return false
	end

	local data = DataService:GetData(player)
	if not data then
		return false
	end

	pendingOffline[player] = nil
	grantSpeedXp(player, data, pending.xp)
	DataService:ForceSave(player)

	StudioLog.print("Gameplay", "[iseesupes] LoginRewardService: offline claim", player.Name, "xp", pending.xp)
	pushState(player)
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

		-- Offline reward from the previous session (before this session's heartbeat runs).
		local now = os.time()
		local lastSeen = if type(data.LastSeenAt) == "number" then data.LastSeenAt else 0
		if lastSeen > 0 and now > lastSeen then
			local level = if type(data.Level) == "number" then data.Level else 1
			local vipCap: number? = nil
			if MonetizationService and MonetizationService:PlayerOwnsGamepassYielding(player, "VIP") then
				vipCap = LoginRewardConfigs.Offline.VipMaxHours
			end
			local xp = LoginRewardConfigs.ComputeOfflineXp(level, now - lastSeen, vipCap)
			if xp > 0 then
				pendingOffline[player] = { xp = xp, awaySeconds = now - lastSeen }
			end
		end
		data.LastSeenAt = now

		pushState(player)

		-- Heartbeat LastSeenAt + re-evaluate streak across midnight.
		local lastStreakCheck = os.clock()
		local wasClaimable = LoginRewardConfigs.EvaluateStreak(data, now).canClaim
		while player.Parent == Players do
			task.wait(LoginRewardConfigs.HeartbeatSeconds)
			local liveData = DataService:GetData(player)
			if not liveData then
				break
			end
			liveData.LastSeenAt = os.time()

			if os.clock() - lastStreakCheck >= LoginRewardConfigs.StreakRecheckSeconds then
				lastStreakCheck = os.clock()
				local claimable = LoginRewardConfigs.EvaluateStreak(liveData, os.time()).canClaim
				if claimable and not wasClaimable then
					pushState(player)
				end
				wasClaimable = claimable
			end
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local data = DataService and DataService:GetData(player)
	if data then
		data.LastSeenAt = os.time()
	end
	pendingOffline[player] = nil
end

function LoginRewardService:KnitStart()
	DataService = Knit.GetService("DataService")
	pcall(function()
		MonetizationService = Knit.GetService("MonetizationService")
	end)

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	StudioLog.ready("LoginRewardService")
end

return LoginRewardService

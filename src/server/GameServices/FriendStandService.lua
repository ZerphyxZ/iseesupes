--!strict

-- Friend invite rewards (+Speed when referred friends join) and friend list for stand display.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local FriendStandConfigs = require(ReplicatedStorage.Shared.Configs.FriendStandConfigs)
local FriendStandDebug = require(ReplicatedStorage.Shared.Utils.FriendStandDebug)
local FriendStandWorld = require(ReplicatedStorage.Shared.Utils.FriendStandWorld)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local DataService: any = nil

local FriendStandService = Knit.CreateService({
	Name = "FriendStandService",
	Client = {
		FriendInviteRewarded = Knit.CreateSignal(), -- (joinedUserId, newCount, speedGranted)
		OpenInvitePrompt = Knit.CreateSignal(), -- fired when player touches the stand
	},
})

local touchConns: { RBXScriptConnection } = {}
local touchCooldownUntil: { [Player]: number } = {}

local function getFriendIdFromEntry(item: any): number?
	if typeof(item) ~= "table" then
		return nil
	end
	local id = item.Id or item.UserId or item.id
	if typeof(id) == "number" and id > 0 then
		return id
	end
	return nil
end

local function getFriendInviteRewards(data: any): { [string]: boolean }
	if type(data.FriendInviteRewards) == "table" then
		return data.FriendInviteRewards
	end
	data.FriendInviteRewards = {}
	return data.FriendInviteRewards
end

local function countFriendInviteRewards(rewards: { [string]: boolean }): number
	local n = 0
	for _, rewarded in rewards do
		if rewarded == true then
			n += 1
		end
	end
	return n
end

function FriendStandService:FetchFriendUserIds(userId: number): { number }
	local ids: { number } = {}
	local maxIds = FriendStandConfigs.FriendFetchPageSize

	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(userId)
	end)
	if ok and pages then
		while true do
			for _, item in pages:GetCurrentPage() do
				local friendId = getFriendIdFromEntry(item)
				if friendId then
					table.insert(ids, friendId)
					if #ids >= maxIds then
						return ids
					end
				end
			end
			if pages.IsFinished then
				break
			end
			local advancedOk, err = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)
			if not advancedOk then
				warn("[iseesupes] FriendStandService: AdvanceToNextPageAsync failed:", err)
				break
			end
		end
	end

	if #ids == 0 then
		for _, player in Players:GetPlayers() do
			if player.UserId ~= userId then
				table.insert(ids, player.UserId)
			end
		end
	end

	if #ids == 0 and RunService:IsStudio() then
		table.insert(ids, userId)
	end

	FriendStandDebug.log("FetchFriendUserIds:", userId, "→", #ids, "friends")
	return ids
end

function FriendStandService:GetInviteProgress(player: Player): (number, number, number)
	local profile = if DataService then DataService:GetProfile(player) else nil
	if not profile then
		return 0, FriendStandConfigs.MaxInvitedFriends, FriendStandConfigs.SpeedPerInvite
	end
	local rewards = getFriendInviteRewards(profile.Data)
	return countFriendInviteRewards(rewards), FriendStandConfigs.MaxInvitedFriends, FriendStandConfigs.SpeedPerInvite
end

function FriendStandService:TryRewardReferrer(referrer: Player, joinedPlayer: Player): boolean
	if not DataService then
		return false
	end

	local profile = DataService:GetProfile(referrer)
	if not profile then
		return false
	end

	local data = profile.Data
	local rewards = getFriendInviteRewards(data)
	local joinedKey = tostring(joinedPlayer.UserId)

	if rewards[joinedKey] == true then
		return false
	end

	local currentCount = countFriendInviteRewards(rewards)
	if currentCount >= FriendStandConfigs.MaxInvitedFriends then
		return false
	end

	rewards[joinedKey] = true

	if type(data.Speed) ~= "number" then
		data.Speed = 0
	end
	data.Speed += FriendStandConfigs.SpeedPerInvite
	SpeedConfigs.SyncLevelFromSpeed(data)

	DataService:Replicate(referrer)
	DataService:NotifyLeaderboards(referrer, { "Speed" })

	local newCount = countFriendInviteRewards(rewards)
	FriendStandService.Client.FriendInviteRewarded:Fire(
		referrer,
		joinedPlayer.UserId,
		newCount,
		FriendStandConfigs.SpeedPerInvite
	)

	print(
		"[iseesupes] FriendStand:",
		referrer.Name,
		"rewarded for invite from",
		joinedPlayer.Name,
		"→ +",
		FriendStandConfigs.SpeedPerInvite,
		"speed (",
		newCount,
		"/",
		FriendStandConfigs.MaxInvitedFriends,
		")"
	)
	return true
end

local function processReferralJoin(joinedPlayer: Player)
	local joinData = joinedPlayer:GetJoinData()
	local referrerId = joinData.ReferredByPlayerId
	if typeof(referrerId) ~= "number" or referrerId <= 0 then
		return
	end
	if referrerId == joinedPlayer.UserId then
		return
	end

	local referrer = Players:GetPlayerByUserId(referrerId)
	if not referrer then
		return
	end

	FriendStandService:TryRewardReferrer(referrer, joinedPlayer)
end

local boundStands: { [Model]: boolean } = {}

local function onStandTouched(hit: BasePart, standModel: Model)
	if not hit or not hit.Parent then
		return
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if (touchCooldownUntil[player] or 0) > now then
		return
	end
	touchCooldownUntil[player] = now + FriendStandConfigs.TouchDebounce

	FriendStandService.Client.OpenInvitePrompt:Fire(player, standModel)
end

local function bindStandTouches(model: Model)
	if boundStands[model] then
		return
	end

	local touchParts = FriendStandWorld.collectTouchParts(model)
	if #touchParts == 0 then
		warn("[iseesupes] FriendStandService: no touch parts on", model:GetFullName())
		return
	end

	boundStands[model] = true

	for _, part in touchParts do
		part.CanTouch = true
		table.insert(touchConns, part.Touched:Connect(function(hit: BasePart)
			onStandTouched(hit, model)
		end))
	end

	FriendStandDebug.log("bound", #touchParts, "touch part(s) on", model:GetFullName())
end

local function tryBindAllStands(): boolean
	local models = FriendStandWorld.collectAllStandModels()
	for _, model in models do
		bindStandTouches(model)
	end
	return #models > 0
end

function FriendStandService.Client:GetFriendUserIds(player: Player): { number }
	local ids = FriendStandService:FetchFriendUserIds(player.UserId)
	FriendStandDebug.log("Client:GetFriendUserIds for", player.Name, "→", #ids)
	return ids
end

function FriendStandService.Client:GetInviteProgress(player: Player): (number, number, number)
	return FriendStandService:GetInviteProgress(player)
end

function FriendStandService:KnitStart()
	DataService = Knit.GetService("DataService")

	Players.PlayerAdded:Connect(processReferralJoin)
	Players.PlayerRemoving:Connect(function(player)
		touchCooldownUntil[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		task.defer(processReferralJoin, player)
	end

	if not tryBindAllStands() then
		task.spawn(function()
			local deadline = os.clock() + FriendStandConfigs.StandResolveTimeout
			while os.clock() < deadline do
				if tryBindAllStands() then
					break
				end
				task.wait(1)
			end
			if next(boundStands) == nil then
				warn(
					"[iseesupes] FriendStandService: no FriendStand models under Workspace.Map (name: FriendStand)"
				)
			end
		end)
	end

	local standName = FriendStandConfigs.StandModelName
	Workspace.DescendantAdded:Connect(function(desc)
		if not desc:IsA("Model") or desc.Name ~= standName then
			return
		end
		local mapFolder = FriendStandWorld.getMapFolder()
		if mapFolder and desc:IsDescendantOf(mapFolder) then
			task.defer(function()
				bindStandTouches(desc)
			end)
		end
	end)

	FriendStandDebug.log("FriendStandService ready")
end

return FriendStandService

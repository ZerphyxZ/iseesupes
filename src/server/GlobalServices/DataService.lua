--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileStore = require(script.Parent.Parent.Modules.ProfileService)
local ProfileTemplate = require(ReplicatedStorage.Shared.Utils.ProfileTemplate)
local LeaderstatsSync = require(script.Parent.Parent.Modules.LeaderstatsSync)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local DATA_VERSION = "iseesupes_v4"

local PlayerDataStore = ProfileStore.GetProfileStore(DATA_VERSION, ProfileTemplate)

local DataService = Knit.CreateService({
	Name = "DataService",
	Client = {
		DataReplicated = Knit.CreateSignal(),
	},
})

local profiles: { [Player]: any } = {}

local function replicateData(player: Player, profile: any)
	LeaderstatsSync.Apply(player, profile.Data)
	DataService.Client.DataReplicated:Fire(player, profile.Data)
end

local function onPlayerAdded(player: Player)
	local profile = PlayerDataStore:LoadProfileAsync(tostring(player.UserId), "ForceLoad")
	if not profile then
		player:Kick("Could not load data. Please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	SpeedConfigs.SyncLevelFromSpeed(profile.Data)

	profile:ListenToRelease(function()
		profiles[player] = nil
		player:Kick("Session ended. Please rejoin.")
	end)

	if player.Parent ~= Players then
		profile:Release()
		return
	end

	profiles[player] = profile
	replicateData(player, profile)
	print("[iseesupes] Profile loaded for", player.Name)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:Release()
		profiles[player] = nil
	end
end

function DataService:GetProfile(player: Player): any?
	return profiles[player]
end

function DataService:GetData(player: Player): any?
	local profile = profiles[player]
	return profile and profile.Data or nil
end

function DataService:Replicate(player: Player)
	local profile = profiles[player]
	if profile then
		replicateData(player, profile)
	end
end

function DataService.Client:RequestData(player: Player)
	local profile = profiles[player]
	return profile and profile.Data or nil
end

function DataService:KnitStart()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService

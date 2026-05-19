--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local DataService: any = nil

local SpeedService = Knit.CreateService({
	Name = "SpeedService",
	Client = {
		LevelUp = Knit.CreateSignal(),
	},
})

local lastAddAt: { [Player]: number } = {}

local function getRebirths(data: any): number
	if type(data.Rebirths) == "number" then
		return data.Rebirths
	end
	return 0
end

function SpeedService:AddSpeed(player: Player): boolean
	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end

	local now = os.clock()
	local last = lastAddAt[player] or 0
	if now - last < SpeedConfigs.AddSpeedMinInterval then
		return false
	end
	lastAddAt[player] = now

	local data = profile.Data
	if type(data.Speed) ~= "number" then
		data.Speed = 0
	end

	local gain = SpeedConfigs.SpeedGainPerStudBatch * SpeedConfigs.GetRebirthGainMultiplier(getRebirths(data))
	local oldLevel = type(data.Level) == "number" and data.Level or 1

	data.Speed += gain
	local _, newLevel = SpeedConfigs.SyncLevelFromSpeed(data)

	DataService:Replicate(player)

	if newLevel > oldLevel then
		SpeedService.Client.LevelUp:Fire(player, oldLevel, newLevel)
	end

	return true
end

function SpeedService.Client:RequestAddSpeed(player: Player): boolean
	return SpeedService:AddSpeed(player)
end

function SpeedService:KnitStart()
	DataService = Knit.GetService("DataService")

	Players.PlayerRemoving:Connect(function(player)
		lastAddAt[player] = nil
	end)

	print("[iseesupes] SpeedService ready.")
end

return SpeedService

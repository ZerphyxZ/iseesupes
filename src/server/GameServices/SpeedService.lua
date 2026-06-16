--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local GodSpeedAuraConfigs = require(ReplicatedStorage.Shared.Configs.GodSpeedAuraConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local DataService: any = nil
local MonetizationService: any = nil

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

	local stepBonus = if type(data.StepSpeedBonus) == "number" then data.StepSpeedBonus else 0
	local gain = (SpeedConfigs.SpeedGainPerStudBatch + stepBonus)
		* SpeedConfigs.GetRebirthGainMultiplier(getRebirths(data))

	if MonetizationService then
		gain *= MonetizationService:GetXpMultiplier(player)
	end

	if player:GetAttribute(GodSpeedAuraConfigs.ActiveAttribute) == true then
		local mult = player:GetAttribute(GodSpeedAuraConfigs.SpeedGainMultiplierAttribute)
		if typeof(mult) == "number" and mult > 1 then
			gain *= mult
		else
			gain *= GodSpeedAuraConfigs.SpeedGainMultiplier
		end
	end
	local oldLevel = type(data.Level) == "number" and data.Level or 1

	data.Speed += gain
	local _, newLevel = SpeedConfigs.SyncLevelFromSpeed(data)

	DataService:Replicate(player)

	if newLevel > oldLevel then
		DataService:NotifyLeaderboards(player, { "Speed" })
		SpeedService.Client.LevelUp:Fire(player, oldLevel, newLevel)
	end

	return true
end

function SpeedService.Client:RequestAddSpeed(player: Player): boolean
	return SpeedService:AddSpeed(player)
end

function SpeedService:KnitStart()
	DataService = Knit.GetService("DataService")
	MonetizationService = Knit.GetService("MonetizationService")

	Players.PlayerRemoving:Connect(function(player)
		lastAddAt[player] = nil
	end)

	StudioLog.ready("SpeedService")
end

return SpeedService

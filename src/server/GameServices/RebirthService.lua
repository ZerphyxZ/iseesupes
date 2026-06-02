--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RebirthConfigs = require(ReplicatedStorage.Shared.Configs.RebirthConfigs)
local LeaderstatsSync = require(script.Parent.Parent.Modules.LeaderstatsSync)

local DataService: any = nil

local RebirthService = Knit.CreateService({
	Name = "RebirthService",
	Client = {
		RebirthSuccess = Knit.CreateSignal(),
	},
})

local function getRebirths(data: any): number
	if type(data.Rebirths) == "number" then
		return data.Rebirths
	end
	return 0
end

local function getLevel(data: any): number
	if type(data.Level) == "number" then
		return data.Level
	end
	return 1
end

function RebirthService:SyncLeaderstats(player: Player, data: any)
	LeaderstatsSync.Apply(player, data)
end

function RebirthService:PerformRebirth(player: Player, skipLevelCheck: boolean): boolean
	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end

	local data = profile.Data
	local rebirths = getRebirths(data)
	local reqLevel = RebirthConfigs.GetRequiredLevel(rebirths)

	if not skipLevelCheck and getLevel(data) < reqLevel then
		return false
	end

	data.Rebirths = rebirths + 1
	if RebirthConfigs.ResetLevelOnRebirth then
		data.Level = 1
		data.Speed = 0
	end

	DataService:Replicate(player)
	DataService:NotifyLeaderboards(player, { "Rebirths", "Speed" })
	self:SyncLeaderstats(player, data)
	RebirthService.Client.RebirthSuccess:Fire(player)
	return true
end

function RebirthService.Client:RequestRebirth(player: Player): boolean
	return RebirthService:PerformRebirth(player, false)
end

local function waitForProfile(player: Player, timeout: number): any?
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local profile = DataService:GetProfile(player)
		if profile then
			return profile
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
		local profile = waitForProfile(player, 30)
		if profile then
			RebirthService:SyncLeaderstats(player, profile.Data)
		end
	end)
end

function RebirthService:KnitStart()
	DataService = Knit.GetService("DataService")

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	print("[iseesupes] RebirthService ready.")
end

return RebirthService

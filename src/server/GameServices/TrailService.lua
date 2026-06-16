--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)
local CharacterMovementSpeed = require(ReplicatedStorage.Shared.Utils.CharacterMovementSpeed)
local TrailVisuals = require(script.Parent.Parent.Modules.TrailVisuals)

local DataService: any = nil

local TrailService = Knit.CreateService({
	Name = "TrailService",
	Client = {},
})

local function getEquippedTrailId(player: Player): string
	local profile = DataService:GetProfile(player)
	if not profile then
		return ""
	end
	local equipped = profile.Data.EquippedTrail
	if type(equipped) == "string" then
		return equipped
	end
	return ""
end

local function syncVisuals(player: Player)
	TrailVisuals.Update(player, getEquippedTrailId(player))
end

local function ownsTrail(data: any, trailId: string): boolean
	return data.OwnedTrails ~= nil and data.OwnedTrails[trailId] == true
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
		if not waitForProfile(player, 30) then
			return
		end

		TrailVisuals.BindPlayer(player, getEquippedTrailId)
		syncVisuals(player)
	end)
end

function TrailService.Client:BuyWithWins(player: Player, trailId: string)
	local profile = DataService:GetProfile(player)
	if not profile then
		return { success = false, message = "No profile" }
	end

	local info = TrailConfigs.GetTrailById(trailId)
	if not info then
		return { success = false, message = "Invalid trail" }
	end

	if info.WinCost <= 0 then
		return { success = false, message = "Not for wins" }
	end

	local data = profile.Data
	if ownsTrail(data, trailId) then
		return { success = false, message = "Already owned" }
	end

	if data.Wins < info.WinCost then
		return { success = false, message = "Not enough wins" }
	end

	data.Wins -= info.WinCost
	if not data.OwnedTrails then
		data.OwnedTrails = {}
	end
	data.OwnedTrails[trailId] = true
	DataService:Replicate(player)
	return { success = true, message = nil }
end

function TrailService.Client:Equip(player: Player, trailId: string)
	local profile = DataService:GetProfile(player)
	if not profile then
		return { success = false, message = "No profile" }
	end

	local info = TrailConfigs.GetTrailById(trailId)
	if not info then
		return { success = false, message = "Invalid trail" }
	end

	local data = profile.Data
	if not ownsTrail(data, trailId) then
		return { success = false, message = "Not owned" }
	end

	data.EquippedTrail = trailId
	DataService:Replicate(player)
	CharacterMovementSpeed.applyToPlayer(player, data)
	syncVisuals(player)
	return { success = true, message = nil }
end

function TrailService.Client:Unequip(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile then
		return { success = false, message = "No profile" }
	end

	profile.Data.EquippedTrail = ""
	DataService:Replicate(player)
	CharacterMovementSpeed.applyToPlayer(player, profile.Data)
	syncVisuals(player)
	return { success = true, message = nil }
end

function TrailService:KnitStart()
	DataService = Knit.GetService("DataService")

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	StudioLog.ready("TrailService")
end

return TrailService

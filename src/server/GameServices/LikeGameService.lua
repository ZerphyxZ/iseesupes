--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)

local LikeGameService = Knit.CreateService({
	Name = "LikeGameService",
	Client = {
		ShowNotification = Knit.CreateSignal(),
	},
})

local DataService: any = nil
local LIKE_REWARD_SPEED = 5000

local function giveSpeedReward(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end

	local data = profile.Data
	if type(data.Speed) ~= "number" then
		data.Speed = 0
	end

	-- Add 5000 speed as the reward
	data.Speed += LIKE_REWARD_SPEED

	-- Mark as claimed in profile
	if type(data.LikeGameClaimed) ~= "boolean" then
		data.LikeGameClaimed = false
	end
	data.LikeGameClaimed = true

	DataService:Replicate(player)
	return true
end

function LikeGameService:OnLikeGameTriggered(player: Player)
	if not player or not player.Parent then
		return
	end

	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local data = profile.Data
	if type(data.LikeGameClaimed) ~= "boolean" then
		data.LikeGameClaimed = false
	end

	-- Check if already claimed
	if data.LikeGameClaimed == true then
		LikeGameService.Client.ShowNotification:Fire(player, "you already Claim the Reward", "Error")
		return
	end

	-- First time claiming - show initial notification
	LikeGameService.Client.ShowNotification:Fire(player, "Like the game", "Success")

	-- After 5 seconds, give the reward
	task.delay(5, function()
		if not player.Parent then
			return
		end

		-- Double-check they haven't claimed in the meantime
		local latestProfile = DataService:GetProfile(player)
		if latestProfile and latestProfile.Data.LikeGameClaimed ~= true then
			if giveSpeedReward(player) then
				LikeGameService.Client.ShowNotification:Fire(player, "+5,000 Speed Reward!", "Success")
			end
		end
	end)
end

function LikeGameService:KnitStart()
	DataService = Knit.GetService("DataService")

	-- Find and connect to ProximityPrompt
	local likeGame = Workspace:FindFirstChild("Map")
	if not likeGame then
		return
	end

	likeGame = likeGame:FindFirstChild("LikeGame")
	if not likeGame then
		return
	end

	local part = likeGame:FindFirstChild("Part")
	if not part then
		return
	end

	local proximityPrompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not proximityPrompt then
		return
	end

	proximityPrompt.Triggered:Connect(function(player: Player)
		LikeGameService:OnLikeGameTriggered(player)
	end)

	print("[LikeGameService] initialized successfully")
end

return LikeGameService

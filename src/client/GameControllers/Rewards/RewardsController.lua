--!strict

-- Rewards UI controller. Wires Reward1–Reward12 buttons in GUI.Frames.Rewards.Background.
-- Each slot has an independent cooldown defined in RewardConfigs.
-- Time/Claim label shows countdown when on cooldown, "Claim!" when ready.
-- Claimed overlay is shown while on cooldown and hidden when claimable.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local RewardConfigs = require(ReplicatedStorage.Shared.Configs.RewardConfigs)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local RewardTiming = require(ReplicatedStorage.Shared.Utils.RewardTiming)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local REWARD_COUNT = 12

local RewardsController = Knit.CreateController({ Name = "RewardsController" })

local function formatCountdown(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, sec)
	else
		return string.format("%ds", sec)
	end
end

local function getSecondsUntilClaimable(data: any, index: number): number
	return RewardTiming.getSecondsUntilClaimable(data, index)
end

local function anyRewardReady(data: any): boolean
	for i = 1, REWARD_COUNT do
		if getSecondsUntilClaimable(data, i) == 0 then
			return true
		end
	end
	return false
end

function RewardsController:KnitStart()
	local RewardService = Knit.GetService("RewardService")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] RewardsController: timed out waiting for PlayerGui.GUI.")
		return
	end

	local frames = gui:WaitForChild("Frames", 30)
	if not frames then
		warn("[iseesupes] RewardsController: missing GUI.Frames.")
		return
	end

	local rewardsFrame = frames:WaitForChild("Rewards", 30)
	if not rewardsFrame or not rewardsFrame:IsA("Frame") then
		warn("[iseesupes] RewardsController: missing GUI.Frames.Rewards.")
		return
	end

	local background = rewardsFrame:WaitForChild("Background", 10)
	if not background then
		warn("[iseesupes] RewardsController: missing GUI.Frames.Rewards.Background.")
		return
	end

	local hud = gui:WaitForChild("HUD", 10)
	local hudRewardsButton = hud and hud:FindFirstChild("Left") and hud.Left:FindFirstChild("Rewards")
	local hudNotification = hudRewardsButton and hudRewardsButton:FindFirstChild("Notification") :: GuiObject?

	-- Collect all 12 slot tables: { button, rewardLabel, timeLabel, claimedOverlay }
	local slots: { { button: ImageButton, rewardLabel: TextLabel, timeLabel: TextLabel, claimedOverlay: GuiObject } } = {}
	for i = 1, REWARD_COUNT do
		local btn = background:FindFirstChild("Reward" .. i)
		if not btn or not btn:IsA("ImageButton") then
			warn("[iseesupes] RewardsController: missing Reward" .. i)
			continue
		end
		local rewardLabel = btn:FindFirstChild("Reward") :: TextLabel?
		local timeLabel = btn:FindFirstChild("Time/Claim") :: TextLabel?
		local claimedOverlay = btn:FindFirstChild("Claimed") :: GuiObject?
		if not rewardLabel or not timeLabel or not claimedOverlay then
			warn("[iseesupes] RewardsController: Reward" .. i .. " is missing child labels.")
			continue
		end

		local info = RewardConfigs.Rewards[i]
		if info then
			rewardLabel.Text = info.Label
		end

		slots[i] = {
			button = btn :: ImageButton,
			rewardLabel = rewardLabel :: TextLabel,
			timeLabel = timeLabel :: TextLabel,
			claimedOverlay = claimedOverlay :: GuiObject,
		}
	end

	local isClaiming: { [number]: boolean } = {}

	local function refreshSlots()
		local data = DataLib.GetData()
		if not data then
			return
		end

		for i = 1, REWARD_COUNT do
			local slot = slots[i]
			if not slot then
				continue
			end

			local remaining = getSecondsUntilClaimable(data, i)
			local ready = remaining == 0

			slot.claimedOverlay.Visible = not ready
			slot.button.AutoButtonColor = ready

			if ready then
				slot.timeLabel.Text = "Claim!"
			else
				slot.timeLabel.Text = formatCountdown(remaining)
			end
		end

		if hudNotification then
			hudNotification.Visible = anyRewardReady(data)
		end
	end

	-- Wire click on each slot
	for i = 1, REWARD_COUNT do
		local slot = slots[i]
		if not slot then
			continue
		end

		local idx = i
		slot.button.MouseButton1Click:Connect(function()
			if isClaiming[idx] then
				return
			end
			local data = DataLib.GetData()
			if not data or getSecondsUntilClaimable(data, idx) > 0 then
				return
			end

			isClaiming[idx] = true

			RewardService:RequestClaimReward(idx):andThen(function(success: boolean)
				if success then
					local info = RewardConfigs.Rewards[idx]
					if info then
						NotificationManager.show("+" .. info.Grant.Amount .. " " .. info.Grant.Type .. "!", "Success")
					end
				else
					NotificationManager.show("Not ready yet!", "Error")
				end
				isClaiming[idx] = false
			end):catch(function(err)
				warn("[iseesupes] RewardsController: ClaimReward error:", err)
				isClaiming[idx] = false
			end)
		end)
	end

	-- Refresh on data change
	DataLib.OnChanged(function()
		refreshSlots()
	end)

	-- Refresh when the panel becomes visible
	rewardsFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if rewardsFrame.Visible then
			refreshSlots()
		end
	end)

	-- Ticker: update countdowns every second
	task.spawn(function()
		while true do
			task.wait(1)
			if rewardsFrame.Visible then
				refreshSlots()
			end
		end
	end)

	refreshSlots()
	StudioLog.ready("RewardsController")
end

return RewardsController

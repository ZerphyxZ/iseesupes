--!strict

-- Rebirth UI. Expects:
--   PlayerGui → GUI → Frames → Rebirth (Stats/Before|After, Bar, RebirthButton, SkipButton)
--   PlayerGui → GUI → HUD → Left → Rebirth → Notification

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local RebirthConfigs = require(ReplicatedStorage.Shared.Configs.RebirthConfigs)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)
local Fireworks = require(script.Parent.Parent.Parent.Modules.Fireworks)

local RebirthController = Knit.CreateController({ Name = "RebirthController" })

local function formatMult(val: number): string
	return "x" .. string.format("%.2f", val)
end

local function getStatsFromData(data: any): (number, number)
	if not data then
		return 0, 1
	end
	local rebirths = 0
	local level = 1
	if type(data.Rebirths) == "number" then
		rebirths = data.Rebirths
	end
	if type(data.Level) == "number" then
		level = data.Level
	end
	return rebirths, level
end

function RebirthController:KnitStart()
	local RebirthService = Knit.GetService("RebirthService")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] RebirthController: timed out waiting for PlayerGui.GUI.")
		return
	end

	local frames = gui:WaitForChild("Frames", 30)
	if not frames then
		return
	end
	local rebirthFrame = frames:WaitForChild("Rebirth", 30)
	if not rebirthFrame or not rebirthFrame:IsA("Frame") then
		warn("[iseesupes] RebirthController: missing GUI.Frames.Rebirth.")
		return
	end

	local statsFrame = rebirthFrame:WaitForChild("Stats", 10)
	local beforeFrame = statsFrame and statsFrame:WaitForChild("Before", 10)
	local afterFrame = statsFrame and statsFrame:WaitForChild("After", 10)
	if not beforeFrame or not afterFrame then
		warn("[iseesupes] RebirthController: missing Stats/Before or After.")
		return
	end

	local beforeLevelLabel = beforeFrame:WaitForChild("Level"):WaitForChild("Text") :: TextLabel
	local beforeSpeedLabel = beforeFrame:WaitForChild("Speed"):WaitForChild("Text") :: TextLabel
	local afterLevelLabel = afterFrame:WaitForChild("Level"):WaitForChild("Text") :: TextLabel
	local afterSpeedLabel = afterFrame:WaitForChild("Speed"):WaitForChild("Text") :: TextLabel

	local barFrame = rebirthFrame:WaitForChild("Bar", 10)
	if not barFrame then
		return
	end
	local progressFrame = barFrame:WaitForChild("Progress") :: Frame
	local progressLabel = barFrame:WaitForChild("Level") :: TextLabel

	local rebirthButton = rebirthFrame:WaitForChild("RebirthButton") :: ImageButton
	local rebirthButtonText = rebirthButton:WaitForChild("Text") :: TextLabel
	local skipButton = rebirthFrame:WaitForChild("SkipButton") :: ImageButton

	local hud = gui:WaitForChild("HUD", 10)
	local hudRebirthButton = hud and hud:WaitForChild("Left"):WaitForChild("Rebirth")
	local hudNotification = hudRebirthButton and hudRebirthButton:FindFirstChild("Notification") :: GuiObject?

	local isRebirthing = false

	local function updateRebirthUI()
		local currentRebirths, currentLevel = getStatsFromData(DataLib.GetData())

		local reqLevel = RebirthConfigs.GetRequiredLevel(currentRebirths)
		local nextReqLevel = RebirthConfigs.GetNextRequiredLevel(currentRebirths)

		local currentMult = RebirthConfigs.GetSpeedMultiplier(currentRebirths)
		local nextMult = RebirthConfigs.GetSpeedMultiplier(currentRebirths + 1)

		beforeLevelLabel.Text = "Level " .. NumberFormatter.Format(reqLevel)
		beforeSpeedLabel.Text = formatMult(currentMult)

		afterLevelLabel.Text = "Level " .. NumberFormatter.Format(nextReqLevel)
		afterSpeedLabel.Text = formatMult(nextMult)

		local progress = currentLevel / reqLevel
		local displayLevel = math.min(currentLevel, reqLevel)

		progressLabel.Text = NumberFormatter.Format(displayLevel) .. "/" .. NumberFormatter.Format(reqLevel)

		local clamped = math.clamp(progress, 0, 1)
		local targetSize = UDim2.new(clamped, 0, 1, 0)
		TweenService:Create(progressFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Size = targetSize }):Play()

		if currentLevel >= reqLevel then
			rebirthButton.AutoButtonColor = true
			rebirthButtonText.Text = "Rebirth"
			if hudNotification then
				hudNotification.Visible = true
			end
		else
			rebirthButton.AutoButtonColor = false
			rebirthButtonText.Text = "No Levels"
			if hudNotification then
				hudNotification.Visible = false
			end
		end
	end

	local function onRebirthSuccess()
		NotificationManager.show("Rebirth Successful!", "Success")

		local character = player.Character
		if character then
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				Fireworks.PlayFireworks(rootPart)
			end
		end

		updateRebirthUI()
	end

	rebirthButton.MouseButton1Click:Connect(function()
		if isRebirthing then
			return
		end

		local currentRebirths, currentLevel = getStatsFromData(DataLib.GetData())
		local reqLevel = RebirthConfigs.GetRequiredLevel(currentRebirths)

		if currentLevel < reqLevel then
			NotificationManager.show("You need Level " .. NumberFormatter.Format(reqLevel) .. " to Rebirth!", "Error")
			return
		end

		isRebirthing = true

		RebirthService:RequestRebirth():andThen(function(success: boolean)
			if not success then
				NotificationManager.show("Rebirth Failed. Please try again.", "Error")
			end
			isRebirthing = false
		end):catch(function(err)
			warn("[iseesupes] RequestRebirth:", err)
			NotificationManager.show("Rebirth Failed. Please try again.", "Error")
			isRebirthing = false
		end)
	end)

	skipButton.MouseButton1Click:Connect(function()
		local product = ProductConfigs.GetProductByKey("SkipRebirth")
		if not product or product.Id == 0 then
			NotificationManager.show("Skip Rebirth is not configured yet.", "Error")
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)

	rebirthFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if rebirthFrame.Visible then
			updateRebirthUI()
		end
	end)

	DataLib.OnChanged(function()
		updateRebirthUI()
	end)

	RebirthService.RebirthSuccess:Connect(onRebirthSuccess)

	updateRebirthUI()
end

return RebirthController

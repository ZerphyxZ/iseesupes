--!strict

-- Speed progression: distance → server add speed, bottom bar UI, level-up panel.
-- Expects: GUI/HUD/Bottom/Bar, GUI/Frames/LevelUp, Workspace/Sounds/LevelUp

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local EffectsSystem = require(script.Parent.Parent.Parent.Modules.EffectsSystem)
local SpeedController = Knit.CreateController({ Name = "SpeedController" })

local TWEEN_INFO_LEVEL = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function getDataNumbers(data: any): (number, number, number, number)
	if not data then
		return 0, 1, 0, 0
	end
	local speed = type(data.Speed) == "number" and data.Speed or 0
	local level = type(data.Level) == "number" and data.Level or 1
	local wins = type(data.Wins) == "number" and data.Wins or 0
	local rebirths = type(data.Rebirths) == "number" and data.Rebirths or 0
	return speed, level, wins, rebirths
end

function SpeedController:KnitStart()
	local SpeedService = Knit.GetService("SpeedService")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] SpeedController: timed out waiting for GUI.")
		return
	end

	local hud = gui:WaitForChild("HUD", 30)
	local bottom = hud and hud:WaitForChild("Bottom", 10)
	local barFrame = bottom and bottom:WaitForChild("Bar", 10)
	if not barFrame then
		warn("[iseesupes] SpeedController: missing HUD/Bottom/Bar.")
		return
	end

	local progressFrame = barFrame:WaitForChild("Progress") :: Frame
	local levelLabel = barFrame:WaitForChild("Level") :: TextLabel
	local reqLabel = barFrame:WaitForChild("Requirement") :: TextLabel
	local totalSpeedLabel = barFrame:WaitForChild("TotalSpeed") :: TextLabel
	local rebirthBoostLabel = barFrame:WaitForChild("RebirthBoost") :: TextLabel

	local framesFolder = gui:WaitForChild("Frames", 10)
	local levelUpFrame = framesFolder and framesFolder:WaitForChild("LevelUp") :: Frame?
	if not levelUpFrame then
		warn("[iseesupes] SpeedController: missing Frames/LevelUp.")
		return
	end

	local newLevelLabel = levelUpFrame:WaitForChild("NewLevel") :: TextLabel
	local newSpeedLabel = levelUpFrame:WaitForChild("NewSpeed") :: TextLabel

	local levelUpSound: Sound? = nil
	local soundsFolder = Workspace:FindFirstChild("Sounds")
	if soundsFolder then
		local snd = soundsFolder:FindFirstChild("LevelUp")
		if snd and snd:IsA("Sound") then
			levelUpSound = snd
		end
	end

	local originalLevelUpPos = levelUpFrame.Position
	local hiddenLevelUpPos =
		UDim2.new(1.5, 0, originalLevelUpPos.Y.Scale, originalLevelUpPos.Y.Offset)
	levelUpFrame.Position = hiddenLevelUpPos
	levelUpFrame.Visible = false

	local accumulatedDistance = 0
	local lastPosition: Vector3? = nil
	local levelUpDismissId = 0
	local lastSpeedValue: number? = nil
	local lastWinValue: number? = nil

	local function updateUI()
		local currentSpeed, currentLevel, _, currentRebirths = getDataNumbers(DataLib.GetData())

		if lastSpeedValue ~= nil then
			local gain = currentSpeed - lastSpeedValue
			if gain > 0 then
				EffectsSystem.ShowSpeedPopUp(gain)
			end
		end
		lastSpeedValue = currentSpeed

		local xpForCurrentLevel = SpeedConfigs.GetExperienceForLevel(currentLevel)
		local xpForNextLevel = SpeedConfigs.GetExperienceForLevel(currentLevel + 1)
		local xpNeededThisLevel = xpForNextLevel - xpForCurrentLevel
		local currentProgressXP = currentSpeed - xpForCurrentLevel

		currentProgressXP = math.clamp(currentProgressXP, 0, xpNeededThisLevel)

		levelLabel.Text = "Level " .. NumberFormatter.Format(currentLevel)
		reqLabel.Text = NumberFormatter.Format(math.floor(currentProgressXP))
			.. "/"
			.. NumberFormatter.Format(xpNeededThisLevel)
		totalSpeedLabel.Text = "Total Speed: " .. NumberFormatter.Format(math.floor(currentSpeed))

		local boostPercent = SpeedConfigs.GetRebirthBoostPercent(currentRebirths)
		rebirthBoostLabel.Text = "Rebirth: +" .. NumberFormatter.Format(boostPercent) .. "%"

		local percent = if xpNeededThisLevel > 0 then currentProgressXP / xpNeededThisLevel else 1
		percent = math.clamp(percent, 0, 1)

		local targetSize = UDim2.new(percent, 0, 1, 0)
		TweenService:Create(progressFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Size = targetSize }):Play()
	end

	local function updateWinsPopups()
		local _, _, currentWins = getDataNumbers(DataLib.GetData())
		if lastWinValue ~= nil then
			local gain = currentWins - lastWinValue
			if gain > 0 then
				EffectsSystem.ShowWinPopUp(gain)
			end
		end
		lastWinValue = currentWins
	end

	local function showLevelUp(oldLevel: number, newLevel: number)
		local oldSpeed = SpeedConfigs.GetSpeedFromLevel(oldLevel)
		local newSpeed = SpeedConfigs.GetSpeedFromLevel(newLevel)

		newLevelLabel.Text = "Level "
			.. NumberFormatter.Format(oldLevel)
			.. " > Level "
			.. NumberFormatter.Format(newLevel)
		newSpeedLabel.Text = "Speed "
			.. NumberFormatter.Format(oldSpeed)
			.. " > Speed "
			.. NumberFormatter.Format(newSpeed)

		if levelUpSound then
			levelUpSound:Play()
		end

		levelUpDismissId += 1
		local dismissId = levelUpDismissId

		levelUpFrame.Visible = true
		local tweenIn = TweenService:Create(levelUpFrame, TWEEN_INFO_LEVEL, { Position = originalLevelUpPos })
		tweenIn:Play()

		task.delay(5, function()
			if dismissId ~= levelUpDismissId then
				return
			end
			local tweenOut =
				TweenService:Create(levelUpFrame, TWEEN_INFO_LEVEL, { Position = hiddenLevelUpPos })
			tweenOut:Play()
			tweenOut.Completed:Wait()
			if dismissId == levelUpDismissId then
				levelUpFrame.Visible = false
			end
		end)
	end

	RunService.Heartbeat:Connect(function()
		local character = player.Character
		if not character then
			lastPosition = nil
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
		if not rootPart or not humanoid or humanoid.Health <= 0 or humanoid.Sit then
			lastPosition = nil
			return
		end

		local currentPosition = rootPart.Position
		if lastPosition then
			local flatDelta = Vector3.new(
				currentPosition.X - lastPosition.X,
				0,
				currentPosition.Z - lastPosition.Z
			)
			local distance = flatDelta.Magnitude
			if distance > 0 and distance < 5 then
				accumulatedDistance += distance
			end

			while accumulatedDistance >= SpeedConfigs.StudsRequired do
				accumulatedDistance -= SpeedConfigs.StudsRequired
				SpeedService:RequestAddSpeed():catch(function() end)
			end
		end
		lastPosition = currentPosition
	end)

	local data = DataLib.GetData()
	if data then
		lastSpeedValue = type(data.Speed) == "number" and data.Speed or 0
		lastWinValue = type(data.Wins) == "number" and data.Wins or 0
	end

	DataLib.OnChanged(function()
		updateUI()
		updateWinsPopups()
	end)

	updateUI()

	SpeedService.LevelUp:Connect(showLevelUp)

	print("[iseesupes] SpeedController ready.")
end

return SpeedController

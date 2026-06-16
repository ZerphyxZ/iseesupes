--!strict

-- Speed progression: distance → server add speed, bottom bar UI, level-up panel.
-- Expects: GUI/HUD/Bottom/Bar, GUI/Frames/LevelUp, Workspace/Sounds/LevelUp

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)
local ThrustConfigs = SpeedConfigs.Thrust
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local CharacterMovementSpeed = require(ReplicatedStorage.Shared.Utils.CharacterMovementSpeed)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local EffectsSystem = require(script.Parent.Parent.Parent.Modules.EffectsSystem)
local SpeedController = Knit.CreateController({ Name = "SpeedController" })

local TWEEN_INFO_LEVEL = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function findThrustBar(bottom: Instance): Frame?
	local names = { "Thrust", "SpeedPoints" }
	local list = bottom:FindFirstChild("List")
	if list then
		for _, name in names do
			local inList = list:FindFirstChild(name)
			if inList and inList:IsA("Frame") then
				return inList
			end
		end
	end
	for _, name in names do
		local direct = bottom:FindFirstChild(name)
		if direct and direct:IsA("Frame") then
			return direct
		end
	end
	return nil
end

local function getThrustNumbers(data: any): (number, number)
	if not data then
		return 0, ThrustConfigs and ThrustConfigs.BaseMaxFuel or 75
	end
	if ThrustConfigs then
		ThrustConfigs.EnsureFuelDefaults(data)
	else
		if typeof(data.ThrustMax) ~= "number" or data.ThrustMax <= 0 then
			data.ThrustMax = 75
		end
		if typeof(data.ThrustCurrent) ~= "number" then
			data.ThrustCurrent = data.ThrustMax
		end
	end
	return data.ThrustCurrent, data.ThrustMax
end

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
	local barFrame: Frame? = nil
	if bottom then
		local list = bottom:FindFirstChild("List")
		if list then
			local inList = list:FindFirstChild("Bar")
			if inList and inList:IsA("Frame") then
				barFrame = inList
			end
		end
		if not barFrame then
			local legacy = bottom:FindFirstChild("Bar")
			if legacy and legacy:IsA("Frame") then
				barFrame = legacy
			end
		end
	end
	if not barFrame then
		warn("[iseesupes] SpeedController: missing HUD/Bottom/List/Bar or Bottom/Bar.")
		return
	end

	-- Thrust fuel bar (same Bottom; ThrustController module may not be synced via Rojo)
	local thrustBarFrame: Frame? = if bottom then findThrustBar(bottom) else nil
	local thrustProgress: Frame? = nil
	local thrustLevelLabel: TextLabel? = nil
	local thrustReqLabel: TextLabel? = nil
	local lastThrustValue: number? = nil

	if thrustBarFrame then
		thrustProgress = thrustBarFrame:WaitForChild("Progress") :: Frame
		thrustLevelLabel = thrustBarFrame:WaitForChild("Level") :: TextLabel
		thrustReqLabel = thrustBarFrame:FindFirstChild("Requirement") :: TextLabel?
		if thrustReqLabel then
			if HudConfigs.UpdateThrustBarRequirementLabel then
				thrustReqLabel.Visible = true
			else
				thrustReqLabel.Visible = false
			end
		end
	else
		warn("[iseesupes] SpeedController: missing HUD/Bottom/List/Thrust or SpeedPoints.")
	end

	local function updateThrustUI()
		if not thrustProgress or not thrustLevelLabel then
			return
		end

		local current, max = getThrustNumbers(DataLib.GetData())

		if lastThrustValue ~= nil then
			local gain = current - lastThrustValue
			if gain > 0.05 then
				EffectsSystem.ShowThrustPopUp(gain)
			end
		end
		lastThrustValue = current

		thrustLevelLabel.Text = "Thrust"
		if thrustReqLabel and HudConfigs.UpdateThrustBarRequirementLabel then
			thrustReqLabel.Text = NumberFormatter.Format(math.floor(current))
				.. "/"
				.. NumberFormatter.Format(math.floor(max))
		end

		local percent = if max > 0 then current / max else 0
		percent = math.clamp(percent, 0, 1)
		local targetSize = UDim2.new(percent, 0, 1, 0)
		TweenService:Create(thrustProgress, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Size = targetSize }):Play()
	end

	local progressFrame = barFrame:WaitForChild("Progress") :: Frame
	local levelLabel = barFrame:WaitForChild("Level") :: TextLabel
	local reqLabel: TextLabel? = barFrame:FindFirstChild("Requirement") :: TextLabel?
	if reqLabel and not HudConfigs.UpdateLevelBarRequirementLabel then
		reqLabel.Visible = false
	end
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
	local winClaimSound: Sound? = nil
	local soundsFolder = Workspace:FindFirstChild("Sounds")
	if soundsFolder then
		local snd = soundsFolder:FindFirstChild("LevelUp")
		if snd and snd:IsA("Sound") then
			levelUpSound = snd
		end
		local winSnd = soundsFolder:FindFirstChild("WinClaim")
		if winSnd and winSnd:IsA("Sound") then
			winClaimSound = winSnd
		end
	end

	local studioLevelUpPos = levelUpFrame.Position
	local originalLevelUpPos = studioLevelUpPos
	local hiddenLevelUpPos =
		UDim2.new(1.5, 0, originalLevelUpPos.Y.Scale, originalLevelUpPos.Y.Offset)

	local function resolveLevelUpVisiblePosition(): UDim2
		local parent = levelUpFrame.Parent
		if not parent or not parent:IsA("GuiObject") then
			return studioLevelUpPos
		end
		local parentGui = parent :: GuiObject
		local parentH = parentGui.AbsoluteSize.Y
		if parentH <= 0 then
			return studioLevelUpPos
		end

		local layout = HudConfigs.LevelUp
		local gapPx = if layout and typeof(layout.GapBelowJumpCounterPx) == "number"
			then layout.GapBelowJumpCounterPx
			else 10

		local jumpCounter = parent:FindFirstChild("JumpCounter")
		if jumpCounter and jumpCounter:IsA("GuiObject") then
			local jc = jumpCounter :: GuiObject
			local bottom = jc.AbsolutePosition.Y + jc.AbsoluteSize.Y
			local yScale = (bottom + gapPx - parentGui.AbsolutePosition.Y) / parentH
			return UDim2.new(studioLevelUpPos.X.Scale, studioLevelUpPos.X.Offset, yScale, studioLevelUpPos.Y.Offset)
		end

		local extraScale = if layout and typeof(layout.FallbackYOffsetScale) == "number"
			then layout.FallbackYOffsetScale
			else 0.05
		return UDim2.new(
			studioLevelUpPos.X.Scale,
			studioLevelUpPos.X.Offset,
			studioLevelUpPos.Y.Scale + extraScale,
			studioLevelUpPos.Y.Offset
		)
	end

	local function refreshLevelUpAnchors()
		originalLevelUpPos = resolveLevelUpVisiblePosition()
		hiddenLevelUpPos = UDim2.new(1.5, 0, originalLevelUpPos.Y.Scale, originalLevelUpPos.Y.Offset)
		if not levelUpFrame.Visible then
			levelUpFrame.Position = hiddenLevelUpPos
		end
	end

	levelUpFrame.Position = hiddenLevelUpPos
	levelUpFrame.Visible = false

	task.defer(function()
		local deadline = os.clock() + 8
		while os.clock() < deadline do
			local parent = levelUpFrame.Parent
			if parent and parent:FindFirstChild("JumpCounter") then
				break
			end
			task.wait(0.1)
		end
		refreshLevelUpAnchors()
	end)

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
		if reqLabel and HudConfigs.UpdateLevelBarRequirementLabel then
			reqLabel.Text = NumberFormatter.Format(math.floor(currentProgressXP))
				.. "/"
				.. NumberFormatter.Format(xpNeededThisLevel)
		end
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
				if winClaimSound then
					winClaimSound:Play()
				end
			end
		end
		lastWinValue = currentWins
	end

	local function showLevelUp(oldLevel: number, newLevel: number)
		-- Show flight speed: it rises every level (walk speed can flat-line between
		-- curve anchors), and it is the speed players actually feel.
		local oldSpeed = math.floor(SpeedConfigs.GetFlightForwardSpeed(oldLevel) + 0.5)
		local newSpeed = math.floor(SpeedConfigs.GetFlightForwardSpeed(newLevel) + 0.5)

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

		refreshLevelUpAnchors()
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
		local ljCfg = CharacterConfigs.LongJump
		if ljCfg.SuppressSpeedXpDuringArc ~= false
			and player:GetAttribute(ljCfg.ArcActiveAttribute or "LongJumpArcActive") == true
		then
			lastPosition = currentPosition
			return
		end
		if lastPosition then
			local flatDelta = Vector3.new(
				currentPosition.X - lastPosition.X,
				0,
				currentPosition.Z - lastPosition.Z
			)
			local distance = flatDelta.Magnitude
			local maxStep = SpeedConfigs.MaxCountedStudsPerFrame or 12
			if distance > 0 and distance < maxStep then
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

	local function applyMovementSpeed()
		CharacterMovementSpeed.applyToPlayer(player, DataLib.GetData())
	end

	player.CharacterAdded:Connect(function()
		task.defer(applyMovementSpeed)
	end)

	DataLib.OnChanged(function()
		lastThrustValue = nil
		updateUI()
		updateWinsPopups()
		updateThrustUI()
		applyMovementSpeed()
	end)

	DataLib.OnThrustChanged(function()
		updateThrustUI()
	end)

	updateUI()
	updateThrustUI()
	applyMovementSpeed()

	SpeedService.LevelUp:Connect(showLevelUp)

	local DataService = Knit.GetService("DataService")
	pcall(function()
		DataService.ThrustDepleted:Connect(updateThrustUI)
	end)

	local TreadmillService = Knit.GetService("TreadmillService")
	TreadmillService.ActiveTreadmillChanged:Connect(updateThrustUI)

	StudioLog.ready("SpeedController")
end

return SpeedController

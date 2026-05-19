--!strict

-- Central HUD: wins, speed shop, custom swim speed, speed peak tiers.
-- Expects: PlayerGui → GUI → HUD (Left/Wins, Bottom/Speed, Right/CustomSpeed, Right/SpeedPeark)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)

local HUDController = Knit.CreateController({ Name = "HUDController" })

local ROBUX_PREFIX = utf8.char(0xE002)

local function getLevelFromData(data: any): number
	if data and type(data.Level) == "number" then
		return data.Level
	end
	return 1
end

local function getWinsFromData(data: any): number
	if data and type(data.Wins) == "number" then
		return data.Wins
	end
	return 0
end

local function setCharacterSwimSpeed(player: Player, speed: number)
	local character = player.Character
	if character then
		character:SetAttribute(SpeedConfigs.SwimSpeedAttribute, speed)
	end
end

local function bindCharacterSwimSpeed(player: Player, getSpeed: () -> number)
	local function apply()
		setCharacterSwimSpeed(player, getSpeed())
	end
	player.CharacterAdded:Connect(function()
		task.defer(apply)
	end)
	if player.Character then
		apply()
	end
end

local function setupWinsHUD(hud: Instance, player: Player)
	local leftFrame = hud:WaitForChild("Left")
	local winsFrame = leftFrame:WaitForChild("Wins")
	local winTextLabel = winsFrame:WaitForChild("Text") :: TextLabel
	local moreButton = winsFrame:WaitForChild("More") :: ImageButton

	HudAnimations.rememberBaseScale(winsFrame)

	local lastWins = 0

	local function updateWinsText()
		local wins = getWinsFromData(DataLib.GetData())
		if wins == lastWins and winTextLabel.Text ~= "" then
			return
		end

		HudAnimations.countUpText(winTextLabel, lastWins, wins, NumberFormatter.Format, 0.4)
		HudAnimations.pulse(winsFrame, nil, 0.28)
		lastWins = wins
	end

	moreButton.MouseButton1Click:Connect(function()
		HudAnimations.buttonPress(moreButton, function()
			local pass = ProductConfigs.GetGamepassByKey("DoubleWins")
			if not pass or pass.Id == 0 then
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		end)
	end)

	DataLib.OnChanged(updateWinsText)
	updateWinsText()
end

local function setupSpeedShopHUD(hud: Instance, player: Player)
	local bottomFrame = hud:WaitForChild("Bottom")
	local speedShopFrame = bottomFrame:WaitForChild("Speed")
	local products = ProductConfigs.SpeedProducts
	if not products or #products == 0 then
		return
	end

	for index, productInfo in ipairs(products) do
		local buttonName = "Product" .. tostring(index)
		local button = speedShopFrame:FindFirstChild(buttonName) :: GuiButton?
		if not button then
			continue
		end

		HudAnimations.rememberBaseScale(button)

		local textLabel = button:FindFirstChild("Text") :: TextLabel?
		if textLabel then
			textLabel.Text = "+" .. NumberFormatter.Format(productInfo.Amount) .. " Speed"
		end

		button.MouseButton1Click:Connect(function()
			HudAnimations.buttonPress(button, function()
				if productInfo.Id == 0 then
					return
				end
				MarketplaceService:PromptProductPurchase(player, productInfo.Id)
			end)
		end)
	end
end

local function setupCustomSpeedHUD(hud: Instance, player: Player)
	local rightFrame = hud:WaitForChild("Right")
	local customSpeedFrame = rightFrame:WaitForChild("CustomSpeed")
	local enterSpeedBox = customSpeedFrame:WaitForChild("EnterSpeed") :: TextBox
	local maxSpeedLabel = customSpeedFrame:WaitForChild("MaxSpeed") :: TextLabel

	HudAnimations.rememberBaseScale(customSpeedFrame)

	local isMaxSpeedMode = true
	local displayedSpeed = 0

	local function getMaxSpeed(): number
		return SpeedConfigs.GetMaxSpeed(getLevelFromData(DataLib.GetData()))
	end

	local function applySwimSpeed(speed: number)
		displayedSpeed = speed
		setCharacterSwimSpeed(player, speed)
	end

	local function updateDisplay()
		local maxSpeed = getMaxSpeed()
		maxSpeedLabel.Text = "MAX: " .. NumberFormatter.Format(maxSpeed)

		if isMaxSpeedMode then
			enterSpeedBox.Text = tostring(maxSpeed)
			applySwimSpeed(maxSpeed)
		end

		HudAnimations.pulse(maxSpeedLabel, 1.06, 0.2)
	end

	enterSpeedBox.Focused:Connect(function()
		HudAnimations.highlightTextBox(enterSpeedBox, true)
	end)

	enterSpeedBox.FocusLost:Connect(function()
		HudAnimations.highlightTextBox(enterSpeedBox, false)

		local maxSpeed = getMaxSpeed()
		local inputNum = tonumber(enterSpeedBox.Text)
		if not inputNum then
			inputNum = maxSpeed
		end

		if inputNum >= maxSpeed then
			inputNum = maxSpeed
			isMaxSpeedMode = true
		else
			inputNum = math.max(0, inputNum)
			isMaxSpeedMode = false
		end

		enterSpeedBox.Text = tostring(inputNum)
		if inputNum ~= displayedSpeed then
			applySwimSpeed(inputNum)
			HudAnimations.pulse(customSpeedFrame, nil, 0.22)
		end
	end)

	bindCharacterSwimSpeed(player, function()
		if isMaxSpeedMode then
			return getMaxSpeed()
		end
		return displayedSpeed
	end)

	DataLib.OnChanged(updateDisplay)
	updateDisplay()
end

local function setupSpeedPeakHUD(hud: Instance, player: Player)
	local rightFrame = hud:WaitForChild("Right")
	local speedPeakButton = rightFrame:WaitForChild("SpeedPeark") :: ImageButton
	local priceLabel = speedPeakButton:WaitForChild("Price") :: TextLabel
	local textLabel = speedPeakButton:WaitForChild("Text") :: TextLabel

	HudAnimations.rememberBaseScale(speedPeakButton)

	local currentTargetTier: ProductConfigs.SpeedPeakTier? = nil
	local wasVisible = speedPeakButton.Visible

	local function refreshButton()
		currentTargetTier = nil

		for _, tier in ProductConfigs.SpeedPeakTiers do
			if tier.Id == 0 then
				continue
			end

			local owned = DataLib.OwnsGamepass(tier.Key)
			if not owned then
				local ok, result = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, tier.Id)
				end)
				if ok and result then
					DataLib.SetGamepass(tier.Key, true)
					owned = true
				end
			end

			if not owned then
				currentTargetTier = tier
				break
			end
		end

		if currentTargetTier then
			local shouldAnimateIn = not wasVisible
			speedPeakButton.Visible = true
			textLabel.Text = "x" .. tostring(currentTargetTier.Level) .. " Speed"
			priceLabel.Text = "Loading..."

			if shouldAnimateIn then
				HudAnimations.slideIn(speedPeakButton, 14, 0.32)
			end
			wasVisible = true

			task.spawn(function()
				local tier = currentTargetTier
				if not tier then
					return
				end
				local success, info = pcall(function()
					return MarketplaceService:GetProductInfo(tier.Id, Enum.InfoType.GamePass)
				end)
				if success and info and currentTargetTier == tier then
					priceLabel.Text = "ONLY " .. ROBUX_PREFIX .. tostring(info.PriceInRobux)
				elseif currentTargetTier == tier then
					priceLabel.Text = "Error"
				end
			end)
		else
			if wasVisible then
				HudAnimations.pulse(speedPeakButton, 0.9, 0.15)
			end
			speedPeakButton.Visible = false
			wasVisible = false
		end
	end

	speedPeakButton.MouseButton1Click:Connect(function()
		HudAnimations.buttonPress(speedPeakButton, function()
			if currentTargetTier and currentTargetTier.Id ~= 0 then
				MarketplaceService:PromptGamePassPurchase(player, currentTargetTier.Id)
			end
		end)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(buyer, passId, purchased)
		if buyer ~= player or not purchased then
			return
		end
		for _, tier in ProductConfigs.SpeedPeakTiers do
			if tier.Id == passId then
				DataLib.SetGamepass(tier.Key, true)
				break
			end
		end
		task.delay(0.5, refreshButton)
	end)

	DataLib.OnGamepassChanged(function()
		task.defer(refreshButton)
	end)

	refreshButton()
end

function HUDController:KnitStart()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] HUDController: timed out waiting for PlayerGui.GUI.")
		return
	end

	local hud = gui:WaitForChild("HUD", 30)
	if not hud then
		warn("[iseesupes] HUDController: missing GUI.HUD.")
		return
	end

	task.spawn(setupWinsHUD, hud, player)
	task.spawn(setupSpeedShopHUD, hud, player)
	task.spawn(setupCustomSpeedHUD, hud, player)
	task.spawn(setupSpeedPeakHUD, hud, player)

	print("[iseesupes] HUDController ready.")
end

return HUDController

--!strict

-- Central HUD: wins, speed shop, custom swim speed, speed peak tiers.
-- Expects: PlayerGui → GUI → HUD (Left/Wins, Bottom/Speed, Right/CustomSpeed, Right/SpeedPeark)

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local LevelDesignConfigs = require(ReplicatedStorage.Shared.Configs.LevelDesignConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local CharacterMovementSpeed = require(ReplicatedStorage.Shared.Utils.CharacterMovementSpeed)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local HUDController = Knit.CreateController({ Name = "HUDController" })

local ROBUX_PREFIX = utf8.char(0xE002)
local SPEED_PEAK_DEBUG = false

local function speedPeakLog(...: any)
	if SPEED_PEAK_DEBUG then
		print("[iseesupes][SpeedPeark]", ...)
	end
end

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

local function setupWinsHUD(hud: Instance, player: Player)
	local leftFrame = hud:WaitForChild("Left")
	local winsFrame = leftFrame:WaitForChild("Wins")
	local winTextLabel = winsFrame:WaitForChild("Text") :: TextLabel
	local moreButton = winsFrame:WaitForChild("More") :: ImageButton

	HudAnimations.rememberBaseScale(winsFrame)

	local lastWins = 0

	local function updateWinsText()
		local wins = getWinsFromData(DataLib.GetData())
		local targetText = NumberFormatter.Format(wins)
		if wins == lastWins and winTextLabel.Text == targetText then
			return
		end

		HudAnimations.countUpText(winTextLabel, lastWins, wins, NumberFormatter.Format, 0.4)
		HudAnimations.pulse(winsFrame, nil, 0.28)
		lastWins = wins
	end

	moreButton.MouseButton1Click:Connect(function()
		local product = ProductConfigs.GetProductByKey("DoubleWins")
		if not product or product.Id == 0 then
			NotificationManager.show("2x Wins is not configured yet.", "Error")
			return
		end
		local data = DataLib.GetData()
		if data and data.OwnedDoubleWins == true then
			NotificationManager.show("You already have 2x Wins!", "Info")
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.Id)
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
		local buttonName = productInfo.ButtonName or ("Product" .. tostring(index))
		local button = speedShopFrame:FindFirstChild(buttonName) :: GuiButton?
		if not button then
			warn("[iseesupes] HUDController: missing Speed/" .. buttonName)
			continue
		end

		local textLabel = button:FindFirstChild("Text") or button:FindFirstChild("Amount")
		if not textLabel or not textLabel:IsA("TextLabel") then
			for _, desc in button:GetDescendants() do
				if (desc.Name == "Text" or desc.Name == "Amount") and desc:IsA("TextLabel") then
					textLabel = desc
					break
				end
			end
		end
		if textLabel then
			local isLastPack = index == #products
			textLabel.Text = ProductConfigs.FormatSpeedPackLabel(productInfo.Amount, isLastPack)
		end

		button.MouseButton1Click:Connect(function()
			if productInfo.Id == 0 then
				warn("[iseesupes] HUDController: Speed product not configured:", productInfo.Key)
				return
			end
			print("[iseesupes] SpeedPack purchase:", productInfo.Key, "id=", productInfo.Id, "amount=", productInfo.Amount)
			MarketplaceService:PromptProductPurchase(player, productInfo.Id)
		end)
	end

	print("[iseesupes] HUDController: wired", #products, "speed pack button(s)")
end

local function setupCustomSpeedHUD(hud: Instance, player: Player)
	local rightFrame = hud:WaitForChild("Right")
	local customSpeedFrame = rightFrame:WaitForChild("CustomSpeed")
	local enterSpeedBox = customSpeedFrame:WaitForChild("EnterSpeed") :: TextBox
	local maxSpeedLabel = customSpeedFrame:WaitForChild("MaxSpeed") :: TextLabel

	HudAnimations.rememberBaseScale(customSpeedFrame)

	local isMaxSpeedMode = true
	local displayedSpeed = 0

	local function formatSpeedText(speed: number): string
		return tostring(math.max(0, math.floor(speed + 0.5)))
	end

	local function getMaxSpeed(): number
		return CharacterMovementSpeed.getSpeedForData(player, DataLib.GetData())
	end

	local function applyCustomSpeed(baseSpeed: number)
		displayedSpeed = math.max(0, math.floor(baseSpeed + 0.5))
		CharacterMovementSpeed.setCustomSpeedCap(player, if isMaxSpeedMode then nil else displayedSpeed)
		CharacterMovementSpeed.applyToPlayer(player, DataLib.GetData())
	end

	local function updateDisplay()
		local maxSpeed = getMaxSpeed()
		maxSpeedLabel.Text = "MAX: " .. NumberFormatter.Format(maxSpeed)

		if isMaxSpeedMode then
			enterSpeedBox.Text = formatSpeedText(maxSpeed)
			applyCustomSpeed(maxSpeed)
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
		inputNum = math.floor(inputNum + 0.5)

		if inputNum >= maxSpeed then
			inputNum = maxSpeed
			isMaxSpeedMode = true
		else
			inputNum = math.max(0, inputNum)
			isMaxSpeedMode = false
		end

		enterSpeedBox.Text = formatSpeedText(inputNum)
		local previous = displayedSpeed
		applyCustomSpeed(inputNum)
		if inputNum ~= previous then
			HudAnimations.pulse(customSpeedFrame, nil, 0.22)
		end
	end)

	player.CharacterAdded:Connect(function()
		task.defer(function()
			applyCustomSpeed(if isMaxSpeedMode then getMaxSpeed() else displayedSpeed)
		end)
	end)

	player:GetAttributeChangedSignal(LevelDesignConfigs.Speed.MultiplierAttribute):Connect(function()
		applyCustomSpeed(if isMaxSpeedMode then getMaxSpeed() else displayedSpeed)
	end)
	player:GetAttributeChangedSignal(LevelDesignConfigs.Speed.OverrideAttribute):Connect(function()
		applyCustomSpeed(if isMaxSpeedMode then getMaxSpeed() else displayedSpeed)
	end)

	DataLib.OnChanged(updateDisplay)
	updateDisplay()
end

local function findFirstSpeedPeakTier(): ProductConfigs.SpeedPeakTier?
	for _, tier in ProductConfigs.SpeedPeakTiers do
		if tier.Id ~= 0 then
			return tier
		end
	end
	return nil
end

local function findSpeedPearkRoot(rightFrame: Instance): Instance?
	local direct = rightFrame:FindFirstChild("SpeedPeark")
	if direct then
		return direct
	end
	local list = rightFrame:FindFirstChild("List")
	if list then
		return list:FindFirstChild("SpeedPeark")
	end
	return nil
end

local function resolveSpeedPearkClickTarget(root: Instance): GuiButton?
	if root:IsA("GuiButton") then
		return root
	end
	for _, desc in root:GetDescendants() do
		if desc:IsA("GuiButton") then
			return desc
		end
	end
	return nil
end

--- Decorative labels/images steal clicks unless Active is false; frame needs Active + InputBegan.
local function prepareSpeedPearkHitTarget(root: Instance, clickButton: GuiButton?)
	if clickButton then
		clickButton.Active = true
		for _, desc in root:GetDescendants() do
			if desc:IsA("GuiObject") and desc ~= clickButton and not desc:IsA("GuiButton") then
				desc.Active = false
			end
		end
		return
	end
	if root:IsA("GuiObject") then
		root.Active = true
		for _, desc in root:GetDescendants() do
			if desc:IsA("GuiObject") and not desc:IsA("GuiButton") then
				desc.Active = false
			end
		end
	end
end

local function setupSpeedPeakHUD(hud: Instance, player: Player)
	local rightFrame = hud:WaitForChild("Right")
	local speedPeakRoot = findSpeedPearkRoot(rightFrame)
	if not speedPeakRoot then
		warn("[iseesupes] HUDController: missing HUD/Right/SpeedPeark (or Right/List/SpeedPeark).")
		return
	end

	local clickTarget = resolveSpeedPearkClickTarget(speedPeakRoot)
	prepareSpeedPearkHitTarget(speedPeakRoot, clickTarget)

	speedPeakLog(
		"bound",
		speedPeakRoot:GetFullName(),
		"class=",
		speedPeakRoot.ClassName,
		"clickTarget=",
		if clickTarget then clickTarget:GetFullName() else "InputBegan-on-root"
	)

	local priceLabel = speedPeakRoot:FindFirstChild("Price", true) :: TextLabel?
	local textLabel = speedPeakRoot:FindFirstChild("Text", true) :: TextLabel?
	if not priceLabel or not textLabel then
		warn("[iseesupes][SpeedPeark] missing Price or Text under", speedPeakRoot:GetFullName())
	end

	local scaleTarget: GuiObject = if clickTarget then clickTarget else (speedPeakRoot :: GuiObject)
	HudAnimations.rememberBaseScale(scaleTarget)

	local speedPeakGui = speedPeakRoot :: GuiObject
	local currentTargetTier: ProductConfigs.SpeedPeakTier? = nil
	local wasVisible = speedPeakGui.Visible

	local function promptSpeedPeakPurchase()
		local tier = currentTargetTier
		if not tier then
			speedPeakLog("click ignored: no currentTargetTier (refresh may not have run)")
			return
		end
		if tier.Id == 0 then
			speedPeakLog("click ignored: product Id is 0 for", tier.Key)
			return
		end

		speedPeakLog("PromptProductPurchase", tier.Key, "productId=", tier.Id)
		local ok, err = pcall(function()
			MarketplaceService:PromptProductPurchase(player, tier.Id)
		end)
		if not ok then
			warn("[iseesupes][SpeedPeark] PromptProductPurchase failed:", err)
		else
			speedPeakLog("PromptProductPurchase called OK")
		end
	end

	local function refreshButton()
		currentTargetTier = findFirstSpeedPeakTier()

		if currentTargetTier then
			local shouldAnimateIn = not wasVisible
			speedPeakGui.Visible = true
			if textLabel then
				textLabel.Text = "x" .. tostring(currentTargetTier.Level) .. " Speed"
			end
			if priceLabel then
				priceLabel.Text = "Loading..."
			end

			speedPeakLog("show tier", currentTargetTier.Key, "productId=", currentTargetTier.Id)

			if shouldAnimateIn then
				HudAnimations.slideIn(speedPeakGui, 14, 0.32)
			end
			wasVisible = true

			task.spawn(function()
				local tier = currentTargetTier
				if not tier then
					return
				end
				local success, infoOrErr = pcall(function()
					return MarketplaceService:GetProductInfo(tier.Id, Enum.InfoType.Product)
				end)
				if success and infoOrErr and currentTargetTier == tier then
					local info = infoOrErr :: { PriceInRobux: number? }
					if priceLabel then
						priceLabel.Text = "ONLY " .. ROBUX_PREFIX .. tostring(info.PriceInRobux)
					end
					speedPeakLog("price loaded", info.PriceInRobux, "robux for", tier.Id)
				elseif currentTargetTier == tier then
					if priceLabel then
						priceLabel.Text = "Error"
					end
					speedPeakLog("GetProductInfo failed for", tier.Id, infoOrErr)
				end
			end)
		else
			speedPeakLog("hide button (no SpeedPeak tier with product Id configured)")
			speedPeakGui.Visible = false
			wasVisible = false
		end
	end

	local function onSpeedPearkActivated()
		speedPeakLog("click/activate received")
		promptSpeedPeakPurchase()
	end

	if clickTarget then
		clickTarget.MouseButton1Click:Connect(onSpeedPearkActivated)
		clickTarget.Activated:Connect(onSpeedPearkActivated)
		speedPeakLog("wired MouseButton1Click + Activated on", clickTarget.Name)
	else
		speedPeakRoot.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				speedPeakLog("InputBegan ignored (gameProcessed)")
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				onSpeedPearkActivated()
			end
		end)
		speedPeakLog("wired InputBegan on root (no GuiButton child)")
	end

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

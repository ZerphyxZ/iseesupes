--!strict

-- HUD menu → Frames open/close (Y expand/collapse). Also wires Boost / Skipstage / AutoSwing HUD actions.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)

local Knit = require(ReplicatedStorage.Packages.Knit)
local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local FrameNavigator = require(script.Parent.Parent.Parent.Modules.FrameNavigator)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)

local AutoFlyConfigs = require(ReplicatedStorage.Shared.Configs.AutoFlyConfigs)

local AUTO_SWING_ATTR = "AutoSwingEnabled"

local GuiFrameController = Knit.CreateController({ Name = "GuiFrameController" })

local function bindProductButton(button: GuiButton, player: Player, productKey: string)
	button.MouseButton1Click:Connect(function()
		local product = ProductConfigs.GetProductByKey(productKey)
		if not product or product.Id == 0 then
			warn("[iseesupes] GuiFrameController: product not configured:", productKey)
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)
end

local function setupAutoFly(hud: Instance, player: Player)
	local left = hud:FindFirstChild("Left")
	local autoFlyRoot = if left then left:FindFirstChild("AutoFly") else nil
	if not autoFlyRoot then
		return
	end

	local visualFrame = autoFlyRoot:FindFirstChild("Frame")
	if not visualFrame or not visualFrame:IsA("GuiObject") then
		if autoFlyRoot:IsA("GuiObject") then
			visualFrame = autoFlyRoot
		else
			return
		end
	end

	local button = autoFlyRoot:FindFirstChild("Button", true)
	if not button or not button:IsA("GuiButton") then
		return
	end

	local label = visualFrame:FindFirstChild("Label")

	local attrName = AutoFlyConfigs.PlayerAttribute
	if typeof(attrName) ~= "string" or attrName == "" then
		attrName = "AutoFlyEnabled"
	end

	local colorOn = AutoFlyConfigs.FrameColorOn
	if typeof(colorOn) ~= "Color3" then
		colorOn = Color3.fromRGB(33, 84, 185)
	end
	local colorOff = AutoFlyConfigs.FrameColorOff
	if typeof(colorOff) ~= "Color3" then
		colorOff = Color3.fromRGB(206, 23, 6)
	end
	local labelOn = AutoFlyConfigs.LabelTextOn
	if typeof(labelOn) ~= "string" or labelOn == "" then
		labelOn = "Auto Fly ON"
	end
	local labelOff = AutoFlyConfigs.LabelTextOff
	if typeof(labelOff) ~= "string" or labelOff == "" then
		labelOff = "Auto Fly OFF"
	end

	local function applyVisual()
		local enabled = player:GetAttribute(attrName) == true
		if label and label:IsA("TextLabel") then
			label.Text = if enabled then labelOn else labelOff
		end
		visualFrame.BackgroundColor3 = if enabled then colorOn else colorOff
	end

	player:GetAttributeChangedSignal(attrName):Connect(applyVisual)
	applyVisual()

	-- Default ON, but restore the player's saved choice. Seed the attribute ONCE from the
	-- profile (default true when the field is unset). Re-seeding on later data changes would
	-- stomp the player's own toggles, so the flag latches after the first seed (or a toggle).
	local seeded = false
	local function seedFromSaved()
		if seeded then
			return
		end
		local data = DataLib.GetData()
		if not data then
			return
		end
		seeded = true
		local saved = data.AutoFlyEnabled
		player:SetAttribute(attrName, if typeof(saved) == "boolean" then saved else true)
	end
	seedFromSaved()
	DataLib.OnChanged(seedFromSaved)

	button.MouseButton1Click:Connect(function()
		seeded = true -- the player made a choice; never let a late seed override it
		local newValue = player:GetAttribute(attrName) ~= true
		player:SetAttribute(attrName, newValue)
		-- Persist the choice so it sticks across sessions.
		Knit.GetService("DataService"):SetAutoFlyEnabled(newValue):catch(warn)
	end)
end

local function setupAutoSwing(hud: Instance, player: Player)
	local left = hud:FindFirstChild("Left")
	local button = if left then left:FindFirstChild("AutoSwing") else nil
	if not button or not button:IsA("GuiButton") then
		return
	end

	local function applyVisual()
		local enabled = player:GetAttribute(AUTO_SWING_ATTR) == true
		button.BackgroundTransparency = if enabled then 0.2 else 0.5
	end

	player:GetAttributeChangedSignal(AUTO_SWING_ATTR):Connect(applyVisual)
	applyVisual()

	button.MouseButton1Click:Connect(function()
		player:SetAttribute(AUTO_SWING_ATTR, player:GetAttribute(AUTO_SWING_ATTR) ~= true)
	end)
end

local function setupRightHudProducts(hud: Instance, player: Player)
	local right = hud:FindFirstChild("Right")
	if not right then
		return
	end

	local boost = right:FindFirstChild("+1 Boost")
	if boost and boost:IsA("GuiButton") then
		bindProductButton(boost, player, HudConfigs.BoostProductKey)
	end

	-- Skip Stage is now handled by SkipStageController (per-stage product IDs)
end

function GuiFrameController:KnitStart()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] GuiFrameController: timed out waiting for PlayerGui.GUI.")
		return
	end

	local hud = gui:WaitForChild("HUD", 30)
	if not hud then
		warn("[iseesupes] GuiFrameController: missing HUD frame under GUI.")
		return
	end

	FrameNavigator.new(gui, hud)
	setupAutoFly(hud, player)
	setupAutoSwing(hud, player)
	setupRightHudProducts(hud, player)

	StudioLog.ready("GuiFrameController")
end

return GuiFrameController

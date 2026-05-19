--!strict

-- HUD menu → Frames open/close (Y expand/collapse). Also wires Boost / Skipstage / AutoSwing HUD actions.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local FrameNavigator = require(script.Parent.Parent.Parent.Modules.FrameNavigator)
local HudAnimations = require(script.Parent.Parent.Parent.Modules.HudAnimations)

local AUTO_SWING_ATTR = "AutoSwingEnabled"

local GuiFrameController = Knit.CreateController({ Name = "GuiFrameController" })

local function bindProductButton(button: GuiButton, player: Player, productKey: string)
	HudAnimations.rememberBaseScale(button)
	button.MouseButton1Click:Connect(function()
		HudAnimations.buttonPress(button, function()
			local product = ProductConfigs.GetProductByKey(productKey)
			if not product or product.Id == 0 then
				warn("[iseesupes] GuiFrameController: product not configured:", productKey)
				return
			end
			MarketplaceService:PromptProductPurchase(player, product.Id)
		end)
	end)
end

local function setupAutoSwing(hud: Instance, player: Player)
	local left = hud:FindFirstChild("Left")
	local button = if left then left:FindFirstChild("AutoSwing") else nil
	if not button or not button:IsA("GuiButton") then
		return
	end

	HudAnimations.rememberBaseScale(button)

	local function applyVisual()
		local enabled = player:GetAttribute(AUTO_SWING_ATTR) == true
		button.BackgroundTransparency = if enabled then 0.2 else 0.5
	end

	player:GetAttributeChangedSignal(AUTO_SWING_ATTR):Connect(applyVisual)
	applyVisual()

	button.MouseButton1Click:Connect(function()
		HudAnimations.buttonPress(button, function()
			player:SetAttribute(AUTO_SWING_ATTR, player:GetAttribute(AUTO_SWING_ATTR) ~= true)
		end)
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

	local skipStage = right:FindFirstChild("Skipstage")
	if skipStage and skipStage:IsA("GuiButton") then
		bindProductButton(skipStage, player, HudConfigs.SkipStageProductKey)
	end
end

function GuiFrameController:KnitStart()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[iseesupes] GuiFrameController: timed out waiting for PlayerGui.GUI.")
		return
	end

	local hud = playerGui:WaitForChild("HUD", 30) or gui:FindFirstChild("HUD")
	if not hud then
		warn("[iseesupes] GuiFrameController: missing HUD ScreenGui (PlayerGui.HUD or GUI.HUD).")
		return
	end

	FrameNavigator.new(gui, hud)
	setupAutoSwing(hud, player)
	setupRightHudProducts(hud, player)

	print("[iseesupes] GuiFrameController ready.")
end

return GuiFrameController

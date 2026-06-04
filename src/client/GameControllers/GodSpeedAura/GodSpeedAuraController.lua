--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GodSpeedAuraConfigs = require(ReplicatedStorage.Shared.Configs.GodSpeedAuraConfigs)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local GodSpeedAuraController = Knit.CreateController({ Name = "GodSpeedAuraController" })

local player = Players.LocalPlayer
local touchConn: RBXScriptConnection? = nil
local lastTouchAt = 0

local function promptPurchase(productId: number, displayName: string)
	if productId == 0 then
		NotificationManager.show(displayName .. " is not configured yet.", "Error")
		return
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, productId)
	end)
	if not ok then
		warn("[iseesupes][GodSpeedAura] PromptProductPurchase failed:", err)
		NotificationManager.show("Could not open purchase window.", "Error")
	end
end

local function bindClientTouch(touch: BasePart)
	if touchConn then
		touchConn:Disconnect()
		touchConn = nil
	end

	touch.CanTouch = true
	touchConn = touch.Touched:Connect(function(hit: BasePart)
		if not hit or not hit.Parent then
			return
		end
		local character = hit:FindFirstAncestorOfClass("Model")
		if not character or Players:GetPlayerFromCharacter(character) ~= player then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end

		local now = os.clock()
		if now - lastTouchAt < GodSpeedAuraConfigs.TouchDebounce then
			return
		end
		lastTouchAt = now

		promptPurchase(GodSpeedAuraConfigs.ProductId, GodSpeedAuraConfigs.DisplayName)
	end)
end

local function scanAndBindClient()
	local map = MapWorld.getMapFolder()
	if not map then
		return false
	end

	local model = map:FindFirstChild(GodSpeedAuraConfigs.ModelName, true)
	if not model or not model:IsA("Model") then
		return false
	end

	local touch = model:FindFirstChild(GodSpeedAuraConfigs.TouchPartName, true)
	if not touch or not touch:IsA("BasePart") then
		for _, desc in model:GetDescendants() do
			if desc.Name == GodSpeedAuraConfigs.TouchPartName and desc:IsA("BasePart") then
				touch = desc
				break
			end
		end
	end

	if touch and touch:IsA("BasePart") then
		bindClientTouch(touch)
		return true
	end

	return false
end

function GodSpeedAuraController:KnitStart()
	local GodSpeedAuraService = Knit.GetService("GodSpeedAuraService")

	GodSpeedAuraService.RequestProductPrompt:Connect(function(productId: number, displayName: string)
		promptPurchase(productId, displayName)
	end)

	GodSpeedAuraService.RunBuffGranted:Connect(function()
		NotificationManager.show(
			GodSpeedAuraConfigs.DisplayName .. " active! Infinite Thrust + boosted speed for this run.",
			"Success"
		)
	end)

	task.spawn(function()
		for attempt = 1, 30 do
			if scanAndBindClient() then
				break
			end
			task.wait(2)
		end
	end)

	print("[iseesupes] GodSpeedAuraController ready.")
end

return GodSpeedAuraController

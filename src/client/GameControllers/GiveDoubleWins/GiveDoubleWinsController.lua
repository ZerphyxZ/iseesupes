--!strict

-- Map.GiveDounleWins Button1–9 Touch → 2x Wins developer product.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local GiveDoubleWinsController = Knit.CreateController({ Name = "GiveDoubleWinsController" })

local player = Players.LocalPlayer

function GiveDoubleWinsController:KnitStart()
	local GiveDoubleWinsService = Knit.GetService("GiveDoubleWinsService")

	GiveDoubleWinsService.RequestProductPrompt:Connect(
		function(productId: number, displayName: string, alreadyOwned: boolean?)
			if alreadyOwned == true then
				NotificationManager.show("You already have " .. displayName .. "!", "Info")
				return
			end
			if productId == 0 then
				NotificationManager.show(displayName .. " is not configured yet.", "Error")
				return
			end
			local ok, err = pcall(function()
				MarketplaceService:PromptProductPurchase(player, productId)
			end)
			if not ok then
				warn("[iseesupes][GiveDoubleWins] PromptProductPurchase failed:", err)
				NotificationManager.show("Could not open purchase window.", "Error")
			end
		end
	)

	GiveDoubleWinsService.PurchaseGranted:Connect(function(grantAmount: number)
		NotificationManager.show("+" .. tostring(grantAmount) .. " Wins!", "Success")
	end)

	StudioLog.ready("GiveDoubleWinsController")
end

return GiveDoubleWinsController

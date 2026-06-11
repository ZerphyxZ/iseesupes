--!strict

-- Gamepass shop (GUI.Frames.PassShop, opened by HUD.Left.Shop via FrameNavigator).
-- Cards are named by pass key (DoubleSpeed, VIP). This controller fills live
-- prices from the Marketplace, tracks owned state, and prompts purchases —
-- including the VIP upsell line inside the OfflineReward popup.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)

local GamepassShopController = Knit.CreateController({ Name = "GamepassShopController" })

function GamepassShopController:KnitStart()
	local MonetizationService = Knit.GetService("MonetizationService")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	local frames = gui and gui:WaitForChild("Frames", 30)
	if not frames then
		return
	end

	local shopFrame = frames:WaitForChild("PassShop", 15) :: Frame?
	if not shopFrame then
		warn("[iseesupes] GamepassShopController: GUI.Frames.PassShop missing (build it in Studio).")
		return
	end
	local background = shopFrame:WaitForChild("Background") :: Frame

	local owned: { [string]: boolean } = {}

	local function applyOwned(key: string)
		local card = background:FindFirstChild(key)
		if not card then
			return
		end
		local isOwned = owned[key] == true
		local overlay = card:FindFirstChild("Owned") :: ImageLabel?
		if overlay then
			overlay.Visible = isOwned
		end
		local buy = card:FindFirstChild("BuyButton")
		local price = buy and buy:FindFirstChild("Price") :: TextLabel?
		if price and isOwned then
			price.Text = "OWNED"
		end
	end

	local function promptPass(key: string)
		if owned[key] then
			return
		end
		local pass = ProductConfigs.GetGamepassByKey(key)
		if not pass or pass.Id == 0 then
			return
		end
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, pass.Id)
		end)
	end

	for _, key in { "DoubleSpeed", "VIP" } do
		local card = background:FindFirstChild(key) :: ImageButton?
		if not card then
			continue
		end

		local pass = ProductConfigs.GetGamepassByKey(key)
		local buy = card:FindFirstChild("BuyButton") :: TextButton?
		local price = buy and buy:FindFirstChild("Price") :: TextLabel?

		-- Live price from the marketplace (async; falls back to "Buy").
		if price and pass and pass.Id ~= 0 then
			task.spawn(function()
				local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, pass.Id, Enum.InfoType.GamePass)
				if ok and info and typeof(info.PriceInRobux) == "number" and not owned[key] then
					price.Text = "R$ " .. info.PriceInRobux
				elseif not owned[key] then
					price.Text = "Buy"
				end
			end)
		elseif price then
			price.Text = "Buy"
		end

		card.MouseButton1Click:Connect(function()
			promptPass(key)
		end)
		if buy then
			buy.MouseButton1Click:Connect(function()
				promptPass(key)
			end)
		end
	end

	-- Owned state: initial snapshot + live updates after purchases.
	MonetizationService.GamepassUpdated:Connect(function(key: string, isOwned: boolean)
		owned[key] = isOwned
		applyOwned(key)
	end)
	MonetizationService:GetGamepassSnapshot()
		:andThen(function(snapshot: { [string]: boolean })
			for key, isOwned in snapshot do
				owned[key] = isOwned
				applyOwned(key)
			end
		end)
		:catch(function() end)

	-- VIP upsell inside the OfflineReward popup.
	task.spawn(function()
		local offlineFrame = frames:WaitForChild("OfflineReward", 15)
		local offlineBg = offlineFrame and offlineFrame:FindFirstChild("Background")
		local upsell = offlineBg and offlineBg:FindFirstChild("VipUpsell") :: TextButton?
		if upsell then
			upsell.MouseButton1Click:Connect(function()
				promptPass("VIP")
			end)
			-- Hide the line for players who already own VIP.
			MonetizationService.GamepassUpdated:Connect(function(key: string, isOwned: boolean)
				if key == "VIP" then
					upsell.Visible = not isOwned
				end
			end)
		end
	end)

	print("[iseesupes] GamepassShopController ready.")
end

return GamepassShopController

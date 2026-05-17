--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)

local MonetizationService = Knit.CreateService({
	Name = "MonetizationService",
	Client = {
		GamepassUpdated = Knit.CreateSignal(),
	},
})

-- gpCache[userId][passId] = owned
local gpCache: { [number]: { [number]: boolean } } = {}

local DataService: any = nil

local function getProductById(productId: number): any?
	for _, product in ProductConfigs.DeveloperProducts do
		if product.Id ~= 0 and product.Id == productId then
			return product
		end
	end
	return nil
end

local function getGamepassById(passId: number): any?
	for _, pass in ProductConfigs.Gamepasses do
		if pass.Id ~= 0 and pass.Id == passId then
			return pass
		end
	end
	return nil
end

local function getGamepassByKey(key: string): any?
	for _, pass in ProductConfigs.Gamepasses do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

local function setGamepassOwned(player: Player, passId: number, owned: boolean)
	local uid = player.UserId
	if not gpCache[uid] then
		gpCache[uid] = {}
	end
	gpCache[uid][passId] = owned

	local cfg = getGamepassById(passId)
	if cfg then
		MonetizationService.Client.GamepassUpdated:Fire(player, cfg.Key, owned)
	end
end

local function checkGamepasses(player: Player)
	local uid = player.UserId
	if not gpCache[uid] then
		gpCache[uid] = {}
	end

	for _, pass in ProductConfigs.Gamepasses do
		if pass.Id == 0 then
			continue
		end

		local owned = gpCache[uid][pass.Id]
		if owned == nil then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, uid, pass.Id)
			if ok then
				owned = result
				gpCache[uid][pass.Id] = owned
			else
				owned = false
			end
		end

		MonetizationService.Client.GamepassUpdated:Fire(player, pass.Key, owned == true)
	end
end

function MonetizationService:PlayerOwnsGamepass(player: Player, key: string): boolean
	local cfg = getGamepassByKey(key)
	if not cfg or cfg.Id == 0 then
		return false
	end
	local cache = gpCache[player.UserId]
	return cache ~= nil and cache[cfg.Id] == true
end

function MonetizationService.Client:GetGamepassSnapshot(player: Player): { [string]: boolean }
	local snapshot: { [string]: boolean } = {}
	for _, pass in ProductConfigs.Gamepasses do
		snapshot[pass.Key] = MonetizationService:PlayerOwnsGamepass(player, pass.Key)
	end
	return snapshot
end

function MonetizationService:KnitStart()
	DataService = Knit.GetService("DataService")

	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkGamepasses, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(checkGamepasses, player)
	end

	MarketplaceService.ProcessReceipt = function(info: { PlayerId: number, ProductId: number })
		local player = Players:GetPlayerByUserId(info.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local profile = DataService:GetProfile(player)
		if not profile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local product = getProductById(info.ProductId)
		if product then
			profile.Data.Coins += product.GrantCoins
			DataService:Replicate(player)
			print("[iseesupes] Granted", product.GrantCoins, "coins to", player.Name)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		warn("[iseesupes] Unknown product id:", info.ProductId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		if not bought then
			return
		end
		setGamepassOwned(player, passId, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		gpCache[player.UserId] = nil
	end)
end

return MonetizationService

--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)

local MonetizationService = Knit.CreateService({
	Name = "MonetizationService",
	Client = {
		GamepassUpdated = Knit.CreateSignal(),
	},
})

-- gpCache[userId][passId] = owned
local gpCache: { [number]: { [number]: boolean } } = {}

local DataService: any = nil
local RebirthService: any = nil

local function getProductById(productId: number): any?
	return ProductConfigs.GetProductById(productId)
end

local function getGamepassById(passId: number): any?
	for _, pass in ProductConfigs.Gamepasses do
		if pass.Id ~= 0 and pass.Id == passId then
			return pass
		end
	end
	for _, tier in ProductConfigs.SpeedPeakTiers do
		if tier.Id ~= 0 and tier.Id == passId then
			return tier
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
	for _, tier in ProductConfigs.SpeedPeakTiers do
		if tier.Key == key then
			return tier
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

	local function checkPass(key: string, passId: number)
		local owned = gpCache[uid][passId]
		if owned == nil then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, uid, passId)
			if ok then
				owned = result
				gpCache[uid][passId] = owned
			else
				owned = false
			end
		end
		MonetizationService.Client.GamepassUpdated:Fire(player, key, owned == true)
	end

	for _, pass in ProductConfigs.Gamepasses do
		if pass.Id ~= 0 then
			checkPass(pass.Key, pass.Id)
		end
	end
	for _, tier in ProductConfigs.SpeedPeakTiers do
		if tier.Id ~= 0 then
			checkPass(tier.Key, tier.Id)
		end
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
	for _, tier in ProductConfigs.SpeedPeakTiers do
		snapshot[tier.Key] = MonetizationService:PlayerOwnsGamepass(player, tier.Key)
	end
	return snapshot
end

function MonetizationService:KnitStart()
	DataService = Knit.GetService("DataService")
	RebirthService = Knit.GetService("RebirthService")

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

		local speedProduct = ProductConfigs.GetSpeedProductById(info.ProductId)
		if speedProduct then
			local grant = speedProduct.Amount
			if grant > 0 then
				local data = profile.Data
				data.Speed = (data.Speed or 0) + grant
				SpeedConfigs.SyncLevelFromSpeed(data)
				DataService:Replicate(player)
				print("[iseesupes] Granted", grant, "speed XP to", player.Name)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local product = getProductById(info.ProductId)
		if product then
			if product.GrantLevels and product.GrantLevels > 0 then
				local data = profile.Data
				local targetLevel = (data.Level or 1) + product.GrantLevels
				data.Speed = math.max(data.Speed or 0, SpeedConfigs.GetExperienceForLevel(targetLevel))
				SpeedConfigs.SyncLevelFromSpeed(data)
				DataService:Replicate(player)
				print("[iseesupes] Granted", product.GrantLevels, "levels to", player.Name)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end

			if product.GrantRebirth == true then
				local ok = RebirthService:PerformRebirth(player, true)
				if ok then
					print("[iseesupes] Skip rebirth granted to", player.Name)
				else
					warn("[iseesupes] Skip rebirth failed for", player.Name)
				end
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end

			if product.GrantCoins > 0 then
				profile.Data.Coins += product.GrantCoins
				DataService:Replicate(player)
				print("[iseesupes] Granted", product.GrantCoins, "coins to", player.Name)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local trail = TrailConfigs.GetTrailByProductId(info.ProductId)
		if trail then
			local data = profile.Data
			if not data.OwnedTrails then
				data.OwnedTrails = {}
			end
			if data.OwnedTrails[trail.ID] then
				warn("[iseesupes] Trail already owned:", trail.ID, player.Name)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			data.OwnedTrails[trail.ID] = true
			DataService:Replicate(player)
			print("[iseesupes] Granted trail", trail.ID, "to", player.Name)
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

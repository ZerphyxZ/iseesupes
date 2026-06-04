--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local AuraShopConfigs = require(ReplicatedStorage.Shared.Configs.AuraShopConfigs)
local GodSpeedAuraConfigs = require(ReplicatedStorage.Shared.Configs.GodSpeedAuraConfigs)
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
local ThrustUpgradeService: any = nil
local AuraShopService: any = nil
local GiveDoubleWinsService: any = nil
local GodSpeedAuraService: any = nil
local SkipStageService: any = nil
local BoostService: any = nil

local function getProductById(productId: number): any?
	return ProductConfigs.GetProductById(productId)
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

local function grantSpeedPeakTier(player: Player, profile: any, tier: ProductConfigs.SpeedPeakTier): boolean
	local data = profile.Data
	-- Developer product: grant every purchase (no permanent "owned" flag).
	local levels = tier.Level
	if levels > 0 then
		local targetLevel = (data.Level or 1) + levels
		data.Speed = math.max(data.Speed or 0, SpeedConfigs.GetExperienceForLevel(targetLevel))
		SpeedConfigs.SyncLevelFromSpeed(data)
	end

	DataService:Replicate(player)
	print("[iseesupes] SpeedPeak granted:", tier.Key, "levels=", levels, "to", player.Name)
	return true
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
end

function MonetizationService:PlayerOwnsGamepass(player: Player, key: string): boolean
	local cfg = getGamepassByKey(key)
	if not cfg or cfg.Id == 0 then
		return false
	end
	local cache = gpCache[player.UserId]
	return cache ~= nil and cache[cfg.Id] == true
end

function MonetizationService:PlayerOwnsDoubleWins(player: Player): boolean
	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		return false
	end
	return profile.Data.OwnedDoubleWins == true
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
	RebirthService = Knit.GetService("RebirthService")
	ThrustUpgradeService = Knit.GetService("ThrustUpgradeService")
	AuraShopService = Knit.GetService("AuraShopService")
	GiveDoubleWinsService = Knit.GetService("GiveDoubleWinsService")
	GodSpeedAuraService = Knit.GetService("GodSpeedAuraService")
	SkipStageService = Knit.GetService("SkipStageService")
	BoostService = Knit.GetService("BoostService")

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

		if info.ProductId == GodSpeedAuraConfigs.ProductId and GodSpeedAuraConfigs.ProductId ~= 0 then
			if GodSpeedAuraService and GodSpeedAuraService:GrantRunBuff(player) then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			warn("[iseesupes][GodSpeedAura] grant failed for", player.Name)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local auraOffer = AuraShopConfigs.GetOfferByProductId(info.ProductId)
		if auraOffer then
			if AuraShopService and AuraShopService:GrantAura(player, auraOffer.Key) then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local speedPeak = ProductConfigs.GetSpeedPeakTierById(info.ProductId)
		if speedPeak then
			print("[iseesupes][SpeedPeark] ProcessReceipt", player.Name, speedPeak.Key, "productId=", info.ProductId)
			if grantSpeedPeakTier(player, profile, speedPeak) then
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			warn("[iseesupes][SpeedPeark] grant failed for", player.Name, speedPeak.Key)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local treadmillProduct = ProductConfigs.GetTreadmillProductById(info.ProductId)
		if treadmillProduct then
			local data = profile.Data
			if typeof(data.OwnedTreadmills) ~= "table" then
				data.OwnedTreadmills = {}
			end
			if data.OwnedTreadmills[treadmillProduct.TierKey] then
				print("[iseesupes] Treadmill already owned:", treadmillProduct.TierKey, player.Name)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			data.OwnedTreadmills[treadmillProduct.TierKey] = true
			DataService:Replicate(player)
			print("[iseesupes] Granted treadmill tier", treadmillProduct.TierKey, "to", player.Name)
			return Enum.ProductPurchaseDecision.PurchaseGranted
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

		local skipStageProduct = ProductConfigs.GetSkipStageProductById(info.ProductId)
		if skipStageProduct then
			if SkipStageService and SkipStageService:TeleportToStage(player, skipStageProduct.Stage) then
				print("[iseesupes] SkipStage: teleported", player.Name, "to Stage", skipStageProduct.Stage)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			warn("[iseesupes] SkipStage: teleport failed for", player.Name, skipStageProduct.Stage)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local product = getProductById(info.ProductId)
		if product then
			if product.GrantDoubleWins == true then
				local data = profile.Data
				if data.OwnedDoubleWins == true then
					print("[iseesupes] DoubleWins already owned:", player.Name)
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				data.OwnedDoubleWins = true
				DataService:Replicate(player)
				if GiveDoubleWinsService then
					GiveDoubleWinsService:FulfillPurchase(player)
				end
				print("[iseesupes] Granted 2x Wins to", player.Name)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end

			if product.GrantBoost == true then
				if BoostService and BoostService:GrantBoost(player) then
					print("[iseesupes] Granted +1 Boost to", player.Name)
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				warn("[iseesupes] Boost grant failed for", player.Name)
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

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
				local preserve = product.PreserveProgressOnRebirth == true
				local ok = RebirthService:PerformRebirth(player, true, preserve)
				if ok then
					print("[iseesupes] Rebirth product granted to", player.Name, "preserveProgress=", preserve)
					return Enum.ProductPurchaseDecision.PurchaseGranted
				end
				warn("[iseesupes] Rebirth product failed for", player.Name, product.Key)
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end

			if product.GrantCoins > 0 then
				profile.Data.Coins += product.GrantCoins
				DataService:Replicate(player)
				print("[iseesupes] Granted", product.GrantCoins, "coins to", player.Name)
			end
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		if ThrustUpgradeService:GrantTierFromProduct(player, info.ProductId) then
			DataService:Replicate(player)
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

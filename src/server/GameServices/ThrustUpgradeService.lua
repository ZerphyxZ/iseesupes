--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local ThrustUpgradeConfigs = require(ReplicatedStorage.Shared.Configs.ThrustUpgradeConfigs)

local ThrustConfigs = SpeedConfigs.Thrust

local ThrustUpgradeService = Knit.CreateService({
	Name = "ThrustUpgradeService",
	Client = {
		UpgradeResult = Knit.CreateSignal(), -- (result: string, tier: number)
	},
})

local DataService: any = nil

local function getCurrentTier(data: any): number
	if type(data.ThrustUpgradeTier) == "number" then
		return data.ThrustUpgradeTier
	end
	return 0
end

local function grantTier(player: Player, tier: number): string
	local tierCfg = ThrustUpgradeConfigs.Tiers[tier]
	if not tierCfg then
		return "InvalidTier"
	end

	local data = DataService:GetData(player)
	if not data then
		return "NoData"
	end

	local currentTier = getCurrentTier(data)

	if currentTier >= tier then
		return "AlreadyOwned"
	end

	if tier ~= currentTier + 1 then
		return "MustBuyPrevious"
	end

	data.ThrustUpgradeTier = tier
	local newMax = ThrustConfigs.BaseMaxFuel + ThrustUpgradeConfigs.GetTotalBonusForTier(tier)
	DataService:ApplyUpgradedMax(player, newMax)

	print("[iseesupes] ThrustUpgradeService:", player.Name, "granted tier", tier, "→ ThrustMax =", newMax)
	return "Success"
end

function ThrustUpgradeService:GrantTierFromProduct(player: Player, productId: number): boolean
	local tier = ThrustUpgradeConfigs.GetTierByProductId(productId)
	if not tier then
		return false
	end

	local result = grantTier(player, tier)
	if result == "Success" then
		ThrustUpgradeService.Client.UpgradeResult:Fire(player, "Success", tier)
		return true
	end

	if result == "AlreadyOwned" then
		-- Receipt may retry; tier already applied — treat as granted.
		return true
	end

	warn("[iseesupes] ThrustUpgradeService: product grant failed:", player.Name, productId, result)
	return false
end

function ThrustUpgradeService.Client:BuyUpgrade(player: Player, tier: number): ()
	if typeof(tier) ~= "number" then
		return
	end
	tier = math.floor(tier)

	local tierCfg = ThrustUpgradeConfigs.Tiers[tier]
	if not tierCfg then
		ThrustUpgradeService.Client.UpgradeResult:Fire(player, "InvalidTier", tier)
		return
	end

	local data = DataService:GetData(player)
	if not data then
		return
	end

	local currentTier = getCurrentTier(data)

	if currentTier >= tier then
		ThrustUpgradeService.Client.UpgradeResult:Fire(player, "AlreadyOwned", tier)
		return
	end

	if tier ~= currentTier + 1 then
		ThrustUpgradeService.Client.UpgradeResult:Fire(player, "MustBuyPrevious", tier)
		return
	end

	if not DataService:TrySpendWins(player, tierCfg.WinCost) then
		ThrustUpgradeService.Client.UpgradeResult:Fire(player, "NotEnoughWins", tier)
		return
	end

	local result = grantTier(player, tier)
	ThrustUpgradeService.Client.UpgradeResult:Fire(player, result, tier)
end

function ThrustUpgradeService:KnitStart()
	DataService = Knit.GetService("DataService")

	Players.PlayerRemoving:Connect(function(_player)
		-- nothing to clean up — state lives in DataService profile
	end)

	print("[iseesupes] ThrustUpgradeService ready.")
end

return ThrustUpgradeService

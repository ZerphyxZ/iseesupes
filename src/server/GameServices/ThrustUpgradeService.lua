--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local RebirthConfigs = require(ReplicatedStorage.Shared.Configs.RebirthConfigs)
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

	-- Allow repeated purchases: track counts per tier
	data.ThrustUpgradePurchases = data.ThrustUpgradePurchases or {}
	data.ThrustUpgradePurchases[tier] = (data.ThrustUpgradePurchases[tier] or 0) + 1

	local totalBonus = ThrustUpgradeConfigs.GetTotalBonusFromPurchases(data)
	local rebirthBonus = RebirthConfigs.GetThrustBonus(data.Rebirths)
	local newMax = ThrustConfigs.ClampMax(ThrustConfigs.BaseMaxFuel + totalBonus + rebirthBonus)
	data.ThrustUpgradeTier = math.max(getCurrentTier(data), tier)
	DataService:ApplyUpgradedMax(player, newMax)
	DataService:ForceSave(player)

	print(
		"[iseesupes] ThrustUpgradeService:",
		player.Name,
		"granted tier",
		tier,
		"count =",
		data.ThrustUpgradePurchases[tier],
		"→ ThrustMax =",
		newMax
	)
	return "Success"
end

--- Grant a tier without spending Wins or Robux (Starter Pack bundle, promos).
function ThrustUpgradeService:GrantFreeTier(player: Player, tier: number): boolean
	local result = grantTier(player, tier)
	if result == "Success" then
		ThrustUpgradeService.Client.UpgradeResult:Fire(player, "Success", tier)
		return true
	end
	warn("[iseesupes] ThrustUpgradeService: free tier grant failed:", player.Name, tier, result)
	return false
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

	-- Receipt retries: treat AlreadyOwned as granted (shouldn't occur now)
	if result == "AlreadyOwned" then
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

	-- Already at the thrust ceiling? Refuse BEFORE charging — don't take wins for fuel the
	-- cap won't grant. This is what bounds the otherwise-infinite repeat Tier-1 buys.
	local packBonus = ThrustUpgradeConfigs.GetTotalBonusFromPurchases(data)
	local rebirthBonus = RebirthConfigs.GetThrustBonus(data.Rebirths)
	if ThrustConfigs.IsAtMaxCap(packBonus, rebirthBonus) then
		ThrustUpgradeService.Client.UpgradeResult:Fire(player, "MaxThrustReached", tier)
		return
	end

	-- No "AlreadyOwned" check — allow repeat purchases (bounded by the cap above)
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

	StudioLog.ready("ThrustUpgradeService")
end

return ThrustUpgradeService

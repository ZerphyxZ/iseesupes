--!strict

-- 3-tier Thrust tank upgrades from the UpgradeShop (Wins and/or Developer Products).
-- Each tier permanently increases the player's ThrustMax by FuelBonus (cumulative).
-- Tiers must be bought in sequence: own tier N-1 before buying tier N.
-- ProductId = Creator Hub developer product (Thrust Pack 1–3). 0 = Robux buy disabled in UI.

export type ThrustUpgradeTier = {
	WinCost: number,
	FuelBonus: number,
	ProductId: number,
}

local ThrustUpgradeConfigs = {
	Tiers = {
		[1] = { WinCost = 30,  FuelBonus = 50,  ProductId = 3602350603 }, -- Thrust Pack 1 (19 R$)
		[2] = { WinCost = 80,  FuelBonus = 100, ProductId = 3602350672 }, -- Thrust Pack 2 (39 R$)
		[3] = { WinCost = 300, FuelBonus = 150, ProductId = 3602350745 }, -- Thrust Pack 3 (109 R$)
	} :: { [number]: ThrustUpgradeTier },

	-- Workspace paths
	FolderName     = "UpgradeShop",
	TouchModelName = "UTouch",
	TouchPartName  = "Touch",

	TouchDebounce  = 2,

	--- When true, BuyRobux stays visible even if ProductId is 0 (shows "—", click disabled).
	ShowRobuxWhenUnconfigured = true,
}

local byProductId: { [number]: number } = {}

local function rebuildProductIndex()
	table.clear(byProductId)
	for tier, cfg in ThrustUpgradeConfigs.Tiers do
		if cfg.ProductId ~= 0 then
			byProductId[cfg.ProductId] = tier
		end
	end
end

rebuildProductIndex()

function ThrustUpgradeConfigs.GetTotalBonusForTier(tier: number): number
	local total = 0
	for i = 1, math.min(tier, 3) do
		total += ThrustUpgradeConfigs.Tiers[i].FuelBonus
	end
	return total
end

function ThrustUpgradeConfigs.GetProductIdForTier(tier: number): number
	local cfg = ThrustUpgradeConfigs.Tiers[tier]
	return if cfg then cfg.ProductId else 0
end

function ThrustUpgradeConfigs.GetTierByProductId(productId: number): number?
	return byProductId[productId]
end

return ThrustUpgradeConfigs

--!strict

-- 3-tier Thrust tank upgrades from the UpgradeShop (Wins and/or Developer Products).
-- Each tier permanently increases the player's ThrustMax by FuelBonus (cumulative).
-- Tiers must be bought in sequence: own tier N-1 before buying tier N.
-- ProductId = 0: Robux button still shows in UI (placeholder price) but purchase is disabled
-- until you paste Developer Product IDs from Creator Dashboard.

export type ThrustUpgradeTier = {
	WinCost: number,
	FuelBonus: number,
	ProductId: number,
}

local ThrustUpgradeConfigs = {
	Tiers = {
		[1] = { WinCost = 50,  FuelBonus = 50,  ProductId = 0 },
		[2] = { WinCost = 200, FuelBonus = 100, ProductId = 0 },
		[3] = { WinCost = 750, FuelBonus = 150, ProductId = 0 },
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

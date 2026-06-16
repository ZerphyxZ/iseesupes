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
	-- Tuned against measured stage lengths: one tank should cover ~45-70% of the
	-- player's current stage, with each pack a felt spike the NEXT stage re-humbles.
	-- Win pacing: pack 1 ≈ stage 3-4, pack 2 ≈ stage 5-6, pack 3 ≈ stage 7-8.
	-- Win prices rebalanced 2026-06-14 (~3.3x) to the inflated win economy; pacing kept.
	-- FuelBonus / ProductId (the Robux paid value) intentionally unchanged.
	Tiers = {
		[1] = { WinCost = 100,  FuelBonus = 40,  ProductId = 3602350603 }, -- Thrust Pack 1 (19 R$)
		[2] = { WinCost = 300,  FuelBonus = 80,  ProductId = 3602350672 }, -- Thrust Pack 2 (39 R$)
		[3] = { WinCost = 1000, FuelBonus = 160, ProductId = 3602350745 }, -- Thrust Pack 3 (109 R$)
	} :: { [number]: ThrustUpgradeTier },

	-- Workspace paths
	FolderName     = "UpgradeShop",
	TouchModelName = "UTouch",
	TouchPartName  = "Touch",
	--- Parts checked for HRP zone + .Touched (Mesh = visible pad players stand on).
	TouchZonePartNames = { "Touch", "Mesh" },

	TouchDebounce  = 2,

	--- HRP zone around UpgradeShop Touch (covers tall / aura / morph suits when .Touched misses).
	TouchZoneHorizontalPadding = 10,
	TouchZoneMaxHeightAbove = 18,
	TouchZoneMinHeightBelow = -8,

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

--- Total fuel bonus from all recorded pack purchases (repeatable buys included).
function ThrustUpgradeConfigs.GetTotalBonusFromPurchases(data: any): number
	local purchases = data and data.ThrustUpgradePurchases
	if type(purchases) ~= "table" then
		return 0
	end
	local total = 0
	for tier, cfg in ThrustUpgradeConfigs.Tiers do
		local count = purchases[tier]
		if type(count) == "number" and count > 0 then
			total += (cfg.FuelBonus or 0) * math.floor(count)
		end
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

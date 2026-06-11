--!strict

-- Paste Creator Dashboard IDs here. Id = 0 means disabled until configured.

local ProductConfigs = {}

export type DeveloperProduct = {
	Id: number,
	Key: string,
	GrantCoins: number,
	GrantRebirth: boolean?,
	--- When true with GrantRebirth, level and speed are not reset (Skip Rebirth / "Lose Nothing!").
	PreserveProgressOnRebirth: boolean?,
	GrantLevels: number?,
	--- Permanent 2x wins from stage-end buttons (GiveDounleWins).
	GrantDoubleWins: boolean?,
	--- Temporary boost: double thrust + speed for 1 run.
	GrantBoost: boolean?,
}

export type Gamepass = {
	Id: number,
	Key: string,
}

export type SpeedProduct = {
	Id: number,
	Key: string,
	--- Speed XP granted on purchase (matches Spidey-style packs: 100k → 100M).
	Amount: number,
	--- HUD button name under GUI.HUD.Bottom.Speed (Product1 … Product4).
	ButtonName: string?,
}

export type SpeedPeakTier = {
	Id: number,
	Key: string,
	Level: number,
}

export type TreadmillProduct = {
	Id: number,
	Key: string,
	--- Matches TreadmillConfigs.Tiers key (Gold, Diamond, Void, Admin).
	TierKey: string,
}

export type SkipStageProduct = {
	Id: number,
	Key: string,
	--- Target stage number (2–9).
	Stage: number,
}

ProductConfigs.DeveloperProducts = {
	CoinPack1 = { Id = 0, Key = "CoinPack1", GrantCoins = 100 } :: DeveloperProduct,
	CoinPack2 = { Id = 0, Key = "CoinPack2", GrantCoins = 500 } :: DeveloperProduct,
	SkipRebirth = {
		Id = 3602187746,
		Key = "SkipRebirth",
		GrantCoins = 0,
		GrantRebirth = true,
		PreserveProgressOnRebirth = true,
	} :: DeveloperProduct,
	SkipStage = { Id = 0, Key = "SkipStage", GrantCoins = 0 } :: DeveloperProduct,
	DoubleWins = {
		Id = 3602185533,
		Key = "DoubleWins",
		GrantCoins = 0,
		GrantDoubleWins = true,
	} :: DeveloperProduct,
	PlusOneBoost = {
		Id = 3602473672,
		Key = "PlusOneBoost",
		GrantCoins = 0,
		GrantBoost = true,
	} :: DeveloperProduct,
}

function ProductConfigs.GetProductByKey(key: string): DeveloperProduct?
	for _, product in ProductConfigs.DeveloperProducts do
		if product.Key == key then
			return product
		end
	end
	return nil
end

function ProductConfigs.GetProductById(productId: number): DeveloperProduct?
	for _, product in ProductConfigs.DeveloperProducts do
		if product.Id ~= 0 and product.Id == productId then
			return product
		end
	end
	return nil
end

ProductConfigs.Gamepasses = {
	--- VIP: +25% Speed XP (movement + treadmill) and 16h offline-reward cap (vs 8h).
	VIP = { Id = 1873684674, Key = "VIP" } :: Gamepass,
	DoubleCoins = { Id = 0, Key = "DoubleCoins" } :: Gamepass,
	--- Permanent 2x Speed XP from movement + treadmills — the genre's top seller.
	--- Stacks with VIP (2 * 1.25 = 2.5x for owners of both).
	DoubleSpeed = { Id = 1873936619, Key = "DoubleSpeed" } :: Gamepass,
}

-- Map.Treadmills paid tiers (developer products; permanent unlock)
ProductConfigs.TreadmillProducts = {
	{ Id = 3602182554, Key = "TreadmillGold3x", TierKey = "Gold" } :: TreadmillProduct,
	{ Id = 3602182632, Key = "TreadmillDiamond9x", TierKey = "Diamond" } :: TreadmillProduct,
	{ Id = 3602182698, Key = "TreadmillVoid25x", TierKey = "Void" } :: TreadmillProduct,
	{ Id = 3602182792, Key = "TreadmillAdmin100x", TierKey = "Admin" } :: TreadmillProduct,
} :: { TreadmillProduct }

-- Bottom HUD speed shop → GUI.HUD.Bottom.Speed.Product1 … Product4 (Developer Products)
ProductConfigs.SpeedProducts = {
	{
		Id = 3602294339,
		Key = "SpeedPack1",
		Amount = 100_000,
		ButtonName = "Product1",
	} :: SpeedProduct,
	{
		Id = 3602294402,
		Key = "SpeedPack2",
		Amount = 1_000_000,
		ButtonName = "Product2",
	} :: SpeedProduct,
	{
		Id = 3602294465,
		Key = "SpeedPack3",
		Amount = 10_000_000,
		ButtonName = "Product3",
	} :: SpeedProduct,
	{
		Id = 3602294543,
		Key = "SpeedPack4",
		Amount = 100_000_000,
		ButtonName = "Product4",
	} :: SpeedProduct,
} :: { SpeedProduct }

--- Spidey-style labels: +100k, +1M, +10M, +100M Speed
function ProductConfigs.FormatSpeedPackLabel(amount: number, includeSpeedWord: boolean?): string
	local suffix = if includeSpeedWord then " Speed" else ""
	if amount >= 1_000_000 then
		local millions = amount / 1_000_000
		if millions == math.floor(millions) then
			return "+" .. tostring(math.floor(millions)) .. "M" .. suffix
		end
		return "+" .. string.format("%.1f", millions) .. "M" .. suffix
	end
	if amount >= 1_000 then
		local thousands = amount / 1_000
		if thousands == math.floor(thousands) then
			return "+" .. tostring(math.floor(thousands)) .. "k" .. suffix
		end
		return "+" .. string.format("%.1f", thousands) .. "k" .. suffix
	end
	return "+" .. tostring(math.floor(amount)) .. suffix
end

-- Right HUD SpeedPeark developer products (repeatable; first tier with Id ~= 0 is shown)
ProductConfigs.SpeedPeakTiers = {
	{ Id = 3602192012, Key = "SpeedPeak1", Level = 2 } :: SpeedPeakTier,
	{ Id = 0, Key = "SpeedPeak2", Level = 5 } :: SpeedPeakTier,
} :: { SpeedPeakTier }

function ProductConfigs.GetSpeedPeakTierById(productId: number): SpeedPeakTier?
	for _, tier in ProductConfigs.SpeedPeakTiers do
		if tier.Id ~= 0 and tier.Id == productId then
			return tier
		end
	end
	return nil
end

function ProductConfigs.GetSpeedPeakTierByKey(key: string): SpeedPeakTier?
	for _, tier in ProductConfigs.SpeedPeakTiers do
		if tier.Key == key then
			return tier
		end
	end
	return nil
end

function ProductConfigs.GetGamepassByKey(key: string): Gamepass?
	for _, pass in ProductConfigs.Gamepasses do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

function ProductConfigs.GetSpeedProductById(productId: number): SpeedProduct?
	for _, product in ProductConfigs.SpeedProducts do
		if product.Id ~= 0 and product.Id == productId then
			return product
		end
	end
	return nil
end

function ProductConfigs.GetTreadmillProductById(productId: number): TreadmillProduct?
	for _, product in ProductConfigs.TreadmillProducts do
		if product.Id ~= 0 and product.Id == productId then
			return product
		end
	end
	return nil
end

function ProductConfigs.GetTreadmillProductForTier(tierKey: string): TreadmillProduct?
	for _, product in ProductConfigs.TreadmillProducts do
		if product.TierKey == tierKey then
			return product
		end
	end
	return nil
end

-- Per-stage teleport developer products (Stage 2–9). Purchase teleports player to that checkpoint.
ProductConfigs.SkipStageProducts = {
	[2] = { Id = 3602397033, Key = "SkipStage2", Stage = 2 } :: SkipStageProduct,
	[3] = { Id = 3602397102, Key = "SkipStage3", Stage = 3 } :: SkipStageProduct,
	[4] = { Id = 3602397189, Key = "SkipStage4", Stage = 4 } :: SkipStageProduct,
	[5] = { Id = 3602397276, Key = "SkipStage5", Stage = 5 } :: SkipStageProduct,
	[6] = { Id = 3602397334, Key = "SkipStage6", Stage = 6 } :: SkipStageProduct,
	[7] = { Id = 3602397399, Key = "SkipStage7", Stage = 7 } :: SkipStageProduct,
	[8] = { Id = 3602397490, Key = "SkipStage8", Stage = 8 } :: SkipStageProduct,
	[9] = { Id = 3602397571, Key = "SkipStage9", Stage = 9 } :: SkipStageProduct,
} :: { [number]: SkipStageProduct }

function ProductConfigs.GetSkipStageProductByStage(stage: number): SkipStageProduct?
	return ProductConfigs.SkipStageProducts[stage]
end

function ProductConfigs.GetSkipStageProductById(productId: number): SkipStageProduct?
	for _, product in ProductConfigs.SkipStageProducts do
		if product.Id == productId then
			return product
		end
	end
	return nil
end

return ProductConfigs

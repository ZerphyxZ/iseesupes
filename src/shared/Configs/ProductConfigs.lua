--!strict

-- Paste Creator Dashboard IDs here. Id = 0 means disabled until configured.

local ProductConfigs = {}

export type DeveloperProduct = {
	Id: number,
	Key: string,
	GrantCoins: number,
	GrantRebirth: boolean?,
	GrantLevels: number?,
}

export type Gamepass = {
	Id: number,
	Key: string,
}

export type SpeedProduct = {
	Id: number,
	Key: string,
	Amount: number,
}

export type SpeedPeakTier = {
	Id: number,
	Key: string,
	Level: number,
}

ProductConfigs.DeveloperProducts = {
	CoinPack1 = { Id = 0, Key = "CoinPack1", GrantCoins = 100 } :: DeveloperProduct,
	CoinPack2 = { Id = 0, Key = "CoinPack2", GrantCoins = 500 } :: DeveloperProduct,
	SkipRebirth = { Id = 0, Key = "SkipRebirth", GrantCoins = 0, GrantRebirth = true } :: DeveloperProduct,
	SkipStage = { Id = 0, Key = "SkipStage", GrantCoins = 0 } :: DeveloperProduct,
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
	VIP = { Id = 0, Key = "VIP" } :: Gamepass,
	DoubleCoins = { Id = 0, Key = "DoubleCoins" } :: Gamepass,
	GoldTreadmill = { Id = 0, Key = "GoldTreadmill" } :: Gamepass,
	DiamondTreadmill = { Id = 0, Key = "DiamondTreadmill" } :: Gamepass,
	DoubleWins = { Id = 0, Key = "DoubleWins" } :: Gamepass,
}

-- Bottom HUD speed shop (Product1, Product2, …)
ProductConfigs.SpeedProducts = {
	{ Id = 0, Key = "SpeedPack1", Amount = 100 } :: SpeedProduct,
	{ Id = 0, Key = "SpeedPack2", Amount = 500 } :: SpeedProduct,
} :: { SpeedProduct }

-- Right HUD SpeedPeak tier gamepasses (first unowned tier is shown)
ProductConfigs.SpeedPeakTiers = {
	{ Id = 3602192012, Key = "SpeedPeak1", Level = 2 } :: SpeedPeakTier,
	{ Id = 0, Key = "SpeedPeak2", Level = 5 } :: SpeedPeakTier,
} :: { SpeedPeakTier }

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

return ProductConfigs

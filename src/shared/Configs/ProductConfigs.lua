--!strict

-- Paste Creator Dashboard IDs here. Id = 0 means disabled until configured.

local ProductConfigs = {}

export type DeveloperProduct = {
	Id: number,
	Key: string,
	GrantCoins: number,
}

export type Gamepass = {
	Id: number,
	Key: string,
}

ProductConfigs.DeveloperProducts = {
	CoinPack1 = { Id = 0, Key = "CoinPack1", GrantCoins = 100 } :: DeveloperProduct,
	CoinPack2 = { Id = 0, Key = "CoinPack2", GrantCoins = 500 } :: DeveloperProduct,
}

ProductConfigs.Gamepasses = {
	VIP = { Id = 0, Key = "VIP" } :: Gamepass,
	DoubleCoins = { Id = 0, Key = "DoubleCoins" } :: Gamepass,
	GoldTreadmill = { Id = 0, Key = "GoldTreadmill" } :: Gamepass,
	DiamondTreadmill = { Id = 0, Key = "DiamondTreadmill" } :: Gamepass,
}

return ProductConfigs

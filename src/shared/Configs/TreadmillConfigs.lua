--!strict

-- Treadmill tiers, world paths, and tuning. Model names must match Workspace.Map.Treadmills children.

export type TreadmillTier = {
	Key: string,
	DisplayName: string,
	--- Instance name under Map.Treadmills (e.g. "SilverTreadmill").
	ModelName: string,
	Multiplier: number,
	HighlightColor: Color3,
	--- ProductConfigs.Gamepasses key; nil = free for everyone.
	GamepassKey: string?,
}

export type TreadmillWorldConfig = {
	MapFolderName: string,
	TreadmillsFolderName: string,
	--- Part used when kicking a player off a locked treadmill.
	KickSpawnPartName: string,
}

export type TreadmillGameplayConfig = {
	TickRate: number,
	RaycastDistance: number,
	KickTeleportOffset: Vector3,
	PointsPerTick: number,
	--- Optional Speed XP per treadmill tick (0 = off; thrust refill is primary).
	SpeedXpPerTick: number,
}

local TreadmillConfigs = {
	World = {
		MapFolderName = "Map",
		TreadmillsFolderName = "Treadmills",
		KickSpawnPartName = "Start",
	} :: TreadmillWorldConfig,

	Gameplay = {
		TickRate = 0.5,
		RaycastDistance = 3.5,
		KickTeleportOffset = Vector3.new(0, 3, 0),
		PointsPerTick = 1,
		SpeedXpPerTick = 0,
	} :: TreadmillGameplayConfig,

	--- Keys are tier ids; ModelName must match the Model in Studio.
	Tiers = {
		Basic = {
			Key = "Basic",
			DisplayName = "Basic Treadmill",
			ModelName = "BasicTreadmill",
			Multiplier = 1,
			HighlightColor = Color3.fromRGB(255, 255, 255),
			GamepassKey = nil,
		},
		Silver = {
			Key = "Silver",
			DisplayName = "Silver Treadmill",
			ModelName = "SilverTreadmill",
			Multiplier = 2,
			HighlightColor = Color3.fromRGB(192, 192, 192),
			GamepassKey = nil,
		},
		Gold = {
			Key = "Gold",
			DisplayName = "Gold Treadmill",
			ModelName = "GoldTreadmill",
			Multiplier = 3,
			HighlightColor = Color3.fromRGB(255, 215, 0),
			GamepassKey = "GoldTreadmill",
		},
		Diamond = {
			Key = "Diamond",
			DisplayName = "Diamond Treadmill",
			ModelName = "DiamondTreadmill",
			Multiplier = 9,
			HighlightColor = Color3.fromRGB(85, 255, 255),
			GamepassKey = "DiamondTreadmill",
		},
	} :: { [string]: TreadmillTier },

	--- Display / progression order in UI.
	TierOrder = { "Basic", "Silver", "Gold", "Diamond" },
}

return TreadmillConfigs

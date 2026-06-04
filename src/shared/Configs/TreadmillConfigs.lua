--!strict

-- Treadmill tiers, world paths, and tuning. Model names must match Workspace.Map.Treadmills children.

export type TreadmillTier = {
	Key: string,
	DisplayName: string,
	--- Instance name under Map.Treadmills (e.g. "SilverTreadmill").
	ModelName: string,
	Multiplier: number,
	HighlightColor: Color3,
}

export type TreadmillWorldConfig = {
	MapFolderName: string,
	TreadmillsFolderName: string,
	--- Part used when kicking a player off a locked treadmill.
	KickSpawnPartName: string,
}

export type TreadmillGameplayConfig = {
	TickRate: number,
	--- Legacy alias; prefer RaycastBaseDistance.
	RaycastDistance: number,
	RaycastBaseDistance: number,
	RaycastHipHeightScale: number,
	RaycastMaxDistance: number,
	UseBoundsFallback: boolean,
	BoundsFallbackHorizontalStuds: number,
	BoundsFallbackVerticalStuds: number,
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
		RaycastBaseDistance = 3.5,
		RaycastHipHeightScale = 1,
		RaycastMaxDistance = 12,
		UseBoundsFallback = true,
		BoundsFallbackHorizontalStuds = 6,
		BoundsFallbackVerticalStuds = 4,
		KickTeleportOffset = Vector3.new(0, 3, 0),
		PointsPerTick = 1,
		SpeedXpPerTick = 5,
	} :: TreadmillGameplayConfig,

	--- Studio: log when player is near treadmills but detection misses (server Output).
	Debug = false,

	--- Keys are tier ids; ModelName must match the Model in Studio.
	Tiers = {
		Silver = {
			Key = "Silver",
			DisplayName = "Silver Treadmill",
			ModelName = "SilverTreadmill",
			Multiplier = 1,
			HighlightColor = Color3.fromRGB(192, 192, 192),
		},
		Gold = {
			Key = "Gold",
			DisplayName = "Gold Treadmill",
			ModelName = "Gold",
			Multiplier = 3,
			HighlightColor = Color3.fromRGB(255, 215, 0),
		},
		Diamond = {
			Key = "Diamond",
			DisplayName = "Diamond Treadmill",
			ModelName = "Diamond",
			Multiplier = 9,
			HighlightColor = Color3.fromRGB(85, 255, 255),
		},
		Void = {
			Key = "Void",
			DisplayName = "Void Treadmill",
			ModelName = "Void",
			Multiplier = 25,
			HighlightColor = Color3.fromRGB(120, 0, 180),
		},
		Admin = {
			Key = "Admin",
			DisplayName = "Admin Treadmill",
			ModelName = "AdminTred",
			Multiplier = 100,
			HighlightColor = Color3.fromRGB(255, 60, 60),
		},
	} :: { [string]: TreadmillTier },

	--- Display / progression order in UI.
	TierOrder = { "Silver", "Gold", "Diamond", "Void", "Admin" },
}

function TreadmillConfigs.GetTierByKey(tierKey: string): TreadmillTier?
	return TreadmillConfigs.Tiers[tierKey]
end

return TreadmillConfigs

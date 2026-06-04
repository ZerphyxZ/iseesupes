--!strict

-- Workspace.Map.RainbowCarpet → Touch → GodSpeed Aura developer product (repeatable per run).

export type GodSpeedAuraConfig = {
	ModelName: string,
	TouchPartName: string,
	ProductId: number,
	DisplayName: string,
	TouchDebounce: number,
	ProductIdAttribute: string,
	ActiveAttribute: string,
	InfiniteThrustAttribute: string,
	SpeedGainMultiplierAttribute: string,
	WalkSpeedMultiplierAttribute: string,
	--- Extra speed XP per stud batch while the run buff is active.
	SpeedGainMultiplier: number,
	--- Walk/swim speed multiplier (Spd_Mult) while the run buff is active.
	WalkSpeedMultiplier: number,
}

local GodSpeedAuraConfigs: GodSpeedAuraConfig = {
	ModelName = "RainbowCarpet",
	TouchPartName = "Touch",
	ProductId = 3602182863,
	DisplayName = "GodSpeed Aura",
	TouchDebounce = 1.5,
	ProductIdAttribute = "ProductId",
	ActiveAttribute = "GodSpeedRunActive",
	InfiniteThrustAttribute = "GodSpeedInfiniteThrust",
	SpeedGainMultiplierAttribute = "GodSpeedSpeedGainMult",
	WalkSpeedMultiplierAttribute = "GodSpeedWalkMult",
	SpeedGainMultiplier = 3,
	WalkSpeedMultiplier = 2,
}

return GodSpeedAuraConfigs

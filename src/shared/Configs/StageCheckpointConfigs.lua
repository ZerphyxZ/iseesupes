--!strict

-- Heat-vision damage on StageCheckpoints glass gates (Speed XP gated).

local StageCheckpointConfigs = {
	Debug = true,
	FolderName = "StageCheckpoints",
	RequirementAttribute = "MinSpeedXp",
	FirstGateStage = 1,
	MaxGateStage = 9,
	-- Fallback only for gate 1 when XP/Bar/Requirement label is empty in Studio.
	DefaultMinSpeedXp = 75,

	UiPaths = {
		SurfaceGui = "XP",
		Wrapper = "Wrapper",
		Bar = "Bar",
		Progress = "Progress",
		Requirement = "Requirement",
	},

	MaxHp = 100,
	BaseDamagePerSecond = 10,
	BarTweenDuration = 0.25,
	DamageTickInterval = 0.05,
	InsufficientSpeedToastCooldown = 1.2,
	-- 0 = auto pane grid sized to the whole gate; set >0 to force random small shard count instead.
	GlassChipCount = 0,
	GateBreakHideDelay = 0.06,
	GateBreakHideDuration = 0.3,

	CollisionGroup = {
		GatePrefix = "StageGate_",
		PlayerPrefix = "Plr_",
	},
}

return StageCheckpointConfigs

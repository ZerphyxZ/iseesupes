--!strict

-- Heat-vision damage on StageCheckpoints metal melt gates (Speed XP gated).

local StageCheckpointConfigs = {
	Debug = true,
	FolderName = "StageCheckpoints",
	RequirementAttribute = "MinSpeedXp",
	FirstGateStage = 1,
	MaxGateStage = 9,
	-- Fallback when a gate has no configured requirement (gate 1 only).
	DefaultMinSpeedXp = 75,

	--- Min total Speed XP to melt each gate (overrides Studio labels for balance).
	GateSpeedRequirements = {
		[1] = 75,
		[2] = 250,
		[3] = 600,
		[4] = 1000,
		[5] = 1600,
		[6] = 2300,
		[7] = 3250,
		[8] = 4500,
		[9] = 6200,
	},

	MaxHp = 100,
	BaseDamagePerSecond = 10,
	--- Extra melt DPS per Speed level above 1 (level 10 ≈ +27% at 0.03).
	LevelDamageBonusPerLevel = 0.03,

	UiPaths = {
		SurfaceGui = "XP",
		Wrapper = "Wrapper",
		Bar = "Bar",
		Progress = "Progress",
		Requirement = "Requirement",
	},

	BarTweenDuration = 0.25,
	DamageTickInterval = 0.05,
	InsufficientSpeedToastCooldown = 1.2,
	-- 0 = auto pane grid sized to the whole gate; set >0 to force random small shard count instead.
	MetalMeltChipCount = 0,
	GlassChipCount = 0,
	GateBreakHideDelay = 0.06,
	GateBreakHideDuration = 0.3,

	GateMeltVisuals = {
		ColdColor = Color3.fromRGB(106, 106, 114),
		HotColor = Color3.fromRGB(255, 85, 0),
		SlagColor = Color3.fromRGB(42, 36, 32),
		HighlightFillColor = Color3.fromRGB(255, 120, 40),
		HighlightOutlineColor = Color3.fromRGB(255, 200, 120),
		HighlightFillTransparencyCold = 0.92,
		HighlightFillTransparencyHot = 0.35,
		HeatThreshold = 0.05,
	},

	CollisionGroup = {
		GatePrefix = "StageGate_",
		PlayerPrefix = "Plr_",
	},
}

function StageCheckpointConfigs.getGateHeatFillTransparency(heat: number): number
	local visuals = StageCheckpointConfigs.GateMeltVisuals
	local t = math.clamp(heat, 0, 1)
	return visuals.HighlightFillTransparencyCold
		+ (visuals.HighlightFillTransparencyHot - visuals.HighlightFillTransparencyCold) * t
end

function StageCheckpointConfigs.GetGateSpeedRequirement(stageNum: number): number?
	if not StageCheckpointConfigs.isMeltGateStage(stageNum) then
		return nil
	end
	local req = StageCheckpointConfigs.GateSpeedRequirements[stageNum]
	if typeof(req) == "number" and req > 0 then
		return math.floor(req)
	end
	return nil
end

function StageCheckpointConfigs.isMeltGateStage(stageNum: number): boolean
	return stageNum >= StageCheckpointConfigs.FirstGateStage
		and stageNum <= StageCheckpointConfigs.MaxGateStage
end

return StageCheckpointConfigs

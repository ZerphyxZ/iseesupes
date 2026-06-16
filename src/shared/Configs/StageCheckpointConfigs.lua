--!strict

-- Heat-vision damage on StageCheckpoints metal melt gates (Speed XP gated).

local StageCheckpointConfigs = {
	Debug = false,
	FolderName = "StageCheckpoints",
	RequirementAttribute = "MinSpeedXp",
	FirstGateStage = 1,
	MaxGateStage = 9,
	-- Fallback when a gate has no configured requirement (gate 1 only).
	DefaultMinSpeedXp = 150,

	--- Min total Speed XP to melt each gate (overrides Studio labels for balance).
	--- Aligned to XP curve: Level N needs ~1000*(1.3^(N-1)-1) total XP.
	--- Entry levels: S1≈L1, S2≈L3, S3≈L6, S4≈L9, S5≈L12, S6≈L15, S7≈L17, S8≈L22, S9≈L25.
	--- Gates 2-3 lowered 2026-06-12 (were 1800/3800 ≈ L5/L7): live funnel showed
	--- 70% churn at gate 2 — a 12x jump from gate 1 while every later gate steps ~2x.
	--- Front of curve now ~4x/4x/2.6x so the first real wall lands at gate 4.
	--- Measured gate→gate lengths (Map Start/End parts, studs):
	--- S1 640, S2 645, S3 793, S4 1409, S5 953, S6 2411, S7 1871,
	--- S8 1180 (vertical climb tower), S9 1479 (final stretch to win room).
	--- Flight speed at entry (FlightSpeedCurve): 50/62/79/95/102/112/118/139/150 —
	--- one thrust tank covers ~45-70% of the current stage without upgrades.
	GateSpeedRequirements = {
		[1] = 150,
		[2] = 690,
		[3] = 2700,
		[4] = 7000,
		[5] = 16000,
		[6] = 35000,
		[7] = 70000,
		[8] = 250000,
		[9] = 540000,
	},

	--- When false, gate parts never block movement (no laser melt gates).
	GateCanCollide = false,

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

	--- When false, never enable gate XP SurfaceGui or write Requirement labels (Studio hides them).
	ShowGateXpUi = false,

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

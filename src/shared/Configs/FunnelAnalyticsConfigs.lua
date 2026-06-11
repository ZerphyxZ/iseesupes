--!strict

-- Creator Dashboard → Analytics → Funnels (LogFunnelStepEvent, server, published only).

local FunnelAnalyticsConfigs = {
	Enabled = true,
	--- Funnel tab name in Creator Hub (must match across all steps).
	FunnelName = "StageProgress",
	MaxStage = 9,
	--- Mirror events to Output in Studio (Roblox does not ingest Studio events).
	DebugPrint = true,
	--- When true, still calls LogFunnelStepEvent in Studio (usually not useful).
	SendInStudio = false,

	--- Onboarding funnel (LogOnboardingFunnelStepEvent) — measures the first-session
	--- drop-off BEFORE gate 1, which StageProgress cannot see. Steps derive from
	--- TutorialStep (GoTreadmill=1 .. Complete=6) and MaxStage; logged once per player.
	Onboarding = {
		Enabled = true,
		Steps = {
			[1] = "Joined",
			[2] = "Treadmill Done",
			[3] = "Wins Claimed",
			[4] = "Avatar Equipped",
			[5] = "Shop Intro",
			[6] = "Tutorial Complete",
			[7] = "Gate 1 Melted",
		},
	},
}

--- Highest onboarding step justified by the player's current data.
function FunnelAnalyticsConfigs.DeriveOnboardingStep(data: any): number
	local tutorialStep = if type(data.TutorialStep) == "number" then data.TutorialStep else 1
	local maxStage = if type(data.MaxStage) == "number" then data.MaxStage else 0

	if maxStage >= 1 then
		return 7
	end
	-- TutorialStep 2..6 map directly to onboarding steps 2..6.
	return math.clamp(tutorialStep, 1, 6)
end

return FunnelAnalyticsConfigs

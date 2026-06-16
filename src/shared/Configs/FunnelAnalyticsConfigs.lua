--!strict

-- Creator Dashboard → Analytics → Funnels (LogFunnelStepEvent, server, published only).

local FunnelAnalyticsConfigs = {
	Enabled = true,
	--- Funnel tab name in Creator Hub (must match across all steps).
	FunnelName = "StageProgress",
	MaxStage = 9,
	--- Legacy [iseesupes][Funnel] / [iseesupes][Onboarding] mirror lines (off — use [StageFunnel] / [OnboardingFunnel] instead).
	DebugPrint = false,
	--- JOIN / LEAVE snapshots per player (verbose diagnostic).
	DebugPrintJoinLeave = false,
	--- One-time startup HEALTH banner + cheat sheet.
	DebugPrintHealth = false,
	--- When true, still calls LogFunnelStepEvent in Studio (usually not useful).
	SendInStudio = false,

	--- Count players who physically reach each stage gate (proximity), not only win-button claims.
	StageVisit = {
		Enabled = true,
		ProximityRadius = 40,
		PollIntervalSeconds = 0.5,
		--- [StageFunnel] RECORD / PROXIMITY / OK / BACKFILL / WARN / ERROR.
		DebugPrint = false,
		--- NEAR hints, SKIP reasons, per-gate map lines (noisy during normal play).
		DebugPrintVerbose = false,
	},

	--- Onboarding funnel (LogOnboardingFunnelStepEvent) — measures the first-session
	--- drop-off BEFORE the core loop, which StageProgress cannot see.
	--- v3 (2026-06-13): "Gate 1 Melted" removed — heat-vision melt gates no longer
	--- exist in the game (run → win button → lobby loop). Historical dashboards keep
	--- the old step for past date ranges; new data uses these 6 steps. Existing
	--- profiles with OnboardingStepLogged = 7 (v2 numbering) exceed the new max of 6,
	--- so the derive target never passes them → no double-logging.
	Onboarding = {
		Enabled = true,
		--- [OnboardingFunnel] RECORD / OK / WARN / ERROR.
		DebugPrint = false,
		--- SKIP on no-op replicates (fires every data sync — keep off unless debugging).
		DebugPrintVerbose = false,
		Steps = {
			[1] = "Joined",
			[2] = "Treadmill Done",
			[3] = "First Win Claimed",
			[4] = "Avatar Equipped",
			[5] = "Shop Intro",
			[6] = "Tutorial Complete",
		},
	},
}

--- Highest onboarding step justified by the player's current data, in play order.
--- Steps 1–4 follow TutorialStep; step 5 uses thrust shop intro flag; step 6 is Complete.
function FunnelAnalyticsConfigs.DeriveOnboardingStep(data: any): number
	local step = if type(data.TutorialStep) == "number" then math.floor(data.TutorialStep) else 1
	if step >= 6 then
		return 6
	end
	if data.TutorialThrustShopIntroShown == true then
		return 5
	end
	return math.clamp(step, 1, 4)
end

return FunnelAnalyticsConfigs

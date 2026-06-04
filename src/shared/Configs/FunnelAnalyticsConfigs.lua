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
}

return FunnelAnalyticsConfigs

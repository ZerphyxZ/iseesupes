--!strict

-- Studio Output categories. Funnel stays on; everything else off by default.
-- Live published servers: non-warn logs are suppressed unless a category is explicitly true.

local StudioLogsConfig = {
	Funnel = false,
	ReadyMessages = false,
	LevelDesign = false,
	ProfileJoin = false,
	HealthRed = false,
	AuraShop = false,
	Notifications = false,
	Gameplay = false,
	PerfWatch = false,
}

return StudioLogsConfig

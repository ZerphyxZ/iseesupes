--!strict

-- HUD → Frames navigation and frame open/close animation tuning.

export type HudFrameLink = {
	--- Path from HUD root, e.g. { "Left", "Trails" }
	ButtonPath: { string },
	--- Child name under GUI.Frames
	FrameName: string,
}

local HudConfigs = {
	OpenDuration = 0.35,
	CloseDuration = 0.28,
	EasingStyle = Enum.EasingStyle.Quint,
	EasingDirection = Enum.EasingDirection.Out,

	CloseButtonNames = { "Close", "X", "CloseButton", "Exit" },

	--- Frames under GUI.Frames that are not HUD-toggled (e.g. level-up popup).
	ExcludeFromNavigator = { "LevelUp", "Notifications" },

	--- HUD buttons that open a full-screen / panel under GUI.Frames
	FrameLinks = {
		{ ButtonPath = { "Left", "Trails" }, FrameName = "Trails" },
		{ ButtonPath = { "Left", "Rebirth" }, FrameName = "Rebirth" },
		{ ButtonPath = { "Left", "Rewards" }, FrameName = "Rewards" },
	} :: { HudFrameLink },

	--- Right HUD: developer product keys (ProductConfigs.DeveloperProducts)
	BoostProductKey = "SpeedPack1",
	SkipStageProductKey = "SkipStage",
}

return HudConfigs

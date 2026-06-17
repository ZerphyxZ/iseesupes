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

	--- Level bar Requirement label (XP progress text). Off = bar fill only.
	UpdateLevelBarRequirementLabel = true,

	--- Thrust bar Requirement label (current/max fuel). On so upgrades show new max.
	UpdateThrustBarRequirementLabel = true,

	--- Level-up toast sits below the Long Jump counter (code-built JumpCounter frame).
	LevelUp = {
		GapBelowJumpCounterPx = 14,
		--- Used when JumpCounter is not present yet.
		FallbackYOffsetScale = 0.05,
	},

	--- Frames under GUI.Frames that are not HUD-toggled (e.g. level-up popup).
	ExcludeFromNavigator = { "LevelUp", "Notifications", "ThrustBoosts", "DailyStreak", "OfflineReward" },

	--- HUD buttons that open a full-screen / panel under GUI.Frames
	FrameLinks = {
		{ ButtonPath = { "Left", "Trails" }, FrameName = "Trails" },
		{ ButtonPath = { "Left", "Rebirth" }, FrameName = "Rebirth" },
		{ ButtonPath = { "Left", "Rewards" }, FrameName = "Rewards" },
		{ ButtonPath = { "Left", "Shop" }, FrameName = "PassShop" },
	} :: { HudFrameLink },

	--- Right HUD: developer product keys (ProductConfigs.DeveloperProducts)
	BoostProductKey = "PlusOneBoost",
	SkipStageProductKey = "SkipStage",

	--- Global GuiButton hover / click scale (UIButtonEffectsController)
	ButtonEffects = {
		HoverScale = 1.06,
		PressScale = 0.92,
		HoverDuration = 0.12,
		PressDuration = 0.08,
		ReleaseDuration = 0.18,
		ExcludePaths = {} :: { { string } },
		--- ImageButtons inside these frames tween their .Parent on hover / press.
		ScaleTweenParentFrameNames = {
			SupesMobile = true,
			VisionMobile = true,
		},
		SkipAttribute = "HudSkipButtonFx",
		BoundAttribute = "_HudButtonFxBound",
	},

	--- Slow continuous rotation of "Shine" ImageLabels inside these HUD buttons (ShineSpinController).
	ShineSpin = {
		DegreesPerSecond = 30,
		ShineName = "Shine",
		ButtonNames = { "StarterPack" },
		--- Rescan PlayerGui for (re)spawned shine labels this often.
		RescanSeconds = 5,
	},

	--- Global GuiButton hover / click SFX (UIButtonEffectsController — all PlayerGui buttons).
	ButtonSounds = {
		SoundId = "rbxassetid://133216848606395",
		HoverVolume = 0.42,
		ClickVolume = 0.58,
		HoverPlaybackSpeed = 1.06,
		ClickPlaybackSpeed = 0.94,
		HoverDebounce = 0.04,
		BoundAttribute = "_HudButtonSoundBound",
	},

	--- Win icons fly from screen centre to HUD Left/Wins (EffectsSystem).
	WinCollectEffect = {
		IconImage = "rbxassetid://137378104956269",
		HudIconName = "Icon",
		MatchHudIconSize = true,
		IconPx = 56,
		IconPxMobile = 48,
		IconPxLowEnd = 40,
		ScaleType = Enum.ScaleType.Fit,
		MaxVisibleIcons = 12,
		StaggerDelay = 0.055,
		FlyDuration = 0.42,
		PopInDuration = 0.16,
		ArrivalPopDuration = 0.12,
		SpawnSpreadPx = 140,
		WinsFramePath = { "GUI", "HUD", "Left", "Wins" },
		FinalPulseScale = 1.18,
	},
}

return HudConfigs

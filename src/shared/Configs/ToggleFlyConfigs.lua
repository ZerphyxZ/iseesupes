--!strict

-- ToggleFly CollectionService zones: pulse SupesMobile so players know to tap and fly forward.

local ToggleFlyConfigs = {
	Enabled = true,
	CollectionTag = "ToggleFly",
	Zone = {
		horizontalPadding = 6,
		maxHeightAbove = 18,
		minHeightBelow = -8,
	},
	--- AutoFly LAUNCH uses a tight BOX over the pad's footprint (+ this many studs) instead of
	--- the wide radial Zone above — so you fly when you actually step ONTO the pad, not as
	--- soon as the glow appears nearby. Keep small.
	LaunchHorizontalPadding = 3,
	HeartbeatPeakScale = 1.14,
	HeartbeatPeriodSeconds = 0.9,
	HideWhenFlying = true,
	SkipWhenTutorialFlyHintActive = true,

	-- ── AutoFly pad highlight ──────────────────────────────────────────────
	-- When AutoFly is ON and the local player is on/near a ToggleFly pad, a glowing Neon slab
	-- is drawn over the pad's footprint, colored from the pad's Color attribute, with an arcade
	-- chime — telling the player "fly here". (A Roblox Highlight does NOT render on these pads
	-- because they're Transparency=1, so we use a real Neon part.) Clears on leave/fly. Local
	-- to each client (ToggleFlyHighlightController).
	HighlightEnabled = true,
	--- Attribute on the tagged pad part holding the per-pad glow Color3.
	HighlightColorAttribute = "Color",
	--- Used if a pad has no Color attribute set. Bright gold so it stays visible on ANY
	--- floor colour (the old blue was invisible on blue stage floors).
	HighlightFallbackColor = Color3.fromRGB(255, 200, 30),
	--- Glow slab transparency breathes between these for an arcade pulse. Kept fairly OPAQUE
	--- (low values) so the Neon glow reads clearly from a distance.
	HighlightFillTransparencyMin = 0.2,
	HighlightFillTransparencyMax = 0.55,
	--- Breathing speed (radians/sec).
	HighlightPulseSpeed = 6,
	--- Studs added to each side of the pad footprint for the glow slab (avoids z-fighting with
	--- the pad's textures and gives a clean glowing border).
	HighlightSizePadding = 0.6,
	--- A high-contrast outline drawn around the glow slab so the pad is visible even when its
	--- Color attribute matches the floor (e.g. a blue pad on a blue floor). White contrasts
	--- with everything. Set thickness 0 to disable the outline.
	HighlightOutlineColor = Color3.fromRGB(255, 255, 255),
	HighlightOutlineThickness = 0.2,
	--- Glow the nearest pad's step part within this many studs even before you step on it, so
	--- it reads as a "fly here" marker as you walk up — AutoFly grabs you the instant you
	--- touch the pad, so an on-pad-only glow is too brief to notice. Kept short so the glow
	--- sits at the pad you're about to step on, not across the room. 0 = only while on it.
	HighlightProximityRange = 25,
	--- How often (seconds) to re-check which pad the player is on. Pulse runs every frame.
	HighlightScanInterval = 0.1,
	--- Kid-friendly arcade chime played once when you step onto a pad. Swap to taste.
	HighlightSoundId = "rbxassetid://4612375233",
	HighlightSoundVolume = 0.6,
}

return ToggleFlyConfigs

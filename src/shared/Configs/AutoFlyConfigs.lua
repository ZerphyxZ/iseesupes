--!strict

-- AutoFly: when enabled, standing on a ToggleFly pad auto-flies toward its Destination child.

local AutoFlyConfigs = {
	Enabled = true,
	PlayerAttribute = "AutoFlyEnabled",
	DestinationChildName = "Destination",
	ArrivalHorizontalStuds = 14,
	ArrivalVerticalStuds = 12,
	--- Closest-approach landing guard. The arrival box above is a tight per-frame AND-gate
	--- (14x12 studs) that misses off-axis / height-offset approaches, letting the player sail
	--- PAST the Destination into a hazard. So we also land once the player has come within this
	--- many studs of the Destination and then starts moving AWAY from it (closest point passed).
	ArrivalNearStuds = 24,
	--- Hard failsafe: cancel a single AutoFly flight if it runs longer than this without landing
	--- (mis-placed Destination / badly diverged path) instead of flying off the map. Raised 8 → 11
	--- to match the SERVER's actual ability budget (GetAbilityTimeCap ≈ 12s on a full 100 tank) — at
	--- 8 the client was force-cancelling long but legitimate crossings (low-level players cross slower:
	--- ~50 stud/s at L1 vs 110 at L16+) partway, dropping the player ("stops the flight in between").
	--- The arrival / closest-approach guards still land normal hops far sooner; this only bounds a
	--- genuinely unreachable destination, and the server thrust/time caps bound it regardless.
	MaxAutoFlySeconds = 11,
	--- On landing, pin the player to the Destination's X/Z and kill horizontal drift so flight
	--- momentum can't coast them sideways off the pad into a hazard — they drop straight down
	--- onto the intended spot. Set false to keep the old free-coast landing.
	SnapToDestinationOnLanding = true,
	AutoStartDebounceSeconds = 1.25,
	--- Seconds to steer straight UP at takeoff before curving toward Destination. Clears steps/edges
	--- that would otherwise catch the player when the Destination is nearly horizontal at launch.
	--- Server's DirectionLerp (≈10/s) naturally smooths the up→Destination transition. Set 0 to
	--- disable.
	AutoFlyRiseSeconds = 0.5,
	SkipWhenTutorialFlyHintActive = true,
	CameraOffset = Vector3.new(0, 3, 22),
	CameraLookAhead = 8,
	CameraLookAtYOffset = 4,
	CameraSmoothRate = 8,
	CameraLandingOffset = Vector3.new(0, 2, 18),
	CameraLandingLookAtYOffset = 2,
	CameraLandingBlendSeconds = 0.3,
	CameraReleaseDuration = 0.75,
	CameraReleaseSmoothRate = 6,
	CameraReleaseOffset = Vector3.new(0, 2, 12),
	CameraReleaseLookAtYOffset = 2,
	CameraReleaseFinishDistance = 0.4,
	--- Player attribute set while AutoFly flight is active so tuning can be overridden.
	AutoFlyActiveAttribute = "AutoFlyActive",
	FrameColorOn = Color3.fromRGB(33, 84, 185),
	FrameColorOff = Color3.fromRGB(206, 23, 6),
	LabelTextOn = "Auto Fly ON",
	LabelTextOff = "Auto Fly OFF",
}

return AutoFlyConfigs

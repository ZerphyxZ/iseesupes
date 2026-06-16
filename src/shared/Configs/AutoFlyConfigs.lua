--!strict

-- AutoFly: when enabled, standing on a ToggleFly pad auto-flies toward its Destination child.

local AutoFlyConfigs = {
	Enabled = true,
	PlayerAttribute = "AutoFlyEnabled",
	DestinationChildName = "Destination",
	ArrivalHorizontalStuds = 14,
	ArrivalVerticalStuds = 12,
	AutoStartDebounceSeconds = 1.25,
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
	FrameColorOn = Color3.fromRGB(33, 84, 185),
	FrameColorOff = Color3.fromRGB(206, 23, 6),
	LabelTextOn = "Auto Fly ON",
	LabelTextOff = "Auto Fly OFF",
}

return AutoFlyConfigs

--!strict

-- Superman heat vision (F / VisionMobile): camera-aimed laser from head/eyes.

local HeatVisionConfigs = {
	ActionName = "SupesHeatVision",
	Key = "F",
	Duration = 5,
	Cooldown = 3,
	MaxRange = 600,
	AimSendHz = 15,
	Debug = false,
	CheckpointDamageEnabled = true,

	AssetsFolder = { "Shared", "Assets", "SupermanHeatVision" },

	--- Offset from Head CFrame when welding HeadPart (attachments are authored on HeadPart).
	HeadWeldOffset = CFrame.new(),

	--- Ray origin slightly in front of the head for third-person camera aim.
	CameraRayOriginForward = 0.5,

	--- Shift-lock-style camera while heat vision is active.
	CameraLock = {
		Enabled = true,
		--- Local offset from HRP: X = shoulder, Y = height, Z = distance behind.
		ShoulderOffset = Vector3.new(1.75, 2.0, 9),
		LookAtHeight = 1.35,
		YawSensitivity = 0.004,
		PitchSensitivity = 0.004,
		TouchSensitivityScale = 1.5,
		MinPitch = math.rad(-25),
		MaxPitch = math.rad(45),
		InitialPitch = math.rad(5),
	},

	FakeDestruction = {
		Interval = 0.05,
		MinMoveDistance = 0.2,
		BreakTier = "HeatVision",
		ChipCount = 8,
	},

	Attributes = {
		Active = "HvActive",
		AimX = "HvAimX",
		AimY = "HvAimY",
		AimZ = "HvAimZ",
	},
}

return HeatVisionConfigs

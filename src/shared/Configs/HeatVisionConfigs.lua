--!strict

-- Superman heat vision (F / VisionMobile): camera-aimed laser from head/eyes.

local HeatVisionConfigs = {
	ActionName = "SupesHeatVision",
	Key = "F",
	--- Console/controller button for the laser (same action as Key).
	GamepadKey = "ButtonX",
	MaxRange = 175,
	--- Gate melt damage only applies when the player is this close to the hit point (blocks lobby sniping).
	CheckpointDamageMaxRange = 90,
	AimSendHz = 15,
	Debug = false,
	CheckpointDamageEnabled = true,

	--- Laser bar (VisionMobile): SolarCurrent / SolarMax in profile. Recharges only while flying.
	SolarEnergy = {
		BaseMax = 60,
		MinToStart = 15,
		DrainPerSecond = 10,
		FlightRefillRate = 7,
	},

	AssetsFolder = { "Shared", "Assets", "SupermanHeatVision" },

	--- Offset from Head CFrame when welding HeadPart (attachments are authored on HeadPart).
	HeadWeldOffset = CFrame.new(),

	--- Ray origin slightly in front of the head for third-person camera aim.
	CameraRayOriginForward = 0.5,

	--- Visual beam grows from eyes to raycast hit (damage uses full ray immediately).
	BeamExtend = {
		Duration = 0.75,
		DurationPerStud = 0.0035,
		MinDuration = 0.45,
		MaxDuration = 1.4,
		StartLength = 0.12,
		Ease = "InOutCubic",
	},

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

function HeatVisionConfigs.getSolarFlightRefillRate(): number
	local solar = HeatVisionConfigs.SolarEnergy
	if solar and typeof(solar.FlightRefillRate) == "number" then
		return solar.FlightRefillRate
	end
	return 7
end

function HeatVisionConfigs.getSolarDrainPerSecond(): number
	local solar = HeatVisionConfigs.SolarEnergy
	if solar and typeof(solar.DrainPerSecond) == "number" then
		return solar.DrainPerSecond
	end
	return 10
end

function HeatVisionConfigs.getCheckpointDamageMaxRange(): number
	local range = HeatVisionConfigs.CheckpointDamageMaxRange
	if typeof(range) == "number" and range > 0 then
		return range
	end
	return 90
end

function HeatVisionConfigs.getEffectiveMinSolarToStart(solarMax: number): number
	local solar = HeatVisionConfigs.SolarEnergy
	local minStart = if solar and typeof(solar.MinToStart) == "number" then solar.MinToStart else 15
	if typeof(solarMax) ~= "number" or solarMax <= 0 then
		return minStart
	end
	return math.min(minStart, solarMax)
end

function HeatVisionConfigs.getMinSolarToStart(solarMax: number?): number
	if typeof(solarMax) == "number" and solarMax > 0 then
		return HeatVisionConfigs.getEffectiveMinSolarToStart(solarMax)
	end
	return HeatVisionConfigs.getEffectiveMinSolarToStart(
		HeatVisionConfigs.SolarEnergy.BaseMax or 60
	)
end

function HeatVisionConfigs.ensureSolarDefaults(data: any)
	local solar = HeatVisionConfigs.SolarEnergy
	local baseMax = if solar and typeof(solar.BaseMax) == "number" then solar.BaseMax else 60
	if typeof(data.SolarMax) ~= "number" or data.SolarMax <= 0 then
		data.SolarMax = baseMax
	end
	if typeof(data.SolarCurrent) ~= "number" then
		data.SolarCurrent = data.SolarMax
	end
	data.SolarCurrent = math.clamp(data.SolarCurrent, 0, data.SolarMax)
end

function HeatVisionConfigs.refillSolarToMax(data: any)
	HeatVisionConfigs.ensureSolarDefaults(data)
	data.SolarCurrent = data.SolarMax
end

function HeatVisionConfigs.migrateSolarProfile(data: any)
	HeatVisionConfigs.ensureSolarDefaults(data)
end

return HeatVisionConfigs

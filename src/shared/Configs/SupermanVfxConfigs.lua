--!strict

-- Tuning for Superman surface-break VFX (takeoff / wall impact / landing) and flight sounds.

export type BreakTier = "Takeoff" | "ImpactWall" | "ImpactFloor" | "Landing"

local SupermanVfxConfigs = {

	Debug = false,

	Sounds = {
		FolderPath = { "Shared", "Assets", "SupermanFlightSounds" },
		GroundCracking             = "GroundCracking",
		StartFlying                = "StartFlying",
		ConstantFlying             = "ConstantFlying",
		ConstantFlyingParentName   = "ConstantFlyingSfx",
		GroundCrackingLifetime     = 6,
		StartFlyingLifetime        = 6,
		StartFlyingVolume          = 1,
		GroundCrackingVolume       = 1,
		ImpactBreak                = "ImpactBreak",
		ImpactBreakLifetime        = 3,
	},

	MinImpactSpeed   = 42,
	MinLandingSpeed  = 12,
	TouchdownMaxHeight = 7,
	--- Feet within this height of floor counts as touchdown even if replicated velocity is zero.
	TouchdownCloseHeight = 2.5,
	MaxActiveScorches = 8,
	FloorRayLength   = 35,
	FloorNormalMinY  = 0.7,
	WallNormalMaxY   = 0.3,

	Break = {
		ParticleTexture = "rbxassetid://1370553768",
		AnchorLifetime  = 3,

		Scorch = {
			Color            = Color3.fromRGB(18, 16, 14),
			FadeDuration     = 3,
			Thickness        = 0.04,
		},

		ParticleDefaults = {
			SpeedMin     = 6,
			SpeedMax     = 14,
			LifetimeMin  = 0.35,
			LifetimeMax  = 0.75,
			Spread       = Vector2.new(55, 55),
			LightEmission = 0.02,
		},

		DustColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(200, 198, 190)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(140, 135, 125)),
			ColorSequenceKeypoint.new(1,   Color3.fromRGB(90,  85,  78)),
		}),

		BlackDustColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Color3.fromRGB(45, 42, 38)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(28, 26, 24)),
			ColorSequenceKeypoint.new(1,   Color3.fromRGB(12, 11, 10)),
		}),

		LandingParticles = {
			--- Neutral gray smoke (1370553768 is green-tinted; do not use for landing).
			Texture       = "rbxassetid://243660364",
			Burst         = 36,
			Scale         = 1.35,
			SpeedMin      = 10,
			SpeedMax      = 22,
			LifetimeMin   = 0.25,
			LifetimeMax   = 0.55,
			Spread        = Vector2.new(70, 70),
			SizePeak      = 2.4,
			LightEmission = 0,
			LightInfluence = 0,
			UseFloorTint  = false,
			--- Warm gray/brown dust (G kept lowest per keypoint to avoid green cast).
			DustColor     = ColorSequence.new({
				ColorSequenceKeypoint.new(0,   Color3.fromRGB(242, 232, 228)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(188, 168, 162)),
				ColorSequenceKeypoint.new(1,   Color3.fromRGB(128, 108, 102)),
			}),
		},

		Tiers = {
			Takeoff = {
				ParticleBurst   = 8,
				ParticleScale   = 0.55,
				ScorchDiameter  = 3.5,
				ScorchAlpha     = 0.55,
				Ring            = false,
			},
			ImpactFloor = {
				ParticleBurst   = 6,
				ParticleScale   = 0.5,
				ScorchDiameter  = 3,
				ScorchAlpha     = 0.4,
				Ring            = false,
			},
			ImpactWall = {
				ParticleBurst   = 12,
				ParticleScale   = 0.85,
				ScorchDiameter  = 5.5,
				ScorchAlpha     = 0.35,
				RingMaxDiameter = 7,
				RingDuration    = 0.2,
				RingColor       = Color3.fromRGB(35, 32, 30),
				Ring            = true,
				UseBlackDust    = true,
			},
			Landing = {
				ParticleBurst   = 0,
				ParticleScale   = 1,
				ScorchDiameter  = 11,
				ScorchAlpha     = 0.3,
				RingMaxDiameter = 16,
				RingDuration    = 0.38,
				RingColor       = Color3.fromRGB(220, 218, 210),
				Ring            = true,
				UseBlackDust    = false,
				UseLandingParticles = true,
				SpawnChunks     = true,
			},
		},

		LandingChunks = {
			FolderName        = "SupermanLandingVfx",
			Count             = 24,
			StaggerSeconds    = 0.018,
			Lifetime          = 3.2,
			WedgeRatio        = 0.7,
			SizeMin           = Vector3.new(0.9,  0.16, 1.0),
			SizeMax           = Vector3.new(2.0,  0.38, 1.85),
			SlideDistance     = 11,
			SlideDistanceSpread = 4,
			LaunchSpeed       = 58,
			LaunchSpeedSpread = 14,
			UpLaunchSpeed     = 26,
			UpLaunchSpread    = 8,
			AngularSpeed      = 32,
			CanCollide        = true,
			FootInset         = 0.2,
			FootSideOffset    = 1.6,
			DefaultColor      = Color3.fromRGB(95, 90, 85),
			FallbackMaterial  = Enum.Material.Concrete,
			NearbyRayLength   = 6,
		},

		Cooldowns = {
			Takeoff      = 0.5,
			ImpactWall   = 0.4,
			ImpactFloor  = 0.55,
			Landing      = 0.8,
		},
	},

	Impact = {
		Cooldown        = 0.4,
		RaycastDistance = 12,
	},
}

return SupermanVfxConfigs

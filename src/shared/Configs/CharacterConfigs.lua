--!strict

-- Central tuning for character mechanics. Edit here instead of CharacterController.lua.
-- Per-player / per-stage overrides: see LevelDesignConfigs.lua (E_* / Spd_* attributes on Player or LD_Zone parts).

local CharacterConfigs = {
	Features = {
		DisableDefaultAnimate = true,
		UseCustomJump = true,
		UseCustomLocomotion = true,
		UseBasicJumpAnims = true,
		UseDoubleJump = true,
		UseGlideVfx = true,
		UseCapeVfx = true,
		UseSuperJump = false,
		UseLongJump = true,
		ForceRunOnTreadmill = true,
	},

	Animations = {
		FolderName = "SupesAnimations",
		Idle = "IdleAnimation",
		Run = "RunAnimation",
		BasicJumpFolder = "BasicJump",
		Jump = "Jump",
		Fall = "Fall",
		Landing = "Landing",
	},

	Locomotion = {
		MoveThreshold = 0.1,
		FadeTime = 0.15,
	},

	BasicJump = {
		JumpVelocity = 80,
		LandingRayDistance = 4,
		MinFallTime = 0.15,
		MinJumpAirTime = 0.05,
		LeaveGroundVelocity = 8,
		ApexVelocityThreshold = 5,
		JumpActionName = "SupesJump",
	},

	DoubleJump = {
		ActionName = "SupesDoubleJump",
		Key = "E",
		Cooldown = 5,
		MaxAbilityDuration = 7,
		Debug = false,

		Network = {
			ClientOwnsFlightPhysics = true,
			SteerSendHz = 15,
		},

		AnimFolder = "DoubleJump",
		Anims = {
			FlightTransit = "FlightTrannsit",
			AfterTransition = "AfterTransition",
			LeanUp = "LeanUp",
			LeapDown = "LeapDown",
			DownSupes = "DownSupes",
		},
		CancelAnims = {
			Folder = "BasicJump",
			Fall = "Fall",
			Landing = "Landing",
		},

		SupermanPose = {
			TransitStartPitch = 0,
			TransitEndPitch = -35,
			TransitPitchLerp = 8,
			TransitLaunchClimbDegrees = 10,
			FlightPitch = -85,
			PitchLerp = 10,
			UprightPitch = 0,
			MaxBankDegrees = 55,
			BankFollowRate = 6,
			BankReturnRate = 2,
			CameraBankBlend = 0.85,
			CameraYawRateForFullBank = 1.2,
			CameraYawRateMin = 0.35,
			--- Launch: forward-lean first, gentle climb, then ease to superman pitch during rise.
			LaunchClimbStartDegrees = 14,
			LaunchClimbEndDegrees = 26,
			LaunchBodyPitch = -72,
			LaunchPitchLerp = 5,
			CameraPitchRateForFullAxis = 1.0,
			CameraPitchRateMin = 0.3,
			CameraPitchVelocityBlend = 0.35,
		},

		Phases = {
			FlightTransit = {
				Duration = 0.4,
				ForwardNudgeSpeed = 16,
			},
			AfterTransition = {
				RiseSpeed = 42,
				ForwardSpeed = 68,
				TargetHeightAboveStart = 28,
				MaxDuration = 1.1,
				MinDuration = 0.5,
				RequiresHold = true,
				SteerMoveThreshold = 0.1,
			},
			LeanUp = {
				ForwardSpeed = 65,
				ForwardDistance = 100,
				MaxDuration = 0.9,
				RequiresHold = true,
			},
			-- Descent physics while still in LeanUp phase (client plays DownSupes anim).
			LeapDown = {
				DescentSpeed = 70,
				SlowDescentHeight = 12,
				MinDuration = 0.15,
				SurfaceRayLength = 250,
				AlignToHit = true,
				HorizontalLerp = 0.15,
			},
			-- Landing timing during LeapDown phase (client plays LeapDown anim).
			DownSupes = {
				TriggerHeightAboveSurface = 6,
				UprightSnapHeight = 6,
				ApproachDescentSpeed = 12,
				UsePlatformStandOnApproach = false,
				LandingLockDuration = 0.2,
				MinGroundedPlayDuration = 0.4,
				SettleDuration = 0.15,
				MaxStableVelocityY = 4,
				MaxDuration = 2.5,
				WalkableNormalMinY = 0.6,
				GroundProbeDistance = 8,
				GroundClearanceTolerance = 1.25,
				AirborneProbeDistance = 64,
				ObstacleProbeDistance = 4,
				WallProbeDistance = 5,
				LandingProbeInterval = 0.12,
				ObstacleProbeInterval = 0.15,
			},
		},

		-- Overlap when switching E phase animations (reduces hard cuts).
		PhaseFadeTime = 0.22,
		LandingFadeTime = 0.28,

		Steering = {
			Enabled = true,
			FollowCameraPitch = true,
			MaxPitchDegrees = 45,
			DirectionLerp = 10,
			HorizontalSpeed = 45,
			DescentHorizontalBlend = 0.35,
			SteerMoveThreshold = 0.1,
			SteerAxisSmoothRate = 14,
			-- LeanUp A/D: snap axis + high yaw so hold time = turn amount (no camera fight).
			UseSlowKeyboardYawOnLeanUp = true,
			KeyboardYawDegreesPerSecond = 115,
			KeyboardStrafeSpeed = 58,
			KeyboardAxisSmoothRateLeanUp = 48,
			KeyboardBankOnlyPhases = {
				LeanUp = true,
			},
		},

		Cancel = {
			--- Downward speed when releasing E mid-air (not the slow landing approach).
			FallSpeed = 90,
			LandingRayLength = 250,
			LandingTriggerHeight = 10,
			MinFallTime = 0,
			MaxFallDuration = 6,
			SettleDuration = 0.35,
			MaxLandingDuration = 1.25,
		},

		Activation = {
			AllowGrounded = true,
			AllowAirborne = true,
		},
	},

	LongJump = {
		DoubleTapWindow = 0.35,
		ForwardPower = 110,
		UpPower = 95,
		Cooldown = 1.0,
		-- SupesAnimations / SuperJump / LeanUp (same asset as SuperJump ability)
		AnimFolder = "SuperJump",
		LeanUpAnim = "LeanUp",
		LeanUpFadeTime = 0.12,
		LeanUpDuration = 0.9,
	},

	SuperJump = {
		AnimFolder = "SuperJump",
		Anims = {
			LeanUp = "LeanUp",
			DownSupes = "DownSupes",
		},
		DoubleTapWindow = 0.35,
		Cooldown = 1.5,
		MaxDuration = 4,
		PhaseFadeTime = 0.22,

		LeanUp = {
			-- Rise first (mostly up); glide forward only after rise completes (latched).
			RiseSpeed = 35,
			RiseHeight = 5,
			RiseMaxDuration = 0.4,
			-- Glide speed = ForwardDistance / MaxGlideDuration (e.g. 20 studs in 0.5s = 40/s).
			ForwardDistance = 50,
			MaxGlideDuration = 0.5,
			GlideFallSpeed = 6,
			MinAirTime = 0.12,
			DescentSpeed = 55,
			SurfaceRayLength = 250,
		},

		DownSupes = {
			TriggerHeightAboveSurface = 6,
			ApproachDescentSpeed = 40,
			MinDuration = 0.15,
			SettleDuration = 0.15,
			MaxDuration = 2,
		},
	},
}

return CharacterConfigs

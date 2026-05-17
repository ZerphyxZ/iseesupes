--!strict

-- Central tuning for character mechanics. Edit here instead of CharacterController.lua.

local CharacterConfigs = {
	Features = {
		DisableDefaultAnimate = true,
		UseCustomJump = true,
		UseCustomLocomotion = true,
		UseBasicJumpAnims = true,
		UseDoubleJump = true,
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
		MaxAbilityDuration = 4,

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
			TransitEndPitch = -40,
			TransitPitchLerp = 12,
			FlightPitch = -85,
			PitchLerp = 10,
			UprightPitch = 0,
		},

		Phases = {
			FlightTransit = {
				Duration = 0.35,
				ForwardNudgeSpeed = 12,
			},
			AfterTransition = {
				RiseSpeed = 50,
				ForwardSpeed = 60,
				TargetHeightAboveStart = 28,
				MaxDuration = 1.1,
				RequiresHold = true,
				SteerMoveThreshold = 0.1,
			},
			LeanUp = {
				ForwardSpeed = 65,
				ForwardDistance = 100,
				MaxDuration = 0.9,
				RequiresHold = true,
			},
			-- Tuning for DownSupes phase (descent toward ground; plays DownSupes anim).
			LeapDown = {
				DescentSpeed = 70,
				SlowDescentHeight = 12,
				MinDuration = 0.15,
				SurfaceRayLength = 250,
				AlignToHit = true,
				HorizontalLerp = 0.15,
			},
			-- Tuning for LeapDown phase (landing anim; controls restore after full playthrough).
			DownSupes = {
				TriggerHeightAboveSurface = 6,
				UprightSnapHeight = 6,
				ApproachDescentSpeed = 12,
				UsePlatformStandOnApproach = false,
				MinGroundedPlayDuration = 1,
				SettleDuration = 0.35,
				MaxStableVelocityY = 4,
				MaxDuration = 2.5,
			},
		},

		LandingFadeTime = 0.2,

		CameraAttach = {
			Enabled = true,
		},

		Cancel = {
			LandingRayDistance = 4,
			MinFallTime = 0.1,
			MaxFallDuration = 6,
		},

		Activation = {
			AllowGrounded = true,
			AllowAirborne = true,
		},
	},
}

return CharacterConfigs

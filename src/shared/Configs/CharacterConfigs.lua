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

		Phases = {
			FlightTransit = { Duration = 0.35 },
			AfterTransition = {
				RiseSpeed = 55,
				TargetHeightAboveStart = 28,
				MaxDuration = 1.1,
				RequiresHold = true,
			},
			LeanUp = {
				ForwardSpeed = 65,
				ForwardDistance = 100,
				MaxDuration = 0.9,
				RequiresHold = true,
			},
			LeapDown = {
				DescentSpeed = 70,
				SurfaceRayLength = 250,
				AlignToHit = true,
				HorizontalLerp = 0.15,
			},
			DownSupes = {
				TriggerHeightAboveSurface = 5,
				Duration = 0.5,
			},
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

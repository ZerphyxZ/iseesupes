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
		UseHeatVision = false,
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
		--- Horizontal air-speed cap (studs/s) so a jump's DISTANCE is independent of walk
		--- speed — it always travels ~JumpHorizontalSpeed × 0.82 studs no matter how fast
		--- you run. Lets walk speed scale high while the S8/S9 pillar jumps stay consistent.
		--- (CharacterController clamps horizontal velocity to this while airborne from a
		--- basic jump; long-jumps and flight set their own speed and are not capped.)
		JumpHorizontalSpeed = 34,
		LandingRayDistance = 4,
		MinFallTime = 0.15,
		MinJumpAirTime = 0.05,
		LeaveGroundVelocity = 8,
		ApexVelocityThreshold = 5,
		JumpActionName = "SupesJump",
		--- Player attribute set true while airborne from an INTENTIONAL basic jump (set in
		--- CharacterController.enterJump, cleared on land / locomotion / ability takeover).
		--- Read by SpeedController to award boosted Speed XP during the arc so jumping feels
		--- rewarding. A plain ledge walk-off never enters enterJump, so it earns no bonus.
		ArcActiveAttribute = "BasicJumpArcActive",
	},

	DoubleJump = {
		ActionName = "SupesDoubleJump",
		Key = "E",
		--- Console/controller button for fly (same action as Key).
		GamepadKey = "ButtonY",
		--- Kryptonite stages: starting flight instantly drains ALL thrust (jump-only stages).
		Kryptonite = {
			Enabled = true,
			Stages = { [8] = true } :: { [number]: boolean },
			Message = "Kryptonite! Your flight power is drained — jump through this stage!",
			--- Stage 8 Krypts platforms fade while stood on, then drop the player through.
			--- Purely client-side: each player sees/feels only their own platform state.
			FadePlatforms = {
				Enabled = true,
				StageModelName = "Stage8",
				FolderName = "Krypts",
				ModelName = "KryptoModels",
				--- Seconds standing on a platform before it lets the player fall through.
				FadeDuration = 2.5,
				--- Seconds for a partially faded platform to fade back after stepping off.
				RecoverDuration = 1.2,
				--- Seconds before a fallen-through platform turns solid again.
				RestoreDelay = 2.0,
				--- Don't fade fully transparent; keep a ghost outline so players can retry.
				MaxTransparency = 0.92,
				--- Downward ray length from character root to detect the platform under foot.
				StandRayLength = 8,
				--- With a tiny StreamingEnabled radius, pull Krypts geometry around the player.
				RequestStreamAround = true,
				StreamRequestInterval = 2.0,
				--- Rough Stage 8 Krypts course bounds (from map authoring).
				StreamBounds = {
					CenterX = -221810,
					RadiusX = 250,
					MinZ = 6600,
					MaxZ = 7800,
				},
			},
		},
		Cooldown = 1,
		--- Must fly at least this long before E / UI / Space can cancel thrust.
		CancelMinActiveTime = 1.25,
		--- Cancel within this many seconds after start → no cooldown on landing (after MinActiveTime).
		CancelCooldownGrace = 2.5,
		MaxAbilityDuration = 7,
		Debug = false,
		--- Grace after E press: skip collision/hard-ground end and block client grounded landing.
		TakeoffGraceSeconds = 1.2,
		--- One-shot upward velocity when still on walkable floor during early takeoff.
		TakeoffGroundBoost = 32,

		Network = {
			ClientOwnsFlightPhysics = true,
			SteerSendHz = 15,
		},

		--- Applied on touch-only clients for smoother camera-steer flight (less twitchy bank/pitch).
		Mobile = {
			Steering = {
				CameraSteerSmoothRate = 5,
				SteerSmoothRate = 5,
				SteerAxisSmoothRate = 5,
				DirectionLerp = 4,
				CameraYawRateForFullBank = 4.8,
				CameraYawRateMin = 0.45,
				CameraYawRateMinAxis = 0.12,
				CameraPitchRateForFullAxis = 2.8,
			},
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
			TransitLaunchClimbDegrees = 12,
			FlightPitch = -85,
			PitchLerp = 10,
			UprightPitch = 0,
			MaxBankDegrees = 42,
			BankFollowRate = 3.5,
			BankReturnRate = 2,
			--- Heading turn rate (deg/s) that drives full bank — roll follows actual yaw like a plane.
			TurnYawRateForFullBank = 95,
			TurnSpeedReference = 65,
			TurnBankWeight = 0.92,
			InputBankWeight = 0.28,
			CameraBankBlend = 0.4,
			--- Higher = need a faster mouse spin for full bank (less sensitive).
			CameraYawRateForFullBank = 3.2,
			CameraYawRateMin = 1.0,
			CameraYawRateMinAxis = 0.16,
			CameraHeadingDegreesForFullBank = 60,
			--- Launch: forward-lean first, gentle climb, then ease to superman pitch during rise.
			LaunchClimbStartDegrees = 8,
			LaunchClimbEndDegrees = 17,
			LaunchBodyPitch = -72,
			LaunchPitchLerp = 5,
			CameraPitchRateForFullAxis = 2.3,
			CameraPitchRateMin = 0.8,
			CameraPitchRateMinAxis = 0.18,
			CameraPitchVelocityBlend = 0.35,
		},

		Phases = {
			FlightTransit = {
				Duration = 0.45,
				ForwardNudgeSpeed = 24,
			},
			AfterTransition = {
				RiseSpeed = 28,
				ForwardSpeed = 68,
				TargetHeightAboveStart = 16,
				--- Min height gain before LeanUp (primary gate; MaxDuration is failsafe-only).
				TakeoffMinHeightAboveStart = 6,
				TakeoffFailsafeDuration = 1.4,
				TakeoffFailsafeMinHeight = 2,
				MaxDuration = 0.9,
				MinDuration = 0.35,
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
				GroundClearanceTolerance = 0.35,
				--- Feet-above-surface before glide counts as near ground (LeanUp / hard-ground). Much tighter than landing trigger.
				FlightNearGroundHeight = 1.25,
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
			DirectionLerp = 5,
			HorizontalSpeed = 32,
			DescentHorizontalBlend = 0.35,
			SteerMoveThreshold = 0.1,
			SteerSmoothRate = 6,
			--- Lower = flight direction follows the camera more gently (less mouse sensitivity).
			CameraSteerSmoothRate = 3,
			SteerAxisSmoothRate = 7,
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
		--- One jump press = long jump; never defer to basic short hop.
		SingleTapInput = true,
		--- Legacy (unused when SingleTapInput): double-tap / hold timing.
		DoubleTapWindow = 0.35,
		HoldThreshold = 0.18,
		ForwardPower = 110,
		UpPower = 95,
		Cooldown = 1.0,
		--- After a ground long jump, allow N extra full-strength long jumps in the air (single Jump press).
		--- Total cycle = 1 ground + MaxAirLongJumps air (HUD shows used/2 when MaxAirLongJumps = 1).
		AirLongJumpEnabled = true,
		--- Air long jumps granted only after a ground long jump; refill ONLY on landing.
		MaxAirLongJumps = 1,
		--- After both jumps in a cycle are spent, this many seconds must pass before they refill, AND the
		--- player must be back on the ground. Drives the "Recharging Xs" HUD countdown.
		ExhaustCooldown = 1.0,
		--- Player attribute set true while airborne from a long jump. Read by SpeedController.
		ArcActiveAttribute = "LongJumpArcActive",
		--- false = long jumps EARN (boosted) Speed XP during the arc so they feel rewarding.
		--- true = legacy behaviour: no XP at all during the arc. Long jump travels fast (110
		--- studs/s), so even un-boosted it earns well; the server's AddSpeedMinInterval throttle
		--- caps total earn at ~20 Speed/s, so this can't be exploited into runaway leveling.
		SuppressSpeedXpDuringArc = false,
		--- Raycast ground check (fixes high-speed FloorMaterial flicker at ~245 walk).
		UseRaycastGroundCheck = true,
		GroundProbeDistance = 6,
		GroundClearanceTolerance = 1.5,
		--- Allow ground long jump briefly after leaving floor (high walk speed).
		CoyoteTimeSeconds = 0.12,
		-- SupesAnimations / SuperJump / LeanUp (same asset as SuperJump ability)
		AnimFolder = "SuperJump",
		LeanUpAnim = "LeanUp",
		LeanUpFadeTime = 0.12,
		LeanUpDuration = 0.9,
		-- Foot smoke + whoosh (Studio: QuickWhoosh in SupermanFlightSounds or Woosh in GlideVfxSounds)
		UseLaunchFeedback = true,
		LaunchSound = "QuickWhoosh",
		LaunchSoundFallbacks = { "QuickWhoosh", "Quick Whoosh", "Woosh" },
		LaunchSoundFolders = {
			{ "Shared", "Assets", "SupermanFlightSounds" },
			{ "Shared", "Assets", "GlideVfxSounds" },
		},
		LaunchVfxTier = "LongJumpLaunch",
		LaunchVfxTierAir = "LongJumpLaunchAir",
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

	--- Lift slightly, fall, Superman landing VFX.
	--- OnFirstJoin only — win claim returns are a plain teleport (no drop/prone landing).
	SpawnIntro = {
		Enabled = true,
		OnFirstJoin = true,
		OnWinClaimReturn = false,
		LiftHeight = 8,
		PrepareDelay = 0.12,
		LobbySettleDelay = 0.25,
		MaxLandingWatchSeconds = 8,
		MinLandingSpeed = 4,
	},
}

return CharacterConfigs

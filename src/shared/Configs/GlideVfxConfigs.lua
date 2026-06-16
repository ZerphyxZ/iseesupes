--!strict

-- Cape states (Idle / Walk / Fly / Land) + limb glide trails/sounds during E-flight.

export type CapeVisualState = "Idle" | "Walk" | "Fly" | "Land"

local GlideVfxConfigs = {
	Enabled = true,

	--- Studio Output diagnostics for cape rig / state / cloth sim.
	Debug = false,

	--- Seconds to wait for Suit/UT/Cape replication after spawn or showcase morph.
	RigWaitSeconds = 8,

	--- Search under character for the cape rig root (first match wins).
	CapeSearchPaths = {
		{ "UT", "Cape" },
		{ "Suit", "UT", "Cape" },
		{ "Cape" },
	},

	--- Mesh part name on or under the cape rig (tried in order).
	CapeMeshNames = { "Cape", "Cape2" },

	--- Legacy names (still checked by resolveCapeRig).
	CapeModelName = "Cape",
	CapePartName = "Cape2",
	InitialPosesFolderName = "InitialPoses",
	PoseFolderName = "CapePoses",

	States = {
		Idle = "Idle",
		Walk = "Walk",
		Fly = "Fly",
		Land = "Land",
	} :: { [string]: CapeVisualState },

	LimbNames = { "LeftFoot", "RightFoot", "LeftHand", "RightHand" },

	Locomotion = {
		MoveThreshold = 0.1,
	},

	WalkFlutter = {
		Enabled = true,
		Frequency = 5,
		AmplitudeRadians = math.rad(18),
	},

	--- If true, only wind attributes run when Roots exists (needs a Studio cloth plugin).
	--- false = always drive bones procedurally (recommended; your logs show wind changes but no plugin motion).
	ClothPluginDrivesBones = false,

	--- Wind attrs on UT.Cape are optional; keep false so procedural Transform drive is not overridden.
	ApplyClothWindAttributes = false,

	--- Remove cloth Roots attrs on client so procedural + Motor6D are not frozen without a plugin.
	StripClothAttrsForProcedural = true,

	CapeMotorName = "CapeTorsoMotor",

	-- Set false to keep the original WeldConstraint and skip Motor6D creation.
	-- CapeAnimatorController drives bones directly; no Motor6D needed.
	UseMotor6D = false,

	--- Optional MeshPart attributes (Six Superman UT.Cape cloth sim).
	ClothAttributes = {
		WindStrength = true,
		WindSpeed = true,
		WindInfluence = true,
	},

	ClothByState = {
		Idle = { WindStrength = 0.4, WindSpeed = 1.5, WindInfluence = 1 },
		Walk = { WindStrength = 1.2, WindSpeed = 4, WindInfluence = 1.5 },
		Fly = { WindStrength = 2.5, WindSpeed = 10, WindInfluence = 2.5 },
		Land = { WindStrength = 1.8, WindSpeed = 6, WindInfluence = 2 },
	},

	--- Only these roots get state offsets / flutter (full cape chains hang from them).
	RootBoneNames = { "Bone", "Bone.011" },

	-- Bone driving is handled by CapeAnimatorController; keep this off to avoid write conflicts.
	Procedural = {
		Enabled = false,
		VelocityInfluence = 0.045,
		MaxBonePitch = math.rad(55),
		RootFlutterScale = 2.5,
	},

	Tween = {
		CapeFadeIn = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		CapeFadeOut = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Bone = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Texture = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},

	Cape = {
		VisibleTransparency = 0,
		TextureTransparency = 0.2,
		--- Used when building runtime Fly poses if CapePoses/Fly is missing.
		BoneSpreadOffset = CFrame.new(0, 0, 0.5) * CFrame.Angles(0, 0, math.rad(-15)),
		--- Per-state bone multipliers from Idle (runtime bootstrap only).
		--- Local-space Bone.Transform offsets (roots only). CFrame on bones does not deform skinned meshes.
		FallbackOffsets = {
			Walk = CFrame.Angles(math.rad(14), math.rad(8), math.rad(-22)),
			Fly = CFrame.Angles(math.rad(28), math.rad(14), math.rad(-50)),
			Land = CFrame.Angles(math.rad(32), math.rad(10), math.rad(-35)),
		},
		--- Expensive on mobile; ClientPerformance disables at runtime on low-end devices.
		EnableFluidForces = true,

		--- Whole-cape tilt via Motor6D (UpperTorso → Cape); visible even when bone skinning is inert.
		MeshMotorOffsets = {
			Idle = CFrame.new(),
			Walk = CFrame.Angles(math.rad(14), math.rad(8), math.rad(-22)),
			Fly = CFrame.Angles(math.rad(28), math.rad(14), math.rad(-50)),
			Land = CFrame.Angles(math.rad(32), math.rad(10), math.rad(-35)),
		},
		MeshMotorFlutterScale = 1.8,
	},

	--- E-ability phases that use Fly cape + glide trails/sounds.
	FlyPhases = {
		FlightTransit = true,
		AfterTransition = true,
		LeanUp = true,
		DownSupes = true,
		CancelFall = true,
	},

	--- E-ability phases that use Land cape pose.
	LandPhases = {
		LeapDown = true,
		CancelLanding = true,
	},

	--- Back-compat alias for older glide-only checks (subset of Fly, no DownSupes).
	GlidePhases = {
		FlightTransit = true,
		AfterTransition = true,
		LeanUp = true,
	},

	Trail = {
		Name = "GlideTrail",
		Texture = "rbxassetid://3517446796",
		Lifetime = 1,
		LightInfluence = 1,
		Brightness = 1,
		LightEmission = 0,
		Attachment0Offset = CFrame.new(0.38, 0, 0),
		Attachment1Offset = CFrame.new(-0.48, 0, 0),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.9, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	},

	Assets = {
		FlyLoop = { "Characters", "Combat", "Fx", "FlyLoopSfx" },
		StartGlideSoundName = "StartGlide",
		FlyLoopParentName = "FlyLoopSfx",
		GlideSoundsFolder = { "Shared", "Assets", "GlideVfxSounds" },
	},
}

return GlideVfxConfigs

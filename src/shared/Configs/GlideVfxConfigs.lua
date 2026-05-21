--!strict

-- Cape + limb trails + sounds during E-glide (FlightTransit / AfterTransition / LeanUp).

local GlideVfxConfigs = {
	Enabled = true,

	CapeModelName = "Cape",
	CapePartName = "Cape2",
	InitialPosesFolderName = "InitialPoses",

	LimbNames = { "LeftFoot", "RightFoot", "LeftHand", "RightHand" },

	Tween = {
		CapeFadeIn = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		CapeFadeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Bone = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Texture = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	},

	Cape = {
		GlideTransparency = 0,
		HiddenTransparency = 1,
		TextureGlideTransparency = 0.2,
		BoneSpreadOffset = CFrame.new(0, 0, 0.5) * CFrame.Angles(0, 0, math.rad(-15)),
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

	--- Phases where cape + trails are active (matches hold-E glide).
	GlidePhases = {
		FlightTransit = true,
		AfterTransition = true,
		LeanUp = true,
	},

	--- Optional ReplicatedStorage paths (first existing instance wins).
	Assets = {
		FlyLoop = { "Characters", "Combat", "Fx", "FlyLoopSfx" },
		StartGlideSoundName = "StartGlide",
		FlyLoopParentName = "FlyLoopSfx",
		--- Optional: ReplicatedStorage.Shared.Assets.GlideVfxSounds (Woosh, Wind, Clothing Sound instances).
		GlideSoundsFolder = { "Shared", "Assets", "GlideVfxSounds" },
	},
}

return GlideVfxConfigs

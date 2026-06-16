--!strict

local GiveWinsConfigs = require(script.Parent.GiveWinsConfigs)
local TreadmillConfigs = require(script.Parent.TreadmillConfigs)
local UpgradeWinsConfigs = require(script.Parent.UpgradeWinsConfigs)
local ThrustUpgradeConfigs = require(script.Parent.ThrustUpgradeConfigs)

export type TutorialStepId = number

local TutorialConfigs = {
	Step = {
		GoTreadmill = 1,
		ClaimWins = 2,
		UpgradeAvatar = 3,
		CoreDone = 4,
		GoStage1 = 5,
		Complete = 6,
		--- Legacy alias (upgrade touch sets CoreDone).
		Done = 4,
	},

	StageCheckpointsFolderName = "StageCheckpoints",
	Stage1CheckpointName = "1",
	Stage1TouchDebounceSeconds = 2,
	--- Fallback when Touched misses (glass/frame parts): studs from any Stage 1 checkpoint part.
	Stage1ProximityRadius = 24,

	MinLevelForClaimStep = 2,
	MinWinsForUpgradeStep = 3,

	ThrustHintMinWins = 30,

	Debug = false,

	WorldResolveTimeout = 30,
	TargetRetrySeconds = 1,

	BasicTreadmillTierKey = "Silver",
	GiveWinsButtonName = "Button1",
	UpgradeWinsButtonName = "Button1",

	GiveWinsFolderName = GiveWinsConfigs.FolderName,
	GiveWinsTouchPartName = GiveWinsConfigs.TouchPartName,
	UpgradeWinsFolderName = UpgradeWinsConfigs.FolderName,
	UpgradeWinsTouchPartName = UpgradeWinsConfigs.TouchPartName,

	ThrustShopFolderName = ThrustUpgradeConfigs.FolderName,
	ThrustShopTouchModelName = ThrustUpgradeConfigs.TouchModelName,
	ThrustShopTouchPartName = ThrustUpgradeConfigs.TouchPartName,

	TreadmillsFolderName = TreadmillConfigs.World.TreadmillsFolderName,

	--- Foot-beam path guide (treadmill → wins → upgrade → stage). Off when hidden in Studio.
	FootBeam = {
		Enabled = true,
	},

	Beam = {
		Texture = "rbxassetid://115279166708864",
		Color = Color3.fromRGB(206, 23, 6),
		-- Wide racing-style chevrons along the floor path.
		Width0 = 8,
		Width1 = 10,
		TextureLength = 14,
		TextureSpeed = 3.5,
		FaceCamera = false,
		LightEmission = 0.95,
		LightInfluence = 0,
		Transparency = NumberSequence.new(0),
		FootOffset = Vector3.new(0, -2.85, 0),
		-- Studs above the target part's bottom face (floor path).
		TargetSurfaceLift = 0.2,
		-- Lay chevrons flat on the floor and point along the path (racing-arrow style).
		AttachmentTiltDegrees = { X = 90, Y = 0, Z = 90 },
		AttachmentYawOffsetDegrees = 0,
	},

	StepMessages = {
		[1] = "Train on the treadmill to level up!",
		[2] = "Claim wins here to unlock your suit!",
		[3] = "Unlock your first suit!",
	},

	FlyIntro = {
		Enabled = true,
		--- Studio layout under StarterGui (cloned to PlayerGui). Script only enables/disables.
		ScreenGuiName = "TutorialFlyHintGui",
		CalloutName = "FlyCallout",
		ArrowName = "FlyArrow",
		ArrowBobPixels = 14,
		ArrowBobPeriodSeconds = 0.65,
		HeartbeatPeakScale = 1.14,
		HeartbeatPeriodSeconds = 0.9,
		LabelPC = "Tap E to Fly",
		LabelMobile = "Tap Supes to Fly",
		LabelGamepad = "Tap Y to Fly",
	},

	--- Stage 1 fly lesson only (GoStage1, before TutorialFlyIntroShown).
	FlightAssist = {
		Enabled = true,
		AttributeName = "TutorialFlightAssist",
		RelaxRequiresHold = true,
		InfiniteThrust = true,
		SkipHardGroundEnd = true,
		MaxAbilityDuration = 45,
		LeanUpMaxDuration = 12,
		RefillThrustOnStepEnter = true,
	},

	LaserIntro = {
		Enabled = false,
		--- Studio layout under StarterGui (cloned to PlayerGui). Script only enables/disables.
		ScreenGuiName = "TutorialLaserHintGui",
		CalloutName = "FlyCallout",
		ArrowName = "FlyArrow",
		ArrowBobPixels = 14,
		ArrowBobPeriodSeconds = 0.65,
		HeartbeatPeakScale = 1.14,
		HeartbeatPeriodSeconds = 0.9,
		LabelPC = "Press F — melt the wall with your Laser",
		LabelMobile = "Press Vision — melt the wall with your Laser",
		LabelGamepad = "Press X — melt the wall with your Laser",
	},

	LowThrustFlyHint = {
		Enabled = true,
		MaxFillRatio = 0.25,
		UseMinFuelThreshold = true,
	},

	FlySteerHints = {
		Enabled = false,
	},

	ThrustShopIntro = {
		Enabled = true,
		ToastMessage = "Behind you: Upgrade Shop — spend wins later to boost thrust!",
		BeamBillboardMessage = "Upgrade thrust here!",
		BeamDurationSeconds = 0,
		CameraHoldSeconds = 1.2,
		CameraTweenSeconds = 0.8,
		GroundedWaitTimeoutSeconds = 5,
		HighlightFillColor = Color3.fromRGB(255, 180, 0),
		HighlightOutlineColor = Color3.fromRGB(255, 255, 255),
		HighlightFillTransparency = 0.5,
		HighlightOutlineTransparency = 0.2,
		PurchaseHintToast = "You have enough wins — upgrade thrust at the shop behind spawn!",
		PurchaseHintBeamSeconds = 0,
		AffordableBeamSeconds = 0,
	},
}

function TutorialConfigs.getBasicTreadmillModelName(): string
	local tier = TreadmillConfigs.Tiers[TutorialConfigs.BasicTreadmillTierKey]
	return if tier then tier.ModelName else "SilverTreadmill"
end

return TutorialConfigs

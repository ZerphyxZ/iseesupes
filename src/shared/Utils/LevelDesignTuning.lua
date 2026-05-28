--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local LevelDesignConfigs = require(ReplicatedStorage.Shared.Configs.LevelDesignConfigs)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local ThrustConfigs = SpeedConfigs.Thrust

local BaseDj = CharacterConfigs.DoubleJump
local BasePh = BaseDj.Phases
local BasePose = BaseDj.SupermanPose
local BaseSteer = BaseDj.Steering
local BaseCancel = BaseDj.Cancel

local ATTR = {
	Cooldown = "E_Cooldown",
	MaxDuration = "E_MaxTime",
	LandingFadeTime = "E_LandFade",
	TransitDuration = "E_TransTime",
	TransitNudgeSpeed = "E_TransNudge",
	RiseSpeed = "E_Rise",
	ForwardSpeed = "E_Fwd",
	TargetHeight = "E_Height",
	AfterMaxDuration = "E_RiseTime",
	AfterMinDuration = "E_RiseMin",
	LeanForwardSpeed = "E_LeanSpd",
	LeanForwardDistance = "E_LeanDist",
	LeanMaxDuration = "E_LeanTime",
	DescentSpeed = "E_FallSpd",
	SlowDescentHeight = "E_SlowHt",
	DescentMinDuration = "E_FallMin",
	SurfaceRayLength = "E_RayLen",
	DescentHorizontalLerp = "E_FallSteer",
	LandingTriggerHeight = "E_LandHt",
	UprightSnapHeight = "E_SnapHt",
	ApproachDescentSpeed = "E_Approach",
	LandingLockDuration = "E_LandLock",
	MinGroundedPlayDuration = "E_LandMin",
	LandingSettleDuration = "E_Settle",
	LandingMaxDuration = "E_LandMax",
	SteerEnabled = "E_Steer",
	SteerDirectionLerp = "E_SteerLerp",
	SteerHorizontalSpeed = "E_SteerSpd",
	SteerDescentBlend = "E_DSteer",
	SteerThreshold = "E_SteerThr",
	CancelFallSpeed = "E_CancelFall",
	CancelRayLength = "E_CanRay",
	CancelLandingHeight = "E_CanHt",
	CancelMinFallTime = "E_CanMin",
	CancelMaxFallDuration = "E_CanMax",
	FlightPitch = "E_Pitch",
	TransitStartPitch = "E_Pitch0",
	TransitEndPitch = "E_Pitch1",
	SpeedMultiplier = LevelDesignConfigs.Speed.MultiplierAttribute,
	SwimSpeedOverride = LevelDesignConfigs.Speed.OverrideAttribute,
}

local LEGACY = {
	Cooldown = "Design_DJ_Cooldown",
	MaxDuration = "Design_DJ_MaxDuration",
	LandingFadeTime = "Design_DJ_LandingFadeTime",
	TransitDuration = "Design_DJ_TransitDuration",
	TransitNudgeSpeed = "Design_DJ_TransitNudgeSpeed",
	RiseSpeed = "Design_DJ_RiseSpeed",
	ForwardSpeed = "Design_DJ_ForwardSpeed",
	TargetHeight = "Design_DJ_TargetHeight",
	AfterMaxDuration = "Design_DJ_AfterMaxDuration",
	AfterMinDuration = "Design_DJ_AfterMinDuration",
	LeanForwardSpeed = "Design_DJ_LeanForwardSpeed",
	LeanForwardDistance = "Design_DJ_LeanForwardDistance",
	LeanMaxDuration = "Design_DJ_LeanMaxDuration",
	DescentSpeed = "Design_DJ_DescentSpeed",
	SlowDescentHeight = "Design_DJ_SlowDescentHeight",
	DescentMinDuration = "Design_DJ_DescentMinDuration",
	SurfaceRayLength = "Design_DJ_SurfaceRayLength",
	DescentHorizontalLerp = "Design_DJ_DescentHorizontalLerp",
	LandingTriggerHeight = "Design_DJ_LandingTriggerHeight",
	UprightSnapHeight = "Design_DJ_UprightSnapHeight",
	ApproachDescentSpeed = "Design_DJ_ApproachDescentSpeed",
	LandingLockDuration = "Design_DJ_LandingLockDuration",
	MinGroundedPlayDuration = "Design_DJ_MinGroundedPlayDuration",
	LandingSettleDuration = "Design_DJ_LandingSettleDuration",
	LandingMaxDuration = "Design_DJ_LandingMaxDuration",
	SteerEnabled = "Design_DJ_SteerEnabled",
	SteerDirectionLerp = "Design_DJ_SteerDirectionLerp",
	SteerHorizontalSpeed = "Design_DJ_SteerHorizontalSpeed",
	SteerDescentBlend = "Design_DJ_SteerDescentBlend",
	SteerThreshold = "Design_DJ_SteerThreshold",
	CancelFallSpeed = "Design_DJ_CancelFallSpeed",
	CancelRayLength = "Design_DJ_CancelRayLength",
	CancelLandingHeight = "Design_DJ_CancelLandingHeight",
	CancelMinFallTime = "Design_DJ_CancelMinFallTime",
	CancelMaxFallDuration = "Design_DJ_CancelMaxFallDuration",
	FlightPitch = "Design_DJ_FlightPitch",
	TransitStartPitch = "Design_DJ_TransitStartPitch",
	TransitEndPitch = "Design_DJ_TransitEndPitch",
	SpeedMultiplier = "Design_SpeedMultiplier",
	SwimSpeedOverride = "Design_SwimSpeedOverride",
}

export type DoubleJumpTuning = typeof(BaseDj)

local function getAttributeSources(player: Player): { Instance }
	local sources: { Instance } = { player }
	local character = player.Character
	if character then
		table.insert(sources, character)
	end
	return sources
end

local function readNumber(source: Instance, name: string, legacyName: string?, default: number): number
	local value = source:GetAttribute(name)
	if typeof(value) == "number" and value == value then
		return value
	end
	if legacyName then
		local legacy = source:GetAttribute(legacyName)
		if typeof(legacy) == "number" and legacy == legacy then
			return legacy
		end
	end
	return default
end

local function clampTuningValue(name: string, value: number): number
	local bounds = LevelDesignConfigs.Clamps[name]
	if bounds then
		return math.clamp(value, bounds.Min, bounds.Max)
	end
	return value
end

local function readNumberForPlayer(player: Player, name: string, legacyName: string?, default: number): number
	for _, source in getAttributeSources(player) do
		local value = source:GetAttribute(name)
		if typeof(value) == "number" and value == value then
			return clampTuningValue(name, value)
		end
		if legacyName then
			local legacy = source:GetAttribute(legacyName)
			if typeof(legacy) == "number" and legacy == legacy then
				return clampTuningValue(name, legacy)
			end
		end
	end
	return default
end

local function readBoolFromNumber(source: Instance, name: string, legacyName: string?, default: boolean): boolean
	local value = source:GetAttribute(name)
	if typeof(value) == "boolean" then
		return value
	end
	if typeof(value) == "number" then
		return value ~= 0
	end
	if legacyName then
		local legacy = source:GetAttribute(legacyName)
		if typeof(legacy) == "boolean" then
			return legacy
		end
		if typeof(legacy) == "number" then
			return legacy ~= 0
		end
	end
	return default
end

local function readBoolForPlayer(player: Player, name: string, legacyName: string?, default: boolean): boolean
	for _, source in getAttributeSources(player) do
		local value = source:GetAttribute(name)
		if typeof(value) == "boolean" then
			return value
		end
		if typeof(value) == "number" then
			return value ~= 0
		end
		if legacyName then
			local legacy = source:GetAttribute(legacyName)
			if typeof(legacy) == "boolean" then
				return legacy
			end
			if typeof(legacy) == "number" then
				return legacy ~= 0
			end
		end
	end
	return default
end

local guidePrintedFor: { [Player]: boolean } = {}

local function attributeValuesEqual(a: any, b: any): boolean
	return a == b
end

local function pruneNonEssentialDefaults(target: Instance)
	for _, spec in LevelDesignConfigs.Attributes do
		if LevelDesignConfigs.isEssential(spec) then
			continue
		end

		local current = target:GetAttribute(spec.Name)
		if current ~= nil and attributeValuesEqual(current, spec.Default) then
			target:SetAttribute(spec.Name, nil)
		end

		if spec.LegacyName then
			local legacy = target:GetAttribute(spec.LegacyName)
			if legacy ~= nil and attributeValuesEqual(legacy, spec.Default) then
				target:SetAttribute(spec.LegacyName, nil)
			end
		end
	end
end

local tuningAttributeNames: { [string]: boolean } = {}
for _, spec in LevelDesignConfigs.Attributes do
	tuningAttributeNames[spec.Name] = true
	if spec.LegacyName then
		tuningAttributeNames[spec.LegacyName] = true
	end
end

local LevelDesignTuning = {}

function LevelDesignTuning.isTuningAttribute(name: string): boolean
	return tuningAttributeNames[name] == true
end

function LevelDesignTuning.setTuningAttribute(player: Player, name: string, value: number): boolean
	if not tuningAttributeNames[name] or typeof(value) ~= "number" or value ~= value then
		return false
	end
	local clamped = clampTuningValue(name, value)
	player:SetAttribute(name, clamped)
	LevelDesignTuning.syncAttributesToCharacter(player)
	return true
end

function LevelDesignTuning.estimateAbilityDuration(tuning: DoubleJumpTuning): number
	local ph = tuning.Phases
	local after = ph.AfterTransition
	local afterTime = math.max(after.MaxDuration or 1.1, after.MinDuration or 0)
	local thrustGlide = ThrustConfigs.BaseMaxFuel / math.max(ThrustConfigs.DrainPerSecond, 0.01)
	return (ph.FlightTransit.Duration or 0.35)
		+ afterTime
		+ thrustGlide
		+ (ph.DownSupes.MaxDuration or 2.5)
		+ 1.5
end

function LevelDesignTuning.getAttributeNames(): { string }
	local names: { string } = {}
	for _, spec in LevelDesignConfigs.Attributes do
		table.insert(names, spec.Name)
	end
	return names
end

function LevelDesignTuning.getEssentialAttributeNames(): { string }
	local names: { string } = {}
	for _, spec in LevelDesignConfigs.Attributes do
		if LevelDesignConfigs.isEssential(spec) then
			table.insert(names, spec.Name)
		end
	end
	return names
end

--- Only creates the ~9 attributes you usually need (not the full advanced list).
function LevelDesignTuning.applyDefaults(target: Instance)
	for _, spec in LevelDesignConfigs.Attributes do
		if not LevelDesignConfigs.isEssential(spec) then
			continue
		end

		if target:GetAttribute(spec.Name) == nil and spec.LegacyName then
			local legacy = target:GetAttribute(spec.LegacyName)
			if legacy ~= nil then
				target:SetAttribute(spec.Name, legacy)
			end
		end
		if target:GetAttribute(spec.Name) == nil then
			target:SetAttribute(spec.Name, spec.Default)
		end
	end

	pruneNonEssentialDefaults(target)
end

function LevelDesignTuning.copyDesignAttributes(from: Instance, to: Instance)
	for _, spec in LevelDesignConfigs.Attributes do
		local value = from:GetAttribute(spec.Name)
		if value == nil and spec.LegacyName then
			value = from:GetAttribute(spec.LegacyName)
		end
		if value ~= nil then
			to:SetAttribute(spec.Name, value)
		end
	end
end

function LevelDesignTuning.printStudioGuide(player: Player)
	if guidePrintedFor[player] then
		return
	end
	guidePrintedFor[player] = true
	print(LevelDesignConfigs.StudioGuide)
end

function LevelDesignTuning.formatActiveTuning(player: Player): string
	local t = LevelDesignTuning.getDoubleJump(player)
	local lean = t.Phases.LeanUp
	return string.format(
		"E_LeanDist=%s E_LeanSpd=%s E_Fwd=%s E_Rise=%s E_Height=%s E_MaxTime=%s",
		tostring(lean.ForwardDistance),
		tostring(lean.ForwardSpeed),
		tostring(t.Phases.AfterTransition.ForwardSpeed),
		tostring(t.Phases.AfterTransition.RiseSpeed),
		tostring(t.Phases.AfterTransition.TargetHeightAboveStart),
		tostring(t.MaxAbilityDuration)
	)
end

--- Reference time to travel E_LeanDist at E_LeanSpd (balance/docs only; glide ends on thrust fuel).
function LevelDesignTuning.getLeanPhaseMaxDuration(
	forwardSpeed: number,
	forwardDistance: number,
	configuredMax: number,
	distanceAlreadyTraveled: number
): number
	local remaining = math.max(0, forwardDistance - distanceAlreadyTraveled)
	local timeForRemaining = if forwardSpeed > 0.01 then remaining / forwardSpeed else 0
	return math.max(configuredMax, timeForRemaining + 0.15)
end

function LevelDesignTuning.syncAttributesToCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	for _, spec in LevelDesignConfigs.Attributes do
		local value = player:GetAttribute(spec.Name)
		if value ~= nil then
			character:SetAttribute(spec.Name, value)
		end
	end
end

function LevelDesignTuning.getDoubleJump(player: Player): DoubleJumpTuning
	local steerEnabledDefault = BaseSteer.Enabled ~= false
	local steerEnabled = readBoolForPlayer(player, ATTR.SteerEnabled, LEGACY.SteerEnabled, steerEnabledDefault)

	local leanSpeed = readNumberForPlayer(player, ATTR.LeanForwardSpeed, LEGACY.LeanForwardSpeed, BasePh.LeanUp.ForwardSpeed)
	local leanDist = readNumberForPlayer(player, ATTR.LeanForwardDistance, LEGACY.LeanForwardDistance, BasePh.LeanUp.ForwardDistance)
	local leanTime = readNumberForPlayer(player, ATTR.LeanMaxDuration, LEGACY.LeanMaxDuration, BasePh.LeanUp.MaxDuration)

	local maxAbilityDuration = readNumberForPlayer(player, ATTR.MaxDuration, LEGACY.MaxDuration, BaseDj.MaxAbilityDuration)

	local tuningDraft: any = {
		MaxAbilityDuration = maxAbilityDuration,
		Phases = {
			FlightTransit = { Duration = readNumberForPlayer(player, ATTR.TransitDuration, LEGACY.TransitDuration, BasePh.FlightTransit.Duration) },
			AfterTransition = {
				MaxDuration = readNumberForPlayer(player, ATTR.AfterMaxDuration, LEGACY.AfterMaxDuration, BasePh.AfterTransition.MaxDuration),
				MinDuration = readNumberForPlayer(player, ATTR.AfterMinDuration, LEGACY.AfterMinDuration, BasePh.AfterTransition.MinDuration),
			},
			LeanUp = { ForwardSpeed = leanSpeed, ForwardDistance = leanDist, MaxDuration = leanTime },
			DownSupes = { MaxDuration = readNumberForPlayer(player, ATTR.LandingMaxDuration, LEGACY.LandingMaxDuration, BasePh.DownSupes.MaxDuration) },
		},
	}
	maxAbilityDuration = math.max(maxAbilityDuration, LevelDesignTuning.estimateAbilityDuration(tuningDraft :: DoubleJumpTuning))
	maxAbilityDuration = ThrustConfigs.GetAbilityTimeCap(ThrustConfigs.BaseMaxFuel, maxAbilityDuration)

	return {
		ActionName = BaseDj.ActionName,
		Key = BaseDj.Key,
		Cooldown = readNumberForPlayer(player, ATTR.Cooldown, LEGACY.Cooldown, BaseDj.Cooldown),
		MaxAbilityDuration = maxAbilityDuration,
		Debug = BaseDj.Debug,
		AnimFolder = BaseDj.AnimFolder,
		Anims = BaseDj.Anims,
		CancelAnims = BaseDj.CancelAnims,
		LandingFadeTime = readNumberForPlayer(player, ATTR.LandingFadeTime, LEGACY.LandingFadeTime, BaseDj.LandingFadeTime),

		SupermanPose = {
			TransitStartPitch = readNumberForPlayer(player, ATTR.TransitStartPitch, LEGACY.TransitStartPitch, BasePose.TransitStartPitch),
			TransitEndPitch = readNumberForPlayer(player, ATTR.TransitEndPitch, LEGACY.TransitEndPitch, BasePose.TransitEndPitch),
			TransitPitchLerp = BasePose.TransitPitchLerp,
			TransitLaunchClimbDegrees = BasePose.TransitLaunchClimbDegrees,
			FlightPitch = readNumberForPlayer(player, ATTR.FlightPitch, LEGACY.FlightPitch, BasePose.FlightPitch),
			PitchLerp = BasePose.PitchLerp,
			UprightPitch = BasePose.UprightPitch,
			MaxBankDegrees = BasePose.MaxBankDegrees,
			BankFollowRate = BasePose.BankFollowRate,
			BankReturnRate = BasePose.BankReturnRate,
			CameraBankBlend = BasePose.CameraBankBlend,
			CameraYawRateForFullBank = BasePose.CameraYawRateForFullBank,
			CameraYawRateMin = BasePose.CameraYawRateMin,
			LaunchClimbStartDegrees = BasePose.LaunchClimbStartDegrees,
			LaunchClimbEndDegrees = BasePose.LaunchClimbEndDegrees,
			LaunchBodyPitch = BasePose.LaunchBodyPitch,
			LaunchPitchLerp = BasePose.LaunchPitchLerp,
			CameraPitchRateForFullAxis = BasePose.CameraPitchRateForFullAxis,
			CameraPitchRateMin = BasePose.CameraPitchRateMin,
			CameraPitchVelocityBlend = BasePose.CameraPitchVelocityBlend,
		},

		Phases = {
			FlightTransit = {
				Duration = readNumberForPlayer(player, ATTR.TransitDuration, LEGACY.TransitDuration, BasePh.FlightTransit.Duration),
				ForwardNudgeSpeed = readNumberForPlayer(player, ATTR.TransitNudgeSpeed, LEGACY.TransitNudgeSpeed, BasePh.FlightTransit.ForwardNudgeSpeed),
			},
			AfterTransition = {
				RiseSpeed = readNumberForPlayer(player, ATTR.RiseSpeed, LEGACY.RiseSpeed, BasePh.AfterTransition.RiseSpeed),
				ForwardSpeed = readNumberForPlayer(player, ATTR.ForwardSpeed, LEGACY.ForwardSpeed, BasePh.AfterTransition.ForwardSpeed),
				TargetHeightAboveStart = readNumberForPlayer(player, ATTR.TargetHeight, LEGACY.TargetHeight, BasePh.AfterTransition.TargetHeightAboveStart),
				MaxDuration = readNumberForPlayer(player, ATTR.AfterMaxDuration, LEGACY.AfterMaxDuration, BasePh.AfterTransition.MaxDuration),
				MinDuration = readNumberForPlayer(player, ATTR.AfterMinDuration, LEGACY.AfterMinDuration, BasePh.AfterTransition.MinDuration),
				RequiresHold = BasePh.AfterTransition.RequiresHold,
				SteerMoveThreshold = readNumberForPlayer(player, ATTR.SteerThreshold, LEGACY.SteerThreshold, BasePh.AfterTransition.SteerMoveThreshold),
			},
			LeanUp = {
				ForwardSpeed = leanSpeed,
				ForwardDistance = leanDist,
				MaxDuration = leanTime,
				RequiresHold = BasePh.LeanUp.RequiresHold,
			},
			LeapDown = {
				DescentSpeed = readNumberForPlayer(player, ATTR.DescentSpeed, LEGACY.DescentSpeed, BasePh.LeapDown.DescentSpeed),
				SlowDescentHeight = readNumberForPlayer(player, ATTR.SlowDescentHeight, LEGACY.SlowDescentHeight, BasePh.LeapDown.SlowDescentHeight),
				MinDuration = readNumberForPlayer(player, ATTR.DescentMinDuration, LEGACY.DescentMinDuration, BasePh.LeapDown.MinDuration),
				SurfaceRayLength = readNumberForPlayer(player, ATTR.SurfaceRayLength, LEGACY.SurfaceRayLength, BasePh.LeapDown.SurfaceRayLength),
				AlignToHit = BasePh.LeapDown.AlignToHit,
				HorizontalLerp = readNumberForPlayer(player, ATTR.DescentHorizontalLerp, LEGACY.DescentHorizontalLerp, BasePh.LeapDown.HorizontalLerp),
			},
			DownSupes = {
				TriggerHeightAboveSurface = readNumberForPlayer(player, ATTR.LandingTriggerHeight, LEGACY.LandingTriggerHeight, BasePh.DownSupes.TriggerHeightAboveSurface),
				UprightSnapHeight = readNumberForPlayer(player, ATTR.UprightSnapHeight, LEGACY.UprightSnapHeight, BasePh.DownSupes.UprightSnapHeight),
				ApproachDescentSpeed = readNumberForPlayer(player, ATTR.ApproachDescentSpeed, LEGACY.ApproachDescentSpeed, BasePh.DownSupes.ApproachDescentSpeed),
				UsePlatformStandOnApproach = BasePh.DownSupes.UsePlatformStandOnApproach,
				LandingLockDuration = readNumberForPlayer(player, ATTR.LandingLockDuration, LEGACY.LandingLockDuration, BasePh.DownSupes.LandingLockDuration),
				MinGroundedPlayDuration = readNumberForPlayer(player, ATTR.MinGroundedPlayDuration, LEGACY.MinGroundedPlayDuration, BasePh.DownSupes.MinGroundedPlayDuration),
				SettleDuration = readNumberForPlayer(player, ATTR.LandingSettleDuration, LEGACY.LandingSettleDuration, BasePh.DownSupes.SettleDuration),
				MaxStableVelocityY = BasePh.DownSupes.MaxStableVelocityY,
				MaxDuration = readNumberForPlayer(player, ATTR.LandingMaxDuration, LEGACY.LandingMaxDuration, BasePh.DownSupes.MaxDuration),
				WalkableNormalMinY = BasePh.DownSupes.WalkableNormalMinY,
				GroundProbeDistance = BasePh.DownSupes.GroundProbeDistance,
				GroundClearanceTolerance = BasePh.DownSupes.GroundClearanceTolerance,
				AirborneProbeDistance = BasePh.DownSupes.AirborneProbeDistance,
				ObstacleProbeDistance = BasePh.DownSupes.ObstacleProbeDistance,
				WallProbeDistance = BasePh.DownSupes.WallProbeDistance,
			},
		},

		Steering = {
			Enabled = steerEnabled,
			FollowCameraPitch = BaseSteer.FollowCameraPitch,
			MaxPitchDegrees = BaseSteer.MaxPitchDegrees,
			DirectionLerp = readNumberForPlayer(player, ATTR.SteerDirectionLerp, LEGACY.SteerDirectionLerp, BaseSteer.DirectionLerp),
			HorizontalSpeed = readNumberForPlayer(player, ATTR.SteerHorizontalSpeed, LEGACY.SteerHorizontalSpeed, BaseSteer.HorizontalSpeed),
			DescentHorizontalBlend = readNumberForPlayer(player, ATTR.SteerDescentBlend, LEGACY.SteerDescentBlend, BaseSteer.DescentHorizontalBlend),
			SteerMoveThreshold = readNumberForPlayer(player, ATTR.SteerThreshold, LEGACY.SteerThreshold, BaseSteer.SteerMoveThreshold),
			SteerAxisSmoothRate = BaseSteer.SteerAxisSmoothRate,
		},

		Cancel = {
			FallSpeed = readNumberForPlayer(player, ATTR.CancelFallSpeed, LEGACY.CancelFallSpeed, BaseCancel.FallSpeed),
			LandingRayLength = readNumberForPlayer(player, ATTR.CancelRayLength, LEGACY.CancelRayLength, BaseCancel.LandingRayLength),
			LandingTriggerHeight = readNumberForPlayer(player, ATTR.CancelLandingHeight, LEGACY.CancelLandingHeight, BaseCancel.LandingTriggerHeight),
			MinFallTime = readNumberForPlayer(player, ATTR.CancelMinFallTime, LEGACY.CancelMinFallTime, BaseCancel.MinFallTime),
			MaxFallDuration = readNumberForPlayer(player, ATTR.CancelMaxFallDuration, LEGACY.CancelMaxFallDuration, BaseCancel.MaxFallDuration),
			SettleDuration = BaseCancel.SettleDuration,
			MaxLandingDuration = BaseCancel.MaxLandingDuration,
		},

		Activation = BaseDj.Activation,
	}
end

function LevelDesignTuning.getSpeedMultiplier(player: Player): number
	local mult = readNumberForPlayer(player, ATTR.SpeedMultiplier, LEGACY.SpeedMultiplier, LevelDesignConfigs.Speed.DefaultMultiplier)
	if mult <= 0 then
		return 1
	end
	return mult
end

function LevelDesignTuning.getSwimSpeedOverride(player: Player): number?
	local override = readNumberForPlayer(player, ATTR.SwimSpeedOverride, LEGACY.SwimSpeedOverride, LevelDesignConfigs.Speed.DefaultOverride)
	if override > 0 then
		return override
	end
	return nil
end

function LevelDesignTuning.resolveSwimSpeed(player: Player, profileSpeed: number): number
	local override = LevelDesignTuning.getSwimSpeedOverride(player)
	if override then
		return override
	end
	return profileSpeed * LevelDesignTuning.getSpeedMultiplier(player)
end

return LevelDesignTuning

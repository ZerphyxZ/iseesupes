--!strict

--[[
	Level design attributes (Player or zone Part). Short names for Studio Properties panel.

	Workflow:
	1. Player → Attributes → edit E_* / Spd_* while playtesting.
	2. Per stage: Part with LD_Zone = true + same attributes; touch copies to Player.

	Key E ability attrs:
	  E_LeanDist  — how far forward before descent
	  E_LeanSpd   — glide forward speed
	  E_Fwd / E_Rise / E_Height — rise phase
]]

local CharacterConfigs = require(script.Parent.CharacterConfigs)

local Dj = CharacterConfigs.DoubleJump
local Ph = Dj.Phases

export type AttributeSpec = {
	Name: string,
	Default: number | boolean,
	Description: string,
	LegacyName: string?,
	--- When true, created on Player join (the ones you usually tweak).
	Essential: boolean?,
}

local LevelDesignConfigs = {
	AttributePrefixes = { "E_", "Spd_" },
	LegacyAttributePrefix = "Design_",

	ZoneMarkerAttribute = "LD_Zone",
	LegacyZoneMarkerAttribute = "LevelDesignZone",
	ZoneCollectionTag = "LD_Zone",
	LegacyZoneCollectionTag = "LevelDesignZone",

	Attributes = {
		{ Name = "E_Cooldown", LegacyName = "Design_DJ_Cooldown", Default = Dj.Cooldown, Description = "Seconds until E can be used again", Essential = true },
		{ Name = "E_MaxTime", LegacyName = "Design_DJ_MaxDuration", Default = Dj.MaxAbilityDuration, Description = "Max E ability time" },
		{ Name = "E_LandFade", LegacyName = "Design_DJ_LandingFadeTime", Default = Dj.LandingFadeTime, Description = "Landing anim fade" },

		{ Name = "E_TransTime", LegacyName = "Design_DJ_TransitDuration", Default = Ph.FlightTransit.Duration, Description = "Transit phase time" },
		{ Name = "E_TransNudge", LegacyName = "Design_DJ_TransitNudgeSpeed", Default = Ph.FlightTransit.ForwardNudgeSpeed, Description = "Transit forward nudge" },

		{ Name = "E_Rise", LegacyName = "Design_DJ_RiseSpeed", Default = Ph.AfterTransition.RiseSpeed, Description = "How fast you go UP while holding E", Essential = true },
		{ Name = "E_Fwd", LegacyName = "Design_DJ_ForwardSpeed", Default = Ph.AfterTransition.ForwardSpeed, Description = "Forward speed during the rise", Essential = true },
		{ Name = "E_Height", LegacyName = "Design_DJ_TargetHeight", Default = Ph.AfterTransition.TargetHeightAboveStart, Description = "How HIGH you rise before gliding (studs)", Essential = true },
		{ Name = "E_RiseTime", LegacyName = "Design_DJ_AfterMaxDuration", Default = Ph.AfterTransition.MaxDuration, Description = "Max rise phase time" },
		{ Name = "E_RiseMin", LegacyName = "Design_DJ_AfterMinDuration", Default = Ph.AfterTransition.MinDuration, Description = "Min rise phase time (prevents instant skip)" },

		{ Name = "E_LeanSpd", LegacyName = "Design_DJ_LeanForwardSpeed", Default = Ph.LeanUp.ForwardSpeed, Description = "Glide speed while holding E", Essential = true },
		{ Name = "E_LeanDist", LegacyName = "Design_DJ_LeanForwardDistance", Default = Ph.LeanUp.ForwardDistance, Description = "Total forward studs from E press before fall", Essential = true },
		{ Name = "E_LeanTime", LegacyName = "Design_DJ_LeanMaxDuration", Default = Ph.LeanUp.MaxDuration, Description = "Optional time cap (auto-extends for E_LeanDist)" },

		{ Name = "E_FallSpd", LegacyName = "Design_DJ_DescentSpeed", Default = Ph.LeapDown.DescentSpeed, Description = "How fast you fall down", Essential = true },
		{ Name = "E_SlowHt", LegacyName = "Design_DJ_SlowDescentHeight", Default = Ph.LeapDown.SlowDescentHeight, Description = "Slow fall height" },
		{ Name = "E_FallMin", LegacyName = "Design_DJ_DescentMinDuration", Default = Ph.LeapDown.MinDuration, Description = "Min descent time" },
		{ Name = "E_RayLen", LegacyName = "Design_DJ_SurfaceRayLength", Default = Ph.LeapDown.SurfaceRayLength, Description = "Ground ray length" },
		{ Name = "E_FallSteer", LegacyName = "Design_DJ_DescentHorizontalLerp", Default = Ph.LeapDown.HorizontalLerp, Description = "Descent steer blend" },

		{ Name = "E_LandHt", LegacyName = "Design_DJ_LandingTriggerHeight", Default = Ph.DownSupes.TriggerHeightAboveSurface, Description = "Landing trigger height" },
		{ Name = "E_SnapHt", LegacyName = "Design_DJ_UprightSnapHeight", Default = Ph.DownSupes.UprightSnapHeight, Description = "Upright snap height" },
		{ Name = "E_Approach", LegacyName = "Design_DJ_ApproachDescentSpeed", Default = Ph.DownSupes.ApproachDescentSpeed, Description = "Approach fall speed" },
		{ Name = "E_LandLock", LegacyName = "Design_DJ_LandingLockDuration", Default = Ph.DownSupes.LandingLockDuration, Description = "Landing lock time" },
		{ Name = "E_LandMin", LegacyName = "Design_DJ_MinGroundedPlayDuration", Default = Ph.DownSupes.MinGroundedPlayDuration, Description = "Min landing anim time" },
		{ Name = "E_Settle", LegacyName = "Design_DJ_LandingSettleDuration", Default = Ph.DownSupes.SettleDuration, Description = "Landing settle time" },
		{ Name = "E_LandMax", LegacyName = "Design_DJ_LandingMaxDuration", Default = Ph.DownSupes.MaxDuration, Description = "Max landing time" },

		{ Name = "E_Steer", LegacyName = "Design_DJ_SteerEnabled", Default = if Dj.Steering.Enabled then 1 else 0, Description = "Steer on (1) / off (0)" },
		{ Name = "E_SteerLerp", LegacyName = "Design_DJ_SteerDirectionLerp", Default = Dj.Steering.DirectionLerp, Description = "Steer turn speed" },
		{ Name = "E_SteerSpd", LegacyName = "Design_DJ_SteerHorizontalSpeed", Default = Dj.Steering.HorizontalSpeed, Description = "Sideways control strength while holding E", Essential = true },
		{ Name = "E_DSteer", LegacyName = "Design_DJ_SteerDescentBlend", Default = Dj.Steering.DescentHorizontalBlend, Description = "Steer during fall" },
		{ Name = "E_SteerThr", LegacyName = "Design_DJ_SteerThreshold", Default = Dj.Steering.SteerMoveThreshold, Description = "Steer input threshold" },

		{ Name = "E_CancelFall", LegacyName = "Design_DJ_CancelFallSpeed", Default = Dj.Cancel.FallSpeed, Description = "Drop speed when you release E (fast)", Essential = true },
		{ Name = "E_CanRay", LegacyName = "Design_DJ_CancelRayLength", Default = Dj.Cancel.LandingRayLength, Description = "Cancel ground ray" },
		{ Name = "E_CanHt", LegacyName = "Design_DJ_CancelLandingHeight", Default = Dj.Cancel.LandingTriggerHeight, Description = "Cancel land height" },
		{ Name = "E_CanMin", LegacyName = "Design_DJ_CancelMinFallTime", Default = Dj.Cancel.MinFallTime, Description = "Cancel min fall time" },
		{ Name = "E_CanMax", LegacyName = "Design_DJ_CancelMaxFallDuration", Default = Dj.Cancel.MaxFallDuration, Description = "Cancel max fall time" },

		{ Name = "E_Pitch", LegacyName = "Design_DJ_FlightPitch", Default = Dj.SupermanPose.FlightPitch, Description = "Flight body pitch" },
		{ Name = "E_Pitch0", LegacyName = "Design_DJ_TransitStartPitch", Default = Dj.SupermanPose.TransitStartPitch, Description = "Transit start pitch" },
		{ Name = "E_Pitch1", LegacyName = "Design_DJ_TransitEndPitch", Default = Dj.SupermanPose.TransitEndPitch, Description = "Transit end pitch" },

		{ Name = "Spd_Mult", LegacyName = "Design_SpeedMultiplier", Default = 1, Description = "Walk/swim speed multiplier (1 = normal, 2 = double)", Essential = true },
		{ Name = "Spd_Over", LegacyName = "Design_SwimSpeedOverride", Default = 0, Description = "Fixed swim speed if > 0" },
	} :: { AttributeSpec },

	Speed = {
		MultiplierAttribute = "Spd_Mult",
		OverrideAttribute = "Spd_Over",
		DefaultMultiplier = 1,
		DefaultOverride = 0,
	},

	--- Applied when reading tuning (prevents broken landings / stuck anims).
	Clamps = {
		E_LeanDist = { Min = 25, Max = 600 },
		E_LeanSpd = { Min = 20, Max = 200 },
		E_Fwd = { Min = 20, Max = 150 },
		E_Rise = { Min = 20, Max = 120 },
		E_Height = { Min = 8, Max = 80 },
		E_RiseMin = { Min = 0, Max = 3 },
		E_FallSpd = { Min = 30, Max = 120 },
		E_CancelFall = { Min = 50, Max = 200 },
		E_MaxTime = { Min = 8, Max = 45 },
		E_Cooldown = { Min = 0.5, Max = 30 },
		E_SteerSpd = { Min = 0, Max = 80 },
		Spd_Mult = { Min = 0.25, Max = 5 },
	},

	--- Printed once when you hit Play (see LevelDesignTuning.printStudioGuide).
	StudioGuide = [[
[iseesupes Level Design]
WHERE: Press Play → Explorer → Players → (your name) → Properties → Attributes

CHANGE: Edit a number — Output shows "Tuning synced → E_LeanDist = ..." then press E again.
       (Studio copies your Properties edit to the server automatically.)

ESSENTIAL (only these show by default):
  E_LeanDist  — total forward studs from E press (25–600, auto-clamped)
  E_LeanSpd   — glide speed (20–200); E_MaxTime auto-extends for long glides
  E_Fwd       — forward speed during rise
  E_Rise      — upward speed during rise
  E_Height    — how high you rise before gliding
  E_FallSpd   — fall speed while holding E
  E_CancelFall — drop speed when you release E (default 90)
  E_SteerSpd  — WASD steer strength in flight
  E_Cooldown  — seconds before E can be used again
  Spd_Mult    — overall speed (1 = normal)

Per-stage zone: Part with LD_Zone=true + same attributes; player copies on touch.
More attrs exist in LevelDesignConfigs.lua (advanced) — add manually if needed.
]],
}

function LevelDesignConfigs.isEssential(spec: AttributeSpec): boolean
	return spec.Essential == true
end

return LevelDesignConfigs

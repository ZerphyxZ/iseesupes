--!strict

-- Stage 5 STATIONARY "SuperLaserGirl" heat-vision turrets (server: SuperLaserGirlService).
--
-- Two anchored SuperGirl rigs tagged `Tag` hold an idle pose and fire the Superman heat-vision
-- beam (HeatVisionRig / ReplicatedStorage.Shared.Assets.SupermanHeatVision) at any player within
-- DetectRadius — intermittent (charge -> short beam -> cooldown), with an arcade "phew" sound and
-- light, recoverable damage (0 HP -> TreadmillService hazard death/respawn). Unlike the patrolling
-- Stage-4 SuperGirl, these never move — they're turrets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SuperGirlConfigs = require(ReplicatedStorage.Shared.Configs.SuperGirlConfigs)

local SuperLaserGirlConfigs = {
	Enabled = true,

	--- CollectionService tag identifying the rigs. May sit on the rig model, an ancestor, or an
	--- inner sub-model — the service resolves the real rig (a Model with a Head) from the tag.
	Tag = "SuperLaserGirl",

	--- Fire when the nearest player is within this many studs (3D, so flying players count).
	DetectRadius = 70,
	--- Perf: when the nearest player is beyond this (3D) she goes dormant (slower tick, no work)
	--- until someone approaches. Keep comfortably above DetectRadius.
	SleepRange = 850,

	--- Telegraph before the beam fires (time to dodge / break line of sight).
	ChargeSeconds = 0.4,
	--- Seconds AFTER the beam ends before she can fire again.
	FireCooldown = 1.5,
	--- How long the beam stays visible per shot (a short burst — "phew", not a constant beam).
	--- The beam snaps to FULL length instantly (see beginBurst), so this is pure on-screen time:
	--- long enough to clearly read the laser hitting the player, short enough to stay an arcade zap.
	BeamSeconds = 0.25,
	--- Raycast length used to aim + grow the beam (keep >= DetectRadius).
	BeamMaxRange = 200,

	--- Damage per hit as a fraction of the player's max health (flat + forgiving).
	DamagePct = 0.10,
	--- Per-player seconds between laser hits (anti-shred).
	HitDebounce = 0.8,
	--- Seconds after a laser death before she can fire again (anti-loop).
	DeathCooldown = 1.5,

	--- Idle pose held while standing. Reuse SuperGirl's RUNTIME idle id (from
	--- ReplicatedStorage.SupesAnimations — edit-time ids do NOT load).
	IdleAnimationId = SuperGirlConfigs.IdleAnimationId,

	--- Arcade "phew" laser sound (one-shot per shot). Reused from SuperGirl; swap to taste.
	LaserSoundId = SuperGirlConfigs.LaserSoundId,
	LaserSoundVolume = SuperGirlConfigs.LaserSoundVolume,

	--- Mirror state to Output (Studio only).
	DebugPrint = true,
}

return SuperLaserGirlConfigs

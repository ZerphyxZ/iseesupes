--!strict

-- Stage 4 walking "SuperGirl" laser hazard (server: SuperGirlService).
-- One NPC per part named WalkPartName: she paces that part with Superman's run
-- animation, and lasers the nearest player within range — air included — for light,
-- recoverable damage (reuses the HealthRed damage model). Telegraphed + dodgeable;
-- she never blocks progress. Designed to make players run/fly away, not to punish.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HealthRedConfigs = require(ReplicatedStorage.Shared.Configs.HealthRedConfigs)

local SuperGirlConfigs = {
	Enabled = true,

	--- CollectionService TAG on the platform part she patrols (the part lives inside a
	--- stage, e.g. Stage3). The SuperGirl rig is paired to the tagged part by proximity
	--- at runtime — every part with this tag activates a SuperGirl, so tagging more
	--- platforms (Stage4/5) extends the feature with zero code changes.
	WalkPartTag = "SuperGirlWalk",
	--- Optional CollectionService tag on the SuperGirl MODEL — an extra pairing hint.
	ModelTag = "SuperGirlLaser",
	--- Substring (lowercased) used to recognise a SuperGirl rig when pairing by proximity.
	ModelNameMatch = "supergirl",
	--- Laser muzzle origin on the rig (her eyes).
	MuzzlePartName = "Head",

	--- Patrol: walk speed (studs/second) back-and-forth along the walk part's long axis.
	PatrolSpeed = 16,
	--- Root height above the walk part's top surface (used only for endpoint math).
	StandHeight = 3,
	--- Studs kept clear of every edge when she picks roam targets, so her (wide) body
	--- never overhangs / looks like it's falling off. Bump up for a bigger rig.
	EdgeMargin = 14,

	--- Laser range (3D, so flying players count): she fires when the nearest player is
	--- within this.
	DetectRange = 70,
	--- How far she will CHASE the nearest player from (3D). Larger than DetectRange so she
	--- walks toward players anywhere on the part, then lasers once they're within DetectRange.
	FollowRange = 500,
	--- She closes to this distance from the player, then holds and aims (so she never piles
	--- on top and "runs in place"). Keep below DetectRange.
	StopDistance = 40,
	--- A player only counts as a chase target if they're within laser range OR within this
	--- many studs of the part's edge. Stops her walking to the edge and "running in place"
	--- at a player who has flown/respawned far off the part — she just resumes roaming.
	FollowEdgeMargin = 30,
	--- Perf: when the NEAREST player is beyond this (3D, studs), she goes dormant — no
	--- per-frame movement and a slower detection tick — since nobody can see her. She wakes
	--- and resumes instantly when a player approaches. Keep comfortably above FollowRange.
	SleepRange = 850,
	--- Telegraph: throw wind-up before the beam actually fires (gives time to dodge).
	ChargeSeconds = 0.4,
	--- Seconds between shots.
	FireCooldown = 1.5,
	--- How long the beam stays visible per shot.
	BeamSeconds = 0.18,

	--- Per-player seconds between laser hits (anti-shred / lenient).
	HitDebounce = 0.8,
	--- Seconds after a laser death before another can fire (anti-loop).
	DeathCooldown = 1.5,
	--- Fallback damage fraction of max health if a stage can't be resolved. Per-stage
	--- values come from HealthRed so the economy stays single-sourced (Stage 4 = 0.14).
	DefaultDamagePct = HealthRedConfigs.DamagePctByStage[4] or 0.14,

	--- Reused animations by ASSET ID. These are the game's RUNTIME ids (from
	--- ReplicatedStorage.SupesAnimations, which is what player characters use and is
	--- owned by this place) — the edit-time Central.UniversalAnimations ids are
	--- different assets that do NOT load here.
	--- RunAnimation = the walk loop (used while moving). ThrowAnimationId (LeanUp) is kept
	--- here but is NOT currently played: as a throw it leaned her body forward, which read
	--- like a face-plant when she fired in place. The laser beam alone is the attack now.
	RunAnimationId = "rbxassetid://135670889243514",
	ThrowAnimationId = "rbxassetid://73374798110711",
	--- Idle pose she holds while standing still / aiming, so she isn't "running in place"
	--- when she's caught up to the player (the run loop looked like a forward face-plant).
	IdleAnimationId = "rbxassetid://138779174236707",

	--- Reused arcade laser sound (LightningBeam), by asset id. Swap to taste.
	LaserSoundId = "rbxassetid://379557765",
	LaserSoundVolume = 0.6,

	--- Arcade beam look (bright neon, eyes → impact).
	BeamColorStart = Color3.fromRGB(255, 60, 20),
	BeamColorEnd = Color3.fromRGB(255, 210, 90),
	BeamWidthStart = 1.6,
	BeamWidthEnd = 0.9,

	--- Mirror state to Output (Studio only).
	DebugPrint = true,
}

return SuperGirlConfigs

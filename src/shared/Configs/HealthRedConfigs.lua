--!strict

-- Soft damage zones (CollectionService tag "HealthRed") on stages 2-5.
-- Lenient, recoverable HP loss while standing in zone; at 0 HP → knockback death
-- and lobby respawn (same path as KillPart). Server-authoritative (HealthRedService).

local HealthRedConfigs = {
	Enabled = true,
	Tag = "HealthRed",

	--- Damage per tick as a FRACTION OF MAX HEALTH, by the stage the part sits in
	--- (resolved from its ancestor Stage<N> model). Percentage-based so it's always
	--- visible at high level. Leave the zone to regen; staying until HP hits 0
	--- triggers hazard death + lobby respawn.
	DamagePctByStage = {
		[2] = 0.08,
		[3] = 0.11,
		[4] = 0.14,
		[5] = 0.17,
	},
	--- Used when a part's stage can't be resolved or isn't in the table above.
	DefaultDamagePct = 0.11,

	--- Per-player seconds between damage applications (anti-shred; also lenient).
	TouchDebounce = 0.8,

	--- Gentle regen (fraction of max health per second) so a careful player heals
	--- back instead of staying chipped. Scales with the player's pool.
	RegenPctPerSecond = 0.06,
	--- Seconds after the last hit before regen begins.
	RegenDelay = 3,

	--- Legacy floor clamp (0 = zones can kill). Unused when 0.
	MinHealthFractionFromTouch = 0,

	--- Seconds after a HealthRed death before another hazard death can fire (anti-loop).
	DeathCooldown = 1.5,

	--- How often (seconds) to poll whether a player is standing in a red zone. The
	--- TouchDebounce above still gates how often damage actually lands, so this is
	--- just detection latency — damage KEEPS applying while in contact, not once.
	ScanInterval = 0.2,

	--- Zone tolerances for the HRP-in-part check (TouchZone). Tighter than the shop-pad
	--- defaults so damage triggers on/in the part, not merely near it.
	Zone = {
		horizontalPadding = 2,
		maxHeightAbove = 6,
		minHeightBelow = -3,
	},

	--- Mirror hits to Output for tuning (Studio only).
	DebugPrint = false,
}

return HealthRedConfigs

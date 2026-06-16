--!strict

-- Background music playlist (client-only). SFX use the default SoundGroup at full volume.
--
-- Preferred: place Sound instances under SoundService (see StudioSoundNames).
-- Fallback Tracks (rbxassetid) used if Studio sounds are missing.

local MusicConfigs = {
	Enabled = true,

	Debug = false,

	--- SoundGroup volume for BGM (SFX such as GroundCracking stay at 1.0 on default group).
	Volume = 0.65,

	PlaybackSpeed = 1,

	FadeInSeconds = 1,

	LoadTimeoutSeconds = 30,

	WaitForStudioSeconds = 15,

	--- Poll active track; advance playlist if Ended never fires.
	WatchdogIntervalSeconds = 2,

	--- Re-attempt starting BGM if nothing plays after join.
	StartRetryIntervalSeconds = 8,
	MaxStartRetries = 5,

	SoundGroupName = "Music",

	--- Sounds you placed in SoundService in Studio (play in this order, then loop).
	StudioSoundNames = {
		"BGSound1",
		"BGSound2",
	},

	--- Play order: BGSound1 → BGSound2 → loop. Fallback if Studio sounds missing.
	Tracks = {
		"rbxassetid://121545323876491",
		"rbxassetid://140175169828824",
	},
}

return MusicConfigs

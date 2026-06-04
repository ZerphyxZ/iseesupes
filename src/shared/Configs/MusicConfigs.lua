--!strict

-- Background music playlist (client-only). SFX use the default SoundGroup at full volume.
--
-- Preferred: place Sound instances under SoundService (see StudioSoundNames).
-- Fallback Tracks (rbxassetid) only used if Studio sounds are missing.

local MusicConfigs = {
	Enabled = true,

	Debug = false,

	--- SoundGroup volume for BGM (SFX such as GroundCracking stay at 1.0 on default group).
	Volume = 0.5,

	PlaybackSpeed = 1,

	FadeInSeconds = 1,

	LoadTimeoutSeconds = 30,

	WaitForStudioSeconds = 15,

	SoundGroupName = "Music",

	--- Sounds you placed in SoundService in Studio (play in this order, then loop).
	StudioSoundNames = {
		"BGSound1",
		"BGSound2",
	},

	--- Used only when StudioSoundNames are not found (e.g. before place is saved).
	Tracks = {
		"rbxassetid://115723365804198",
		"rbxassetid://84268579794179",
	},
}

return MusicConfigs

--!strict

-- Workspace/Map/FriendStand — friend showcase + invite prompt on Hitbox touch.

export type FriendStandConfig = {
	RootPath: { string },
	AlternateRootPaths: { { string } },
	CharacterSpawnPartName: string,
	CharacterSpawnPartAliases: { string },
	PartsReplicateTimeout: number,
	HitboxPartName: string,
	TouchPartNames: { string },
	MaxInvitedFriends: number,
	SpeedPerInvite: number,
	TouchDebounce: number,
	DisplayModelName: string,
	FriendFetchPageSize: number,
	DisplayCycleSeconds: number,
	DisplayRefreshSeconds: number,
	DisplayYawOffsetDegrees: number,
	DisplayHeightOffset: number,
	AlignFeetToSpawnBottom: boolean,
	StandModelName: string,
	MapFolderPath: { string },
	FaceLocalPlayer: boolean,
	FaceTurnSmoothness: number,
	FaceUpdateInterval: number,
	RunAnimFolderName: string,
	RunAnimName: string,
	RigReadyTimeout: number,
	StandResolveTimeout: number,
	ParentDisplayToWorkspace: boolean,
	FriendFetchTimeout: number,
	DebugPrint: boolean,
}

local FriendStandConfigs: FriendStandConfig = {
	RootPath = { "Map", "FriendStand" },
	AlternateRootPaths = {
		{ "FriendStand" },
	},
	CharacterSpawnPartName = "CharacterSpawn",
	CharacterSpawnPartAliases = { "CharacterSpawn", "Spawn", "NPCSpawn" },
	PartsReplicateTimeout = 45,
	HitboxPartName = "Hitbox",
	TouchPartNames = { "Hitbox", "Stand", "CharacterSpawn" },
	MaxInvitedFriends = 10,
	SpeedPerInvite = 700,
	TouchDebounce = 3,
	DisplayModelName = "FriendDisplay",
	FriendFetchPageSize = 50,
	DisplayCycleSeconds = 6,
	DisplayRefreshSeconds = 300,
	DisplayYawOffsetDegrees = 0,
	--- Extra vertical tweak after foot placement (negative = lower).
	DisplayHeightOffset = -1.25,
	--- Use bottom of CharacterSpawn for foot placement (avoids floating when spawn part is tall).
	AlignFeetToSpawnBottom = true,
	StandModelName = "FriendStand",
	MapFolderPath = { "Map" },
	FaceLocalPlayer = true,
	--- Higher = faster turn toward local player (Heartbeat lerp).
	FaceTurnSmoothness = 10,
	FaceUpdateInterval = 0.2,
	RunAnimFolderName = "SupesAnimations",
	--- Showcase avatars (FriendStand + leaderboard top stands) play this looped animation.
	RunAnimName = "IdleAnimation",
	RigReadyTimeout = 8,
	StandResolveTimeout = 120,
	ParentDisplayToWorkspace = false,
	FriendFetchTimeout = 12,
	DebugPrint = false,
}

return FriendStandConfigs

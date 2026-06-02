--!strict

-- World content under Workspace.Map (GiveWins, Leaderboards, FriendStand, treadmills, etc.).

local WorldMapConfigs = {
	MapFolderName = "Map",
	--- Tried in order under Workspace.Map, then Workspace root (GiveWins lobby teleport, treadmill kick).
	LobbySpawnPartNames = { "Start", "SpawnLocation" },
}

return WorldMapConfigs

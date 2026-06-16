--!strict

local Workspace = game:GetService("Workspace")

local WorldMapConfigs = require(script.Parent.Parent.Configs.WorldMapConfigs)

local MapWorld = {}

function MapWorld.getMapFolder(): Folder?
	local map = Workspace:FindFirstChild(WorldMapConfigs.MapFolderName)
	return if map and map:IsA("Folder") then map :: Folder else nil
end

function MapWorld.findChildInMap(childName: string): Instance?
	local map = MapWorld.getMapFolder()
	if not map then
		return nil
	end
	-- Prefer a direct child (fast, unambiguous). Fall back to a recursive search so a
	-- top-level folder accidentally nested one level deep (e.g. dragged into Lobby in
	-- the Explorer) still resolves instead of silently breaking the feature.
	return map:FindFirstChild(childName) or map:FindFirstChild(childName, true)
end

function MapWorld.walkPathFromWorkspace(segments: { string }): Instance?
	local node: Instance = Workspace
	for _, name in segments do
		local child = node:FindFirstChild(name)
		if not child then
			return nil
		end
		node = child
	end
	return node
end

local function tryNamedSpawn(root: Instance, names: { string }): BasePart?
	for _, name in names do
		local inst = root:FindFirstChild(name)
		if inst and inst:IsA("BasePart") then
			return inst
		end
	end
	return nil
end

local function trySpawnLocationIn(root: Instance): SpawnLocation?
	for _, desc in root:GetDescendants() do
		if desc:IsA("SpawnLocation") then
			return desc
		end
	end
	return nil
end

--- Lobby / win-claim / treadmill kick spawn (cached reference optional).
function MapWorld.resolveLobbySpawn(cached: BasePart?): BasePart?
	if cached and cached.Parent then
		return cached
	end

	local names = WorldMapConfigs.LobbySpawnPartNames
	local map = MapWorld.getMapFolder()
	if map then
		local inMap = tryNamedSpawn(map, names)
		if inMap then
			return inMap
		end
		local spawnLoc = trySpawnLocationIn(map)
		if spawnLoc then
			return spawnLoc
		end
	end

	local atRoot = tryNamedSpawn(Workspace, names)
	if atRoot then
		return atRoot
	end

	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			return child
		end
	end

	return nil
end

return MapWorld

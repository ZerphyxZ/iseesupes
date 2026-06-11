--!strict

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local StageCheckpointWorld = require(script.Parent.StageCheckpointWorld)

local StageCheckpointCollision = {}

local registeredGroups: { [string]: boolean } = {}
local registeredPlayerGroups: { [string]: boolean } = {}

--- Legacy group from init.server.lua; some parts may briefly stay in it (CharacterAdded ordering).
local LEGACY_PLAYERS_GROUP = "Players"

local function playerGroupName(player: Player): string
	local cfg = require(script.Parent.Parent.Configs.StageCheckpointConfigs)
	return cfg.CollisionGroup.PlayerPrefix .. tostring(player.UserId)
end

local function ensureGroup(groupName: string)
	if registeredGroups[groupName] then
		return
	end
	-- Roblox caps collision groups at 32; never let a failed register kill the
	-- caller (the player still plays, just without per-player gate physics).
	local ok, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
	if ok then
		registeredGroups[groupName] = true
	else
		warn("[iseesupes] StageCheckpointCollision: RegisterCollisionGroup failed for", groupName, err)
	end
end

--- Characters live in per-player groups (for gate pass-through), so player-vs-player
--- collision must be disabled pairwise across all player groups.
local function ensurePlayerGroupNoCollide(groupName: string)
	if registeredPlayerGroups[groupName] then
		return
	end
	registeredPlayerGroups[groupName] = true

	pcall(function()
		PhysicsService:RegisterCollisionGroup(LEGACY_PLAYERS_GROUP)
		PhysicsService:CollisionGroupSetCollidable(groupName, LEGACY_PLAYERS_GROUP, false)
	end)

	for otherGroup in registeredPlayerGroups do
		if otherGroup ~= groupName then
			pcall(function()
				PhysicsService:CollisionGroupSetCollidable(groupName, otherGroup, false)
			end)
		end
	end
end

function StageCheckpointCollision.registerGateGroup(stageNum: number)
	ensureGroup(StageCheckpointWorld.getGateCollisionGroupName(stageNum))
end

function StageCheckpointCollision.ensurePlayerGroup(player: Player)
	local group = playerGroupName(player)
	ensureGroup(group)
	ensurePlayerGroupNoCollide(group)
end

function StageCheckpointCollision.applyToCharacter(player: Player, character: Model)
	local group = playerGroupName(player)
	ensureGroup(group)
	ensurePlayerGroupNoCollide(group)
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = group
		end
	end
end

function StageCheckpointCollision.allowPassThrough(player: Player, stageNum: number)
	local playerGroup = playerGroupName(player)
	local gateGroup = StageCheckpointWorld.getGateCollisionGroupName(stageNum)
	ensureGroup(playerGroup)
	ensureGroup(gateGroup)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(playerGroup, gateGroup, false)
	end)
end

function StageCheckpointCollision.blockGateForPlayer(player: Player, stageNum: number)
	local playerGroup = playerGroupName(player)
	local gateGroup = StageCheckpointWorld.getGateCollisionGroupName(stageNum)
	ensureGroup(playerGroup)
	ensureGroup(gateGroup)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(playerGroup, gateGroup, true)
	end)
end

function StageCheckpointCollision.resetAllGatesForPlayer(player: Player)
	local cfg = require(script.Parent.Parent.Configs.StageCheckpointConfigs)
	StageCheckpointCollision.ensurePlayerGroup(player)
	for stageNum = cfg.FirstGateStage, cfg.MaxGateStage do
		StageCheckpointCollision.blockGateForPlayer(player, stageNum)
	end
end

function StageCheckpointCollision.bindPlayer(player: Player)
	StageCheckpointCollision.ensurePlayerGroup(player)

	local function onCharacter(character: Model)
		StageCheckpointCollision.applyToCharacter(player, character)
	end

	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

--- Frees the player's collision group on leave. Without this, groups accumulate
--- across joins until the 32-group engine cap — after which new players get no
--- per-player physics (gates stop blocking them, player collision returns).
function StageCheckpointCollision.unbindPlayer(player: Player)
	local group = playerGroupName(player)
	registeredGroups[group] = nil
	registeredPlayerGroups[group] = nil
	pcall(function()
		PhysicsService:UnregisterCollisionGroup(group)
	end)
end

function StageCheckpointCollision.init()
	for _, player in Players:GetPlayers() do
		StageCheckpointCollision.bindPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		StageCheckpointCollision.bindPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		StageCheckpointCollision.unbindPlayer(player)
	end)
end

return StageCheckpointCollision

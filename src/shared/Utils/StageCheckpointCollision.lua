--!strict

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local StageCheckpointWorld = require(script.Parent.StageCheckpointWorld)

local StageCheckpointCollision = {}

local registeredGroups: { [string]: boolean } = {}

local function playerGroupName(player: Player): string
	local cfg = require(script.Parent.Parent.Configs.StageCheckpointConfigs)
	return cfg.CollisionGroup.PlayerPrefix .. tostring(player.UserId)
end

local function ensureGroup(groupName: string)
	if registeredGroups[groupName] then
		return
	end
	PhysicsService:RegisterCollisionGroup(groupName)
	registeredGroups[groupName] = true
end

function StageCheckpointCollision.registerGateGroup(stageNum: number)
	ensureGroup(StageCheckpointWorld.getGateCollisionGroupName(stageNum))
end

function StageCheckpointCollision.ensurePlayerGroup(player: Player)
	ensureGroup(playerGroupName(player))
end

function StageCheckpointCollision.applyToCharacter(player: Player, character: Model)
	local group = playerGroupName(player)
	ensureGroup(group)
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
	PhysicsService:CollisionGroupSetCollidable(playerGroup, gateGroup, false)
end

function StageCheckpointCollision.blockGateForPlayer(player: Player, stageNum: number)
	local playerGroup = playerGroupName(player)
	local gateGroup = StageCheckpointWorld.getGateCollisionGroupName(stageNum)
	ensureGroup(playerGroup)
	ensureGroup(gateGroup)
	PhysicsService:CollisionGroupSetCollidable(playerGroup, gateGroup, true)
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

function StageCheckpointCollision.init()
	for _, player in Players:GetPlayers() do
		StageCheckpointCollision.bindPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		StageCheckpointCollision.bindPlayer(player)
	end)
end

return StageCheckpointCollision

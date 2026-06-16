--!strict

-- Shows the #1 player of each global leaderboard on its Map stand
-- (TimeStand / SpeedStand / WinsStand / RebirthStand), idle animation playing.
-- Reuses the FriendStand showcase pipeline (FriendStandDisplay).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local LeaderboardConfigs = require(ReplicatedStorage.Shared.Configs.LeaderboardConfigs)
local FriendStandDebug = require(ReplicatedStorage.Shared.Utils.FriendStandDebug)
local FriendStandDisplay = require(ReplicatedStorage.Shared.Utils.FriendStandDisplay)
local FriendStandWorld = require(ReplicatedStorage.Shared.Utils.FriendStandWorld)

local LeaderboardStandController = Knit.CreateController({ Name = "LeaderboardStandController" })

type StandBinding = {
	model: Model,
	spawn: BasePart,
	boardKey: string,
	displayModel: Model?,
	currentUserId: number?,
	generation: number,
}

local bindings: { [string]: StandBinding } = {}
local topUsers: { [string]: number } = {}
local faceConn: RBXScriptConnection? = nil

local function displayNameFor(standName: string): string
	return "TopDisplay_" .. standName
end

local function ensureFaceLoop()
	if faceConn then
		return
	end
	faceConn = RunService.Heartbeat:Connect(function(dt: number)
		local lookAt = FriendStandDisplay.getLocalPlayerLookTarget()
		if not lookAt then
			return
		end
		for _, binding in bindings do
			local model = binding.displayModel
			if model and model.Parent then
				FriendStandDisplay.updateModelFacing(model, lookAt, dt)
			end
		end
	end)
end

local function showTopUser(binding: StandBinding)
	local userId = topUsers[binding.boardKey]
	if not userId or userId <= 0 then
		return
	end
	if binding.currentUserId == userId and binding.displayModel and binding.displayModel.Parent then
		return
	end

	binding.generation += 1
	local generation = binding.generation
	local standName = binding.model.Name

	if binding.displayModel then
		FriendStandDisplay.stopRunOnModel(binding.displayModel)
		binding.displayModel = nil
	end
	binding.currentUserId = nil
	FriendStandDisplay.destroyDisplayIn(binding.model, displayNameFor(standName))

	local model = FriendStandDisplay.createFriendModel(userId)
	if not model then
		FriendStandDebug.warn("LeaderboardStand: avatar load failed for", userId, "on", standName)
		return
	end
	if generation ~= binding.generation then
		model:Destroy()
		return
	end

	model.Parent = FriendStandDisplay.getDisplayParent(binding.model)

	if not FriendStandDisplay.waitForRigReady(model) or generation ~= binding.generation then
		model:Destroy()
		return
	end

	local lookAt = FriendStandDisplay.getLocalPlayerLookTarget()
	if not FriendStandDisplay.prepareShowcaseModel(model, binding.spawn, lookAt, displayNameFor(standName)) then
		model:Destroy()
		return
	end

	binding.displayModel = model
	binding.currentUserId = userId
	ensureFaceLoop()

	FriendStandDebug.log("LeaderboardStand:", standName, "showing #1 of", binding.boardKey, "userId", userId)
end

local function refreshAllStands()
	for _, binding in bindings do
		task.spawn(showTopUser, binding)
	end
end

local function bindStand(model: Model, boardKey: string)
	if bindings[model.Name] then
		return
	end

	task.spawn(function()
		local spawn = FriendStandWorld.waitForSpawnPart(model)
		if not spawn then
			FriendStandDebug.warn("LeaderboardStand: CharacterSpawn missing on", model:GetFullName())
			return
		end
		local binding: StandBinding = {
			model = model,
			spawn = spawn,
			boardKey = boardKey,
			displayModel = nil,
			currentUserId = nil,
			generation = 0,
		}
		bindings[model.Name] = binding
		showTopUser(binding)
	end)
end

local function startStandResolveLoop()
	task.spawn(function()
		local wanted = LeaderboardConfigs.TopStands
		local deadline = os.clock() + (LeaderboardConfigs.TopStandResolveTimeout or 120)

		while os.clock() < deadline do
			local mapFolder = FriendStandWorld.getMapFolder()
			if mapFolder then
				local remaining = 0
				for standName, boardKey in wanted do
					if not bindings[standName] then
						local model = mapFolder:FindFirstChild(standName, true)
						if model and model:IsA("Model") then
							bindStand(model, boardKey)
						else
							remaining += 1
						end
					end
				end
				if remaining == 0 then
					return
				end
			end
			task.wait(2)
		end

		for standName in LeaderboardConfigs.TopStands do
			if not bindings[standName] then
				FriendStandDebug.warn("LeaderboardStand: never found Workspace.Map." .. standName)
			end
		end
	end)
end

function LeaderboardStandController:KnitStart()
	local LeaderboardService = Knit.GetService("LeaderboardService")

	LeaderboardService.TopUsersChanged:Connect(function(newTopUsers: { [string]: number })
		topUsers = newTopUsers or {}
		refreshAllStands()
	end)

	LeaderboardService:GetTopUsers()
		:andThen(function(newTopUsers: { [string]: number })
			topUsers = newTopUsers or {}
			refreshAllStands()
		end)
		:catch(function(err)
			FriendStandDebug.warn("LeaderboardStand: GetTopUsers failed:", err)
		end)

	startStandResolveLoop()

	StudioLog.ready("LeaderboardStandController")
end

return LeaderboardStandController

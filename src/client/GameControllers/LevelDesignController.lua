--!strict

-- Studio only: forward Player/Character attribute edits from Properties to the server (authoritative for E physics).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local LevelDesignConfigs = require(ReplicatedStorage.Shared.Configs.LevelDesignConfigs)
local LevelDesignTuning = require(ReplicatedStorage.Shared.Utils.LevelDesignTuning)

local LevelDesignController = Knit.CreateController({ Name = "LevelDesignController" })

local player = Players.LocalPlayer
local pendingSync: { [string]: number } = {}
local syncScheduled = false
local boundInstances: { [Instance]: boolean } = {}

local function getService()
	return Knit.GetService("LevelDesignService")
end

local function flushSync()
	syncScheduled = false
	local service = getService()
	for name, value in pendingSync do
		pendingSync[name] = nil
		service:SyncAttribute(name, value)
	end
end

local function queueSync(name: string, value: number)
	if not LevelDesignTuning.isTuningAttribute(name) then
		return
	end
	pendingSync[name] = value
	if syncScheduled then
		return
	end
	syncScheduled = true
	task.defer(flushSync)
end

local function bindTuningAttributes(instance: Instance)
	if boundInstances[instance] then
		return
	end
	boundInstances[instance] = true

	for _, spec in LevelDesignConfigs.Attributes do
		instance:GetAttributeChangedSignal(spec.Name):Connect(function()
			local value = instance:GetAttribute(spec.Name)
			if typeof(value) == "number" then
				queueSync(spec.Name, value)
			end
		end)
	end
end

function LevelDesignController:KnitStart()
	if not RunService:IsStudio() then
		return
	end

	bindTuningAttributes(player)

	player.CharacterAdded:Connect(function(character)
		bindTuningAttributes(character)
	end)

	if player.Character then
		bindTuningAttributes(player.Character)
	end

	print("[iseesupes] LevelDesignController — edit Attributes in Properties; values sync to server on change.")
end

return LevelDesignController

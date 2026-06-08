--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local Knit = require(ReplicatedStorage.Packages.Knit)

local function loadFolder(folder: Instance?)
	if not folder then
		return
	end
	for _, module in folder:GetDescendants() do
		if module:IsA("ModuleScript") then
			require(module)
		end
	end
end

-- Setup collision groups for player-to-player collisions disabled
local function setupPlayerCollisions()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Players")
	end)

	local function addCharacterToCollisionGroup(character: Model)
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then
			return
		end

		-- Add all parts in the character to the collision group
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				pcall(function()
					PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)
					PhysicsService:AddCollisionGroupMember("Players", part)
				end)
			end
		end
	end

	local function onPlayerAdded(player: Player)
		local function onCharacterAdded(character: Model)
			addCharacterToCollisionGroup(character)
		end

		-- Add character if already loaded
		if player.Character then
			addCharacterToCollisionGroup(player.Character)
		end

		-- Connect to future character loads
		player.CharacterAdded:Connect(onCharacterAdded)
	end

	-- Setup for all current players
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	-- Setup for new players joining
	Players.PlayerAdded:Connect(onPlayerAdded)
end

setupPlayerCollisions()

loadFolder(script:FindFirstChild("GlobalServices"))
loadFolder(script:FindFirstChild("GameServices"))

Knit.Start()
	:andThen(function()
		print("[iseesupes] Server started.")
	end)
	:catch(function(err)
		warn("[iseesupes] Server Knit failed:", tostring(err))
	end)

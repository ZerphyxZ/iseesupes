--!strict

-- Studio-only dev tool: lets the developer reset their own profile to test
-- onboarding and first-join flows without affecting any published data.
--
-- Usage: type "/devresetdata" in the in-game chat while in Studio.
-- The server wipes the player's profile data and respawns them fresh.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Only register this service in Studio
if not RunService:IsStudio() then
	local Knit = require(ReplicatedStorage.Packages.Knit)
	-- Return a no-op stub so the Knit loader doesn't error
	return Knit.CreateService({ Name = "DevResetService" })
end

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProfileTemplate = require(ReplicatedStorage.Shared.Utils.ProfileTemplate)

local DevResetService = Knit.CreateService({ Name = "DevResetService" })

local DataService: any = nil

local function resetPlayer(player: Player)
	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		warn("[DevReset] No profile found for", player.Name)
		return
	end

	-- Wipe all data back to template defaults
	ProfileTemplate.applyTo(profile.Data)

	DataService:Replicate(player)
	player:LoadCharacter()

	print("[DevReset] ✅ Profile wiped for", player.Name, "— rejoining as a fresh player.")
end

function DevResetService:KnitStart()
	DataService = Knit.GetService("DataService")

	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(msg: string)
			if msg:lower() == "/devresetdata" then
				print("[DevReset] Resetting data for", player.Name)
				resetPlayer(player)
			end
			if msg:lower() == "/devfunnel" then
				local ok, svc = pcall(function()
					return Knit.GetService("SkipStageService")
				end)
				if ok and svc then
					svc:PrintFunnel()
				end
			end
		end)
	end)

	print("[iseesupes] DevResetService ready (Studio only). Type /devresetdata to test onboarding.")
end

return DevResetService

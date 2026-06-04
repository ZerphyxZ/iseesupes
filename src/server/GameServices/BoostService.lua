--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local ThrustConfigs = require(ReplicatedStorage.Shared.Configs.ThrustConfigs)

local BoostService = Knit.CreateService({
	Name = "BoostService",
	Client = {
		BoostActivated = Knit.CreateSignal(),
		BoostCleared = Knit.CreateSignal(),
	},
})

local DataService: any = nil

local BOOST_THRUST_MULTIPLIER = 2
local BOOST_SPEED_MULTIPLIER = 1.5

function BoostService:IsBoostActive(player: Player): boolean
	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end
	return profile.Data.BoostActive == true
end

function BoostService:GrantBoost(player: Player): boolean
	if not player or not player.Parent then
		return false
	end

	local profile = DataService:GetProfile(player)
	if not profile then
		return false
	end

	local data = profile.Data

	-- Save original thrust max before boosting (only if not already boosted)
	if type(data.BoostOriginalThrustMax) ~= "number" then
		data.BoostOriginalThrustMax = data.ThrustMax or ThrustConfigs.BaseMaxFuel
	end

	-- Mark boost as active in profile data
	data.BoostActive = true

	-- Calculate doubled thrust
	local originalMaxThrust = data.BoostOriginalThrustMax
	local doubledThrust = originalMaxThrust * BOOST_THRUST_MULTIPLIER

	-- Set player attributes for client-side UI indication and thrust sync
	player:SetAttribute("BoostActive", true)
	player:SetAttribute("BoostSpeedMultiplier", BOOST_SPEED_MULTIPLIER)
	player:SetAttribute("ThrustPower", doubledThrust)

	-- Use DataService to properly apply the new max thrust (this handles syncing)
	DataService:ApplyUpgradedMax(player, doubledThrust)

	BoostService.Client.BoostActivated:Fire(player)

	print("[BoostService] Boost activated for", player.Name, "thrust:", originalMaxThrust, "->", doubledThrust)
	return true
end

function BoostService:ClearBoost(player: Player)
	if not player or not player.Parent then
		return
	end

	local profile = DataService:GetProfile(player)
	if not profile then
		return
	end

	local data = profile.Data

	-- Only clear if boost is active
	if data.BoostActive ~= true then
		return
	end

	-- Restore original thrust max from saved value
	local restoreThrust = ThrustConfigs.BaseMaxFuel
	if type(data.BoostOriginalThrustMax) == "number" then
		restoreThrust = data.BoostOriginalThrustMax
		data.BoostOriginalThrustMax = nil
	end

	-- Clear boost flag from profile
	data.BoostActive = nil

	-- Clear player attributes and restore ThrustPower attribute
	player:SetAttribute("BoostActive", nil)
	player:SetAttribute("BoostSpeedMultiplier", nil)
	player:SetAttribute("ThrustPower", restoreThrust)

	-- Use DataService to properly restore the original max thrust
	DataService:ApplyUpgradedMax(player, restoreThrust)

	BoostService.Client.BoostCleared:Fire(player)

	print("[BoostService] Boost cleared for", player.Name, "thrust restored to:", restoreThrust)
end

function BoostService:KnitStart()
	DataService = Knit.GetService("DataService")
end

return BoostService

--!strict
-- Local-only debug logging (no HTTP).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

local DebugLog = {}

local function isDebugEnabled(): boolean
	local djCfg = CharacterConfigs.DoubleJump
	return djCfg.Debug == true
end

function DebugLog.write(location: string, message: string, data: { [string]: any }?, _hypothesisId: string?)
	if not isDebugEnabled() then
		return
	end

	local side = if RunService:IsServer() then "server" else "client"
	warn("[DJ_DEBUG]", side, location, message, data or {})
end

return DebugLog

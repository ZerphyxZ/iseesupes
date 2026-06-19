--!strict

-- Studio-only dev tool: reset profile to test onboarding / tutorial from scratch.
--
-- Chat commands (Studio only):
--   /devresetdata  /devreset  /dev reset  /reset

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local RunService = game:GetService("RunService")

-- Only register this service in Studio
if not RunService:IsStudio() then
	local Knit = require(ReplicatedStorage.Packages.Knit)
	return Knit.CreateService({ Name = "DevResetService" })
end

local Knit = require(ReplicatedStorage.Packages.Knit)

local DevResetService = Knit.CreateService({ Name = "DevResetService" })

local DataService: any = nil

local RESET_COMMANDS: { [string]: boolean } = {
	["/devresetdata"] = true,
	["/devreset"] = true,
	["/dev reset"] = true,
	["/reset"] = true,
}

local function normalizeChatCommand(msg: string): string
	local trimmed = string.lower(msg:gsub("^%s+", ""))
	return trimmed:match("^(%S+)") or ""
end

local function resetPlayer(player: Player)
	if not DataService then
		warn("[DevReset] DataService not ready")
		return
	end

	local ok = DataService:ResetProfileForStudioTest(player, true)
	if not ok then
		warn("[DevReset] ResetProfileForStudioTest failed for", player.Name)
		return
	end

	player:LoadCharacter()
	print(
		"[DevReset] Profile wiped (",
		player.Name,
		") — tutorial reset to step",
		1,
		"(GoTreadmill); foot beam should guide from treadmill"
	)
end

function DevResetService:KnitStart()
	DataService = Knit.GetService("DataService")

	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(msg: string)
			local cmd = normalizeChatCommand(msg)
			if RESET_COMMANDS[cmd] then
				print("[DevReset] Resetting data for", player.Name, "(command:", cmd, ")")
				resetPlayer(player)
				return
			end
			if cmd == "/devfunnel" then
				local ok, svc = pcall(function()
					return Knit.GetService("SkipStageService")
				end)
				if ok and svc then
					svc:PrintFunnel()
				end
			end
		end)
	end)

	StudioLog.ready("DevResetService", "Studio chat: /devreset or /devresetdata")
end

return DevResetService

--!strict

local RunService = game:GetService("RunService")

local StudioLogsConfig = require(script.Parent.Parent.Configs.StudioLogsConfig)

local StudioLog = {}

local function isCategoryEnabled(category: string): boolean
	local enabled = (StudioLogsConfig :: any)[category]
	if enabled == true then
		return true
	end
	return false
end

function StudioLog.isEnabled(category: string): boolean
	if not RunService:IsStudio() then
		return isCategoryEnabled(category)
	end
	return isCategoryEnabled(category)
end

function StudioLog.ifEnabled(category: string, fn: () -> ())
	if StudioLog.isEnabled(category) then
		fn()
	end
end

function StudioLog.print(category: string, ...: any)
	if StudioLog.isEnabled(category) then
		print(...)
	end
end

function StudioLog.ready(name: string, suffix: string?)
	if not StudioLog.isEnabled("ReadyMessages") then
		return
	end
	if suffix and suffix ~= "" then
		print("[iseesupes]", name, "ready.", suffix)
	else
		print("[iseesupes]", name, "ready.")
	end
end

function StudioLog.warnAlways(...: any)
	warn(...)
end

return StudioLog

--!strict

local FriendStandConfigs = require(script.Parent.Parent.Configs.FriendStandConfigs)

local FriendStandDebug = {}

function FriendStandDebug.log(...: any)
	if not FriendStandConfigs.DebugPrint then
		return
	end
	print("[FriendStand]", ...)
end

function FriendStandDebug.warn(...: any)
	warn("[FriendStand]", ...)
end

return FriendStandDebug

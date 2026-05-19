--!strict

-- Client notifications. Wire your toast UI via NotificationManager.OnShow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

export type NotificationKind = "Success" | "Error" | "Info"

local NotificationManager = {}

NotificationManager.OnShow = Signal.new()

function NotificationManager.show(message: string, kind: string?)
	NotificationManager.OnShow:Fire(message, kind or "Info")
	print("[iseesupes][Notification]", kind or "Info", message)
end

return NotificationManager

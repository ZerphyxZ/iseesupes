--!strict
-- Agent debug logging (NDJSON via HTTP ingest + Studio warn).

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local DEBUG_ENDPOINT = "http://127.0.0.1:7242/ingest/ec2fa071-a096-4a67-a4a0-c5b59906f669"

local DebugLog = {}

function DebugLog.write(location: string, message: string, data: { [string]: any }?, hypothesisId: string?)
	local payload = {
		id = string.format("dj_%.3f", os.clock()),
		timestamp = math.floor(os.clock() * 1000),
		location = location,
		message = message,
		data = data or {},
		hypothesisId = hypothesisId or "",
		side = if RunService:IsServer() then "server" else "client",
	}

	local body = HttpService:JSONEncode(payload)

	-- #region agent log
	pcall(function()
		HttpService:RequestAsync({
			Url = DEBUG_ENDPOINT,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = body,
		})
	end)
	warn("[DJ_DEBUG]", payload.side, message, body)
	-- #endregion
end

return DebugLog

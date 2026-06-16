--!strict

-- Client-only quality hints (mobile / low graphics). Shared so configs can reference flags.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ClientPerformance = {}

local cachedMobile: boolean? = nil
local cachedLowEnd: boolean? = nil

function ClientPerformance.isMobile(): boolean
	if cachedMobile ~= nil then
		return cachedMobile
	end
	-- Touch-only devices (phones/tablets). Touch + keyboard = many laptops; treat as desktop.
	cachedMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	return cachedMobile
end

function ClientPerformance.isLowEnd(): boolean
	if cachedLowEnd ~= nil then
		return cachedLowEnd
	end

	local low = ClientPerformance.isMobile()
	if not low then
		local ok, gameSettings = pcall(function()
			return UserSettings():GetService("UserGameSettings")
		end)
		if ok and gameSettings then
			local quality = gameSettings.SavedQualityLevel
			if typeof(quality) == "number" and quality > 0 and quality <= 3 then
				low = true
			end
		end
	end

	cachedLowEnd = low
	return cachedLowEnd
end

--- Heavy Superman break particles, scorch decals, impact raycasts.
function ClientPerformance.shouldReduceSupermanVfx(): boolean
	return ClientPerformance.isLowEnd()
end

--- Limb glide trails during E-flight.
function ClientPerformance.shouldDisableFlightTrails(): boolean
	return ClientPerformance.isLowEnd()
end

--- Cape MeshPart fluid sim + per-frame bone flutter.
function ClientPerformance.shouldReduceCapeDynamics(): boolean
	return ClientPerformance.isLowEnd()
end

--- Seconds between cape bone updates (0 = every Heartbeat).
function ClientPerformance.getCapeTickInterval(): number
	return if ClientPerformance.isLowEnd() then 1 / 20 else 0
end

--- E-flight steer replication rate (Hz).
function ClientPerformance.getSteerSendHz(): number
	if ClientPerformance.isLowEnd() then
		return 8
	end
	if ClientPerformance.isMobile() then
		return 10
	end
	return 15
end

--- LeanUp landing watchdog interval when heavy checks are skipped.
function ClientPerformance.getLandingWatchdogInterval(): number
	if ClientPerformance.isMobile() or ClientPerformance.isLowEnd() then
		return 0.22
	end
	return 0.15
end

--- Skip verbose flight debug logs outside Studio.
function ClientPerformance.shouldSkipFlightDebugLogs(): boolean
	return not RunService:IsStudio()
end

return ClientPerformance

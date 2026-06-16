--!strict

-- Toast copy for blocked actions (E / thrust UI, etc.).

local NotificationConfigs = {}

export type NotificationKind = "Success" | "Error" | "Info"

--- Min seconds between flight-cooldown toasts (spamming fly while on CD).
CooldownToastDebounceSeconds = 10

local function formatSeconds(seconds: number): string
	local sec = math.max(0, seconds)
	if sec >= 10 then
		return string.format("%ds", math.ceil(sec))
	end
	return string.format("%.1fs", math.max(0.1, sec))
end

NotificationConfigs.KindByReason = {
	cooldown = "Error",
	no_thrust = "Error",
	no_solar = "Error",
	active = "Info",
	grounded = "Info",
	airborne = "Info",
	super_jump_active = "Info",
	dead = "Error",
	disabled = "Info",
	no_character = "Error",
} :: { [string]: NotificationKind }

function NotificationConfigs.GetKind(reason: string): NotificationKind
	return NotificationConfigs.KindByReason[reason] or "Info"
end

function NotificationConfigs.GetMessage(reason: string, detail: number?): string
	if reason == "cooldown" then
		local seconds = if type(detail) == "number" then detail else 0
		return "Flight on cooldown — " .. formatSeconds(seconds) .. " left"
	end
	if reason == "no_thrust" then
		return "Not enough thrust — wait on the ground to recharge"
	end
	if reason == "no_solar" then
		return "Not enough solar energy — fly to recharge heat vision"
	end
	if reason == "active" then
		return "Already using thrust flight!"
	end
	if reason == "grounded" then
		return "Can't start thrust here on the ground!"
	end
	if reason == "airborne" then
		return "You need to be in the air first!"
	end
	if reason == "super_jump_active" then
		return "Finish your super jump first!"
	end
	if reason == "dead" then
		return "Can't use thrust right now!"
	end
	if reason == "disabled" then
		return "Thrust flight is disabled!"
	end
	if reason == "no_character" then
		return "Character not ready yet!"
	end
	return "Can't do that right now!"
end

return NotificationConfigs

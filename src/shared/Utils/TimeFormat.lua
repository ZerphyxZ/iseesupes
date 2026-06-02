--!strict

local TimeFormat = {}

function TimeFormat.formatPlayTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local days = math.floor(s / 86400)
	s = s % 86400
	local hours = math.floor(s / 3600)
	s = s % 3600
	local minutes = math.floor(s / 60)

	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm", minutes)
	end
	return string.format("%ds", s)
end

return TimeFormat

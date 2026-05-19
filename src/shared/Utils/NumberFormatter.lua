--!strict

local NumberFormatter = {}

function NumberFormatter.Format(n: number): string
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end
	local int = math.floor(n + 0.5)
	local s = tostring(int)
	local pattern = "(%d)(%d%d%d)$"
	while true do
		local replaced, count = s:gsub(pattern, "%1,%2")
		s = replaced
		if count == 0 then
			break
		end
	end
	return sign .. s
end

return NumberFormatter

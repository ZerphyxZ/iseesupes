--!strict

-- Parses Addon labels such as "+1/Step", "+50k/Step", "+1.5m/Step".

local StepBonusParser = {}

local SUFFIX_MULTIPLIERS: { [string]: number } = {
	k = 1e3,
	K = 1e3,
	m = 1e6,
	M = 1e6,
	b = 1e9,
	B = 1e9,
}

local function parseNumberToken(token: string): number?
	local numPart, suffix = string.match(token, "^([%d%.]+)([kKmMbB]?)$")
	if not numPart then
		return nil
	end
	local base = tonumber(numPart)
	if not base then
		return nil
	end
	if suffix and suffix ~= "" then
		local mult = SUFFIX_MULTIPLIERS[suffix]
		if mult then
			base *= mult
		end
	end
	return base
end

function StepBonusParser.parse(text: string): number?
	if text == "" then
		return nil
	end

	local token = string.match(text, "([%+%-]?[%d%.]+[kKmMbB]?)/[Ss]tep")
	if not token then
		token = string.match(text, "([%+%-]?[%d%.]+[kKmMbB]?)")
	end
	if not token then
		return nil
	end

	local value = parseNumberToken(token)
	if not value or value <= 0 then
		return nil
	end

	return math.floor(value + 0.5)
end

function StepBonusParser.format(bonus: number): string
	if bonus >= 1e9 then
		return string.format("+%.1fb/Step", bonus / 1e9)
	elseif bonus >= 1e6 then
		return string.format("+%.1fm/Step", bonus / 1e6)
	elseif bonus >= 1e3 then
		return string.format("+%.0fk/Step", bonus / 1e3)
	end
	return "+" .. tostring(math.floor(bonus)) .. "/Step"
end

return StepBonusParser

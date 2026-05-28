--!strict

-- Parses WinAmount UI text such as "+1 Win", "+4 Win", "1 Win".

local WinAmountParser = {}

function WinAmountParser.parse(text: string): number?
	if text == "" then
		return nil
	end

	local digits = string.match(text, "(%d+)")
	if not digits then
		return nil
	end

	local amount = tonumber(digits)
	if not amount or amount <= 0 then
		return nil
	end

	return math.floor(amount)
end

-- Parses "500 Wins Required", "1 Win", etc.
function WinAmountParser.parseWinsRequired(text: string): number?
	return WinAmountParser.parse(text)
end

return WinAmountParser

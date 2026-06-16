--!strict

-- Stage 1 fly-lesson assist: active only at TutorialStep GoStage1 before first successful fly.

local TutorialConfigs = require(script.Parent.Parent.Configs.TutorialConfigs)

local TutorialFlightAssist = {}

function TutorialFlightAssist.getAttributeName(): string
	local cfg = TutorialConfigs.FlightAssist
	if cfg and type(cfg.AttributeName) == "string" and cfg.AttributeName ~= "" then
		return cfg.AttributeName
	end
	return "TutorialFlightAssist"
end

function TutorialFlightAssist.isActiveForData(data: any): boolean
	local cfg = TutorialConfigs.FlightAssist
	if not cfg or cfg.Enabled == false then
		return false
	end
	if not data then
		return false
	end
	if data.TutorialFlyIntroShown == true then
		return false
	end
	local step = if type(data.TutorialStep) == "number" then math.floor(data.TutorialStep) else 0
	return step == TutorialConfigs.Step.GoStage1
end

function TutorialFlightAssist.isActiveForPlayer(player: Player): boolean
	return player:GetAttribute(TutorialFlightAssist.getAttributeName()) == true
end

return TutorialFlightAssist

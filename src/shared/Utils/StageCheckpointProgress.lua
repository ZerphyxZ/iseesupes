--!strict

local StageCheckpointProgress = {}

function StageCheckpointProgress.getEffectiveStage(data: any): number
	if not data then
		return 0
	end
	local stage = if type(data.Stage) == "number" then data.Stage else 0
	local maxStage = if type(data.MaxStage) == "number" then data.MaxStage else 0
	if stage == 1 and maxStage <= 0 then
		return 0
	end
	return math.max(0, stage)
end

return StageCheckpointProgress

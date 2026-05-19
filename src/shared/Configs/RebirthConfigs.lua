--!strict

local RebirthConfigs = {
	LevelStep = 5,
	MultAdd = 0.5,
	ResetLevelOnRebirth = true,
}

function RebirthConfigs.GetRequiredLevel(rebirths: number): number
	return (rebirths + 1) * RebirthConfigs.LevelStep
end

function RebirthConfigs.GetNextRequiredLevel(rebirths: number): number
	return (rebirths + 2) * RebirthConfigs.LevelStep
end

function RebirthConfigs.GetSpeedMultiplier(rebirths: number): number
	return 1 + (rebirths * RebirthConfigs.MultAdd)
end

return RebirthConfigs

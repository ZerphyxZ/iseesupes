--!strict

local StageCheckpointConfigs = require(script.Parent.Parent.Configs.StageCheckpointConfigs)

local StageCheckpointDebug = {}

local lastLogAt: { [string]: number } = {}

function StageCheckpointDebug.log(message: string, throttleKey: string?, throttleSec: number?)
	if not StageCheckpointConfigs.Debug then
		return
	end
	if throttleKey then
		local now = os.clock()
		local waitSec = throttleSec or 1
		local last = lastLogAt[throttleKey]
		if last and now - last < waitSec then
			return
		end
		lastLogAt[throttleKey] = now
	end
	print("[iseesupes][StageCheckpoint]", message)
end

function StageCheckpointDebug.logAlways(message: string)
	if not StageCheckpointConfigs.Debug then
		return
	end
	print("[iseesupes][StageCheckpoint]", message)
end

function StageCheckpointDebug.countKeys(map: { [any]: any }): number
	local count = 0
	for _ in map do
		count += 1
	end
	return count
end

function StageCheckpointDebug.formatStageList(stages: { number }): string
	if #stages == 0 then
		return "(none)"
	end
	local parts: { string } = {}
	for _, stageNum in stages do
		table.insert(parts, tostring(stageNum))
	end
	return table.concat(parts, ",")
end

return StageCheckpointDebug

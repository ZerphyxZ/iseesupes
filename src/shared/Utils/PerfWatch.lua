--!strict

-- Lightweight Studio timing wrapper for MicroProfiler spike diagnosis.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local PerfWatch = {}

function PerfWatch.enabled(): boolean
	return StudioLog.isEnabled("PerfWatch")
end

function PerfWatch.measure<T>(label: string, fn: () -> T): T
	if not PerfWatch.enabled() then
		return fn()
	end
	local t0 = os.clock()
	local ok, result = pcall(fn)
	local ms = (os.clock() - t0) * 1000
	if ok then
		print(string.format("[PerfWatch] %s %.2fms", label, ms))
		return result
	end
	print(string.format("[PerfWatch] %s %.2fms (error)", label, ms))
	error(result)
end

return PerfWatch

--!strict

-- Client-side data and gamepass access. Controllers read through here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Packages.Signal)

type Callback = (data: any) -> ()
type GamepassCallback = (key: string, owned: boolean) -> ()

local DataLib = {}

local _lastData: any = nil
local _gamepasses: { [string]: boolean } = {}
local _dataChangedEvent = Signal.new()
local _thrustChangedEvent = Signal.new()
local _solarChangedEvent = Signal.new()
local _gamepassChangedEvent = Signal.new()

function DataLib.SetData(data: any)
	_lastData = data
	_dataChangedEvent:Fire(data)
end

function DataLib.GetData(): any
	return _lastData
end

-- True once the player's data snapshot has replicated at least once.
function DataLib.IsLoaded(): boolean
	return _lastData ~= nil
end

-- Calls `callback` once as soon as data is available (immediately if already loaded).
-- Returns the underlying connection, or nil if it fired immediately.
function DataLib.OnReady(callback: () -> ()): any
	if _lastData ~= nil then
		task.spawn(callback)
		return nil
	end
	local conn
	conn = _dataChangedEvent:Connect(function()
		if conn then
			conn:Disconnect()
			conn = nil
		end
		callback()
	end)
	return conn
end

function DataLib.OnChanged(callback: Callback)
	return _dataChangedEvent:Connect(callback)
end

function DataLib.SetThrust(current: number, max: number)
	if _lastData then
		_lastData.ThrustCurrent = current
		_lastData.ThrustMax = max
	end
	_thrustChangedEvent:Fire(current, max)
end

function DataLib.SetSolar(current: number, max: number)
	if _lastData then
		_lastData.SolarCurrent = current
		_lastData.SolarMax = max
	end
	_solarChangedEvent:Fire(current, max)
end

function DataLib.OnThrustChanged(callback: (current: number, max: number) -> ())
	return _thrustChangedEvent:Connect(callback)
end

function DataLib.OnSolarChanged(callback: (current: number, max: number) -> ())
	return _solarChangedEvent:Connect(callback)
end

function DataLib.SetGamepass(key: string, owned: boolean)
	_gamepasses[key] = owned
	_gamepassChangedEvent:Fire(key, owned)
end

function DataLib.SetGamepasses(snapshot: { [string]: boolean })
	_gamepasses = snapshot
	for key, owned in snapshot do
		_gamepassChangedEvent:Fire(key, owned)
	end
end

function DataLib.OwnsGamepass(key: string): boolean
	return _gamepasses[key] == true
end

function DataLib.GetGamepasses(): { [string]: boolean }
	return _gamepasses
end

function DataLib.OnGamepassChanged(callback: GamepassCallback)
	return _gamepassChangedEvent:Connect(callback)
end

return DataLib

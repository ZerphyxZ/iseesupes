--!strict

-- Applies level-based walk/swim speed to the live character (server authority + client mirror).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelDesignTuning = require(ReplicatedStorage.Shared.Utils.LevelDesignTuning)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)

local CharacterMovementSpeed = {}

local function roundSpeed(speed: number): number
	return math.max(0, math.floor(speed + 0.5))
end

function CharacterMovementSpeed.getLevel(data: any): number
	if data and type(data.Level) == "number" then
		return math.max(1, math.floor(data.Level))
	end
	return 1
end

function CharacterMovementSpeed.getBaseSpeedForLevel(level: number): number
	return SpeedConfigs.GetSpeedFromLevel(level)
end

function CharacterMovementSpeed.getSpeedForLevel(player: Player, level: number, data: any?): number
	local base = CharacterMovementSpeed.getBaseSpeedForLevel(level)
	if data then
		base *= TrailConfigs.GetEquippedSpeedMultiplier(data)
	end
	return roundSpeed(LevelDesignTuning.resolveSwimSpeed(player, base))
end

function CharacterMovementSpeed.getSpeedForData(player: Player, data: any): number
	local level = CharacterMovementSpeed.getLevel(data)
	return CharacterMovementSpeed.getSpeedForLevel(player, level, data)
end

function CharacterMovementSpeed.getCustomSpeedCap(character: Model): number?
	local cap = character:GetAttribute(SpeedConfigs.CustomSpeedCapAttribute)
	if typeof(cap) == "number" and cap > 0 then
		return roundSpeed(cap)
	end
	return nil
end

--- Profile max with optional Custom Speed HUD cap applied (integer studs/s).
function CharacterMovementSpeed.getEffectiveSpeed(player: Player, data: any?): number
	local maxSpeed = CharacterMovementSpeed.getSpeedForData(player, data)
	local character = player.Character
	if character then
		local cap = CharacterMovementSpeed.getCustomSpeedCap(character)
		if cap and cap < maxSpeed then
			return cap
		end
	end
	return maxSpeed
end

function CharacterMovementSpeed.setCustomSpeedCap(player: Player, cap: number?)
	local character = player.Character
	if not character then
		return
	end
	if cap and cap > 0 then
		character:SetAttribute(SpeedConfigs.CustomSpeedCapAttribute, roundSpeed(cap))
	else
		character:SetAttribute(SpeedConfigs.CustomSpeedCapAttribute, nil)
	end
end

function CharacterMovementSpeed.applyToCharacter(player: Player, character: Model, data: any?): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local maxSpeed = CharacterMovementSpeed.getSpeedForData(player, data)
	local speed = CharacterMovementSpeed.getEffectiveSpeed(player, data)
	humanoid.WalkSpeed = speed
	character:SetAttribute(SpeedConfigs.SwimSpeedAttribute, speed)

	local ratio = if maxSpeed > 0 then speed / maxSpeed else 1
	character:SetAttribute(SpeedConfigs.CustomSpeedRatioAttribute, ratio)
	return true
end

function CharacterMovementSpeed.applyToPlayer(player: Player, data: any?): boolean
	local character = player.Character
	if not character then
		return false
	end
	return CharacterMovementSpeed.applyToCharacter(player, character, data)
end

return CharacterMovementSpeed

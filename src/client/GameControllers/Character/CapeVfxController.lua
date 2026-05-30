--!strict

-- Cape Idle / Walk / Fly / Land + glide trails during E-flight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local AvatarReplace = require(ReplicatedStorage.Shared.Utils.AvatarReplace)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local GlideVfxConfigs = require(ReplicatedStorage.Shared.Configs.GlideVfxConfigs)
local CapeVfx = require(script.Parent.Parent.Parent.Modules.CapeVfx)
local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)

local CapeVfxController = Knit.CreateController({ Name = "CapeVfxController" })

local LOG_PREFIX = "[iseesupes][CapeVfxCtrl]"

local DJ_PHASE_ATTR = "DjAbilityPhase"

local player = Players.LocalPlayer

local function debugLog(...)
	if not GlideVfxConfigs.Debug then
		return
	end
	print(LOG_PREFIX, ...)
end

local currentAbilityPhase: string? = nil
local currentLocomotion: "idle" | "run" | "landing" = "idle"
local heartbeatConn: RBXScriptConnection? = nil
local rigReadyHandled: { [Model]: boolean } = {}

local function resolvePath(root: Instance, segments: { string }): Instance?
	local current: Instance = root
	for _, name in segments do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function findSoundsFolder(): Folder?
	local folder = resolvePath(ReplicatedStorage, GlideVfxConfigs.Assets.GlideSoundsFolder)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function isCapeEnabled(): boolean
	if not GlideVfxConfigs.Enabled then
		return false
	end
	if CharacterConfigs.Features.UseCapeVfx == false then
		return false
	end
	if CharacterConfigs.Features.UseGlideVfx == false then
		return false
	end
	return true
end

local function readAbilityPhaseFromAttribute(): string?
	local attr = player:GetAttribute(DJ_PHASE_ATTR)
	if typeof(attr) == "string" and attr ~= "" then
		return attr
	end
	return nil
end

local function getEffectiveAbilityPhase(): string?
	return readAbilityPhaseFromAttribute() or currentAbilityPhase
end

local function resolveDesiredCapeState(): CapeVfx.CapeVisualState
	local phaseState = CapeVfx.phaseToCapeState(getEffectiveAbilityPhase())
	if phaseState then
		return phaseState
	end
	return CapeVfx.locomotionToCapeState(currentLocomotion)
end

local function applyCapeForCharacter(character: Model?, force: boolean?)
	if not character then
		return
	end

	local capeState = resolveDesiredCapeState()
	local sounds = findSoundsFolder()

	debugLog(
		"applyForCharacter",
		capeState,
		"force=",
		force == true,
		"phase=",
		tostring(getEffectiveAbilityPhase()),
		"loco=",
		currentLocomotion,
		"path=",
		tostring(CapeVfx.getResolvedCapePath(character)),
		"active=",
		tostring(CapeVfx.getActiveCapeState(character))
	)

	local ok, err = pcall(function()
		CapeVfx.applyCapeState(character, capeState, force)
		CapeVfx.setFlyEffectsActive(character, capeState == GlideVfxConfigs.States.Fly, sounds)
	end)
	if not ok then
		warn(LOG_PREFIX, "apply error:", err)
	end
end

local function onAbilityPhase(phase: string?)
	currentAbilityPhase = phase
	debugLog("abilityPhase", tostring(phase))
	applyCapeForCharacter(player.Character)
end

local function syncAbilityPhaseFromAttribute()
	local attrPhase = readAbilityPhaseFromAttribute()
	if attrPhase ~= currentAbilityPhase then
		onAbilityPhase(attrPhase)
	end
end

local function onCapeRigReady(character: Model)
	if rigReadyHandled[character] then
		return
	end
	rigReadyHandled[character] = true
	debugLog("rig ready", character.Name, "path=", CapeVfx.getResolvedCapePath(character))
	CapeVfx.forceRefresh(character)
	applyCapeForCharacter(character, true)
end

local function scheduleCapeRefresh(character: Model)
	debugLog("scheduleCapeRefresh", character.Name, "avatar=", character:GetAttribute(AvatarReplace.EQUIPPED_SHOWCASE_ATTR))

	CapeVfx.watchForRig(character, function()
		onCapeRigReady(character)
	end)

	task.spawn(function()
		local rig = CapeVfx.waitForRig(character, GlideVfxConfigs.RigWaitSeconds)
		if rig and character.Parent then
			onCapeRigReady(character)
		elseif character.Parent then
			CapeVfx.warnNoRigOnce(character)
		end
	end)
end

local function syncGlideTrailColorFromData()
	local data = DataLib.GetData()
	local trailId = if data and type(data.EquippedTrail) == "string" then data.EquippedTrail else ""
	local info = if trailId ~= "" then TrailConfigs.GetTrailById(trailId) else nil
	local defaultTrail = TrailConfigs.GetDefaultTrail()
	local color: ColorSequence? = nil
	if info and info.Color then
		color = info.Color
	elseif defaultTrail and defaultTrail.Color then
		color = defaultTrail.Color
	end
	CapeVfx.setEquippedTrailColor(color)

	local character = player.Character
	if character then
		CapeVfx.setGlideTrailColor(character, color)
	end
end

local function onLocomotionChanged(character: Model, locomotion: string)
	if character ~= player.Character then
		return
	end
	if locomotion == "idle" or locomotion == "run" or locomotion == "landing" then
		currentLocomotion = locomotion
	end
	local effectivePhase = getEffectiveAbilityPhase()
	debugLog("locomotion", locomotion, "phase=", tostring(effectivePhase))
	if not CapeVfx.isFlyPhase(effectivePhase) and not CapeVfx.isLandPhase(effectivePhase) then
		applyCapeForCharacter(character)
	end
end

local function bindCharacter(character: Model)
	debugLog("bindCharacter", character.Name, "avatar=", character:GetAttribute(AvatarReplace.EQUIPPED_SHOWCASE_ATTR))
	character:GetAttributeChangedSignal(AvatarReplace.EQUIPPED_SHOWCASE_ATTR):Connect(function()
		debugLog("avatarAttrChanged", character:GetAttribute(AvatarReplace.EQUIPPED_SHOWCASE_ATTR))
		scheduleCapeRefresh(character)
	end)
	character.Destroying:Once(function()
		rigReadyHandled[character] = nil
		CapeVfx.cleanupCharacter(character)
	end)
	scheduleCapeRefresh(character)
end

local function heartbeatFallback()
	local character = player.Character
	if not character then
		return
	end

	if CapeVfx.needsApply(character) and CapeVfx.resolveCapeRig(character) then
		debugLog("heartbeat retry needsApply")
		applyCapeForCharacter(character, true)
	end

	if not CharacterConfigs.Features.UseDoubleJump then
		return
	end
	local effectivePhase = getEffectiveAbilityPhase()
	if CapeVfx.isFlyPhase(effectivePhase) or CapeVfx.isLandPhase(effectivePhase) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local threshold = GlideVfxConfigs.Locomotion.MoveThreshold
	local locomotion: "idle" | "run" = if humanoid.MoveDirection.Magnitude > threshold then "run" else "idle"
	if locomotion ~= currentLocomotion and currentLocomotion ~= "landing" then
		currentLocomotion = locomotion
		applyCapeForCharacter(character)
	end
end

function CapeVfxController:KnitStart()
	if not isCapeEnabled() then
		warn(LOG_PREFIX, "disabled (Enabled/UseCapeVfx/UseGlideVfx)")
		return
	end

	debugLog("KnitStart", "Debug=", GlideVfxConfigs.Debug)

	local DoubleJumpService = Knit.GetService("DoubleJumpService")
	local CharacterController = Knit.GetController("CharacterController")

	DoubleJumpService.PhaseChanged:Connect(function(phase: string)
		onAbilityPhase(phase)
	end)

	DoubleJumpService.AbilityEnded:Connect(function()
		task.defer(syncAbilityPhaseFromAttribute)
	end)

	player:GetAttributeChangedSignal(DJ_PHASE_ATTR):Connect(syncAbilityPhaseFromAttribute)

	if CharacterController.ConnectLocomotionChanged then
		CharacterController:ConnectLocomotionChanged(onLocomotionChanged)
	end

	player.CharacterAdded:Connect(function(character)
		currentAbilityPhase = readAbilityPhaseFromAttribute()
		currentLocomotion = "idle"
		table.clear(rigReadyHandled)
		CapeVfx.cleanupCharacter(character)
		task.defer(function()
			syncGlideTrailColorFromData()
			bindCharacter(character)
			syncAbilityPhaseFromAttribute()
		end)
	end)

	DataLib.OnChanged(function()
		syncGlideTrailColorFromData()
	end)

	task.defer(syncGlideTrailColorFromData)

	if player.Character then
		currentAbilityPhase = readAbilityPhaseFromAttribute()
		bindCharacter(player.Character)
		syncAbilityPhaseFromAttribute()
	end

	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	heartbeatConn = RunService.Heartbeat:Connect(function(_dt)
		heartbeatFallback()
	end)

	print("[iseesupes] CapeVfxController ready (cape Idle/Walk/Fly/Land + GlideTrail on E-flight).")
end

return CapeVfxController

--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

local AnimRoot = CharacterConfigs.Animations
local Loc = CharacterConfigs.Locomotion
local SjCfg = CharacterConfigs.SuperJump
local Features = CharacterConfigs.Features

local PHASE = {
	LeanUp = "LeanUp",
	DownSupes = "DownSupes",
}

local PHASE_ATTR = "SjAbilityPhase"
local DJ_PHASE_ATTR = "DjAbilityPhase"

local SuperJumpController = Knit.CreateController({ Name = "SuperJumpController" })

local player = Players.LocalPlayer
local animFolder: Folder? = nil
local abilityActive = false
local currentPhase: string? = nil
local abilitySessionId = 0
local smoothedSteerDir: Vector3? = nil
local phaseAttrConn: RBXScriptConnection? = nil
local toolUnequipConn: RBXScriptConnection? = nil

local CharacterController: any = nil

type SuperJumpTracks = {
	leanUp: AnimationTrack,
	downSupes: AnimationTrack,
}

type CharacterSuperJumpState = {
	character: Model,
	humanoid: Humanoid,
	tracks: SuperJumpTracks,
	currentTrack: AnimationTrack?,
	heartbeatConn: RBXScriptConnection?,
	leanUpLocked: boolean,
}

local characterStates: { [Model]: CharacterSuperJumpState } = {}

local function getPhaseFadeTime(): number
	return SjCfg.PhaseFadeTime or Loc.FadeTime
end

local function fadeOutTrack(track: AnimationTrack, fade: number, state: CharacterSuperJumpState?)
	if not track.IsPlaying then
		return
	end
	pcall(function()
		track:AdjustWeight(0, fade)
	end)
	task.delay(fade + 0.02, function()
		if state and state.currentTrack == track then
			return
		end
		pcall(function()
			if track.IsPlaying then
				track:Stop(0)
			end
		end)
	end)
end

local function crossfadeToTrack(state: CharacterSuperJumpState, track: AnimationTrack, fadeTime: number?)
	local fade = fadeTime or getPhaseFadeTime()
	if state.currentTrack == track then
		if track.IsPlaying then
			return
		end
		return
	end
	local outgoing = state.currentTrack
	state.currentTrack = track
	if outgoing and outgoing ~= track then
		fadeOutTrack(outgoing, fade, state)
	end
	pcall(function()
		track:Play(fade)
	end)
end

local function getAnimFolder(): Folder?
	if animFolder then
		return animFolder
	end
	local folder = ReplicatedStorage:FindFirstChild(AnimRoot.FolderName)
	if folder and folder:IsA("Folder") then
		animFolder = folder
		return folder
	end
	return nil
end

local function getAnimationInFolder(folder: Folder, subFolderName: string, animName: string): Animation?
	local sub = folder:FindFirstChild(subFolderName)
	if not sub then
		warn("[iseesupes] Missing folder:", subFolderName)
		return nil
	end
	local inst = sub:FindFirstChild(animName)
	if inst and inst:IsA("Animation") then
		return inst
	end
	warn("[iseesupes] Missing Animation:", animName, "in", subFolderName)
	return nil
end

local function getSuperJumpToolName(): string
	return SjCfg.ToolName or "SuperJump"
end

local function hasSuperJumpToolEquipped(character: Model): boolean
	local tool = character:FindFirstChild(getSuperJumpToolName())
	return tool ~= nil and tool:IsA("Tool")
end

local function flatUnit(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function getSteerThreshold(): number
	local steerCfg = SjCfg.Steering
	return steerCfg.SteerMoveThreshold or Loc.MoveThreshold
end

local function getSuperJumpSteerDirection(state: CharacterSuperJumpState): Vector3
	local camera = workspace.CurrentCamera
	if camera then
		local flatLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		if flatLook.Magnitude >= 0.01 then
			local camDir = flatUnit(flatLook)
			local move = state.humanoid.MoveDirection
			if move.Magnitude >= getSteerThreshold() then
				return flatUnit(camDir * 0.7 + flatUnit(move) * 0.3)
			end
			return camDir
		end
	end

	local move = state.humanoid.MoveDirection
	if move.Magnitude >= getSteerThreshold() then
		return flatUnit(move)
	end
	return Vector3.zero
end

local function publishSteerInput(state: CharacterSuperJumpState, dt: number)
	if not abilityActive then
		return
	end

	local raw = getSuperJumpSteerDirection(state)
	if raw.Magnitude < 0.01 then
		return
	end

	local steerCfg = SjCfg.Steering
	local smoothRate = steerCfg.SteerSmoothRate or 14
	local alpha = math.min(1, smoothRate * dt)
	if smoothedSteerDir then
		smoothedSteerDir = flatUnit((smoothedSteerDir :: Vector3):Lerp(raw, alpha))
	else
		smoothedSteerDir = raw
	end

	pcall(function()
		Knit.GetService("SuperJumpService"):UpdateSteerInput(smoothedSteerDir :: Vector3)
	end)
end

local function setAbilityBlocking(blocked: boolean)
	if CharacterController and CharacterController.SetAbilityBlocking then
		CharacterController:SetAbilityBlocking(blocked)
	end
end

local function stopAllTracks(state: CharacterSuperJumpState)
	pcall(function()
		state.tracks.leanUp:Stop(Loc.FadeTime)
		state.tracks.downSupes:Stop(Loc.FadeTime)
	end)
	state.currentTrack = nil
	state.leanUpLocked = false
end

local function playLeanUpOnce(state: CharacterSuperJumpState)
	if state.leanUpLocked then
		return
	end
	state.leanUpLocked = true
	crossfadeToTrack(state, state.tracks.leanUp, 0)
end

local function playDownSupesLanding(state: CharacterSuperJumpState)
	state.leanUpLocked = false
	crossfadeToTrack(state, state.tracks.downSupes, getPhaseFadeTime())
end

local function playPhaseAnim(state: CharacterSuperJumpState, phase: string)
	if phase == PHASE.LeanUp then
		playLeanUpOnce(state)
	elseif phase == PHASE.DownSupes then
		playDownSupesLanding(state)
	end
end

local function ensureDownSupesPlaying(state: CharacterSuperJumpState)
	if currentPhase ~= PHASE.DownSupes then
		return
	end
	if state.currentTrack == state.tracks.downSupes and state.tracks.downSupes.IsPlaying then
		return
	end
	playDownSupesLanding(state)
end

local function onAbilityEnded()
	abilityActive = false
	currentPhase = nil
	smoothedSteerDir = nil
	setAbilityBlocking(false)

	local character = player.Character
	if character then
		local st = characterStates[character]
		if st then
			stopAllTracks(st)
		end
	end
end

local function onPhaseChanged(phase: string)
	if phase == currentPhase then
		return
	end
	currentPhase = phase

	local character = player.Character
	if not character then
		return
	end

	local state = characterStates[character]
	if not state then
		return
	end

	playPhaseAnim(state, phase)
end

local function onAbilityPhaseAttributeChanged()
	if not abilityActive then
		return
	end
	local attrPhase = player:GetAttribute(PHASE_ATTR)
	if attrPhase == nil or (typeof(attrPhase) == "string" and attrPhase == "") then
		onAbilityEnded()
	end
end

local function bindPhaseAttributeSync()
	if phaseAttrConn then
		phaseAttrConn:Disconnect()
		phaseAttrConn = nil
	end
	phaseAttrConn = player:GetAttributeChangedSignal(PHASE_ATTR):Connect(onAbilityPhaseAttributeChanged)
end

local function cleanupCharacter(character: Model)
	if toolUnequipConn then
		toolUnequipConn:Disconnect()
		toolUnequipConn = nil
	end

	local state = characterStates[character]
	if not state then
		return
	end
	if state.heartbeatConn then
		state.heartbeatConn:Disconnect()
	end
	stopAllTracks(state)
	characterStates[character] = nil
end

local function setupCharacter(character: Model)
	cleanupCharacter(character)

	if not Features.UseSuperJump then
		return
	end

	local folder = getAnimFolder()
	if not folder then
		warn("[iseesupes] SuperJump setup failed: animation folder not found")
		return
	end

	local leanAnim = getAnimationInFolder(folder, SjCfg.AnimFolder, SjCfg.Anims.LeanUp)
	local downAnim = getAnimationInFolder(folder, SjCfg.AnimFolder, SjCfg.Anims.DownSupes)
	if not leanAnim or not downAnim then
		warn("[iseesupes] SuperJump setup failed: missing LeanUp or DownSupes animation")
		return
	end

	if leanAnim.AnimationId == "" or downAnim.AnimationId == "" then
		warn("[iseesupes] SuperJump animations need AnimationId set in Studio")
		return
	end

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ leanAnim, downAnim })
		end)
	end)

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function loadTrack(anim: Animation, looped: boolean): AnimationTrack
		local track = animator:LoadAnimation(anim)
		track.Looped = looped
		track.Priority = Enum.AnimationPriority.Action2
		return track
	end

	local tracks: SuperJumpTracks = {
		leanUp = loadTrack(leanAnim, true),
		downSupes = loadTrack(downAnim, false),
	}

	local state: CharacterSuperJumpState = {
		character = character,
		humanoid = humanoid,
		tracks = tracks,
		currentTrack = nil,
		heartbeatConn = nil,
		leanUpLocked = false,
	}
	characterStates[character] = state

	state.heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if abilityActive then
			publishSteerInput(state, dt)
			ensureDownSupesPlaying(state)
		end
	end)

	if toolUnequipConn then
		toolUnequipConn:Disconnect()
	end
	toolUnequipConn = character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and child.Name == getSuperJumpToolName() and abilityActive then
			onAbilityEnded()
		end
	end)

	character.Destroying:Once(function()
		cleanupCharacter(character)
		if abilityActive then
			onAbilityEnded()
		end
	end)
end

local function ensureAbilityState(character: Model): CharacterSuperJumpState?
	local state = characterStates[character]
	if state then
		return state
	end
	setupCharacter(character)
	return characterStates[character]
end

local function startAbilitySession(character: Model): CharacterSuperJumpState?
	abilitySessionId += 1
	currentPhase = nil

	local state = ensureAbilityState(character)
	if not state then
		return nil
	end
	state.leanUpLocked = false
	state.currentTrack = nil
	smoothedSteerDir = nil
	return state
end

function SuperJumpController:TrySuperJumpOnJump(): boolean
	if not Features.UseSuperJump then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	if not hasSuperJumpToolEquipped(character) then
		return false
	end

	if CharacterController and CharacterController.IsAbilityBlocking and CharacterController:IsAbilityBlocking() then
		return true
	end

	if player:GetAttribute(DJ_PHASE_ATTR) then
		return true
	end

	if abilityActive then
		return true
	end

	local service = Knit.GetService("SuperJumpService")
	service:RequestStart():andThen(function(ok: boolean, _reason: string?)
		if ok and not abilityActive then
			abilityActive = true
			setAbilityBlocking(true)
			startAbilitySession(character)
		end
	end):catch(warn)

	return true
end

function SuperJumpController:KnitInit()
	CharacterController = Knit.GetController("CharacterController")
	if CharacterController and CharacterController.RegisterJumpInterceptor then
		CharacterController:RegisterJumpInterceptor(function()
			return SuperJumpController:TrySuperJumpOnJump()
		end)
	end
end

function SuperJumpController:KnitStart()
	bindPhaseAttributeSync()

	local folder = ReplicatedStorage:WaitForChild(AnimRoot.FolderName, 30)
	if folder and folder:IsA("Folder") then
		animFolder = folder
	end

	local SuperJumpService = Knit.GetService("SuperJumpService")

	SuperJumpService.PhaseChanged:Connect(function(phase: string)
		if not abilityActive then
			abilityActive = true
			setAbilityBlocking(true)
			local character = player.Character
			if character then
				startAbilitySession(character)
			end
		end
		onPhaseChanged(phase)
	end)

	SuperJumpService.AbilityEnded:Connect(onAbilityEnded)

	player.CharacterAdded:Connect(function(character)
		if abilityActive then
			onAbilityEnded()
		end
		setupCharacter(character)
	end)

	if player.Character then
		setupCharacter(player.Character)
	end

	print("[iseesupes] SuperJumpController ready.")
end

return SuperJumpController

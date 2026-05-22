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
local lastSpaceBeginAt = 0
local phaseAttrConn: RBXScriptConnection? = nil

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
	if state.currentTrack == track and track.IsPlaying then
		return
	end
	local outgoing = state.currentTrack
	if outgoing and outgoing ~= track then
		fadeOutTrack(outgoing, fade, state)
	end
	pcall(function()
		track:Play(fade)
	end)
	state.currentTrack = track
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

local function isGrounded(humanoid: Humanoid): boolean
	return humanoid.FloorMaterial ~= Enum.Material.Air
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
end

local function playPhaseAnim(state: CharacterSuperJumpState, phase: string)
	if phase == PHASE.LeanUp then
		crossfadeToTrack(state, state.tracks.leanUp, getPhaseFadeTime())
	elseif phase == PHASE.DownSupes then
		crossfadeToTrack(state, state.tracks.downSupes, getPhaseFadeTime())
	end
end

local function onAbilityEnded()
	abilityActive = false
	currentPhase = nil
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

local function syncPhaseFromAttribute()
	if not abilityActive then
		return
	end

	local attrPhase = player:GetAttribute(PHASE_ATTR)
	if attrPhase == nil or (typeof(attrPhase) == "string" and attrPhase == "") then
		if abilityActive then
			onAbilityEnded()
		end
		return
	end
	if typeof(attrPhase) ~= "string" then
		return
	end

	if attrPhase ~= currentPhase then
		onPhaseChanged(attrPhase)
	end
end

local function bindPhaseAttributeSync()
	if phaseAttrConn then
		phaseAttrConn:Disconnect()
		phaseAttrConn = nil
	end
	phaseAttrConn = player:GetAttributeChangedSignal(PHASE_ATTR):Connect(syncPhaseFromAttribute)
end

local function cleanupCharacter(character: Model)
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
		downSupes = loadTrack(downAnim, true),
	}

	local state: CharacterSuperJumpState = {
		character = character,
		humanoid = humanoid,
		tracks = tracks,
		currentTrack = nil,
		heartbeatConn = nil,
	}
	characterStates[character] = state

	state.heartbeatConn = RunService.Heartbeat:Connect(function()
		if abilityActive then
			syncPhaseFromAttribute()
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

function SuperJumpController:TryConsumeSecondTap(): boolean
	if not Features.UseSuperJump then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	if CharacterController and CharacterController.IsAbilityBlocking and CharacterController:IsAbilityBlocking() then
		return false
	end

	if player:GetAttribute(DJ_PHASE_ATTR) then
		return false
	end

	if abilityActive then
		return false
	end

	local now = os.clock()
	local window = SjCfg.DoubleTapWindow or 0.35
	local isSecondTap = lastSpaceBeginAt > 0 and (now - lastSpaceBeginAt) <= window
	lastSpaceBeginAt = now

	if not isSecondTap then
		return false
	end

	if isGrounded(humanoid) then
		return false
	end

	local service = Knit.GetService("SuperJumpService")
	service:RequestStart():andThen(function(ok: boolean, _reason: string?)
		if ok then
			abilityActive = true
			setAbilityBlocking(true)
			ensureAbilityState(character)
			syncPhaseFromAttribute()
			local phase = player:GetAttribute(PHASE_ATTR)
			if typeof(phase) == "string" and phase ~= "" then
				onPhaseChanged(phase)
			end
		end
	end):catch(warn)

	return true
end

function SuperJumpController:KnitInit()
	CharacterController = Knit.GetController("CharacterController")
	if CharacterController and CharacterController.RegisterJumpInterceptor then
		CharacterController:RegisterJumpInterceptor(function()
			return SuperJumpController:TryConsumeSecondTap()
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
				ensureAbilityState(character)
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

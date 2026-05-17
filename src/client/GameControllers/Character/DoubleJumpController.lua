--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DoubleJumpLanding = require(ReplicatedStorage.Shared.Utils.DoubleJumpLanding)
local DebugLog = require(ReplicatedStorage.Shared.Utils.DebugLog)

local AnimRoot = CharacterConfigs.Animations
local Loc = CharacterConfigs.Locomotion
local DjCfg = CharacterConfigs.DoubleJump
local PhaseCfg = DjCfg.Phases
local PoseCfg = DjCfg.SupermanPose
local Features = CharacterConfigs.Features

local PHASE = {
	FlightTransit = "FlightTransit",
	AfterTransition = "AfterTransition",
	LeanUp = "LeanUp",
	LeapDown = "LeapDown",
	DownSupes = "DownSupes",
	CancelFall = "CancelFall",
	CancelLanding = "CancelLanding",
}

local KEY_CODES: { [string]: Enum.KeyCode } = {
	E = Enum.KeyCode.E,
}

local PHASE_ATTR = "DjAbilityPhase"

local PHASE_RANK: { [string]: number } = {
	[PHASE.FlightTransit] = 1,
	[PHASE.AfterTransition] = 2,
	[PHASE.LeanUp] = 3,
	[PHASE.DownSupes] = 4,
	[PHASE.LeapDown] = 5,
	[PHASE.CancelFall] = 10,
	[PHASE.CancelLanding] = 11,
}

local function isPhaseAdvance(fromPhase: string?, toPhase: string): boolean
	if not fromPhase then
		return true
	end
	local fromRank = PHASE_RANK[fromPhase]
	local toRank = PHASE_RANK[toPhase]
	if not fromRank or not toRank then
		return true
	end
	if toRank >= PHASE_RANK[PHASE.CancelFall] then
		return true
	end
	return toRank >= fromRank
end

local DoubleJumpController = Knit.CreateController({ Name = "DoubleJumpController" })

local player = Players.LocalPlayer
local animFolder: Folder? = nil
local actionBound = false
local abilityActive = false
local holdingLocally = false
local currentPhase: string? = nil

type AbilityTracks = {
	flightTransit: AnimationTrack,
	afterTransition: AnimationTrack,
	leanUp: AnimationTrack,
	leapDown: AnimationTrack,
	downSupes: AnimationTrack,
	fall: AnimationTrack,
	landing: AnimationTrack,
}

type CharacterAbilityState = {
	character: Model,
	humanoid: Humanoid,
	tracks: AbilityTracks,
	currentTrack: AnimationTrack?,
	heartbeatConn: RBXScriptConnection?,
	rayParams: RaycastParams,
	cancelFallStartedAt: number?,
	landingPlayed: boolean,
	startCFrame: CFrame,
	flightDirection: Vector3,
	currentPitch: number,
	phaseStartedAt: number,
	downSupesGroundedFrames: number,
	touchdownUprightApplied: boolean,
	leapDownCommitted: boolean,
	movementLocked: boolean,
	savedWalkSpeed: number?,
	savedJumpHeight: number?,
}

local characterStates: { [Model]: CharacterAbilityState } = {}

-- Set false to silence DownSupes debug lines in Studio Output.
local DEBUG_DOWNSUPES = true
local DOWNSUPES_PULSE_SEC = 0.25

type DownSupesDiagState = {
	lastPulseAt: number,
	lastShouldStart: boolean?,
	lastDownPlaying: boolean?,
}

local downSupesDiag: DownSupesDiagState = {
	lastPulseAt = 0,
	lastShouldStart = nil,
	lastDownPlaying = nil,
}

local function resetDownSupesDiag()
	downSupesDiag.lastPulseAt = 0
	downSupesDiag.lastShouldStart = nil
	downSupesDiag.lastDownPlaying = nil
end

local function currentTrackName(state: CharacterAbilityState): string
	local track = state.currentTrack
	if not track then
		return "nil"
	end
	local tracks = state.tracks
	if track == tracks.downSupes then
		return "downSupes"
	end
	if track == tracks.leapDown then
		return "leapDown"
	end
	if track == tracks.leanUp then
		return "leanUp"
	end
	if track == tracks.afterTransition then
		return "afterTransition"
	end
	if track == tracks.flightTransit then
		return "flightTransit"
	end
	return "other"
end

local function downSupesSnapshot(tracks: AbilityTracks): { [string]: any }
	local down = tracks.downSupes
	local leap = tracks.leapDown
	return {
		downPlaying = down.IsPlaying,
		downTime = string.format("%.2f", down.TimePosition),
		downLen = string.format("%.2f", down.Length),
		leapPlaying = leap.IsPlaying,
		leapTime = string.format("%.2f", leap.TimePosition),
	}
end

local function logDownSupes(event: string, reason: string?, fields: { [string]: any }?)
	if not DEBUG_DOWNSUPES then
		return
	end

	local line = "[DJ_DownSupes] " .. event
	if reason and reason ~= "" then
		line ..= " | " .. reason
	end
	if fields then
		for key, value in fields do
			line ..= string.format(" | %s=%s", tostring(key), tostring(value))
		end
	end
	line ..= string.format(" | phase=%s | abilityActive=%s", tostring(currentPhase), tostring(abilityActive))
	warn(line)
end

type CameraAttachState = {
	savedCameraType: Enum.CameraType,
	savedCameraSubject: Instance?,
}

local cameraAttach: CameraAttachState? = nil
local phaseAttrConn: RBXScriptConnection? = nil

local CharacterController: any = nil

local onPhaseChanged: (string) -> ()
local enforceLandingAnim: (CharacterAbilityState) -> ()

local function syncPhaseFromAttribute()
	if not abilityActive then
		return
	end

	local attrPhase = player:GetAttribute(PHASE_ATTR)
	if typeof(attrPhase) ~= "string" or attrPhase == "" then
		return
	end

	if attrPhase == currentPhase then
		if attrPhase == PHASE.LeanUp or attrPhase == PHASE.LeapDown then
			local character = player.Character
			if character then
				local state = characterStates[character]
				if state then
					enforceLandingAnim(state)
				end
			end
		end
		return
	end

	if not isPhaseAdvance(currentPhase, attrPhase) then
		-- #region agent log
		DebugLog.write("DoubleJumpController:syncPhaseFromAttribute", "stale_phase_ignored", {
			fromPhase = currentPhase,
			toPhase = attrPhase,
		}, "B")
		-- #endregion
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local state = characterStates[character]
	if not state then
		return
	end

	-- #region agent log
	DebugLog.write("DoubleJumpController:syncPhaseFromAttribute", "attr_phase_sync", {
		fromPhase = currentPhase,
		toPhase = attrPhase,
		leapDownPlaying = state.tracks.leapDown.IsPlaying,
		downSupesPlaying = state.tracks.downSupes.IsPlaying,
	}, "B")
	-- #endregion

	onPhaseChanged(attrPhase)
end

local function bindPhaseAttributeSync()
	if phaseAttrConn then
		phaseAttrConn:Disconnect()
		phaseAttrConn = nil
	end
	phaseAttrConn = player:GetAttributeChangedSignal(PHASE_ATTR):Connect(syncPhaseFromAttribute)
end

local function isCameraAttachEnabled(): boolean
	local cfg = DjCfg.CameraAttach
	return cfg == nil or cfg.Enabled ~= false
end

local function detachCamera()
	local attach = cameraAttach
	if not attach then
		return
	end

	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = attach.savedCameraType
		if attach.savedCameraSubject then
			cam.CameraSubject = attach.savedCameraSubject
		end
	end

	cameraAttach = nil
end

local function attachCamera(character: Model)
	if not isCameraAttachEnabled() then
		return
	end

	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	detachCamera()

	cameraAttach = {
		savedCameraType = cam.CameraType,
		savedCameraSubject = cam.CameraSubject,
	}

	cam.CameraSubject = humanoid
	cam.CameraType = Enum.CameraType.Attach
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

local function setAbilityBlocking(blocked: boolean)
	if CharacterController and CharacterController.SetAbilityBlocking then
		CharacterController:SetAbilityBlocking(blocked)
	end
end

local function setMovementLocked(state: CharacterAbilityState, locked: boolean)
	local humanoid = state.humanoid
	if locked then
		if not state.movementLocked then
			state.savedWalkSpeed = humanoid.WalkSpeed
			state.savedJumpHeight = humanoid.JumpHeight
			state.movementLocked = true
		end
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		return
	end

	if not state.movementLocked then
		return
	end

	humanoid.WalkSpeed = state.savedWalkSpeed or 16
	humanoid.JumpHeight = state.savedJumpHeight or 7.2
	state.movementLocked = false
	state.savedWalkSpeed = nil
	state.savedJumpHeight = nil
end

local function applyAbilityMovementLock(locked: boolean)
	local character = player.Character
	if not character then
		return
	end
	local state = characterStates[character]
	if state then
		setMovementLocked(state, locked)
	end
end

local function flatUnit(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function getSteerThreshold(): number
	return PhaseCfg.AfterTransition.SteerMoveThreshold or CharacterConfigs.Locomotion.MoveThreshold
end

local function getFlightDirection(humanoid: Humanoid, startCFrame: CFrame): Vector3
	local move = humanoid.MoveDirection
	if move.Magnitude >= getSteerThreshold() then
		return flatUnit(move)
	end
	return flatUnit(startCFrame.LookVector)
end

local function restoreUprightPose(root: BasePart, flightDir: Vector3)
	local flat = flatUnit(flightDir)
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + flat)
	root.AssemblyAngularVelocity = Vector3.zero
end

local function initFlightDirection(state: CharacterAbilityState)
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	state.startCFrame = root.CFrame
	state.flightDirection = flatUnit(state.startCFrame.LookVector)
end

local function cframeWithPitch(position: Vector3, flightDir: Vector3, pitchDeg: number): CFrame
	local flat = flatUnit(flightDir)
	local base = CFrame.lookAt(position, position + flat)
	return base * CFrame.Angles(math.rad(pitchDeg), 0, 0)
end

local function lerpPitch(state: CharacterAbilityState, targetPitch: number, dt: number)
	local alpha = math.min(1, PoseCfg.PitchLerp * dt)
	state.currentPitch = state.currentPitch + (targetPitch - state.currentPitch) * alpha
end

local function applyClientOrientation(state: CharacterAbilityState, phase: string, dt: number)
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	if phase ~= PHASE.FlightTransit and phase ~= PHASE.AfterTransition then
		return
	end

	state.flightDirection = getFlightDirection(state.humanoid, state.startCFrame)

	if phase == PHASE.FlightTransit then
		local elapsed = os.clock() - state.phaseStartedAt
		local duration = PhaseCfg.FlightTransit.Duration
		local progress = if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 1
		local targetPitch = PoseCfg.TransitStartPitch
			+ (PoseCfg.TransitEndPitch - PoseCfg.TransitStartPitch) * progress
		local alpha = math.min(1, PoseCfg.TransitPitchLerp * dt)
		state.currentPitch = state.currentPitch + (targetPitch - state.currentPitch) * alpha
	else
		lerpPitch(state, PoseCfg.FlightPitch, dt)
	end

	root.CFrame = cframeWithPitch(root.Position, state.flightDirection, state.currentPitch)
end

local function applyClientMovement(state: CharacterAbilityState, phase: string)
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local vel: Vector3

	if phase == PHASE.FlightTransit or phase == PHASE.AfterTransition then
		state.flightDirection = getFlightDirection(state.humanoid, state.startCFrame)
	end

	if phase == PHASE.FlightTransit then
		local nudge = PhaseCfg.FlightTransit.ForwardNudgeSpeed or 0
		vel = if nudge > 0 then state.flightDirection * nudge else Vector3.zero
	elseif phase == PHASE.AfterTransition then
		local cfg = PhaseCfg.AfterTransition
		vel = state.flightDirection * cfg.ForwardSpeed + Vector3.new(0, cfg.RiseSpeed, 0)
	else
		return
	end

	root.AssemblyLinearVelocity = vel
end

local function stopDownSupesHard(tracks: AbilityTracks, reason: string?)
	if tracks.downSupes.IsPlaying then
		logDownSupes("stop_downsupes", reason or "stopDownSupesHard", downSupesSnapshot(tracks))
	end
	pcall(function()
		if tracks.downSupes.IsPlaying then
			tracks.downSupes:AdjustWeight(0)
		end
		tracks.downSupes:Stop(0)
	end)
end

local function stopAbilityLandingTracks(state: CharacterAbilityState)
	pcall(function()
		state.tracks.leapDown:Stop(0)
		state.tracks.downSupes:Stop(0)
	end)
end

local function stopAllTracks(state: CharacterAbilityState)
	local tracks = state.tracks
	stopAbilityLandingTracks(state)
	pcall(function()
		tracks.flightTransit:Stop(Loc.FadeTime)
		tracks.afterTransition:Stop(Loc.FadeTime)
		tracks.leanUp:Stop(Loc.FadeTime)
		tracks.fall:Stop(Loc.FadeTime)
		tracks.landing:Stop(Loc.FadeTime)
	end)
	state.currentTrack = nil
end

local function stopCurrentTrack(state: CharacterAbilityState, reason: string?)
	if state.currentTrack then
		if state.currentTrack == state.tracks.downSupes then
			logDownSupes("stop_current_track", reason or "stopCurrentTrack", downSupesSnapshot(state.tracks))
		end
		pcall(function()
			state.currentTrack:Stop(Loc.FadeTime)
		end)
		state.currentTrack = nil
	end
end

local function getLandingFadeTime(): number
	return DjCfg.LandingFadeTime or Loc.FadeTime
end

local function applyTouchdownUprightOnce(state: CharacterAbilityState)
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	restoreUprightPose(root, state.flightDirection)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	state.humanoid.PlatformStand = false
end

local function stopLeanUpHard(tracks: AbilityTracks)
	pcall(function()
		if tracks.leanUp.IsPlaying then
			tracks.leanUp:Stop(0)
		end
	end)
end

local function playLeanUpHold(state: CharacterAbilityState, reason: string?)
	if state.leapDownCommitted then
		return
	end
	local tracks = state.tracks
	if tracks.leanUp.IsPlaying and state.currentTrack == tracks.leanUp then
		return
	end
	stopCurrentTrack(state, reason or "before_play_leanup")
	state.currentTrack = tracks.leanUp
	tracks.leanUp:Play(Loc.FadeTime)
end

local function playDownSupesDescent(state: CharacterAbilityState, reason: string?)
	local tracks = state.tracks
	local snap = downSupesSnapshot(tracks)
	if tracks.downSupes.IsPlaying and state.currentTrack == tracks.downSupes then
		logDownSupes("skip_play_downsupes", reason or "playDownSupesDescent", {
			downTime = snap.downTime,
			currentTrack = currentTrackName(state),
		})
		return
	end
	logDownSupes("play_downsupes", reason or "playDownSupesDescent", {
		wasPlaying = snap.downPlaying,
		wasTime = snap.downTime,
		currentTrack = currentTrackName(state),
	})
	stopCurrentTrack(state, "before_play_downsupes")
	local landingFade = getLandingFadeTime()
	state.currentTrack = tracks.downSupes
	tracks.downSupes:Play(landingFade)
end

local function playLeapDownLanding(state: CharacterAbilityState, reason: string?)
	local tracks = state.tracks
	if state.leapDownCommitted then
		if tracks.downSupes.IsPlaying then
			stopDownSupesHard(tracks, reason or "playLeapDownLanding_cleanup")
		end
		if tracks.leanUp.IsPlaying then
			stopLeanUpHard(tracks)
		end
		return
	end
	local snap = downSupesSnapshot(tracks)
	logDownSupes("play_leapdown", reason or "playLeapDownLanding", snap)
	stopDownSupesHard(tracks, reason or "playLeapDownLanding")
	stopLeanUpHard(tracks)
	local landingFade = getLandingFadeTime()
	state.currentTrack = tracks.leapDown
	tracks.leapDown:Play(landingFade)
	state.leapDownCommitted = true
	applyTouchdownUprightOnce(state)
end

enforceLandingAnim = function(state: CharacterAbilityState)
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local landingCfg = PhaseCfg.DownSupes
	local grounded = DoubleJumpLanding.isGroundedForLanding(state.humanoid, root, state.rayParams, landingCfg)

	if currentPhase == PHASE.LeanUp or currentPhase == PHASE.DownSupes then
		playLeanUpHold(state, "enforce_leanup")
	elseif currentPhase == PHASE.LeapDown then
		if state.tracks.downSupes.IsPlaying then
			stopDownSupesHard(state.tracks, "leapdown_phase")
		end
		if state.tracks.leanUp.IsPlaying then
			stopLeanUpHard(state.tracks)
		end
		if grounded then
			if not state.touchdownUprightApplied then
				state.touchdownUprightApplied = true
				applyTouchdownUprightOnce(state)
			end
		else
			state.touchdownUprightApplied = false
		end
	end
end

local function tickLandingWatchdog(state: CharacterAbilityState)
	if not abilityActive or not currentPhase then
		return
	end

	enforceLandingAnim(state)
end

local function playTrack(state: CharacterAbilityState, track: AnimationTrack, fadeTime: number?)
	local fade = fadeTime or Loc.FadeTime
	stopCurrentTrack(state)
	state.currentTrack = track
	track:Play(fade)
end

local function playPhaseAnim(state: CharacterAbilityState, phase: string)
	local tracks = state.tracks
	if phase == PHASE.FlightTransit then
		playTrack(state, tracks.flightTransit)
	elseif phase == PHASE.AfterTransition then
		playTrack(state, tracks.afterTransition)
	elseif phase == PHASE.LeanUp or phase == PHASE.DownSupes then
		state.touchdownUprightApplied = false
		state.leapDownCommitted = false
		state.downSupesGroundedFrames = 0
		state.humanoid.PlatformStand = false
		playLeanUpHold(state, "playPhaseAnim")
	elseif phase == PHASE.LeapDown then
		state.touchdownUprightApplied = false
		state.humanoid.PlatformStand = false
		playLeapDownLanding(state, "playPhaseAnim")
	elseif phase == PHASE.CancelFall then
		state.cancelFallStartedAt = os.clock()
		state.landingPlayed = false
		playTrack(state, tracks.fall)
	elseif phase == PHASE.CancelLanding then
		state.landingPlayed = true
		if state.currentTrack == tracks.fall then
			pcall(function()
				tracks.fall:Stop(Loc.FadeTime)
			end)
		end
		playTrack(state, tracks.landing)
	end
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

local function stabilizeCharacter(character: Model, flightDir: Vector3?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if flightDir then
			restoreUprightPose(root, flightDir)
		end
	end
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function onAbilityEnded()
	local character = player.Character
	local grounded = false
	if character then
		local state = characterStates[character]
		if state then
			grounded = DoubleJumpLanding.isGrounded(state.humanoid)
		end
	end
	-- #region agent log
	DebugLog.write("DoubleJumpController:onAbilityEnded", "ability_ended_client", {
		phase = currentPhase,
		grounded = grounded,
	}, "B")
	-- #endregion
	applyAbilityMovementLock(false)
	detachCamera()
	abilityActive = false
	holdingLocally = false
	currentPhase = nil
	resetDownSupesDiag()

	if character then
		local state = characterStates[character]
		if state then
			stopAbilityLandingTracks(state)
			stabilizeCharacter(character, state.flightDirection)
			stopAllTracks(state)
		end
	end

	setAbilityBlocking(false)

	if character then
		-- Keep ability tracks loaded; only stop playback (do not nil characterStates).
		if characterStates[character] then
			characterStates[character].currentTrack = nil
			characterStates[character].cancelFallStartedAt = nil
			characterStates[character].landingPlayed = false
			characterStates[character].leapDownCommitted = false
		end
	end
end

onPhaseChanged = function(phase: string)
	currentPhase = phase

	local character = player.Character
	if not character then
		return
	end

	local state = characterStates[character]
	if not state then
		return
	end

	state.phaseStartedAt = os.clock()

	if phase == PHASE.FlightTransit then
		state.currentPitch = PoseCfg.TransitStartPitch
	elseif phase == PHASE.LeanUp or phase == PHASE.DownSupes or phase == PHASE.LeapDown or phase == PHASE.CancelFall then
		state.currentPitch = PoseCfg.UprightPitch
		state.flightDirection = flatUnit(state.flightDirection)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			restoreUprightPose(root, state.flightDirection)
		end
	end

	local tracks = state.tracks
	-- #region agent log
	DebugLog.write("DoubleJumpController:onPhaseChanged", "client_phase_anim", {
		phase = phase,
		leapDownPlaying = tracks.leapDown.IsPlaying,
		downSupesPlaying = tracks.downSupes.IsPlaying,
		afterTransitionPlaying = tracks.afterTransition.IsPlaying,
		grounded = DoubleJumpLanding.isGrounded(state.humanoid),
	}, "B")
	-- #endregion

	playPhaseAnim(state, phase)

	-- #region agent log
	DebugLog.write("DoubleJumpController:onPhaseChanged", "after_play_phase_anim", {
		phase = phase,
		leapDownPlaying = tracks.leapDown.IsPlaying,
		downSupesPlaying = tracks.downSupes.IsPlaying,
		currentTrack = if state.currentTrack == tracks.downSupes
			then "downSupes"
			elseif state.currentTrack == tracks.leapDown
			then "leapDown"
			elseif state.currentTrack == tracks.leanUp
			then "leanUp"
			else "other"
	}, "B")
	-- #endregion
end

local function setupCharacter(character: Model)
	cleanupCharacter(character)

	if not Features.UseDoubleJump then
		return
	end

	local folder = getAnimFolder()
	if not folder then
		return
	end

	local djAnims = DjCfg.Anims
	local flightAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.FlightTransit)
	local afterAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.AfterTransition)
	local leanAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.LeanUp)
	local leapAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.LeapDown)
	local downAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.DownSupes)
	local fallAnim = getAnimationInFolder(folder, DjCfg.CancelAnims.Folder, DjCfg.CancelAnims.Fall)
	local landingAnim = getAnimationInFolder(folder, DjCfg.CancelAnims.Folder, DjCfg.CancelAnims.Landing)

	if not flightAnim or not afterAnim or not leanAnim or not leapAnim or not downAnim or not fallAnim or not landingAnim then
		return
	end

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function loadTrack(anim: Animation, looped: boolean, priority: Enum.AnimationPriority?): AnimationTrack
		local track = animator:LoadAnimation(anim)
		track.Looped = looped
		track.Priority = priority or Enum.AnimationPriority.Action2
		return track
	end

	local tracks: AbilityTracks = {
		flightTransit = loadTrack(flightAnim, false),
		afterTransition = loadTrack(afterAnim, true),
		leanUp = loadTrack(leanAnim, true),
		leapDown = loadTrack(leapAnim, false, Enum.AnimationPriority.Action3),
		downSupes = loadTrack(downAnim, false, Enum.AnimationPriority.Action2),
		fall = loadTrack(fallAnim, true),
		landing = loadTrack(landingAnim, false),
	}

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local startCFrame = if root then root.CFrame else CFrame.identity

	local state: CharacterAbilityState = {
		character = character,
		humanoid = humanoid,
		tracks = tracks,
		currentTrack = nil,
		heartbeatConn = nil,
		rayParams = rayParams,
		cancelFallStartedAt = nil,
		landingPlayed = false,
		startCFrame = startCFrame,
		flightDirection = flatUnit(startCFrame.LookVector),
		currentPitch = PoseCfg.TransitStartPitch,
		phaseStartedAt = os.clock(),
		downSupesGroundedFrames = 0,
		touchdownUprightApplied = false,
		leapDownCommitted = false,
		movementLocked = false,
		savedWalkSpeed = nil,
		savedJumpHeight = nil,
	}
	characterStates[character] = state

	tracks.downSupes.Stopped:Connect(function()
		logDownSupes("track_stopped", "AnimationTrack.Stopped", {
			time = string.format("%.2f", tracks.downSupes.TimePosition),
			currentTrack = currentTrackName(state),
		})
	end)

	state.heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if abilityActive and currentPhase then
			setMovementLocked(state, true)
			syncPhaseFromAttribute()
			tickLandingWatchdog(state)

			local orientPhase = currentPhase
			if orientPhase == PHASE.FlightTransit or orientPhase == PHASE.AfterTransition then
				applyClientOrientation(state, orientPhase, dt)
				applyClientMovement(state, orientPhase)
			end
		end

		if not abilityActive or currentPhase ~= PHASE.CancelFall then
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart or state.landingPlayed then
			return
		end

		local started = state.cancelFallStartedAt
		if not started then
			return
		end

		if os.clock() - started < DjCfg.Cancel.MinFallTime then
			return
		end

		local hit = workspace:Raycast(
			rootPart.Position,
			Vector3.new(0, -DjCfg.Cancel.LandingRayDistance, 0),
			state.rayParams
		)
		if hit and rootPart.AssemblyLinearVelocity.Y < 0 then
			-- Server drives CancelLanding phase; client only mirrors if needed early
		end
	end)

	character.Destroying:Once(function()
		cleanupCharacter(character)
		if abilityActive then
			onAbilityEnded()
		end
	end)
end

local function getDoubleJumpService()
	return Knit.GetService("DoubleJumpService")
end

local function onDoubleJumpAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if not Features.UseDoubleJump then
		return Enum.ContextActionResult.Pass
	end

	local service = getDoubleJumpService()

	if inputState == Enum.UserInputState.Begin then
		if abilityActive then
			service:SetHolding(true)
			holdingLocally = true
			return Enum.ContextActionResult.Sink
		end

		holdingLocally = true
		service:RequestStart():andThen(function(ok: boolean, _reason: string?)
			if ok then
				abilityActive = true
				service:SetHolding(true)

				local character = player.Character
				if character and not characterStates[character] then
					setupCharacter(character)
				end

				if character then
					local abilityState = characterStates[character]
					if abilityState then
						initFlightDirection(abilityState)
						abilityState.currentPitch = PoseCfg.TransitStartPitch
						abilityState.phaseStartedAt = os.clock()
					end
				end

				setAbilityBlocking(true)
				applyAbilityMovementLock(true)
				attachCamera(character :: Model)
				task.defer(syncPhaseFromAttribute)

				if currentPhase then
					local state = characterStates[character :: Model]
					if state then
						playPhaseAnim(state, currentPhase)
					end
				end
			else
				holdingLocally = false
			end
		end):catch(warn)

		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End then
		holdingLocally = false
		if abilityActive then
			service:SetHolding(false)
		end
		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Pass
end

local function bindAction()
	if actionBound or not Features.UseDoubleJump then
		return
	end

	local keyCode = KEY_CODES[DjCfg.Key]
	if not keyCode then
		warn("[iseesupes] Unknown DoubleJump key:", DjCfg.Key)
		return
	end

	actionBound = true
	ContextActionService:BindAction(DjCfg.ActionName, onDoubleJumpAction, false, keyCode)
end

function DoubleJumpController:KnitStart()
	CharacterController = Knit.GetController("CharacterController")

	local folder = ReplicatedStorage:WaitForChild(AnimRoot.FolderName, 30)
	if folder and folder:IsA("Folder") then
		animFolder = folder
	end

	bindAction()
	bindPhaseAttributeSync()

	local DoubleJumpService = getDoubleJumpService()

	DoubleJumpService.PhaseChanged:Connect(function(phase: string)
		if not abilityActive and phase == PHASE.FlightTransit then
			abilityActive = true
			local character = player.Character
			if character and not characterStates[character] then
				setupCharacter(character)
			end
			if character then
				local abilityState = characterStates[character]
				if abilityState then
					initFlightDirection(abilityState)
				end
			end
			setAbilityBlocking(true)
			applyAbilityMovementLock(true)
			attachCamera(character)
			onPhaseChanged(phase)
		end
	end)

	DoubleJumpService.AbilityEnded:Connect(onAbilityEnded)

	DoubleJumpService.Rejected:Connect(function(_reason: string) end)

	player.CharacterAdded:Connect(function(character)
		if abilityActive then
			onAbilityEnded()
		end
		setupCharacter(character)
	end)

	if player.Character then
		setupCharacter(player.Character)
	end

	print("[iseesupes] DoubleJumpController ready.")
end

return DoubleJumpController

--!strict

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DoubleJumpLanding = require(ReplicatedStorage.Shared.Utils.DoubleJumpLanding)
local DebugLog = require(ReplicatedStorage.Shared.Utils.DebugLog)
local LevelDesignTuning = require(ReplicatedStorage.Shared.Utils.LevelDesignTuning)

local AnimRoot = CharacterConfigs.Animations
local Loc = CharacterConfigs.Locomotion
local DjCfg = CharacterConfigs.DoubleJump
local Features = CharacterConfigs.Features

local cachedTuning: LevelDesignTuning.DoubleJumpTuning? = nil
local tuningAttrConns: { RBXScriptConnection } = {}

local function refreshTuning()
	cachedTuning = LevelDesignTuning.getDoubleJump(Players.LocalPlayer)
end

local function getTuning(): LevelDesignTuning.DoubleJumpTuning
	if not cachedTuning then
		refreshTuning()
	end
	return cachedTuning :: LevelDesignTuning.DoubleJumpTuning
end

local function bindTuningAttrListeners(character: Model?)
	for _, conn in tuningAttrConns do
		conn:Disconnect()
	end
	table.clear(tuningAttrConns)

	local function onAttr(_name: string)
		refreshTuning()
	end
	table.insert(tuningAttrConns, Players.LocalPlayer.AttributeChanged:Connect(onAttr))
	if character then
		table.insert(tuningAttrConns, character.AttributeChanged:Connect(onAttr))
	end
	refreshTuning()
end

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
	-- Cancel fall uses the same LeapDown landing phase as a full ability completion.
	if toPhase == PHASE.LeapDown and (fromPhase == PHASE.CancelFall or fromPhase == PHASE.CancelLanding) then
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
	cancelApproachStarted: boolean,
	animPreloaded: boolean,
	jumpLocked: boolean,
	savedJumpHeight: number?,
	locomotionReleasedAfterLanding: boolean,
	landingGroundedAt: number?,
	leanAnimSubphase: string?, -- "glide" | "descent" while in LeanUp
}

local characterStates: { [Model]: CharacterAbilityState } = {}

local DEBUG_DOWNSUPES = DjCfg.Debug == true

local globalDjAnimsPreloaded = false
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

local phaseAttrConn: RBXScriptConnection? = nil

local CharacterController: any = nil

local onPhaseChanged: (string) -> ()
local onAbilityEnded: () -> ()
local enforceLandingAnim: (CharacterAbilityState) -> ()
local setupCharacter: (Model) -> ()

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

	if attrPhase == currentPhase then
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

local function validateAnimationId(anim: Animation, label: string): boolean
	if anim.AnimationId == "" then
		warn("[iseesupes] Animation has no AnimationId:", label)
		return false
	end
	return true
end

local function collectDoubleJumpAnimations(folder: Folder): { Animation }?
	local djAnims = DjCfg.Anims
	local flightAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.FlightTransit)
	local afterAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.AfterTransition)
	local leanAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.LeanUp)
	local leapAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.LeapDown)
	local downAnim = getAnimationInFolder(folder, DjCfg.AnimFolder, djAnims.DownSupes)
	local fallAnim = getAnimationInFolder(folder, DjCfg.CancelAnims.Folder, DjCfg.CancelAnims.Fall)
	local landingAnim = getAnimationInFolder(folder, DjCfg.CancelAnims.Folder, DjCfg.CancelAnims.Landing)

	if not flightAnim or not afterAnim or not leanAnim or not leapAnim or not downAnim or not fallAnim or not landingAnim then
		warn(
			"[iseesupes] DoubleJump setup failed: missing animations under",
			AnimRoot.FolderName,
			"/",
			DjCfg.AnimFolder,
			"or",
			DjCfg.CancelAnims.Folder
		)
		return nil
	end

	local labels = {
		{ flightAnim, "FlightTransit" },
		{ afterAnim, "AfterTransition" },
		{ leanAnim, "LeanUp" },
		{ leapAnim, "LeapDown" },
		{ downAnim, "DownSupes" },
		{ fallAnim, "CancelFall" },
		{ landingAnim, "CancelLanding" },
	}
	for _, entry in labels do
		if not validateAnimationId(entry[1], entry[2]) then
			return nil
		end
	end

	return {
		flightAnim,
		afterAnim,
		leanAnim,
		leapAnim,
		downAnim,
		fallAnim,
		landingAnim,
	}
end

local function preloadDoubleJumpAnimations(anims: { Animation })
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(anims)
	end)
	if not ok then
		warn("[iseesupes] DoubleJump animation preload failed:", err)
	end
end

local function preloadDoubleJumpFromFolder(folder: Folder): boolean
	local anims = collectDoubleJumpAnimations(folder)
	if not anims then
		return false
	end
	preloadDoubleJumpAnimations(anims)
	globalDjAnimsPreloaded = true
	return true
end

local abilityBlockedAt: number? = nil
local ABILITY_BLOCK_WATCHDOG_SEC = 0.5

local function setAbilityBlocking(blocked: boolean)
	if blocked then
		abilityBlockedAt = os.clock()
	else
		abilityBlockedAt = nil
	end
	if CharacterController and CharacterController.SetAbilityBlocking then
		CharacterController:SetAbilityBlocking(blocked)
	end
end

local function setAbilityJumpLock(state: CharacterAbilityState, locked: boolean)
	local humanoid = state.humanoid
	if locked then
		if not state.jumpLocked then
			state.savedJumpHeight = humanoid.JumpHeight
			state.jumpLocked = true
		end
		humanoid.JumpHeight = 0
		return
	end

	if not state.jumpLocked then
		return
	end

	humanoid.JumpHeight = state.savedJumpHeight or 7.2
	state.jumpLocked = false
	state.savedJumpHeight = nil
end

local function applyAbilityJumpLock(locked: boolean)
	local character = player.Character
	if not character then
		return
	end
	local state = characterStates[character]
	if state then
		setAbilityJumpLock(state, locked)
	end
end

local function flatUnit(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function flatDistance(from: Vector3, to: Vector3): number
	local a = Vector3.new(from.X, 0, from.Z)
	local b = Vector3.new(to.X, 0, to.Z)
	return (b - a).Magnitude
end

local function getSteerThreshold(): number
	local tuning = getTuning()
	local steerCfg = tuning.Steering
	local phaseCfg = tuning.Phases
	return steerCfg.SteerMoveThreshold
		or phaseCfg.AfterTransition.SteerMoveThreshold
		or CharacterConfigs.Locomotion.MoveThreshold
end

local function getCameraRelativeSteerInput(state: CharacterAbilityState): Vector3
	local move = state.humanoid.MoveDirection
	if move.Magnitude >= getSteerThreshold() then
		return flatUnit(move)
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end

	local forward = 0
	local right = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		forward += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		forward -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		right -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		right += 1
	end

	if forward == 0 and right == 0 then
		return Vector3.zero
	end

	local look = camera.CFrame.LookVector
	local rightVector = camera.CFrame.RightVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatRight = Vector3.new(rightVector.X, 0, rightVector.Z)
	if flatLook.Magnitude < 0.01 then
		return Vector3.zero
	end
	flatLook = flatLook.Unit
	if flatRight.Magnitude > 0.01 then
		flatRight = flatRight.Unit
	else
		flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)
	end

	return flatUnit(flatLook * forward + flatRight * right)
end

local function publishSteerInput(state: CharacterAbilityState)
	if not abilityActive or not holdingLocally then
		return
	end

	local steer = getCameraRelativeSteerInput(state)
	pcall(function()
		if steer.Magnitude >= getSteerThreshold() then
			state.humanoid:Move(steer, false)
		end
	end)

	pcall(function()
		Knit.GetService("DoubleJumpService"):UpdateSteerInput(steer)
	end)
end

local function applySteerToFlightDirection(state: CharacterAbilityState, dt: number)
	local steerCfg = getTuning().Steering
	if steerCfg.Enabled == false then
		return
	end

	local steer = getCameraRelativeSteerInput(state)
	local target = if steer.Magnitude >= getSteerThreshold() then steer else state.flightDirection
	local alpha = math.min(1, (steerCfg.DirectionLerp or 10) * dt)
	state.flightDirection = flatUnit(state.flightDirection:Lerp(target, alpha))
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
	local alpha = math.min(1, getTuning().SupermanPose.PitchLerp * dt)
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

	applySteerToFlightDirection(state, dt)

	local poseCfg = getTuning().SupermanPose
	if phase == PHASE.FlightTransit then
		local elapsed = os.clock() - state.phaseStartedAt
		local duration = getTuning().Phases.FlightTransit.Duration
		local progress = if duration > 0 then math.clamp(elapsed / duration, 0, 1) else 1
		local targetPitch = poseCfg.TransitStartPitch
			+ (poseCfg.TransitEndPitch - poseCfg.TransitStartPitch) * progress
		local alpha = math.min(1, poseCfg.TransitPitchLerp * dt)
		state.currentPitch = state.currentPitch + (targetPitch - state.currentPitch) * alpha
	else
		lerpPitch(state, poseCfg.FlightPitch, dt)
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
		applySteerToFlightDirection(state, 1 / 60)
	end

	local phaseCfg = getTuning().Phases
	if phase == PHASE.FlightTransit then
		local nudge = phaseCfg.FlightTransit.ForwardNudgeSpeed or 0
		vel = if nudge > 0 then state.flightDirection * nudge else Vector3.zero
	elseif phase == PHASE.AfterTransition then
		local cfg = phaseCfg.AfterTransition
		vel = state.flightDirection * cfg.ForwardSpeed + Vector3.new(0, cfg.RiseSpeed, 0)
	else
		return
	end

	root.AssemblyLinearVelocity = vel
end

local function getPhaseFadeTime(): number
	local tuning = getTuning()
	local fromTuning = (tuning :: any).PhaseFadeTime
	if typeof(fromTuning) == "number" and fromTuning > 0 then
		return fromTuning
	end
	return DjCfg.PhaseFadeTime or Loc.FadeTime
end

local function fadeOutTrack(track: AnimationTrack, fade: number, state: CharacterAbilityState?)
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

local function crossfadeToTrack(state: CharacterAbilityState, track: AnimationTrack, fadeTime: number?)
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

local function stopDownSupesHard(tracks: AbilityTracks, reason: string?)
	if tracks.downSupes.IsPlaying then
		logDownSupes("stop_downsupes", reason or "stopDownSupesHard", downSupesSnapshot(tracks))
	end
	fadeOutTrack(tracks.downSupes, getPhaseFadeTime())
end

local function stopAbilityLandingTracks(state: CharacterAbilityState, fadeTime: number?)
	local fade = fadeTime or Loc.FadeTime
	pcall(function()
		state.tracks.leapDown:Stop(fade)
		state.tracks.downSupes:Stop(fade)
		state.tracks.fall:Stop(fade)
		state.tracks.landing:Stop(fade)
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

local function getLandingFadeTime(): number
	return getTuning().LandingFadeTime or Loc.FadeTime
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
	fadeOutTrack(tracks.leanUp, getPhaseFadeTime())
end

local function playLeanUpHold(state: CharacterAbilityState, _reason: string?)
	if state.leapDownCommitted then
		return
	end
	crossfadeToTrack(state, state.tracks.leanUp, getPhaseFadeTime())
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
	crossfadeToTrack(state, tracks.downSupes, getPhaseFadeTime())
end

--- Mirrors server LeanUp forward vs descent split (DoubleJumpService LeanUp tick).
local function isLeanUpInDescent(state: CharacterAbilityState): boolean
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local leanCfg = getTuning().Phases.LeanUp
	local dist = flatDistance(state.startCFrame.Position, root.Position)
	local phaseElapsed = os.clock() - state.phaseStartedAt
	local maxPhaseTime = LevelDesignTuning.getLeanPhaseMaxDuration(
		leanCfg.ForwardSpeed,
		leanCfg.ForwardDistance,
		leanCfg.MaxDuration,
		dist
	)
	return dist >= leanCfg.ForwardDistance or phaseElapsed >= maxPhaseTime
end

local function updateLeanUpAnimSubphase(state: CharacterAbilityState)
	if currentPhase ~= PHASE.LeanUp and currentPhase ~= PHASE.DownSupes then
		return
	end
	if state.leapDownCommitted then
		return
	end

	local want = if isLeanUpInDescent(state) then "descent" else "glide"
	if state.leanAnimSubphase == want then
		return
	end
	state.leanAnimSubphase = want
	if want == "descent" then
		playDownSupesDescent(state, "lean_subphase_descent")
	else
		playLeanUpHold(state, "lean_subphase_glide")
	end
end

local function playLeapDownLanding(state: CharacterAbilityState, reason: string?)
	if state.leapDownCommitted then
		return
	end
	state.leapDownCommitted = true
	state.leanAnimSubphase = nil

	local tracks = state.tracks
	local snap = downSupesSnapshot(tracks)
	logDownSupes("play_leapdown", reason or "playLeapDownLanding", snap)
	local landingFade = getLandingFadeTime()
	crossfadeToTrack(state, tracks.leapDown, landingFade)
end

local function releaseLandingLocomotion(state: CharacterAbilityState)
	if state.locomotionReleasedAfterLanding then
		return
	end
	state.locomotionReleasedAfterLanding = true

	setAbilityBlocking(false)

	local landingFade = getLandingFadeTime()
	local tracks = state.tracks
	if tracks.leapDown.IsPlaying then
		pcall(function()
			tracks.leapDown:AdjustWeight(0.35, landingFade)
			task.delay(landingFade, function()
				if tracks.leapDown.IsPlaying then
					tracks.leapDown:Stop(0.08)
				end
			end)
		end)
	end
end

enforceLandingAnim = function(state: CharacterAbilityState)
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local landingCfg = getTuning().Phases.DownSupes
	local grounded = DoubleJumpLanding.isGroundedForLanding(state.humanoid, root, state.rayParams, landingCfg)

	if currentPhase == PHASE.LeanUp or currentPhase == PHASE.DownSupes then
		if grounded and not state.leapDownCommitted then
			playLeapDownLanding(state, "enforce_leanup_grounded")
		else
			updateLeanUpAnimSubphase(state)
		end
	elseif
		currentPhase == PHASE.LeapDown
		or currentPhase == PHASE.CancelLanding
		or (currentPhase == PHASE.CancelFall and state.leapDownCommitted)
	then
		if state.tracks.fall.IsPlaying then
			pcall(function()
				state.tracks.fall:Stop(Loc.FadeTime)
			end)
		end
		if grounded then
			if not state.touchdownUprightApplied then
				state.touchdownUprightApplied = true
				applyTouchdownUprightOnce(state)
			end
			state.humanoid.PlatformStand = false
			if not state.landingGroundedAt then
				state.landingGroundedAt = os.clock()
			end
		else
			state.touchdownUprightApplied = false
			state.landingGroundedAt = nil
		end
	end
end

local function enforceCancelApproachLanding(state: CharacterAbilityState)
	if not abilityActive then
		return
	end
	if currentPhase ~= PHASE.CancelFall and currentPhase ~= PHASE.CancelLanding then
		return
	end
	if state.cancelApproachStarted then
		return
	end
	if state.leapDownCommitted and state.tracks.leapDown.IsPlaying then
		return
	end

	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local tuning = getTuning()
	local cancelCfg = tuning.Cancel
	local landingCfg = tuning.Phases.DownSupes
	local started = state.cancelFallStartedAt or state.phaseStartedAt
	local elapsed = os.clock() - started
	local hit = DoubleJumpLanding.raycastDownFromRoot(
		root,
		cancelCfg.LandingRayLength or 250,
		state.rayParams
	)

	if
		not DoubleJumpLanding.shouldStartCancelLanding(
			state.humanoid,
			root,
			hit,
			state.rayParams,
			landingCfg,
			cancelCfg,
			elapsed
		)
	then
		return
	end

	state.cancelApproachStarted = true
	state.humanoid.PlatformStand = false

	if state.tracks.fall.IsPlaying then
		pcall(function()
			state.tracks.fall:Stop(Loc.FadeTime)
		end)
	end

	if not state.leapDownCommitted then
		playLeapDownLanding(state, "cancel_approach")
	end
end

local function tickLandingLocomotionRelease(state: CharacterAbilityState)
	if state.locomotionReleasedAfterLanding or not state.landingGroundedAt then
		return
	end
	if currentPhase ~= PHASE.LeapDown and currentPhase ~= PHASE.CancelLanding then
		return
	end

	local landingCfg = getTuning().Phases.DownSupes
	local landingLock = landingCfg.LandingLockDuration or 0.2
	if os.clock() - (state.landingGroundedAt :: number) >= landingLock then
		releaseLandingLocomotion(state)
	end
end

local function tickLandingAnimFailsafe(state: CharacterAbilityState)
	if currentPhase ~= PHASE.LeapDown and currentPhase ~= PHASE.CancelLanding then
		return
	end

	local elapsed = os.clock() - state.phaseStartedAt
	local landingCfg = getTuning().Phases.DownSupes
	local maxLand = (landingCfg.MaxDuration or 2.5) + 0.75

	if elapsed < maxLand then
		return
	end

	stopLeanUpHard(state.tracks)
	stopDownSupesHard(state.tracks, "landing_failsafe")
	pcall(function()
		if state.tracks.leapDown.IsPlaying then
			state.tracks.leapDown:Stop(0.1)
		end
	end)
	state.leapDownCommitted = false
	releaseLandingLocomotion(state)

	if elapsed > maxLand + 1.5 and abilityActive then
		onAbilityEnded()
	end
end

local function tickLandingWatchdog(state: CharacterAbilityState)
	if not abilityActive or not currentPhase then
		return
	end

	enforceLandingAnim(state)
	enforceCancelApproachLanding(state)
	tickLandingLocomotionRelease(state)
	tickLandingAnimFailsafe(state)
end

local function playTrack(state: CharacterAbilityState, track: AnimationTrack, fadeTime: number?)
	crossfadeToTrack(state, track, fadeTime or getPhaseFadeTime())
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
		state.leanAnimSubphase = nil
		state.downSupesGroundedFrames = 0
		state.humanoid.PlatformStand = false
		playLeanUpHold(state, "playPhaseAnim")
		updateLeanUpAnimSubphase(state)
	elseif phase == PHASE.CancelFall then
		state.cancelFallStartedAt = os.clock()
		state.landingPlayed = false
		state.cancelApproachStarted = false
		state.leapDownCommitted = false
		state.touchdownUprightApplied = false
		state.humanoid.PlatformStand = false
		playTrack(state, tracks.fall)
		enforceCancelApproachLanding(state)
	elseif phase == PHASE.LeapDown or phase == PHASE.CancelLanding then
		if phase == PHASE.CancelLanding then
			state.landingPlayed = true
			state.cancelApproachStarted = true
		end
		state.touchdownUprightApplied = false
		state.locomotionReleasedAfterLanding = false
		state.landingGroundedAt = nil
		state.humanoid.PlatformStand = false
		if state.tracks.fall.IsPlaying then
			pcall(function()
				state.tracks.fall:Stop(Loc.FadeTime)
			end)
		end
		if not state.leapDownCommitted then
			playLeapDownLanding(state, "playPhaseAnim")
		end
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

local function hardStopAllAbilityTracks(state: CharacterAbilityState)
	for _, track in pairs(state.tracks) do
		pcall(function()
			if track.IsPlaying then
				track:Stop(0.05)
			end
		end)
	end
	state.currentTrack = nil
end

onAbilityEnded = function()
	local character = player.Character

	-- Idempotent path: even if called twice (PHASE_ATTR cleared + AbilityEnded signal),
	-- always run the cleanup so locomotion / jump / animations can never be left locked.
	DebugLog.write("DoubleJumpController:onAbilityEnded", "ability_ended_client", {
		phase = currentPhase,
		hadCharacter = character ~= nil,
	}, "B")

	applyAbilityJumpLock(false)
	abilityActive = false
	holdingLocally = false
	currentPhase = nil
	resetDownSupesDiag()
	setAbilityBlocking(false)

	if character then
		local state = characterStates[character]
		if state then
			pcall(function()
				stabilizeCharacter(character, state.flightDirection)
			end)
			hardStopAllAbilityTracks(state)
			state.cancelFallStartedAt = nil
			state.landingPlayed = false
			state.leapDownCommitted = false
			state.leanAnimSubphase = nil
			state.cancelApproachStarted = false
			state.locomotionReleasedAfterLanding = false
			state.landingGroundedAt = nil
			state.touchdownUprightApplied = false
			pcall(function()
				state.humanoid.PlatformStand = false
			end)
		end
	end
end

local function ensureAbilityState(character: Model): CharacterAbilityState?
	local state = characterStates[character]
	if state then
		return state
	end
	setupCharacter(character)
	return characterStates[character]
end

onPhaseChanged = function(phase: string)
	-- PhaseChanged signal and DjAbilityPhase replication can both fire for the same step.
	if phase == currentPhase then
		return
	end
	currentPhase = phase

	local character = player.Character
	if not character then
		return
	end

	local state = ensureAbilityState(character)
	if not state then
		return
	end

	state.phaseStartedAt = os.clock()

	if phase == PHASE.FlightTransit then
		state.currentPitch = getTuning().SupermanPose.TransitStartPitch
	elseif
		phase == PHASE.LeanUp
		or phase == PHASE.DownSupes
		or phase == PHASE.LeapDown
		or phase == PHASE.CancelFall
		or phase == PHASE.CancelLanding
	then
		state.currentPitch = getTuning().SupermanPose.UprightPitch
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
		afterTransitionPlaying = tracks.afterTransition.IsPlaying,
		flightTransitPlaying = tracks.flightTransit.IsPlaying,
		leanUpPlaying = tracks.leanUp.IsPlaying,
		currentTrack = currentTrackName(state),
	}, "B")
	-- #endregion
end

setupCharacter = function(character: Model)
	cleanupCharacter(character)

	if not Features.UseDoubleJump then
		return
	end

	local folder = getAnimFolder()
	if not folder then
		warn("[iseesupes] DoubleJump setup failed: animation folder not found:", AnimRoot.FolderName)
		return
	end

	local collected = collectDoubleJumpAnimations(folder)
	if not collected then
		return
	end

	if not globalDjAnimsPreloaded then
		task.spawn(function()
			preloadDoubleJumpAnimations(collected)
			globalDjAnimsPreloaded = true
		end)
	end

	local flightAnim = collected[1]
	local afterAnim = collected[2]
	local leanAnim = collected[3]
	local leapAnim = collected[4]
	local downAnim = collected[5]
	local fallAnim = collected[6]
	local landingAnim = collected[7]

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
		downSupes = loadTrack(downAnim, true, Enum.AnimationPriority.Action2),
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
		currentPitch = getTuning().SupermanPose.TransitStartPitch,
		phaseStartedAt = os.clock(),
		downSupesGroundedFrames = 0,
		touchdownUprightApplied = false,
		leapDownCommitted = false,
		cancelApproachStarted = false,
		animPreloaded = true,
		jumpLocked = false,
		savedJumpHeight = nil,
		locomotionReleasedAfterLanding = false,
		landingGroundedAt = nil,
		leanAnimSubphase = nil,
	}
	characterStates[character] = state

	tracks.downSupes.Stopped:Connect(function()
		logDownSupes("track_stopped", "AnimationTrack.Stopped", {
			time = string.format("%.2f", tracks.downSupes.TimePosition),
			currentTrack = currentTrackName(state),
		})
	end)

	-- Non-looped transit can end a frame before the server phase flips; crossfade early to avoid a T-pose gap.
	tracks.flightTransit.Stopped:Connect(function()
		if not abilityActive then
			return
		end
		if currentPhase ~= PHASE.FlightTransit and currentPhase ~= PHASE.AfterTransition then
			return
		end
		if tracks.afterTransition.IsPlaying and state.currentTrack == tracks.afterTransition then
			return
		end
		crossfadeToTrack(state, tracks.afterTransition, getPhaseFadeTime())
	end)

	state.heartbeatConn = RunService.Heartbeat:Connect(function(_dt)
		if abilityActive and currentPhase then
			setAbilityJumpLock(state, true)
			publishSteerInput(state)
			syncPhaseFromAttribute()
			tickLandingWatchdog(state)
			-- Server is NetworkOwner during E and writes CFrame + AssemblyLinearVelocity each tick.
			-- We deliberately do NOT call applyClientOrientation / applyClientMovement here:
			-- those would dual-write physics and visibly fight server replication, causing jitter.
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
				if character then
					ensureAbilityState(character)
				end

				if character then
					local abilityState = characterStates[character]
					if abilityState then
						initFlightDirection(abilityState)
						abilityState.currentPitch = getTuning().SupermanPose.TransitStartPitch
						abilityState.phaseStartedAt = os.clock()
					end
				end

				setAbilityBlocking(true)
				applyAbilityJumpLock(true)
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
		task.spawn(function()
			preloadDoubleJumpFromFolder(folder)
		end)
	end

	bindAction()
	bindPhaseAttributeSync()
	bindTuningAttrListeners(player.Character)

	-- Watchdog: if ability blocking lingers without an active ability, force-clear it.
	-- Defends against missed AbilityEnded signals / race conditions on respawn.
	RunService.Heartbeat:Connect(function()
		if abilityBlockedAt and not abilityActive then
			if os.clock() - (abilityBlockedAt :: number) >= ABILITY_BLOCK_WATCHDOG_SEC then
				DebugLog.write("DoubleJumpController:watchdog", "force_unblock", {
					phase = currentPhase,
				}, "B")
				setAbilityBlocking(false)
				applyAbilityJumpLock(false)
			end
		end
	end)

	local DoubleJumpService = getDoubleJumpService()

	DoubleJumpService.PhaseChanged:Connect(function(phase: string)
		refreshTuning()
		local character = player.Character
		if not abilityActive and phase == PHASE.FlightTransit then
			abilityActive = true
			if character then
				ensureAbilityState(character)
				local abilityState = characterStates[character]
				if abilityState then
					initFlightDirection(abilityState)
				end
			end
			setAbilityBlocking(true)
			applyAbilityJumpLock(true)
			onPhaseChanged(phase)
		elseif abilityActive then
			if character then
				ensureAbilityState(character)
			end
			if character and characterStates[character] then
				onPhaseChanged(phase)
			end
		end
	end)

	DoubleJumpService.AbilityEnded:Connect(onAbilityEnded)

	DoubleJumpService.Rejected:Connect(function(_reason: string) end)

	player.CharacterAdded:Connect(function(character)
		if abilityActive then
			onAbilityEnded()
		end
		bindTuningAttrListeners(character)
		setupCharacter(character)
	end)

	if player.Character then
		setupCharacter(player.Character)
	end

	print("[iseesupes] DoubleJumpController ready.")
end

return DoubleJumpController

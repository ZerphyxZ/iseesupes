--!strict

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local DoubleJumpLanding = require(ReplicatedStorage.Shared.Utils.DoubleJumpLanding)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)
local DoubleJumpFlightPhysics = require(ReplicatedStorage.Shared.Utils.DoubleJumpFlightPhysics)
local DebugLog = require(ReplicatedStorage.Shared.Utils.DebugLog)
local CharacterStance = require(ReplicatedStorage.Shared.Utils.CharacterStance)
local LevelDesignTuning = require(ReplicatedStorage.Shared.Utils.LevelDesignTuning)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local ThrustConfigs = SpeedConfigs.Thrust

local AnimRoot = CharacterConfigs.Animations
local Loc = CharacterConfigs.Locomotion
local DjCfg = CharacterConfigs.DoubleJump
local Features = CharacterConfigs.Features

local cachedTuning: LevelDesignTuning.DoubleJumpTuning? = nil
local tuningAttrConns: { RBXScriptConnection } = {}
local levelTuningConns: { RBXScriptConnection } = {}

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

local function bindLevelTuningRefresh()
	for _, conn in levelTuningConns do
		conn:Disconnect()
	end
	table.clear(levelTuningConns)

	local function hookLevel(levelValue: IntValue)
		table.insert(levelTuningConns, levelValue.Changed:Connect(refreshTuning))
		refreshTuning()
	end

	local function onLeaderstats(folder: Instance)
		if not folder:IsA("Folder") then
			return
		end
		local levelValue = folder:FindFirstChild("Level")
		if levelValue and levelValue:IsA("IntValue") then
			hookLevel(levelValue)
			return
		end
		table.insert(levelTuningConns, folder.ChildAdded:Connect(function(child)
			if child.Name == "Level" and child:IsA("IntValue") then
				hookLevel(child)
			end
		end))
	end

	local localPlayer = Players.LocalPlayer
	local existing = localPlayer:FindFirstChild("leaderstats")
	if existing then
		onLeaderstats(existing)
	end
	table.insert(levelTuningConns, localPlayer.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then
			onLeaderstats(child)
		end
	end))
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
	ButtonY = Enum.KeyCode.ButtonY,
	ButtonX = Enum.KeyCode.ButtonX,
	ButtonB = Enum.KeyCode.ButtonB,
	ButtonL1 = Enum.KeyCode.ButtonL1,
	ButtonR1 = Enum.KeyCode.ButtonR1,
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

local function getDoubleJumpService()
	return Knit.GetService("DoubleJumpService")
end

local player = Players.LocalPlayer
local animFolder: Folder? = nil
local actionBound = false
local abilityActive = false
local abilityStartedAt: number? = nil
local holdingLocally = false
local lastCancelTooSoonToastAt = -math.huge
local smoothedSteerDir: Vector3? = nil
local smoothedSteerAxis = 0
local smoothedSteerPitchAxis = 0
local lastSteerSendAt = 0
local pendingSteerHasDirection = false
local pendingSteerDirection: Vector3? = nil

local function getCancelMinActiveTime(): number
	local minT = getTuning().CancelMinActiveTime
	if type(minT) == "number" and minT >= 0 then
		return minT
	end
	return 1.25
end

local function isAbilityActiveOnClient(): boolean
	return abilityActive or player:GetAttribute(PHASE_ATTR) ~= nil
end

local function canCancelAbilityYet(): boolean
	if not abilityStartedAt then
		return not isAbilityActiveOnClient()
	end
	return os.clock() - abilityStartedAt >= getCancelMinActiveTime()
end

local function notifyCancelTooSoon()
	local now = os.clock()
	if now - lastCancelTooSoonToastAt < 0.6 then
		return
	end
	lastCancelTooSoonToastAt = now
	local minActive = getCancelMinActiveTime()
	local remaining = minActive
	if abilityStartedAt then
		remaining = math.max(0.1, minActive - (now - abilityStartedAt))
	end
	if remaining >= 10 then
		NotificationManager.show(string.format("Hold thrust — cancel in %ds", math.ceil(remaining)), "Info")
	else
		NotificationManager.show(string.format("Hold thrust — cancel in %.1fs", remaining), "Info")
	end
end

local function markAbilityStarted()
	abilityStartedAt = os.clock()
end

local function clientOwnsFlightPhysics(): boolean
	local net = DjCfg.Network
	if net and net.ClientOwnsFlightPhysics == false then
		return false
	end
	return true
end

local function getSteerSendHz(): number
	local net = DjCfg.Network
	if net and typeof(net.SteerSendHz) == "number" and net.SteerSendHz > 0 then
		return net.SteerSendHz
	end
	return 15
end

local function isClientThrustDepleted(): boolean
	if not abilityActive then
		return false
	end
	local data = DataLib.GetData()
	if not data then
		return false
	end
	return (data.ThrustCurrent or 0) <= 0
end
local lastCameraYaw: number? = nil
local lastCameraPitch: number? = nil
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
	startPosition: Vector3,
	flightDirection: Vector3,
	lastFlatHeading: Vector3?,
	currentPitch: number,
	currentRoll: number,
	lastBankHeadingYaw: number?,
	phaseStartedAt: number,
	descentStartedAt: number?,
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
	landingWatchdogAt: number?,
	thrustCancelSent: boolean,
}

local characterStates: { [Model]: CharacterAbilityState } = {}

local DEBUG_DOWNSUPES = DjCfg.Debug == true

local globalDjAnimsPreloaded = false
local DOWNSUPES_PULSE_SEC = 0.25
local LANDING_WATCHDOG_HEAVY_INTERVAL = 0.15

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

local function unit3D(vector: Vector3): Vector3
	if vector.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return vector.Unit
end

local function usesCameraPitchSteer(): boolean
	return getTuning().Steering.FollowCameraPitch ~= false
end

local function phaseUsesCameraPitchSteer(_phase: string?): boolean
	return _phase == PHASE.LeanUp
end

local function phaseUsesCameraPitchFlight(phase: string?): boolean
	return phase == PHASE.AfterTransition or phase == PHASE.LeanUp
end

local function clampSteerPitch(dir: Vector3, maxPitchDeg: number): Vector3
	local unit = unit3D(dir)
	local flat = Vector3.new(unit.X, 0, unit.Z)
	if flat.Magnitude < 0.01 then
		return unit
	end
	flat = flat.Unit
	local maxY = math.sin(math.rad(math.max(5, maxPitchDeg)))
	local y = math.clamp(unit.Y, -maxY, maxY)
	return unit3D(Vector3.new(flat.X, y, flat.Z))
end

local function normalizeFlightDirection(dir: Vector3, phase: string?): Vector3
	if usesCameraPitchSteer() and phaseUsesCameraPitchSteer(phase) then
		return unit3D(dir)
	end
	return flatUnit(dir)
end

local function flatDistance(from: Vector3, to: Vector3): number
	local a = Vector3.new(from.X, 0, from.Z)
	local b = Vector3.new(to.X, 0, to.Z)
	return (b - a).Magnitude
end

local function getFlightProbeOptions(phase: string): DoubleJumpLanding.FlightProbeOptions?
	if phase ~= PHASE.AfterTransition and phase ~= PHASE.LeanUp then
		return nil
	end
	local folder = StageCheckpointWorld.getFlightProbeFolder()
	if not folder then
		return {
			ignoreWalkableInstance = StageCheckpointWorld.isCheckpointSpawnPart,
		}
	end
	return {
		ignoreWallProbeHitsIn = folder,
		ignoreWalkableInstance = StageCheckpointWorld.isCheckpointSpawnPart,
	}
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
	local steering = getTuning().Steering
	local followPitch = steering.FollowCameraPitch ~= false and phaseUsesCameraPitchSteer(currentPhase)
	local maxPitch = steering.MaxPitchDegrees or 80

	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end

	local look = camera.CFrame.LookVector
	local rightVector = camera.CFrame.RightVector

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

	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatRight = Vector3.new(rightVector.X, 0, rightVector.Z)
	if flatLook.Magnitude < 0.01 then
		if followPitch then
			return clampSteerPitch(look, maxPitch)
		end
		return Vector3.zero
	end
	flatLook = flatLook.Unit
	if flatRight.Magnitude > 0.01 then
		flatRight = flatRight.Unit
	else
		flatRight = Vector3.new(-flatLook.Z, 0, flatLook.X)
	end

	if forward == 0 and right == 0 then
		if followPitch then
			-- Include camera pitch so looking up/down moves the player up/down,
			-- mirroring how yaw already steers left/right.
			return clampSteerPitch(look, maxPitch)
		end
		-- No keys held: steer toward camera's flat horizontal direction so the
		-- character flies where the player looks without diving from camera pitch.
		return flatLook
	end

	-- LeanUp: A/D alone uses slow axis yaw + bank; avoid snapping heading to camera strafe.
	if currentPhase == PHASE.LeanUp and forward == 0 and right ~= 0 then
		return Vector3.zero
	end

	return flatUnit(flatLook * forward + flatRight * right)
end

local TOUCH_STICK_DRIFT_DEADZONE = 0.22

local function getTouchSteerAxis(): number
	if not UserInputService.TouchEnabled then
		return 0
	end

	local playerScripts = player:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return 0
	end

	local playerModuleScript = playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript then
		return 0
	end

	local ok, controls = pcall(function()
		return require(playerModuleScript :: ModuleScript):GetControls()
	end)
	if not ok or not controls then
		return 0
	end

	local okMove, moveVector = pcall(function()
		return controls:GetMoveVector()
	end)
	if not okMove or typeof(moveVector) ~= "Vector3" or moveVector.Magnitude <= TOUCH_STICK_DRIFT_DEADZONE then
		return 0
	end

	if math.abs(moveVector.Z) > math.abs(moveVector.X) then
		return 0
	end

	if math.abs(moveVector.X) < TOUCH_STICK_DRIFT_DEADZONE then
		return 0
	end

	if moveVector.X > 0 then
		return -1
	end
	if moveVector.X < 0 then
		return 1
	end
	return 0
end

local function wrapYawDelta(delta: number): number
	while delta > math.pi do
		delta -= 2 * math.pi
	end
	while delta < -math.pi do
		delta += 2 * math.pi
	end
	return delta
end

local function resetCameraSteerTracking()
	lastCameraYaw = nil
	lastCameraPitch = nil
	lastSteerSendAt = 0
	pendingSteerHasDirection = false
	pendingSteerDirection = nil
end

function DoubleJumpController:resetSteerTrackingAfterMorph()
	resetCameraSteerTracking()
end

local function getCameraPitch(): number?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local look = camera.CFrame.LookVector
	local horizontalMag = math.sqrt(look.X * look.X + look.Z * look.Z)
	if horizontalMag < 0.01 then
		return nil
	end
	return math.atan2(-look.Y, horizontalMag)
end

local function getCameraPitchRateSteerAxis(dt: number): number
	local pitch = getCameraPitch()
	if pitch == nil then
		return 0
	end

	if lastCameraPitch == nil then
		lastCameraPitch = pitch
		return 0
	end

	local safeDt = math.clamp(dt, 1 / 240, 1 / 15)
	local delta = wrapYawDelta(pitch - lastCameraPitch)
	lastCameraPitch = pitch

	local poseCfg = getTuning().SupermanPose
	local fullPitchRate = poseCfg.CameraPitchRateForFullAxis or 1.0
	if fullPitchRate <= 0 then
		return 0
	end

	local pitchRate = delta / safeDt
	local axis = math.clamp(-pitchRate / fullPitchRate, -1, 1)
	local minRate = poseCfg.CameraPitchRateMin or 0.3
	local minAxis = poseCfg.CameraPitchRateMinAxis or 0.25
	if math.abs(pitchRate) >= minRate and math.abs(axis) < minAxis then
		axis = math.sign(pitchRate) * -minAxis
	end
	return axis
end

local function getCameraFlatYaw(): number?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local flatLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	if flatLook.Magnitude < 0.01 then
		return nil
	end
	return math.atan2(flatLook.X, flatLook.Z)
end

--- Bank from how fast the camera is spinning, not angle vs flight (which hits zero once body catches up).
local function getCameraYawRateSteerAxis(dt: number): number
	local yaw = getCameraFlatYaw()
	if yaw == nil then
		return 0
	end

	if lastCameraYaw == nil then
		lastCameraYaw = yaw
		return 0
	end

	local safeDt = math.clamp(dt, 1 / 240, 1 / 15)
	local delta = wrapYawDelta(yaw - lastCameraYaw)
	lastCameraYaw = yaw

	local poseCfg = getTuning().SupermanPose
	local fullBankRate = poseCfg.CameraYawRateForFullBank or 1.2
	if fullBankRate <= 0 then
		return 0
	end

	local yawRate = delta / safeDt
	local axis = math.clamp(-yawRate / fullBankRate, -1, 1)
	local minRate = poseCfg.CameraYawRateMin or 0.35
	if UserInputService.TouchEnabled then
		minRate = math.max(minRate, 0.9)
	end
	local minAxis = poseCfg.CameraYawRateMinAxis or 0.28
	if math.abs(yawRate) >= minRate and math.abs(axis) < minAxis then
		axis = -math.sign(yawRate) * minAxis
	end
	return axis
end

local function getCameraHeadingBankAxis(state: CharacterAbilityState): number
	local poseCfg = getTuning().SupermanPose
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end

	local flatLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	if flatLook.Magnitude < 0.01 then
		return 0
	end
	flatLook = flatLook.Unit

	local flatFlight = Vector3.new(state.flightDirection.X, 0, state.flightDirection.Z)
	if flatFlight.Magnitude < 0.01 then
		return 0
	end
	flatFlight = flatFlight.Unit

	-- Camera left/right of current flight heading → bank while mouse-steering.
	local sinTurn = flatFlight:Cross(flatLook).Y
	local cosTurn = flatFlight:Dot(flatLook)
	local turnAngle = math.atan2(sinTurn, cosTurn)
	local fullBankAngle = math.rad(poseCfg.CameraHeadingDegreesForFullBank or 48)
	return math.clamp(-turnAngle / fullBankAngle, -1, 1)
end

local function getSteerAxisFromInput(state: CharacterAbilityState, dt: number): number
	local steerAxis = 0

	-- A = left, D = right (bank roll sign)
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		steerAxis += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		steerAxis -= 1
	end

	local touchSteer = getTouchSteerAxis()
	if touchSteer ~= 0 then
		steerAxis = touchSteer
	end

	local headingAxis = getCameraHeadingBankAxis(state)
	if math.abs(headingAxis) > 0.02 then
		if math.abs(steerAxis) < 0.01 then
			steerAxis = headingAxis
		else
			steerAxis = math.clamp(steerAxis + headingAxis * 0.75, -1, 1)
		end
	end

	local adHeld = UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.D)
	local rateAxis = getCameraYawRateSteerAxis(dt)
	if math.abs(rateAxis) > 0.02 and not (currentPhase == PHASE.LeanUp and adHeld) then
		local blend = getTuning().SupermanPose.CameraBankBlend or 0.85
		if math.abs(steerAxis) < 0.01 then
			steerAxis = rateAxis
		else
			steerAxis = math.clamp(steerAxis + rateAxis * blend, -1, 1)
		end
	end

	return math.clamp(steerAxis, -1, 1)
end

local function flushSteerToServer()
	local service = Knit.GetService("DoubleJumpService")
	pcall(function()
		service:UpdateSteerState(
			if pendingSteerHasDirection then pendingSteerDirection else nil,
			smoothedSteerAxis,
			smoothedSteerPitchAxis
		)
	end)
end

local function publishSteerInput(state: CharacterAbilityState, dt: number)
	if not abilityActive then
		return
	end

	local steerCfg = getTuning().Steering
	local targetAxis = getSteerAxisFromInput(state, dt)
	local adHeldOnLeanUp = currentPhase == PHASE.LeanUp
		and (UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.D))
	local axisSmoothRate = if adHeldOnLeanUp
		then (steerCfg.KeyboardAxisSmoothRateLeanUp or 48)
		else (steerCfg.SteerAxisSmoothRate or steerCfg.SteerSmoothRate or 14)
	local axisAlpha = math.min(1, axisSmoothRate * dt)
	smoothedSteerAxis = smoothedSteerAxis + (targetAxis - smoothedSteerAxis) * axisAlpha

	if phaseUsesCameraPitchFlight(currentPhase) then
		local targetPitchAxis = getCameraPitchRateSteerAxis(dt)
		smoothedSteerPitchAxis = smoothedSteerPitchAxis + (targetPitchAxis - smoothedSteerPitchAxis) * axisAlpha
	else
		smoothedSteerPitchAxis = smoothedSteerPitchAxis + (0 - smoothedSteerPitchAxis) * axisAlpha
	end

	local raw = getCameraRelativeSteerInput(state)
	local adOnlyOnLeanUp = currentPhase == PHASE.LeanUp
		and not UserInputService:IsKeyDown(Enum.KeyCode.W)
		and not UserInputService:IsKeyDown(Enum.KeyCode.S)
		and (UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.D))
	if adOnlyOnLeanUp then
		raw = Vector3.zero
	end
	if raw.Magnitude >= 0.01 then
		local moveKeysHeld = UserInputService:IsKeyDown(Enum.KeyCode.W)
			or UserInputService:IsKeyDown(Enum.KeyCode.S)
			or UserInputService:IsKeyDown(Enum.KeyCode.A)
			or UserInputService:IsKeyDown(Enum.KeyCode.D)
		local smoothRate = if moveKeysHeld
			then (steerCfg.SteerSmoothRate or 14)
			else (steerCfg.CameraSteerSmoothRate or steerCfg.SteerSmoothRate or 6)
		local alpha = math.min(1, smoothRate * dt)
		local normalized = normalizeFlightDirection(raw, currentPhase)
		if smoothedSteerDir then
			smoothedSteerDir =
				normalizeFlightDirection((smoothedSteerDir :: Vector3):Lerp(normalized, alpha), currentPhase)
		else
			smoothedSteerDir = normalized
		end
		pendingSteerHasDirection = true
		pendingSteerDirection = smoothedSteerDir
	else
		pendingSteerHasDirection = false
		pendingSteerDirection = nil
		smoothedSteerDir = nil
	end

	if not clientOwnsFlightPhysics() then
		local now = os.clock()
		if now - lastSteerSendAt >= 1 / getSteerSendHz() then
			flushSteerToServer()
			lastSteerSendAt = now
		end
	end
end

local function applySteerToFlightDirection(state: CharacterAbilityState, dt: number)
	local steerCfg = getTuning().Steering
	if steerCfg.Enabled == false then
		return
	end

	local steer = getCameraRelativeSteerInput(state)
	local target = if steer.Magnitude >= getSteerThreshold() then steer else state.flightDirection
	local alpha = math.min(1, (steerCfg.DirectionLerp or 10) * dt)
	state.flightDirection = normalizeFlightDirection(state.flightDirection:Lerp(target, alpha), currentPhase)
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

local function computeClientFlightVelocity(
	flightDirection: Vector3,
	riseSpeed: number,
	forwardSpeed: number,
	phase: string?
): Vector3
	local dir = normalizeFlightDirection(flightDirection, phase)
	if usesCameraPitchSteer() and phaseUsesCameraPitchSteer(phase) then
		local speed = math.sqrt(forwardSpeed * forwardSpeed + riseSpeed * riseSpeed)
		return dir * speed
	end
	return dir * forwardSpeed + Vector3.new(0, riseSpeed, 0)
end

local function cframeWithPose(position: Vector3, flightDir: Vector3, pitchDeg: number, rollDeg: number): CFrame
	local flat = flatUnit(flightDir)
	local base = CFrame.lookAt(position, position + flat)
	return base * CFrame.Angles(math.rad(pitchDeg), 0, math.rad(rollDeg))
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
		root.CFrame = cframeWithPose(root.Position, state.flightDirection, state.currentPitch, 0)
	else
		lerpPitch(state, poseCfg.FlightPitch, dt)
		root.CFrame = cframeWithPose(root.Position, state.flightDirection, state.currentPitch, 0)
	end
end

local function buildFlightPhysicsState(state: CharacterAbilityState): DoubleJumpFlightPhysics.FlightState
	return {
		flightDirection = state.flightDirection,
		lastFlatHeading = state.lastFlatHeading,
		currentPitch = state.currentPitch,
		currentRoll = state.currentRoll,
		descentStartedAt = state.descentStartedAt,
		clientSteerAxis = smoothedSteerAxis,
		clientSteerPitchAxis = smoothedSteerPitchAxis,
		clientSteerDirection = smoothedSteerDir,
		lastBankHeadingYaw = state.lastBankHeadingYaw,
	}
end

local function applyFlightStateFromPhysics(state: CharacterAbilityState, fpState: DoubleJumpFlightPhysics.FlightState)
	state.flightDirection = fpState.flightDirection
	state.lastFlatHeading = fpState.lastFlatHeading
	state.currentPitch = fpState.currentPitch
	state.currentRoll = fpState.currentRoll
	state.descentStartedAt = fpState.descentStartedAt
	state.lastBankHeadingYaw = fpState.lastBankHeadingYaw
end

local function tickClientFlightPhysics(state: CharacterAbilityState, dt: number, phase: string)
	if not clientOwnsFlightPhysics() then
		return
	end

	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local steerDir: Vector3? = nil
	if pendingSteerHasDirection and smoothedSteerDir and smoothedSteerDir.Magnitude >= getSteerThreshold() then
		steerDir = smoothedSteerDir
	end

	local fpState = buildFlightPhysicsState(state)
	local phaseElapsed = os.clock() - state.phaseStartedAt
	local tuning = getTuning()

	local tickOpts: { thrustDepleted: boolean }? = nil
	if
		isClientThrustDepleted()
		and (phase == PHASE.FlightTransit or phase == PHASE.AfterTransition or phase == PHASE.LeanUp)
	then
		if not state.thrustCancelSent then
			state.thrustCancelSent = true
			holdingLocally = false
			getDoubleJumpService():SetHolding(false)
		end
		tickOpts = { thrustDepleted = true }
	end

	DoubleJumpFlightPhysics.tickPhase(
		root,
		fpState,
		{
			phase = phase,
			phaseElapsed = phaseElapsed,
			phaseStartedAt = state.phaseStartedAt,
			startPosition = state.startPosition,
			rayParams = state.rayParams,
			humanoid = state.humanoid,
			steerDirection = steerDir,
		},
		dt,
		tuning,
		tickOpts
	)

	applyFlightStateFromPhysics(state, fpState)
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

--- Mirrors server LeanUp: descent anim only on safety cap (thrust fuel ends glide server-side).
local function isLeanUpInDescent(_state: CharacterAbilityState): boolean
	local phaseElapsed = os.clock() - _state.phaseStartedAt
	return phaseElapsed >= ThrustConfigs.LeanUpSafetyMaxDuration
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

local function phaseNeedsHeavyLandingChecks(phase: string?): boolean
	return phase == PHASE.LeapDown
		or phase == PHASE.DownSupes
		or phase == PHASE.CancelLanding
		or phase == PHASE.CancelFall
end

enforceLandingAnim = function(state: CharacterAbilityState, runHeavyChecks: boolean?)
	local root = state.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	if runHeavyChecks == false then
		if currentPhase == PHASE.LeanUp or currentPhase == PHASE.DownSupes then
			updateLeanUpAnimSubphase(state)
		end
		return
	end

	local landingCfg = getTuning().Phases.DownSupes
	local moveDir = state.flightDirection
	if DoubleJumpLanding.hasObstacleContact(
		state.humanoid,
		root,
		state.rayParams,
		landingCfg,
		moveDir,
		getFlightProbeOptions(currentPhase)
	) then
		stopLeanUpHard(state.tracks)
		stopDownSupesHard(state.tracks, "wall_contact")
		pcall(function()
			if state.tracks.leapDown.IsPlaying then
				state.tracks.leapDown:Stop(0.08)
			end
		end)
		state.leapDownCommitted = false
		return
	end

	local grounded = DoubleJumpLanding.isGroundedForLanding(state.humanoid, root, state.rayParams, landingCfg, moveDir)

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
	if DoubleJumpLanding.hasObstacleContact(
		state.humanoid,
		root,
		state.rayParams,
		landingCfg,
		state.flightDirection,
		getFlightProbeOptions(currentPhase)
	) then
		stopLeanUpHard(state.tracks)
		stopDownSupesHard(state.tracks, "wall_contact")
		return
	end

	local started = state.cancelFallStartedAt or state.phaseStartedAt
	local elapsed = os.clock() - started
	local hit = DoubleJumpLanding.raycastDownFromRoot(
		root,
		cancelCfg.LandingRayLength or 250,
		state.rayParams
	)
	local walkableHit = if hit and DoubleJumpLanding.isWalkableHit(hit, landingCfg) then hit else nil

	if
		not DoubleJumpLanding.shouldStartCancelLanding(
			state.humanoid,
			root,
			walkableHit,
			state.rayParams,
			landingCfg,
			cancelCfg,
			elapsed,
			state.flightDirection
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

	local now = os.clock()
	local needsHeavy = phaseNeedsHeavyLandingChecks(currentPhase)
	if not needsHeavy then
		local last = state.landingWatchdogAt or 0
		if now - last < LANDING_WATCHDOG_HEAVY_INTERVAL then
			if currentPhase == PHASE.LeanUp then
				updateLeanUpAnimSubphase(state)
			end
			tickLandingLocomotionRelease(state)
			tickLandingAnimFailsafe(state)
			return
		end
		state.landingWatchdogAt = now
	end

	enforceLandingAnim(state, needsHeavy)
	if needsHeavy or currentPhase == PHASE.CancelFall then
		enforceCancelApproachLanding(state)
	end
	tickLandingLocomotionRelease(state)
	tickLandingAnimFailsafe(state)
end

local function playTrack(state: CharacterAbilityState, track: AnimationTrack, fadeTime: number?)
	crossfadeToTrack(state, track, fadeTime or getPhaseFadeTime())
end

local function playPhaseAnim(state: CharacterAbilityState, phase: string)
	local tracks = state.tracks
	if phase == PHASE.FlightTransit then
		state.humanoid.AutoRotate = false
		state.humanoid.PlatformStand = false
		playTrack(state, tracks.flightTransit)
	elseif phase == PHASE.AfterTransition then
		state.humanoid.AutoRotate = false
		state.humanoid.PlatformStand = false
		playTrack(state, tracks.afterTransition)
	elseif phase == PHASE.LeanUp or phase == PHASE.DownSupes then
		state.touchdownUprightApplied = false
		state.leapDownCommitted = false
		state.leanAnimSubphase = nil
		state.downSupesGroundedFrames = 0
		state.humanoid.AutoRotate = false
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
		humanoid.AutoRotate = true
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
	abilityStartedAt = nil
	holdingLocally = false
	smoothedSteerDir = nil
	smoothedSteerAxis = 0
	smoothedSteerPitchAxis = 0
	resetCameraSteerTracking()
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
			state.thrustCancelSent = false
			pcall(function()
				state.humanoid.PlatformStand = false
			end)
		else
			CharacterStance.resetToStanding(character)
		end
	end
end

local function cancelActiveAbilityFromInput()
	if not abilityActive and not player:GetAttribute(PHASE_ATTR) then
		return false
	end

	if not canCancelAbilityYet() then
		notifyCancelTooSoon()
		return true
	end

	holdingLocally = false
	getDoubleJumpService():SetHolding(false)
	return true
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
		state.currentRoll = 0
		state.lastBankHeadingYaw = nil
		state.descentStartedAt = nil
	elseif phase == PHASE.LeanUp or phase == PHASE.DownSupes then
		state.currentPitch = getTuning().SupermanPose.UprightPitch
		state.currentRoll = 0
		state.lastBankHeadingYaw = nil
		state.descentStartedAt = nil
		state.flightDirection = flatUnit(state.flightDirection)
	elseif
		phase == PHASE.LeapDown
		or phase == PHASE.CancelFall
		or phase == PHASE.CancelLanding
	then
		state.currentPitch = getTuning().SupermanPose.UprightPitch
		state.currentRoll = 0
		state.lastBankHeadingYaw = nil
		state.descentStartedAt = nil
		state.flightDirection = flatUnit(state.flightDirection)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and clientOwnsFlightPhysics() then
			DoubleJumpFlightPhysics.restoreUprightPose(root, state.flightDirection)
		elseif root then
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
		startPosition = if root then root.Position else Vector3.zero,
		flightDirection = flatUnit(startCFrame.LookVector),
		lastFlatHeading = flatUnit(startCFrame.LookVector),
		currentPitch = getTuning().SupermanPose.TransitStartPitch,
		currentRoll = 0,
		lastBankHeadingYaw = nil,
		phaseStartedAt = os.clock(),
		descentStartedAt = nil,
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
		thrustCancelSent = false,
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

	state.heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		if abilityActive and currentPhase then
			setAbilityJumpLock(state, true)
			publishSteerInput(state, dt)
			syncPhaseFromAttribute()
			if clientOwnsFlightPhysics() then
				tickClientFlightPhysics(state, dt, currentPhase)
			end
			tickLandingWatchdog(state)
		end
	end)

	character.Destroying:Once(function()
		cleanupCharacter(character)
		if abilityActive then
			onAbilityEnded()
		end
	end)
end

local function onDoubleJumpAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if not Features.UseDoubleJump then
		return Enum.ContextActionResult.Pass
	end

	local service = getDoubleJumpService()

	if inputState == Enum.UserInputState.Begin then
		if abilityActive or player:GetAttribute(PHASE_ATTR) then
			-- Toggle: second E press ends Superman flight (cancel fall → land).
			cancelActiveAbilityFromInput()
			return Enum.ContextActionResult.Sink
		end

		holdingLocally = true
		markAbilityStarted()
		service:RequestStart():andThen(function(ok: boolean, _reason: string?)
			if ok then
				abilityActive = true
				markAbilityStarted()
				resetCameraSteerTracking()
				smoothedSteerDir = nil
				smoothedSteerAxis = 0
				smoothedSteerPitchAxis = 0
				pendingSteerHasDirection = false
				pendingSteerDirection = nil
				service:SetHolding(true)

				local character = player.Character
				if character then
					ensureAbilityState(character)
				end

				if character then
					local abilityState = characterStates[character]
					if abilityState then
						initFlightDirection(abilityState)
						local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if rootPart then
							abilityState.startPosition = rootPart.Position
						end
						abilityState.currentPitch = getTuning().SupermanPose.TransitStartPitch
						abilityState.currentRoll = 0
						abilityState.descentStartedAt = nil
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
				abilityStartedAt = nil
			end
		end):catch(warn)

		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End then
		holdingLocally = false
		-- Ability runs to completion on its own; only a second E press cancels it.
		-- Don't call SetHolding(false) here — that would cancel and clear steering.
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

	local inputs: { Enum.KeyCode } = { keyCode }
	local gamepadKey = KEY_CODES[DjCfg.GamepadKey]
	if gamepadKey then
		table.insert(inputs, gamepadKey)
	end

	actionBound = true
	ContextActionService:BindAction(DjCfg.ActionName, onDoubleJumpAction, false, table.unpack(inputs))
end

function DoubleJumpController:KnitStart()
	CharacterController = Knit.GetController("CharacterController")

	task.defer(function()
		CharacterController:RegisterJumpInterceptor(function()
			return cancelActiveAbilityFromInput()
		end)
	end)

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
	bindLevelTuningRefresh()

	DataLib.OnChanged(function(data)
		if data and type(data.Level) == "number" then
			refreshTuning()
		end
	end)

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
			markAbilityStarted()
			resetCameraSteerTracking()
			smoothedSteerDir = nil
			smoothedSteerAxis = 0
			smoothedSteerPitchAxis = 0
			pendingSteerHasDirection = false
			pendingSteerDirection = nil
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

	-- Kryptonite stage: server wiped our thrust the moment we took off.
	DoubleJumpService.KryptoniteDrained:Connect(function()
		local kryptonite = DjCfg.Kryptonite
		local message = (kryptonite and kryptonite.Message) or "Kryptonite! Flight is drained — jump!"
		NotificationManager.show(message, "Error")
	end)

	-- Server sets ForceStandUp=true before teleporting player to lobby after a win claim.
	-- Calling onAbilityEnded() here cancels flight, sets PlatformStand=false, and stops all
	-- tracks so the character doesn't land in a prone Superman pose at the lobby spawn.
	player:GetAttributeChangedSignal("ForceStandUp"):Connect(function()
		if player:GetAttribute("ForceStandUp") == true then
			onAbilityEnded()
		end
	end)

	player.CharacterAdded:Connect(function(character)
		if abilityActive or player:GetAttribute(PHASE_ATTR) then
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

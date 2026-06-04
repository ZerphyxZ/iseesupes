--!strict

-- Long jump: double-tap jump OR hold jump button for HoldThreshold (mobile-friendly).
-- - Double-tap (desktop preferred): tap Space twice within DoubleTapWindow → long jump.
-- - Hold (mobile preferred): press and HOLD Space / mobile jump button. Normal jump fires
--   immediately on press; if still held after HoldThreshold seconds, long jump fires too.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local HumanoidLocomotion = require(ReplicatedStorage.Shared.Utils.HumanoidLocomotion)
local SupermanLaunchFeedback = require(script.Parent.Parent.Parent.Modules.SupermanLaunchFeedback)

local AnimRoot = CharacterConfigs.Animations
local Loc = CharacterConfigs.Locomotion
local Features = CharacterConfigs.Features
local LjCfg = CharacterConfigs.LongJump
local DJ_PHASE_ATTR = "DjAbilityPhase"

local LongJumpController = Knit.CreateController({ Name = "LongJumpController" })

local player = Players.LocalPlayer

local CharacterController: any = nil
local animFolder: Folder? = nil

local lastJumpPressAt = -math.huge
local cooldownEndsAt = 0
local holdLongJumpToken = 0 -- increments each press so older hold-checks bail out

-- How long the jump button must be held (after the initial press) to trigger long jump.
-- Short enough to feel responsive on mobile, long enough that quick taps stay normal jumps.
local HOLD_LONG_JUMP_THRESHOLD = 0.18

--- True if the player is still holding ANY jump input (keyboard Space or mobile jump button).
--- Roblox sets humanoid.Jump = true while the mobile jump button is pressed, and
--- UserInputService:IsKeyDown(Space) is true while Space is held on desktop.
local function isJumpInputStillHeld(humanoid: Humanoid?): boolean
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		return true
	end
	if humanoid and humanoid.Jump then
		return true
	end
	return false
end

type CharacterLongJumpState = {
	character: Model,
	humanoid: Humanoid,
	leanUpTrack: AnimationTrack,
	animStopToken: number,
	groundedConn: RBXScriptConnection?,
}

local characterStates: { [Model]: CharacterLongJumpState } = {}

local function flatUnit(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
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
		warn("[iseesupes][LongJump] Missing folder:", subFolderName)
		return nil
	end
	local inst = sub:FindFirstChild(animName)
	if inst and inst:IsA("Animation") then
		return inst
	end
	warn("[iseesupes][LongJump] Missing Animation:", animName, "in", subFolderName)
	return nil
end

local function getLeanUpFadeTime(): number
	return LjCfg.LeanUpFadeTime or Loc.FadeTime
end

local function getLeanUpDuration(): number
	return LjCfg.LeanUpDuration or 0.9
end

local function stopLeanUpAnim(state: CharacterLongJumpState)
	state.animStopToken += 1
	if state.groundedConn then
		state.groundedConn:Disconnect()
		state.groundedConn = nil
	end
	pcall(function()
		if state.leanUpTrack.IsPlaying then
			state.leanUpTrack:Stop(getLeanUpFadeTime())
		end
	end)
end

local function playLeanUpAnim(state: CharacterLongJumpState)
	stopLeanUpAnim(state)
	state.animStopToken += 1
	local token = state.animStopToken
	local fade = getLeanUpFadeTime()

	pcall(function()
		state.leanUpTrack:Play(fade)
	end)

	local function tryStop()
		if state.animStopToken ~= token then
			return
		end
		stopLeanUpAnim(state)
	end

	task.delay(getLeanUpDuration(), tryStop)

	if state.groundedConn then
		state.groundedConn:Disconnect()
	end
	state.groundedConn = state.humanoid.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			tryStop()
		end
	end)
end

local function applyLongJump(character: Model): boolean
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end

	if LjCfg.UseLaunchFeedback ~= false then
		local fallbacks = LjCfg.LaunchSoundFallbacks
		local soundNames: { string } = if type(fallbacks) == "table" and #fallbacks > 0
			then fallbacks
			else { LjCfg.LaunchSound or "QuickWhoosh", "Woosh" }
		SupermanLaunchFeedback.playLaunchBurst(character, {
			vfxTier = LjCfg.LaunchVfxTier or "LongJumpLaunch",
			soundNames = soundNames,
			soundFolders = LjCfg.LaunchSoundFolders,
		})
	end

	local forward = flatUnit(hrp.CFrame.LookVector)
	hrp.AssemblyLinearVelocity = forward * LjCfg.ForwardPower + Vector3.new(0, LjCfg.UpPower, 0)

	local state = characterStates[character]
	if state then
		playLeanUpAnim(state)
	end

	return true
end

local function isBlocked(): boolean
	if CharacterController and CharacterController.IsAbilityBlocking and CharacterController:IsAbilityBlocking() then
		return true
	end
	if player:GetAttribute(DJ_PHASE_ATTR) then
		return true
	end
	return false
end

function LongJumpController:TryLongJumpOnJump(): boolean
	if not Features.UseLongJump then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and HumanoidLocomotion.usesEngineLocomotion(humanoid) then
		return false
	end

	if isBlocked() then
		return false
	end

	local now = os.clock()
	local window = LjCfg.DoubleTapWindow or 0.35

	if now - lastJumpPressAt <= window then
		lastJumpPressAt = -math.huge

		if now < cooldownEndsAt then
			local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)
			local remaining = cooldownEndsAt - now
			if remaining >= 10 then
				NotificationManager.show(
					string.format("Long jump on cooldown — %ds left", math.ceil(remaining)),
					"Error"
				)
			else
				NotificationManager.show(
					string.format("Long jump on cooldown — %.1fs left", math.max(0.1, remaining)),
					"Error"
				)
			end
			return true
		end

		if applyLongJump(character) then
			cooldownEndsAt = now + (LjCfg.Cooldown or 2.5)
		end
		return true
	end

	lastJumpPressAt = now

	-- HOLD path (mobile-friendly alternative to double-tap): schedule a long-jump
	-- check after the threshold. If the player is still holding jump AND not on
	-- cooldown, fire long jump. The first press already went through as a normal jump.
	holdLongJumpToken += 1
	local myToken = holdLongJumpToken
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	task.delay(HOLD_LONG_JUMP_THRESHOLD, function()
		if myToken ~= holdLongJumpToken then return end -- a newer press happened, ignore us
		if not player.Character or player.Character ~= character then return end
		if isBlocked() then return end
		if not isJumpInputStillHeld(humanoid) then return end
		local nowDelayed = os.clock()
		if nowDelayed < cooldownEndsAt then return end -- silently skip during cooldown on hold path
		if applyLongJump(character) then
			cooldownEndsAt = nowDelayed + (LjCfg.Cooldown or 2.5)
			lastJumpPressAt = -math.huge -- consume so the next tap isn't treated as second-tap
		end
	end)

	return false
end

local function cleanupCharacter(character: Model)
	local state = characterStates[character]
	if not state then
		return
	end
	stopLeanUpAnim(state)
	characterStates[character] = nil
end

local function setupCharacter(character: Model)
	cleanupCharacter(character)

	if not Features.UseLongJump then
		return
	end

	local folder = getAnimFolder()
	if not folder then
		return
	end

	local animFolderName = LjCfg.AnimFolder or "SuperJump"
	local leanUpName = LjCfg.LeanUpAnim or "LeanUp"
	local leanAnim = getAnimationInFolder(folder, animFolderName, leanUpName)
	if not leanAnim or leanAnim.AnimationId == "" then
		warn("[iseesupes][LongJump] LeanUp animation missing or has no AnimationId")
		return
	end

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ leanAnim })
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

	local leanUpTrack = animator:LoadAnimation(leanAnim)
	leanUpTrack.Looped = false
	leanUpTrack.Priority = Enum.AnimationPriority.Action2

	characterStates[character] = {
		character = character,
		humanoid = humanoid,
		leanUpTrack = leanUpTrack,
		animStopToken = 0,
		groundedConn = nil,
	}
end

function LongJumpController:KnitInit()
	CharacterController = Knit.GetController("CharacterController")
	if CharacterController and CharacterController.RegisterJumpInterceptor then
		CharacterController:RegisterJumpInterceptor(function()
			return LongJumpController:TryLongJumpOnJump()
		end)
	end
end

function LongJumpController:KnitStart()
	player.CharacterAdded:Connect(function(character)
		lastJumpPressAt = -math.huge
		setupCharacter(character)
	end)

	if player.Character then
		setupCharacter(player.Character)
	end

	print("[iseesupes] LongJumpController ready.")
end

return LongJumpController

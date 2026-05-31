--!strict

-- Long jump: double-tap jump (Space or mobile CharacterJump) within DoubleTapWindow.
-- First press = normal jump (interceptor returns false). Second press in window = velocity burst + LeanUp anim.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

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

	if isBlocked() then
		return false
	end

	local now = os.clock()
	local window = LjCfg.DoubleTapWindow or 0.35

	if now - lastJumpPressAt <= window then
		lastJumpPressAt = -math.huge

		if now < cooldownEndsAt then
			return true
		end

		if applyLongJump(character) then
			cooldownEndsAt = now + (LjCfg.Cooldown or 2.5)
		end
		return true
	end

	lastJumpPressAt = now
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

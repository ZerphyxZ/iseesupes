--!strict

-- Long jump: single tap jump (Space + TouchGui JumpButton). Basic short hop is never used.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local DoubleJumpLanding = require(ReplicatedStorage.Shared.Utils.DoubleJumpLanding)
local HumanoidLocomotion = require(ReplicatedStorage.Shared.Utils.HumanoidLocomotion)
local ClientPerformance = require(ReplicatedStorage.Shared.Utils.ClientPerformance)
local PerfWatch = require(ReplicatedStorage.Shared.Utils.PerfWatch)
local SupermanLaunchFeedback = require(script.Parent.Parent.Parent.Modules.SupermanLaunchFeedback)

local AnimRoot = CharacterConfigs.Animations
local Loc = CharacterConfigs.Locomotion
local Features = CharacterConfigs.Features
local LjCfg = CharacterConfigs.LongJump

local LongJumpController = Knit.CreateController({ Name = "LongJumpController" })

local player = Players.LocalPlayer

local CharacterController: any = nil
local animFolder: Folder? = nil

local cooldownEndsAt = 0
local touchJumpButtonHeld = false
local touchJumpButtonBound: GuiButton? = nil

type CharacterLongJumpState = {
	character: Model,
	humanoid: Humanoid,
	leanUpTrack: AnimationTrack,
	animStopToken: number,
	groundedConn: RBXScriptConnection?,
	landResetConn: RBXScriptConnection?,
	groundRayConn: RBXScriptConnection?,
	groundRayParams: RaycastParams,
	airLongJumpCharges: number,
	lastGroundedAt: number,
}

--- os.clock() time when spent air jumps can be granted again (recharge gate).
local airJumpReadyAt = 0

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

local function isAirLongJumpEnabled(): boolean
	return LjCfg.AirLongJumpEnabled ~= false
end

local function getMaxAirLongJumps(): number
	local max = LjCfg.MaxAirLongJumps
	if typeof(max) == "number" and max > 0 then
		return math.floor(max)
	end
	return 1
end

--- Ground long jump + air chain (HUD shows used out of this total per landing cycle).
local function getMaxLongJumpsInCycle(): number
	return 1 + getMaxAirLongJumps()
end

local function getLongJumpLandingCfg(): { [string]: any }
	local downSupes = CharacterConfigs.DoubleJump.Phases.DownSupes
	return {
		GroundProbeDistance = LjCfg.GroundProbeDistance or 6,
		WalkableNormalMinY = downSupes.WalkableNormalMinY or 0.6,
		GroundClearanceTolerance = LjCfg.GroundClearanceTolerance or downSupes.GroundClearanceTolerance or 0.35,
	}
end

local function makeGroundRayParams(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	return params
end

local function isGroundedForLongJump(humanoid: Humanoid, root: BasePart, rayParams: RaycastParams): boolean
	if LjCfg.UseRaycastGroundCheck == false then
		return humanoid.FloorMaterial ~= Enum.Material.Air
	end
	return DoubleJumpLanding.isOnWalkableGround(humanoid, root, rayParams, getLongJumpLandingCfg())
end

local function touchGroundedTimestamp(state: CharacterLongJumpState, humanoid: Humanoid, root: BasePart)
	if isGroundedForLongJump(humanoid, root, state.groundRayParams) then
		state.lastGroundedAt = os.clock()
	end
end

local function canGroundLongJump(humanoid: Humanoid, root: BasePart, state: CharacterLongJumpState?): boolean
	local now = os.clock()
	if isGroundedForLongJump(humanoid, root, if state then state.groundRayParams else makeGroundRayParams(humanoid.Parent :: Model)) then
		if state then
			state.lastGroundedAt = now
		end
		return true
	end
	-- FloorMaterial fallback when raycast misses (steep / fast movement).
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		if state then
			state.lastGroundedAt = now
		end
		return true
	end
	if not state then
		return false
	end
	local coyote = LjCfg.CoyoteTimeSeconds
	if typeof(coyote) ~= "number" or coyote <= 0 then
		coyote = 0.12
	end
	return (now - state.lastGroundedAt) <= coyote
end

local function isClearlyAirborne(humanoid: Humanoid, root: BasePart, state: CharacterLongJumpState?): boolean
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return false
	end
	local rayParams = if state then state.groundRayParams else makeGroundRayParams(humanoid.Parent :: Model)
	if isGroundedForLongJump(humanoid, root, rayParams) then
		return false
	end
	return true
end

--- Mirror long-jump count to player attributes for the HUD ("Long Jump used/max").
--- `used` is jumps performed this cycle: 0 on ground, 1 after ground LJ, 2 after air LJ.
local function publishLongJumpCounter(used: number)
	player:SetAttribute("LongJumpMax", getMaxLongJumpsInCycle())
	player:SetAttribute("LongJumpUsed", math.clamp(math.floor(used), 0, getMaxLongJumpsInCycle()))
end

--- os.clock() time the air jumps recharge at (0 = ready now). The HUD counter reads
--- this to show the "Recharging Xs" countdown.
local function publishLongJumpReadyAt(readyAt: number)
	player:SetAttribute("LongJumpReadyAt", readyAt)
end

local refillToken = 0

local function refillAirJumps(state: CharacterLongJumpState)
	state.airLongJumpCharges = 0
	airJumpReadyAt = 0
	publishLongJumpCounter(0)
	publishLongJumpReadyAt(0)
end

local function getArcActiveAttributeName(): string
	return LjCfg.ArcActiveAttribute or "LongJumpArcActive"
end

local function setLongJumpArcActive(active: boolean)
	player:SetAttribute(getArcActiveAttributeName(), if active then true else nil)
end

local function clearLongJumpArcActive()
	setLongJumpArcActive(false)
end

--- Called when the player is on the ground. Air jumps refill ONLY here — never in
--- mid-air — so the player must actually land before getting them back. If the
--- recharge gate is still counting down, the refill waits for it to finish while
--- the player stays grounded (so the countdown can't be "waited out" in the air).
local function onGrounded(state: CharacterLongJumpState, humanoid: Humanoid)
	-- Do not reset mid-arc (high speed triggers Landed/Running on launch and wiped charges).
	if player:GetAttribute(getArcActiveAttributeName()) == true then
		return
	end
	local now = os.clock()
	if now >= airJumpReadyAt then
		refillAirJumps(state)
		return
	end
	refillToken += 1
	local myToken = refillToken
	task.delay(airJumpReadyAt - now, function()
		if myToken ~= refillToken then
			return
		end
		if humanoid.Parent then
			local root = humanoid.Parent:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and isGroundedForLongJump(humanoid, root, state.groundRayParams) then
				refillAirJumps(state)
			end
		end
	end)
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

local function applyLongJump(character: Model, opts: { isAir: boolean? }?): boolean
	return PerfWatch.measure("LongJump.applyLongJump", function(): boolean
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return false
		end

		local state = characterStates[character]
		local isAir = opts ~= nil and opts.isAir == true
		if isAir then
			if not state or state.airLongJumpCharges <= 0 then
				return false
			end
		else
			local hum = character:FindFirstChildOfClass("Humanoid")
			if not hum then
				return false
			end
			if not canGroundLongJump(hum, hrp, state) then
				return false
			end
		end

		if LjCfg.UseLaunchFeedback ~= false then
			local fallbacks = LjCfg.LaunchSoundFallbacks
			local soundNames: { string } = if type(fallbacks) == "table" and #fallbacks > 0
				then fallbacks
				else { LjCfg.LaunchSound or "QuickWhoosh", "Woosh" }
			local vfxTier = if isAir
				then (LjCfg.LaunchVfxTierAir or "LongJumpLaunchAir")
				else (LjCfg.LaunchVfxTier or "LongJumpLaunch")
			SupermanLaunchFeedback.playLaunchBurst(character, {
				vfxTier = vfxTier,
				soundNames = soundNames,
				soundFolders = LjCfg.LaunchSoundFolders,
				skipParticles = ClientPerformance.shouldReduceSupermanVfx(),
			})
		end

		local forward = flatUnit(hrp.CFrame.LookVector)
		hrp.AssemblyLinearVelocity = forward * LjCfg.ForwardPower + Vector3.new(0, LjCfg.UpPower, 0)

		if state then
			if isAir then
				state.airLongJumpCharges -= 1
				publishLongJumpCounter(getMaxLongJumpsInCycle() - state.airLongJumpCharges)
				if state.airLongJumpCharges <= 0 then
					-- Both jumps spent: start the recharge gate (must land + wait before more).
					airJumpReadyAt = os.clock() + (LjCfg.ExhaustCooldown or 1.0)
					publishLongJumpReadyAt(airJumpReadyAt)
				end
			else
				state.airLongJumpCharges = getMaxAirLongJumps()
				publishLongJumpCounter(1)
				publishLongJumpReadyAt(0)
			end
			playLeanUpAnim(state)
		end

		setLongJumpArcActive(true)
		return true
	end)
end

local function tryAirLongJump(character: Model, humanoid: Humanoid): boolean
	if not isAirLongJumpEnabled() then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local state = characterStates[character]
	if not isClearlyAirborne(humanoid, root, state) then
		return false
	end
	if not state or state.airLongJumpCharges <= 0 then
		return false
	end
	return applyLongJump(character, { isAir = true })
end

local function isBlocked(): boolean
	if CharacterController and CharacterController.IsAbilityBlocking and CharacterController:IsAbilityBlocking() then
		return true
	end
	if player:GetAttribute("DjAbilityPhase") then
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

	if humanoid and tryAirLongJump(character, humanoid) then
		return true
	end

	local now = os.clock()
	if now < cooldownEndsAt then
		return true
	end

	if applyLongJump(character) then
		cooldownEndsAt = now + (LjCfg.Cooldown or 2.5)
	end

	-- Always consume jump input — never fall through to basic short hop.
	return true
end

local function isTouchPressInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function bindTouchGuiJumpButton(button: GuiButton)
	if touchJumpButtonBound == button then
		return
	end
	touchJumpButtonBound = button

	button.InputBegan:Connect(function(input: InputObject, _gameProcessed: boolean)
		if not isTouchPressInput(input) then
			return
		end
		touchJumpButtonHeld = true
		if CharacterController and CharacterController.PressJump then
			CharacterController:PressJump()
		end
	end)

	button.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		if not isTouchPressInput(input) then
			return
		end
		touchJumpButtonHeld = false
		if CharacterController and CharacterController.ReleaseJump then
			CharacterController:ReleaseJump()
		end
	end)

	print("[iseesupes][LongJump] bound TouchGui JumpButton")
end

local function tryBindTouchGuiJumpButton()
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return false
	end

	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not touchGui then
		return false
	end

	local jumpButton = touchGui:FindFirstChild("JumpButton", true)
	if jumpButton and jumpButton:IsA("GuiButton") then
		bindTouchGuiJumpButton(jumpButton)
		return true
	end

	return false
end

local function watchForTouchGuiJumpButton()
	local playerGui = player:WaitForChild("PlayerGui")

	if tryBindTouchGuiJumpButton() then
		return
	end

	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "TouchGui" then
			task.defer(tryBindTouchGuiJumpButton)
		end
	end)

	playerGui.DescendantAdded:Connect(function(desc)
		if desc.Name == "JumpButton" and desc:IsA("GuiButton") then
			local touchGui = playerGui:FindFirstChild("TouchGui")
			if touchGui and desc:IsDescendantOf(touchGui) then
				task.defer(function()
					bindTouchGuiJumpButton(desc)
				end)
			end
		end
	end)
end

local function cleanupCharacter(character: Model)
	clearLongJumpArcActive()
	local state = characterStates[character]
	if not state then
		return
	end
	stopLeanUpAnim(state)
	if state.landResetConn then
		state.landResetConn:Disconnect()
		state.landResetConn = nil
	end
	if state.groundRayConn then
		state.groundRayConn:Disconnect()
		state.groundRayConn = nil
	end
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

	local now = os.clock()
	local state: CharacterLongJumpState = {
		character = character,
		humanoid = humanoid,
		leanUpTrack = leanUpTrack,
		animStopToken = 0,
		groundedConn = nil,
		landResetConn = nil,
		groundRayConn = nil,
		groundRayParams = makeGroundRayParams(character),
		airLongJumpCharges = 0,
		lastGroundedAt = now,
	}
	state.groundRayConn = RunService.Heartbeat:Connect(function()
		if characterStates[character] ~= state then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			touchGroundedTimestamp(state, humanoid, root)
		end
	end)
	state.landResetConn = humanoid.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			if player:GetAttribute(getArcActiveAttributeName()) == true then
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				-- High walk speed fires Running on launch; wait until descending before ending arc.
				if root and root.AssemblyLinearVelocity.Y > 2 then
					return
				end
				clearLongJumpArcActive()
			end
			onGrounded(state, humanoid)
		end
	end)
	characterStates[character] = state
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
	task.defer(watchForTouchGuiJumpButton)

	player.CharacterAdded:Connect(function(character)
		touchJumpButtonHeld = false
		clearLongJumpArcActive()
		airJumpReadyAt = 0
		cooldownEndsAt = 0
		publishLongJumpCounter(0)
		publishLongJumpReadyAt(0)
		setupCharacter(character)
	end)

	publishLongJumpCounter(0)
	publishLongJumpReadyAt(0)
	if player.Character then
		setupCharacter(player.Character)
	end

	StudioLog.ready("LongJumpController")
end

return LongJumpController

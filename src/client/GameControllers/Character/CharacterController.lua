--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

local Anim = CharacterConfigs.Animations
local Loc = CharacterConfigs.Locomotion
local JumpCfg = CharacterConfigs.BasicJump
local Features = CharacterConfigs.Features

local CharacterController = Knit.CreateController({ Name = "CharacterController" })

export type LocomotionSignal = "idle" | "run" | "landing"

local locomotionChanged = Instance.new("BindableEvent")

local player = Players.LocalPlayer
local animFolder: Folder? = nil
local jumpActionBound = false
local abilityBlocking = false
local jumpInterceptors: { () -> boolean } = {}
local treadmillController: any = nil

type AnimMode = "locomotion" | "jump" | "fall" | "landing"

type CharacterState = {
	character: Model,
	humanoid: Humanoid,
	idleTrack: AnimationTrack,
	runTrack: AnimationTrack,
	jumpTrack: AnimationTrack?,
	fallTrack: AnimationTrack?,
	landingTrack: AnimationTrack?,
	heartbeatConn: RBXScriptConnection?,
	stateChangedConn: RBXScriptConnection?,
	jumpStoppedConn: RBXScriptConnection?,
	landingStoppedConn: RBXScriptConnection?,
	mode: AnimMode,
	currentState: "idle" | "run" | "none",
	landingPlayed: boolean,
	airTime: number,
	hasLeftGround: boolean,
}

local characterStates: { [Model]: CharacterState } = {}
local setupRetryScheduled: { [Model]: boolean } = {}

local setupCharacter: (character: Model) -> boolean
local ensureCharacterReady: (character: Model) -> CharacterState?

local function getAnimFolder(): Folder?
	if animFolder then
		return animFolder
	end

	local folder = ReplicatedStorage:FindFirstChild(Anim.FolderName)
	if not folder or not folder:IsA("Folder") then
		warn("[iseesupes] Missing ReplicatedStorage." .. Anim.FolderName)
		return nil
	end

	animFolder = folder
	return animFolder
end

local function getAnimation(folder: Folder, name: string): Animation?
	local inst = folder:FindFirstChild(name)
	if inst and inst:IsA("Animation") then
		return inst
	end
	warn("[iseesupes] Missing Animation:", name, "in", Anim.FolderName)
	return nil
end

local function getAnimationInFolder(folder: Folder, subFolderName: string, animName: string): Animation?
	local sub = folder:FindFirstChild(subFolderName)
	if not sub then
		warn("[iseesupes] Missing folder:", subFolderName, "in", Anim.FolderName)
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

local function markLeftGroundIfNeeded(state: CharacterState, root: BasePart?)
	if state.hasLeftGround then
		return
	end

	local airDuration = os.clock() - state.airTime
	local velY = if root then root.AssemblyLinearVelocity.Y else 0

	if not isGrounded(state.humanoid) then
		state.hasLeftGround = true
	elseif airDuration >= JumpCfg.MinJumpAirTime and velY > JumpCfg.LeaveGroundVelocity then
		state.hasLeftGround = true
	end
end

local function canEnterFall(state: CharacterState, root: BasePart?): boolean
	if not state.hasLeftGround then
		return false
	end
	local velY = if root then root.AssemblyLinearVelocity.Y else 0
	return velY < JumpCfg.ApexVelocityThreshold
end

local function canEnterLandingFromFall(state: CharacterState, root: BasePart): boolean
	if not state.hasLeftGround then
		return false
	end
	if os.clock() - state.airTime < JumpCfg.MinFallTime then
		return false
	end
	return root.AssemblyLinearVelocity.Y <= 0
end

local function getRootPart(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function stopLocomotion(state: CharacterState)
	pcall(function()
		state.idleTrack:Stop(Loc.FadeTime)
		state.runTrack:Stop(Loc.FadeTime)
	end)
	state.currentState = "none"
end

local function stopAirAnims(state: CharacterState)
	pcall(function()
		if state.jumpTrack then
			state.jumpTrack:Stop(Loc.FadeTime)
		end
		if state.fallTrack then
			state.fallTrack:Stop(Loc.FadeTime)
		end
		if state.landingTrack then
			state.landingTrack:Stop(Loc.FadeTime)
		end
	end)
end

local function disconnectJumpLandingConns(state: CharacterState)
	if state.jumpStoppedConn then
		state.jumpStoppedConn:Disconnect()
		state.jumpStoppedConn = nil
	end
	if state.landingStoppedConn then
		state.landingStoppedConn:Disconnect()
		state.landingStoppedConn = nil
	end
end

local function isOnTreadmill(): boolean
	if not Features.ForceRunOnTreadmill then
		return false
	end
	if not treadmillController then
		treadmillController = Knit.GetController("TreadmillController")
	end
	return treadmillController ~= nil and treadmillController:IsOnTreadmill()
end

local function wantsRunLocomotion(humanoid: Humanoid): boolean
	return humanoid.MoveDirection.Magnitude > Loc.MoveThreshold or isOnTreadmill()
end

local function notifyLocomotion(character: Model, locomotion: LocomotionSignal)
	locomotionChanged:Fire(character, locomotion)
end

function CharacterController:ConnectLocomotionChanged(
	fn: (character: Model, locomotion: LocomotionSignal) -> ()
): RBXScriptConnection
	return locomotionChanged.Event:Connect(fn)
end

local function playLocomotion(state: CharacterState, locomotion: "idle" | "run")
	if not Features.UseCustomLocomotion then
		return
	end

	if state.currentState == locomotion then
		return
	end

	state.currentState = locomotion

	if locomotion == "run" then
		state.idleTrack:Stop(Loc.FadeTime)
		state.runTrack:Play(Loc.FadeTime)
	else
		state.runTrack:Stop(Loc.FadeTime)
		state.idleTrack:Play(Loc.FadeTime)
	end

	notifyLocomotion(state.character, locomotion)
end

local enterLocomotion: (state: CharacterState) -> ()
local enterFall: (state: CharacterState) -> ()
local enterLanding: (state: CharacterState) -> ()

enterLocomotion = function(state: CharacterState)
	if state.mode == "locomotion" then
		return
	end

	disconnectJumpLandingConns(state)
	stopAirAnims(state)
	state.mode = "locomotion"
	state.landingPlayed = false
	state.airTime = 0
	state.hasLeftGround = false

	if not Features.UseCustomLocomotion then
		return
	end

	playLocomotion(state, if wantsRunLocomotion(state.humanoid) then "run" else "idle")
end

enterFall = function(state: CharacterState)
	if not Features.UseBasicJumpAnims or not state.fallTrack then
		return
	end

	if state.mode == "fall" or state.mode == "landing" then
		return
	end

	local root = getRootPart(state.character)
	if not canEnterFall(state, root) then
		return
	end

	disconnectJumpLandingConns(state)
	stopLocomotion(state)
	stopAirAnims(state)

	state.mode = "fall"
	state.landingPlayed = false
	if state.airTime <= 0 then
		state.airTime = os.clock()
	end

	state.fallTrack:Play(Loc.FadeTime)
end

enterLanding = function(state: CharacterState)
	if not Features.UseBasicJumpAnims or not state.landingTrack then
		return
	end

	if state.mode == "landing" or state.landingPlayed then
		return
	end

	state.landingPlayed = true
	state.mode = "landing"

	stopLocomotion(state)
	if state.fallTrack then
		state.fallTrack:Stop(Loc.FadeTime)
	end
	if state.jumpTrack then
		state.jumpTrack:Stop(Loc.FadeTime)
	end

	state.landingTrack:Play(Loc.FadeTime)
	notifyLocomotion(state.character, "landing")

	disconnectJumpLandingConns(state)
	state.landingStoppedConn = state.landingTrack.Stopped:Connect(function()
		if isGrounded(state.humanoid) then
			enterLocomotion(state)
		end
	end)
end

local function enterJump(state: CharacterState)
	if not Features.UseBasicJumpAnims or not state.jumpTrack then
		return
	end

	if state.mode ~= "locomotion" then
		return
	end

	disconnectJumpLandingConns(state)
	stopLocomotion(state)
	stopAirAnims(state)

	state.mode = "jump"
	state.landingPlayed = false
	state.airTime = os.clock()
	state.hasLeftGround = false

	state.jumpTrack:Play(Loc.FadeTime)

	state.jumpStoppedConn = state.jumpTrack.Stopped:Connect(function()
		local root = getRootPart(state.character)
		markLeftGroundIfNeeded(state, root)
		if state.mode == "jump" and state.hasLeftGround and canEnterFall(state, root) then
			enterFall(state)
		end
	end)
end

local function resetAirAndLocomotionState(state: CharacterState, playLocomotionAnims: boolean)
	disconnectJumpLandingConns(state)
	stopAirAnims(state)
	state.mode = "locomotion"
	state.landingPlayed = false
	state.hasLeftGround = false
	state.airTime = 0

	if playLocomotionAnims and Features.UseCustomLocomotion then
		playLocomotion(state, if wantsRunLocomotion(state.humanoid) then "run" else "idle")
	else
		stopLocomotion(state)
	end
end

function CharacterController:SetAbilityBlocking(blocked: boolean)
	abilityBlocking = blocked

	local character = player.Character
	if not character then
		return
	end

	local state = characterStates[character]
	if not state then
		return
	end

	if blocked then
		resetAirAndLocomotionState(state, false)
	else
		resetAirAndLocomotionState(state, true)
	end
end

function CharacterController:IsAbilityBlocking(): boolean
	return abilityBlocking
end

function CharacterController:RegisterJumpInterceptor(fn: () -> boolean)
	table.insert(jumpInterceptors, fn)
end

local function tryCustomJump(character: Model)
	if not Features.UseCustomJump or abilityBlocking then
		return
	end

	local state = ensureCharacterReady(character)
	if not state then
		return
	end

	if state.mode ~= "locomotion" then
		return
	end

	if not isGrounded(state.humanoid) then
		return
	end

	local root = getRootPart(character)
	if not root then
		return
	end

	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, JumpCfg.JumpVelocity, velocity.Z)

	if Features.UseBasicJumpAnims then
		enterJump(state)
	end
end

local function onJumpAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	local character = player.Character
	if not character then
		return Enum.ContextActionResult.Pass
	end

	for _, interceptor in jumpInterceptors do
		if interceptor() then
			return Enum.ContextActionResult.Sink
		end
	end

	tryCustomJump(character)
	return Enum.ContextActionResult.Sink
end

local function bindJumpAction()
	if not Features.UseCustomJump or jumpActionBound then
		return
	end
	jumpActionBound = true
	ContextActionService:BindAction(JumpCfg.JumpActionName, onJumpAction, false, Enum.KeyCode.Space)
end

local function cleanupCharacter(character: Model)
	local state = characterStates[character]
	if not state then
		return
	end

	if state.heartbeatConn then
		state.heartbeatConn:Disconnect()
	end
	if state.stateChangedConn then
		state.stateChangedConn:Disconnect()
	end
	disconnectJumpLandingConns(state)

	pcall(function()
		stopLocomotion(state)
		stopAirAnims(state)
	end)

	characterStates[character] = nil
end

local function scheduleSetupRetry(character: Model, _reason: string)
	if setupRetryScheduled[character] then
		return
	end
	setupRetryScheduled[character] = true
	task.defer(function()
		setupRetryScheduled[character] = nil
		if character.Parent then
			setupCharacter(character)
		end
	end)
end

function setupCharacter(character: Model): boolean
	cleanupCharacter(character)

	local folder = getAnimFolder()
	if not folder then
		scheduleSetupRetry(character, "no_anim_folder")
		return false
	end

	local idleAnim = getAnimation(folder, Anim.Idle)
	local runAnim = getAnimation(folder, Anim.Run)
	if not idleAnim or not runAnim then
		scheduleSetupRetry(character, "missing_locomotion_anims")
		return false
	end

	local jumpAnim: Animation? = nil
	local fallAnim: Animation? = nil
	local landingAnim: Animation? = nil

	if Features.UseBasicJumpAnims then
		jumpAnim = getAnimationInFolder(folder, Anim.BasicJumpFolder, Anim.Jump)
		fallAnim = getAnimationInFolder(folder, Anim.BasicJumpFolder, Anim.Fall)
		landingAnim = getAnimationInFolder(folder, Anim.BasicJumpFolder, Anim.Landing)
		if not jumpAnim or not fallAnim or not landingAnim then
			scheduleSetupRetry(character, "missing_jump_anims")
			return false
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	end
	if not humanoid then
		scheduleSetupRetry(character, "no_humanoid")
		return false
	end

	if Features.DisableDefaultAnimate then
		local animate = character:FindFirstChild("Animate")
		if animate and animate:IsA("LocalScript") then
			animate.Disabled = true
		end
	end

	if Features.UseCustomJump then
		humanoid.JumpHeight = 0
		humanoid.UseJumpPower = true
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local idleTrack = animator:LoadAnimation(idleAnim)
	local runTrack = animator:LoadAnimation(runAnim)

	idleTrack.Looped = true
	runTrack.Looped = true
	idleTrack.Priority = Enum.AnimationPriority.Idle
	runTrack.Priority = Enum.AnimationPriority.Movement

	local jumpTrack: AnimationTrack? = nil
	local fallTrack: AnimationTrack? = nil
	local landingTrack: AnimationTrack? = nil

	if Features.UseBasicJumpAnims and jumpAnim and fallAnim and landingAnim then
		jumpTrack = animator:LoadAnimation(jumpAnim)
		fallTrack = animator:LoadAnimation(fallAnim)
		landingTrack = animator:LoadAnimation(landingAnim)

		fallTrack.Looped = true
		jumpTrack.Looped = false
		landingTrack.Looped = false
		jumpTrack.Priority = Enum.AnimationPriority.Action
		fallTrack.Priority = Enum.AnimationPriority.Action
		landingTrack.Priority = Enum.AnimationPriority.Action
	end

	local state: CharacterState = {
		character = character,
		humanoid = humanoid,
		idleTrack = idleTrack,
		runTrack = runTrack,
		jumpTrack = jumpTrack,
		fallTrack = fallTrack,
		landingTrack = landingTrack,
		heartbeatConn = nil,
		stateChangedConn = nil,
		jumpStoppedConn = nil,
		landingStoppedConn = nil,
		mode = "locomotion",
		currentState = "idle",
		landingPlayed = false,
		airTime = 0,
		hasLeftGround = false,
	}
	characterStates[character] = state

	if Features.UseCustomLocomotion then
		idleTrack:Play(Loc.FadeTime)
		notifyLocomotion(character, "idle")
	end

	if Features.UseBasicJumpAnims then
		state.stateChangedConn = humanoid.StateChanged:Connect(function(_old, new)
			if abilityBlocking then
				return
			end

			if new == Enum.HumanoidStateType.Freefall then
				local root = getRootPart(character)
				markLeftGroundIfNeeded(state, root)
				if (state.mode == "locomotion" or state.mode == "jump") and canEnterFall(state, root) then
					enterFall(state)
				end
			elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				if isGrounded(humanoid) and state.mode == "fall" and not state.landingPlayed then
					local root = getRootPart(character)
					if root and canEnterLandingFromFall(state, root) then
						enterLanding(state)
					elseif state.mode == "fall" then
						enterLocomotion(state)
					end
				end
			end
		end)
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	state.heartbeatConn = RunService.Heartbeat:Connect(function()
		if humanoid.Health <= 0 then
			return
		end

		if abilityBlocking then
			return
		end

		if Features.UseBasicJumpAnims and state.mode == "fall" then
			local root = getRootPart(character)
			if root and not state.landingPlayed then
				local fallDuration = os.clock() - state.airTime
				if fallDuration >= JumpCfg.MinFallTime then
					local hit = workspace:Raycast(
						root.Position,
						Vector3.new(0, -JumpCfg.LandingRayDistance, 0),
						rayParams
					)
					if hit and root.AssemblyLinearVelocity.Y < 0 then
						enterLanding(state)
					end
				end
			end

			if root and not state.landingPlayed and canEnterLandingFromFall(state, root) and isGrounded(humanoid) then
				enterLanding(state)
			end
			return
		end

		if Features.UseBasicJumpAnims and state.mode == "landing" then
			if state.landingTrack and isGrounded(humanoid) and not state.landingTrack.IsPlaying then
				enterLocomotion(state)
			end
			return
		end

		if Features.UseBasicJumpAnims and state.mode == "jump" then
			local root = getRootPart(character)
			if root then
				markLeftGroundIfNeeded(state, root)

				if canEnterFall(state, root) then
					enterFall(state)
				end
			end
			return
		end

		if state.mode ~= "locomotion" then
			return
		end

		playLocomotion(state, if wantsRunLocomotion(humanoid) then "run" else "idle")
	end)

	humanoid.Died:Once(function()
		cleanupCharacter(character)
	end)
	character.Destroying:Once(function()
		cleanupCharacter(character)
	end)

	return true
end

function ensureCharacterReady(character: Model): CharacterState?
	local existing = characterStates[character]
	if existing then
		return existing
	end

	if setupCharacter(character) then
		return characterStates[character]
	end

	local folder = ReplicatedStorage:FindFirstChild(Anim.FolderName)
	if not folder then
		folder = ReplicatedStorage:WaitForChild(Anim.FolderName, 3)
	end
	if folder and folder:IsA("Folder") then
		animFolder = folder
		setupCharacter(character)
	end

	return characterStates[character]
end

function CharacterController:KnitStart()
	local folder = ReplicatedStorage:WaitForChild(Anim.FolderName, 30)
	if folder and folder:IsA("Folder") then
		animFolder = folder
	else
		warn("[iseesupes] Timed out waiting for", Anim.FolderName)
	end

	task.defer(bindJumpAction)

	treadmillController = Knit.GetController("TreadmillController")

	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end

	print("[iseesupes] CharacterController ready.")
end

return CharacterController

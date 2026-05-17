--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)

local AnimRoot = CharacterConfigs.Animations
local Loc = CharacterConfigs.Locomotion
local DjCfg = CharacterConfigs.DoubleJump
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
}

local characterStates: { [Model]: CharacterAbilityState } = {}

local CharacterController: any = nil

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

local function stopAllTracks(state: CharacterAbilityState)
	local tracks = state.tracks
	pcall(function()
		tracks.flightTransit:Stop(Loc.FadeTime)
		tracks.afterTransition:Stop(Loc.FadeTime)
		tracks.leanUp:Stop(Loc.FadeTime)
		tracks.leapDown:Stop(Loc.FadeTime)
		tracks.downSupes:Stop(Loc.FadeTime)
		tracks.fall:Stop(Loc.FadeTime)
		tracks.landing:Stop(Loc.FadeTime)
	end)
	state.currentTrack = nil
end

local function stopCurrentTrack(state: CharacterAbilityState)
	if state.currentTrack then
		pcall(function()
			state.currentTrack:Stop(Loc.FadeTime)
		end)
		state.currentTrack = nil
	end
end

local function playTrack(state: CharacterAbilityState, track: AnimationTrack)
	stopCurrentTrack(state)
	state.currentTrack = track
	track:Play(Loc.FadeTime)
end

local function playPhaseAnim(state: CharacterAbilityState, phase: string)
	local tracks = state.tracks
	if phase == PHASE.FlightTransit then
		playTrack(state, tracks.flightTransit)
	elseif phase == PHASE.AfterTransition then
		playTrack(state, tracks.afterTransition)
	elseif phase == PHASE.LeanUp then
		playTrack(state, tracks.leanUp)
	elseif phase == PHASE.LeapDown then
		playTrack(state, tracks.leapDown)
	elseif phase == PHASE.DownSupes then
		playTrack(state, tracks.downSupes)
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

local function onAbilityEnded()
	abilityActive = false
	holdingLocally = false
	currentPhase = nil

	local character = player.Character
	if character then
		local state = characterStates[character]
		if state then
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
		end
	end
end

local function onPhaseChanged(phase: string)
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

	local function loadTrack(anim: Animation, looped: boolean): AnimationTrack
		local track = animator:LoadAnimation(anim)
		track.Looped = looped
		track.Priority = Enum.AnimationPriority.Action2
		return track
	end

	local tracks: AbilityTracks = {
		flightTransit = loadTrack(flightAnim, false),
		afterTransition = loadTrack(afterAnim, true),
		leanUp = loadTrack(leanAnim, false),
		leapDown = loadTrack(leapAnim, false),
		downSupes = loadTrack(downAnim, false),
		fall = loadTrack(fallAnim, true),
		landing = loadTrack(landingAnim, false),
	}

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local state: CharacterAbilityState = {
		character = character,
		humanoid = humanoid,
		tracks = tracks,
		currentTrack = nil,
		heartbeatConn = nil,
		rayParams = rayParams,
		cancelFallStartedAt = nil,
		landingPlayed = false,
	}
	characterStates[character] = state

	state.heartbeatConn = RunService.Heartbeat:Connect(function()
		if not abilityActive or currentPhase ~= PHASE.CancelFall then
			return
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or state.landingPlayed then
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
			root.Position,
			Vector3.new(0, -DjCfg.Cancel.LandingRayDistance, 0),
			state.rayParams
		)
		if hit and root.AssemblyLinearVelocity.Y < 0 then
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
				setAbilityBlocking(true)
				service:SetHolding(true)

				local character = player.Character
				if character and not characterStates[character] then
					setupCharacter(character)
				end

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

	local DoubleJumpService = getDoubleJumpService()

	DoubleJumpService.PhaseChanged:Connect(function(phase: string)
		if not abilityActive and phase == PHASE.FlightTransit then
			abilityActive = true
			setAbilityBlocking(true)
			local character = player.Character
			if character and not characterStates[character] then
				setupCharacter(character)
			end
		end
		onPhaseChanged(phase)
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

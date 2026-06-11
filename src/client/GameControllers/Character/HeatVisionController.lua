--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local HeatVisionConfigs = require(ReplicatedStorage.Shared.Configs.HeatVisionConfigs)
local HeatVisionCamera = require(script.Parent.Parent.Parent.Modules.HeatVisionCamera)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)
local SupermanGroundVfx = require(script.Parent.Parent.Parent.Modules.SupermanGroundVfx)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local Features = CharacterConfigs.Features

local DJ_PHASE_ATTR = "DjAbilityPhase"
local SJ_PHASE_ATTR = "SjAbilityPhase"

local KEY_CODES: { [string]: Enum.KeyCode } = {
	F = Enum.KeyCode.F,
	ButtonX = Enum.KeyCode.ButtonX,
	ButtonY = Enum.KeyCode.ButtonY,
	ButtonB = Enum.KeyCode.ButtonB,
	ButtonL1 = Enum.KeyCode.ButtonL1,
	ButtonR1 = Enum.KeyCode.ButtonR1,
}

local HeatVisionController = Knit.CreateController({ Name = "HeatVisionController" })

local player = Players.LocalPlayer

local HeatVisionService: any = nil
local StageCheckpointController: any = nil
local actionBound = false
local localActive = false
local aimRenderBound = false
local lastAimSendAt = 0
local lastFakeBreakAt = 0
local lastFakeBreakPos: Vector3? = nil
local lastRejectedToastAt = -math.huge

local aimSendInterval = 1 / math.max(HeatVisionConfigs.AimSendHz, 1)
local AIM_RENDER_STEP = "HeatVisionAim"

local function isFlying(): boolean
	local djPhase = player:GetAttribute(DJ_PHASE_ATTR)
	if djPhase ~= nil and djPhase ~= "" then
		return true
	end
	local sjPhase = player:GetAttribute(SJ_PHASE_ATTR)
	return sjPhase ~= nil and sjPhase ~= ""
end

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function notifyRejected(reason: string?)
	local now = os.clock()
	if now - lastRejectedToastAt < 0.6 then
		return
	end
	lastRejectedToastAt = now
	if reason == "no_solar" then
		NotificationManager.show("Fly to recharge solar energy for heat vision", "Info")
	elseif reason == "active" then
		return
	elseif reason == "cooldown" then
		NotificationManager.show("Laser beam recharging...", "Info")
	elseif reason == "no_rig" then
		NotificationManager.show("Heat vision assets missing", "Info")
	elseif reason == "flying" then
		NotificationManager.show("Can't use heat vision while flying", "Info")
	else
		NotificationManager.show("Heat vision unavailable", "Info")
	end
end

local function buildRayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	local filter: { Instance } = {}
	if character then
		table.insert(filter, character)
		local rig = character:FindFirstChild("HeatVisionRig")
		if rig then
			table.insert(filter, rig)
		end
	end
	local glassFolder = SupermanGroundVfx.getGlassBreakVfxFolder()
	if glassFolder then
		table.insert(filter, glassFolder)
	end
	local metalFolder = SupermanGroundVfx.getMetalMeltVfxFolder()
	if metalFolder then
		table.insert(filter, metalFolder)
	end
	if #filter > 0 then
		params.FilterDescendantsInstances = filter
	end
	return params
end

local rayParams: RaycastParams = buildRayParams()

local function tryFakeDestruction()
	local cam = getCamera()
	local character = player.Character
	if not cam or not character then
		return
	end

	local origin = cam.CFrame.Position + cam.CFrame.LookVector * HeatVisionConfigs.CameraRayOriginForward
	local direction = cam.CFrame.LookVector
	local result = Workspace:Raycast(origin, direction * HeatVisionConfigs.MaxRange, buildRayParams())
	if not result then
		return
	end

	if HeatVisionConfigs.CheckpointDamageEnabled and StageCheckpointWorld.isCheckpointHit(result.Instance) then
		local stageNum = StageCheckpointWorld.getCheckpointFromHit(result.Instance)
		local nextMeltGate = if StageCheckpointController and StageCheckpointController.GetNextMeltGateStage
			then StageCheckpointController:GetNextMeltGateStage()
			else nil
		if stageNum and nextMeltGate and stageNum == nextMeltGate and result.Instance:IsA("BasePart") then
			local now = os.clock()
			if now - lastFakeBreakAt < HeatVisionConfigs.FakeDestruction.Interval then
				return
			end
			local minMove = HeatVisionConfigs.FakeDestruction.MinMoveDistance
			if lastFakeBreakPos and (result.Position - lastFakeBreakPos).Magnitude < minMove then
				return
			end
			lastFakeBreakAt = now
			lastFakeBreakPos = result.Position
			SupermanGroundVfx.spawnGateMetalMeltImpact(
				result.Instance :: BasePart,
				result.Position,
				result.Normal
			)
		end
		return
	end

	local now = os.clock()
	if now - lastFakeBreakAt < HeatVisionConfigs.FakeDestruction.Interval then
		return
	end

	local minMove = HeatVisionConfigs.FakeDestruction.MinMoveDistance
	if lastFakeBreakPos and (result.Position - lastFakeBreakPos).Magnitude < minMove then
		return
	end

	lastFakeBreakAt = now
	lastFakeBreakPos = result.Position
	SupermanGroundVfx.spawnHeatMeltAt(result, character, direction, HeatVisionConfigs.FakeDestruction.ChipCount)
end

local function stopAimLoop()
	localActive = false
	HeatVisionCamera.stop()
	if aimRenderBound then
		RunService:UnbindFromRenderStep(AIM_RENDER_STEP)
		aimRenderBound = false
	end

	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.AutoRotate = true
	end
end

local function onAimRenderStep(_dt: number)
	if not localActive then
		return
	end

	local character = player.Character
	local cam = getCamera()
	if not character or not cam or not HeatVisionService then
		return
	end

	local now = os.clock()
	if now - lastAimSendAt >= aimSendInterval then
		lastAimSendAt = now
		HeatVisionService:UpdateAim(cam.CFrame.LookVector)
	end

	tryFakeDestruction()
end

local function startAimLoop()
	if aimRenderBound then
		return
	end

	local character = player.Character
	if character then
		HeatVisionCamera.start(character)
	end

	local cam = getCamera()
	if cam and HeatVisionService then
		HeatVisionService:UpdateAim(cam.CFrame.LookVector)
		lastAimSendAt = os.clock()
	end

	localActive = true
	lastFakeBreakAt = 0
	lastFakeBreakPos = nil
	rayParams = buildRayParams()

	aimRenderBound = true
	RunService:BindToRenderStep(AIM_RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, onAimRenderStep)
end

function HeatVisionController:Cancel()
	if not localActive and player:GetAttribute(HeatVisionConfigs.Attributes.Active) ~= true then
		return
	end

	stopAimLoop()

	if HeatVisionService then
		HeatVisionService:RequestCancel():catch(warn)
	end
end

function HeatVisionController:Begin()
	if localActive or player:GetAttribute(HeatVisionConfigs.Attributes.Active) == true then
		HeatVisionController:Cancel()
		return
	end
	if isFlying() then
		notifyRejected("flying")
		return
	end
	if not HeatVisionService then
		return
	end

	HeatVisionService:RequestStart()
		:andThen(function(ok: boolean, reason: string?)
			if ok then
				startAimLoop()
			else
				notifyRejected(reason)
			end
		end)
		:catch(warn)
end

function HeatVisionController:IsLocalActive(): boolean
	return localActive
end

local function onHeatVisionAction(_name: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if not Features.UseHeatVision then
		return Enum.ContextActionResult.Pass
	end

	HeatVisionController:Begin()
	return Enum.ContextActionResult.Sink
end

local function bindAction()
	if actionBound or not Features.UseHeatVision then
		return
	end

	local keyCode = KEY_CODES[HeatVisionConfigs.Key]
	if not keyCode then
		warn("[iseesupes][HeatVision] Unknown key:", HeatVisionConfigs.Key)
		return
	end

	local inputs: { Enum.KeyCode } = { keyCode }
	local gamepadKey = KEY_CODES[HeatVisionConfigs.GamepadKey]
	if gamepadKey then
		table.insert(inputs, gamepadKey)
	end

	actionBound = true
	ContextActionService:BindAction(HeatVisionConfigs.ActionName, onHeatVisionAction, false, table.unpack(inputs))
end

function HeatVisionController:KnitStart()
	HeatVisionService = Knit.GetService("HeatVisionService")
	StageCheckpointController = Knit.GetController("StageCheckpointController")

	bindAction()

	HeatVisionService.AbilityEnded:Connect(function()
		stopAimLoop()
	end)

	HeatVisionService.Rejected:Connect(function(reason: string)
		notifyRejected(reason)
	end)

	player.CharacterAdded:Connect(function()
		stopAimLoop()
		rayParams = buildRayParams()
	end)

	player:GetAttributeChangedSignal(HeatVisionConfigs.Attributes.Active):Connect(function()
		if player:GetAttribute(HeatVisionConfigs.Attributes.Active) ~= true then
			stopAimLoop()
		end
	end)
end

return HeatVisionController

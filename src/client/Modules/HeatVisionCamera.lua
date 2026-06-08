--!strict

-- Shift-lock-style over-the-shoulder camera during heat vision.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarReplace = require(ReplicatedStorage.Shared.Utils.AvatarReplace)
local HeatVisionConfigs = require(ReplicatedStorage.Shared.Configs.HeatVisionConfigs)

local HeatVisionCamera = {}

local player = Players.LocalPlayer

type SavedCameraState = {
	cameraType: Enum.CameraType?,
	cameraSubject: Instance?,
	mouseBehavior: Enum.MouseBehavior?,
	mouseIconEnabled: boolean?,
}

local active = false
local yaw = 0
local pitch = 0
local saved: SavedCameraState = {}
local renderStepBound = false

local function getRootPart(character: Model): BasePart?
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function getYawPitchFromLookVector(look: Vector3): (number, number)
	if look.Magnitude < 0.001 then
		return yaw, pitch
	end

	local unit = look.Unit
	local horizontalMag = math.sqrt(unit.X * unit.X + unit.Z * unit.Z)
	if horizontalMag < 0.001 then
		return yaw, math.atan2(-unit.Y, 1)
	end

	local extractedPitch = math.atan2(-unit.Y, horizontalMag)
	local extractedYaw = math.atan2(unit.X, -unit.Z)
	return extractedYaw, extractedPitch
end

local function initAimFromCamera(camera: Camera, cfg: typeof(HeatVisionConfigs.CameraLock))
	local extractedYaw, extractedPitch = getYawPitchFromLookVector(camera.CFrame.LookVector)
	yaw = extractedYaw
	pitch = math.clamp(extractedPitch, cfg.MinPitch, cfg.MaxPitch)
end

local function getSensitivityScale(): number
	local cfg = HeatVisionConfigs.CameraLock
	if UserInputService.TouchEnabled then
		return cfg.TouchSensitivityScale or 1
	end
	return 1
end

local function applyBodyYaw(root: BasePart)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
end

local function getControlsMoveVector(): Vector3
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return Vector3.zero
	end

	local playerModuleScript = playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript or not playerModuleScript:IsA("ModuleScript") then
		return Vector3.zero
	end

	local ok, controls = pcall(function()
		return require(playerModuleScript):GetControls()
	end)
	if not ok or not controls then
		return Vector3.zero
	end

	local okMove, moveVector = pcall(function()
		return controls:GetMoveVector()
	end)
	if not okMove or typeof(moveVector) ~= "Vector3" then
		return Vector3.zero
	end
	return moveVector
end

local function applyCameraRelativeMove(humanoid: Humanoid)
	local moveVector = getControlsMoveVector()
	if moveVector.Magnitude < 0.01 then
		return
	end
	humanoid:Move(moveVector, true)
end

local function updateCamera(character: Model)
	local cfg = HeatVisionConfigs.CameraLock
	local camera = Workspace.CurrentCamera
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = getRootPart(character)
	if not camera or not humanoid or not root then
		return
	end

	local scale = getSensitivityScale()
	local delta = UserInputService:GetMouseDelta()
	local mouseMoved = delta.Magnitude > 0.001

	if mouseMoved then
		yaw -= delta.X * cfg.YawSensitivity * scale
		pitch = math.clamp(pitch - delta.Y * cfg.PitchSensitivity * scale, cfg.MinPitch, cfg.MaxPitch)
		applyBodyYaw(root)
	end

	local rootPos = root.Position
	local facing = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)
	local focus = rootPos + Vector3.new(0, cfg.LookAtHeight, 0)
	local camPos = focus
		- facing.LookVector * cfg.ShoulderOffset.Z
		+ facing.RightVector * cfg.ShoulderOffset.X
		+ Vector3.new(0, cfg.ShoulderOffset.Y, 0)
	camera.CFrame = CFrame.lookAt(camPos, focus + facing.LookVector * 200)

	applyCameraRelativeMove(humanoid)
end

local function onRenderStep(_dt: number)
	if not active then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	updateCamera(character)
end

local function bindRenderStep()
	if renderStepBound then
		return
	end
	renderStepBound = true
	RunService:BindToRenderStep("HeatVisionCamera", Enum.RenderPriority.Camera.Value, onRenderStep)
end

local function unbindRenderStep()
	if not renderStepBound then
		return
	end
	renderStepBound = false
	RunService:UnbindFromRenderStep("HeatVisionCamera")
end

local function resetPlayerModuleCamera()
	local playerScripts = player:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return
	end

	local playerModuleScript = playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript or not playerModuleScript:IsA("ModuleScript") then
		return
	end

	pcall(function()
		local playerModule = require(playerModuleScript)
		local cameras = playerModule:GetCameras()
		if not cameras then
			return
		end

		if cameras.ActivateCameraController then
			cameras:ActivateCameraController(Enum.CameraControllerType.Classic)
		end

		local controller = cameras.activeCameraController
		if controller then
			if controller.Enable then
				controller:Enable(false)
				controller:Enable(true)
			elseif controller.SetEnabled then
				controller:SetEnabled(false)
				controller:SetEnabled(true)
			end
		end
	end)
end

local function snapCameraToPlayer(humanoid: Humanoid)
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end

	AvatarReplace.snapLocalCamera(humanoid.Parent)
	humanoid.AutoRotate = true
	resetPlayerModuleCamera()
end

local function releaseDefaultControls()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		snapCameraToPlayer(humanoid)
	end
end

local function scheduleCameraRecovery()
	task.defer(function()
		if active then
			return
		end
		releaseDefaultControls()
	end)

	task.delay(0.05, function()
		if active then
			return
		end
		releaseDefaultControls()
	end)
end

function HeatVisionCamera.isActive(): boolean
	return active
end

function HeatVisionCamera.update(_character: Model)
	-- Camera runs on BindToRenderStep at Camera priority.
end

function HeatVisionCamera.start(character: Model): boolean
	if not HeatVisionConfigs.CameraLock.Enabled then
		return false
	end
	if active then
		return true
	end

	local cfg = HeatVisionConfigs.CameraLock
	local camera = Workspace.CurrentCamera
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = getRootPart(character)
	if not camera or not humanoid or not root then
		return false
	end

	saved = {
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		mouseBehavior = UserInputService.MouseBehavior,
		mouseIconEnabled = UserInputService.MouseIconEnabled,
	}

	initAimFromCamera(camera, cfg)

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	camera.CameraType = Enum.CameraType.Scriptable
	humanoid.AutoRotate = false

	active = true
	updateCamera(character)
	bindRenderStep()

	return true
end

function HeatVisionCamera.stop()
	local wasRunning = active or renderStepBound

	active = false
	unbindRenderStep()

	if wasRunning then
		releaseDefaultControls()
		scheduleCameraRecovery()
	else
		local camera = Workspace.CurrentCamera
		if camera and camera.CameraType == Enum.CameraType.Scriptable then
			releaseDefaultControls()
			scheduleCameraRecovery()
		end
	end

	table.clear(saved)
end

return HeatVisionCamera

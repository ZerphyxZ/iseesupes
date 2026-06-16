--!strict

-- Scriptable follow camera during AutoFly routes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AutoFlyConfigs = require(ReplicatedStorage.Shared.Configs.AutoFlyConfigs)

local AutoFlyCamera = {}

local active = false
local releasing = false
local releaseConn: RBXScriptConnection? = nil
local releaseStartedAt = 0
local savedCameraType: Enum.CameraType? = nil
local savedCameraSubject: Instance? = nil
local smoothedCFrame: CFrame? = nil
local landingBlend = 0

local function getRoot(): BasePart?
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getFlatBackFromRoot(root: BasePart): Vector3
	local back = -root.CFrame.LookVector
	local flat = Vector3.new(back.X, 0, back.Z)
	if flat.Magnitude > 0.05 then
		return flat.Unit
	end
	return back
end

local function computeDefaultPlayerCameraCFrame(root: BasePart): CFrame
	local cfg = AutoFlyConfigs
	local offset = cfg.CameraReleaseOffset
	if typeof(offset) ~= "Vector3" then
		offset = Vector3.new(0, 2, 12)
	end
	local lookAtYOffset = cfg.CameraReleaseLookAtYOffset
	if typeof(lookAtYOffset) ~= "number" then
		lookAtYOffset = 2
	end

	local back = -root.CFrame.LookVector
	local flat = Vector3.new(back.X, 0, back.Z)
	if flat.Magnitude > 0.05 then
		back = flat.Unit
	end

	local camPos = root.Position + Vector3.new(0, offset.Y, 0) + back * offset.Z + back:Cross(Vector3.yAxis) * offset.X
	local lookAt = root.Position + Vector3.new(0, lookAtYOffset, 0)
	return CFrame.lookAt(camPos, lookAt)
end

local function restoreDefaultCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local player = Players.LocalPlayer
	local character = player.Character
	local hum = if character then character:FindFirstChildOfClass("Humanoid") else nil

	local restoreType = savedCameraType
	if restoreType == nil or restoreType == Enum.CameraType.Scriptable then
		restoreType = Enum.CameraType.Custom
	end
	camera.CameraType = restoreType
	if hum then
		camera.CameraSubject = hum
	elseif savedCameraSubject and savedCameraSubject:IsDescendantOf(game) then
		-- Never re-pin a destroyed subject (the previous character, when the new one
		-- has not streamed in yet). Leaving it for the CameraWatchdog to re-attach to
		-- the live humanoid avoids a frozen camera on a slow cold join.
		camera.CameraSubject = savedCameraSubject
	end

	savedCameraType = nil
	savedCameraSubject = nil
end

local function finishRelease()
	if releaseConn then
		releaseConn:Disconnect()
		releaseConn = nil
	end
	releasing = false
	smoothedCFrame = nil
	restoreDefaultCamera()
end

local function cancelRelease()
	if releaseConn then
		releaseConn:Disconnect()
		releaseConn = nil
	end
	releasing = false
end

local function tickRelease(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		finishRelease()
		return
	end

	local root = getRoot()
	if not root then
		finishRelease()
		return
	end

	local cfg = AutoFlyConfigs
	local duration = cfg.CameraReleaseDuration
	if typeof(duration) ~= "number" or duration <= 0 then
		duration = 0.75
	end
	local rate = cfg.CameraReleaseSmoothRate
	if typeof(rate) ~= "number" or rate <= 0 then
		rate = 6
	end
	local finishDist = cfg.CameraReleaseFinishDistance
	if typeof(finishDist) ~= "number" then
		finishDist = 0.4
	end

	local elapsed = os.clock() - releaseStartedAt
	local progress = math.min(1, elapsed / duration)
	local easedRate = rate * (1 - 0.7 * progress * progress)
	local alpha = math.min(1, easedRate * dt)

	local targetCF = computeDefaultPlayerCameraCFrame(root)
	if smoothedCFrame then
		smoothedCFrame = smoothedCFrame:Lerp(targetCF, alpha)
	else
		smoothedCFrame = targetCF
	end
	camera.CFrame = smoothedCFrame

	local dist = (smoothedCFrame.Position - targetCF.Position).Magnitude
	if dist <= finishDist or elapsed >= duration then
		finishRelease()
	end
end

function AutoFlyCamera.isActive(): boolean
	return active
end

-- True while the auto-fly camera legitimately owns CurrentCamera — either following a
-- route or smoothly releasing it. The camera watchdog uses this to distinguish an
-- intentional Scriptable camera from a leaked one.
function AutoFlyCamera.isBusy(): boolean
	return active or releasing
end

function AutoFlyCamera.startFollow(_character: Model)
	cancelRelease()
	landingBlend = 0

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- Never capture Scriptable as the restore target: re-engaging auto-fly before a
	-- previous release finished (or grabbing while another cutscene owns the camera)
	-- would otherwise restore to a locked, uncontrollable camera — a permanent soft-lock.
	local currentType = camera.CameraType
	savedCameraType = if currentType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else currentType
	savedCameraSubject = camera.CameraSubject
	smoothedCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	active = true
end

function AutoFlyCamera.update(dt: number, root: BasePart, destination: BasePart, isLanding: boolean?)
	if not active then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local cfg = AutoFlyConfigs
	local flightOffset = cfg.CameraOffset
	if typeof(flightOffset) ~= "Vector3" then
		flightOffset = Vector3.new(0, 10, 22)
	end
	local lookAhead = cfg.CameraLookAhead
	if typeof(lookAhead) ~= "number" then
		lookAhead = 8
	end
	local lookAtYOffset = cfg.CameraLookAtYOffset
	if typeof(lookAtYOffset) ~= "number" then
		lookAtYOffset = 14
	end

	local landingOffset = cfg.CameraLandingOffset
	if typeof(landingOffset) ~= "Vector3" then
		landingOffset = Vector3.new(0, 2, 18)
	end
	local landingLookAtYOffset = cfg.CameraLandingLookAtYOffset
	if typeof(landingLookAtYOffset) ~= "number" then
		landingLookAtYOffset = 2
	end

	if isLanding then
		local blendSeconds = cfg.CameraLandingBlendSeconds
		if typeof(blendSeconds) ~= "number" or blendSeconds <= 0 then
			blendSeconds = 0.3
		end
		landingBlend = math.min(1, landingBlend + dt / blendSeconds)
	else
		landingBlend = 0
	end

	local toTarget = destination.Position - root.Position
	local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
	local back = if flat.Magnitude > 0.05 then -flat.Unit else -root.CFrame.LookVector
	if isLanding and landingBlend > 0 then
		back = getFlatBackFromRoot(root)
	end

	local offset = if isLanding then flightOffset:Lerp(landingOffset, landingBlend) else flightOffset
	local camPos = root.Position + Vector3.new(0, offset.Y, 0) + back * offset.Z + back:Cross(Vector3.yAxis) * offset.X

	local flightLookAt = destination.Position + Vector3.new(0, lookAtYOffset + lookAhead * 0.25, 0)
	local landingLookAt = root.Position + Vector3.new(0, landingLookAtYOffset, 0)
	local lookAt = if isLanding then flightLookAt:Lerp(landingLookAt, landingBlend) else flightLookAt

	local targetCF = CFrame.lookAt(camPos, lookAt)

	if smoothedCFrame then
		local rate = cfg.CameraSmoothRate
		if typeof(rate) ~= "number" or rate <= 0 then
			rate = 8
		end
		local alpha = math.min(1, rate * dt)
		smoothedCFrame = smoothedCFrame:Lerp(targetCF, alpha)
		camera.CFrame = smoothedCFrame
	else
		smoothedCFrame = targetCF
		camera.CFrame = targetCF
	end
end

function AutoFlyCamera.release()
	if not active and not releasing then
		return
	end
	if releasing then
		return
	end

	active = false
	landingBlend = 0

	local camera = workspace.CurrentCamera
	if not camera then
		finishRelease()
		return
	end

	local root = getRoot()
	if not root then
		finishRelease()
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	releasing = true
	releaseStartedAt = os.clock()

	if releaseConn then
		releaseConn:Disconnect()
	end
	releaseConn = RunService.RenderStepped:Connect(tickRelease)
end

return AutoFlyCamera

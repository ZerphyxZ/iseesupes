--!strict

-- Uses StarterGui → TutorialLaserHintGui (layout authored in Studio). Runtime: enable/disable only.
-- Shown at Stage 1 while the melt wall is unbroken; hidden by TutorialController on CheckpointBroken.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)
local VisionMobileUI = require(ReplicatedStorage.Shared.Utils.VisionMobileUI)
local HudAnimations = require(script.Parent.HudAnimations)

local TutorialLaserHint = {}

local player = Players.LocalPlayer

type HintLayer = {
	screenGui: ScreenGui,
	callout: Frame?,
	arrow: ImageLabel?,
	heartbeatTarget: GuiObject,
	arrowBobConn: RBXScriptConnection?,
	arrowBasePosition: UDim2?,
}

local activeLayer: HintLayer? = nil

local function getLaserIntroCfg(): any
	return TutorialConfigs.LaserIntro or {}
end

local function isMobile(): boolean
	return UserInputService.TouchEnabled
end

local function isGamepad(): boolean
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
end

local function getLabelText(): string
	local cfg = getLaserIntroCfg()
	if isGamepad() then
		return cfg.LabelGamepad or "Press X — melt the wall with your Laser"
	end
	if isMobile() then
		return cfg.LabelMobile or "Press Vision — melt the wall with your Laser"
	end
	return cfg.LabelPC or "Press F — melt the wall with your Laser"
end

local function findHintScreenGui(playerGui: PlayerGui): ScreenGui?
	local cfg = getLaserIntroCfg()
	local name = cfg.ScreenGuiName or "TutorialLaserHintGui"
	local gui = playerGui:FindFirstChild(name)
	if gui and gui:IsA("ScreenGui") then
		return gui
	end
	return nil
end

local function findNamedDescendant<T>(root: Instance, name: string, className: string): T?
	local inst = root:FindFirstChild(name, true)
	if inst and inst:IsA(className) then
		return inst :: any
	end
	return nil
end

local function setCalloutLabel(callout: Frame)
	local label = callout:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		label.Text = getLabelText()
	end
end

local function setGuiPartVisible(guiObject: GuiObject?, visible: boolean)
	if not guiObject then
		return
	end
	guiObject.Visible = visible
end

function TutorialLaserHint.ensureHidden()
	local playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		return
	end
	local screenGui = findHintScreenGui(playerGui)
	if screenGui then
		screenGui.Enabled = false
	end
end

local function stopArrowBob(layer: HintLayer)
	if layer.arrowBobConn then
		layer.arrowBobConn:Disconnect()
		layer.arrowBobConn = nil
	end
	local arrow = layer.arrow
	if arrow and layer.arrowBasePosition then
		arrow.Position = layer.arrowBasePosition
	end
end

local function startArrowBob(layer: HintLayer)
	stopArrowBob(layer)
	local arrow = layer.arrow
	if not arrow then
		return
	end

	local cfg = getLaserIntroCfg()
	layer.arrowBasePosition = arrow.Position
	local amplitude = if type(cfg.ArrowBobPixels) == "number" then cfg.ArrowBobPixels else 14
	local period = if type(cfg.ArrowBobPeriodSeconds) == "number" then cfg.ArrowBobPeriodSeconds else 0.65
	local startTime = os.clock()
	local basePos = layer.arrowBasePosition :: UDim2

	layer.arrowBobConn = RunService.Heartbeat:Connect(function()
		if not arrow.Parent then
			return
		end
		local t = (os.clock() - startTime) / period
		local bob = math.sin(t * math.pi * 2) * amplitude
		arrow.Position = UDim2.new(
			basePos.X.Scale,
			basePos.X.Offset,
			basePos.Y.Scale,
			basePos.Y.Offset + bob
		)
	end)
end

function TutorialLaserHint.hide()
	local layer = activeLayer
	if not layer then
		return
	end
	activeLayer = nil

	HudAnimations.stopHeartbeat(layer.heartbeatTarget)
	stopArrowBob(layer)

	layer.screenGui.Enabled = false
	setGuiPartVisible(layer.callout, false)
	setGuiPartVisible(layer.arrow, false)
end

function TutorialLaserHint.show(): boolean
	local cfg = getLaserIntroCfg()
	if cfg.Enabled == false then
		return false
	end

	local playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		return false
	end

	local screenGui = findHintScreenGui(playerGui)
	if not screenGui then
		warn("[iseesupes][TutorialLaserHint] Missing PlayerGui." .. (cfg.ScreenGuiName or "TutorialLaserHintGui") .. " — add it under StarterGui.")
		return false
	end

	local visionFrame = VisionMobileUI.findVisionMobile(playerGui)
	if not visionFrame then
		return false
	end

	if activeLayer then
		TutorialLaserHint.hide()
	end

	local calloutName = cfg.CalloutName or "FlyCallout"
	local arrowName = cfg.ArrowName or "FlyArrow"
	local callout = findNamedDescendant(screenGui, calloutName, "Frame") :: Frame?
	local arrow = findNamedDescendant(screenGui, arrowName, "ImageLabel") :: ImageLabel?

	if not callout then
		warn("[iseesupes][TutorialLaserHint] Missing Frame:", calloutName, "under", screenGui:GetFullName())
		return false
	end
	if not arrow then
		warn("[iseesupes][TutorialLaserHint] Missing ImageLabel:", arrowName, "under", screenGui:GetFullName())
		return false
	end

	setCalloutLabel(callout)

	screenGui.Enabled = true
	setGuiPartVisible(callout, true)
	setGuiPartVisible(arrow, true)

	local layer: HintLayer = {
		screenGui = screenGui,
		callout = callout,
		arrow = arrow,
		heartbeatTarget = visionFrame,
		arrowBobConn = nil,
		arrowBasePosition = nil,
	}
	activeLayer = layer

	startArrowBob(layer)

	HudAnimations.startHeartbeat(
		visionFrame,
		cfg.HeartbeatPeakScale,
		cfg.HeartbeatPeriodSeconds
	)

	return true
end

function TutorialLaserHint.isActive(): boolean
	return activeLayer ~= nil
end

return TutorialLaserHint

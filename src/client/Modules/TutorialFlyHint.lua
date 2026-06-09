--!strict

-- Uses StarterGui → TutorialFlyHintGui (layout authored in Studio). Runtime: enable/disable only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local SupesMobileUI = require(ReplicatedStorage.Shared.Utils.SupesMobileUI)
local TutorialConfigs = require(ReplicatedStorage.Shared.Configs.TutorialConfigs)
local ThrustConfigs = require(ReplicatedStorage.Shared.Configs.ThrustConfigs)
local HudAnimations = require(script.Parent.HudAnimations)

local TutorialFlyHint = {}

local player = Players.LocalPlayer
local PHASE_ATTR = "DjAbilityPhase"

type HintLayer = {
	screenGui: ScreenGui,
	callout: Frame?,
	arrow: ImageLabel?,
	supesFrame: Frame,
	supesButton: ImageButton?,
	heartbeatTarget: GuiObject,
	dismissConns: { RBXScriptConnection },
	arrowBobConn: RBXScriptConnection?,
	arrowBasePosition: UDim2?,
	mode: "main" | "lowThrust",
}

local activeLayer: HintLayer? = nil
local lowThrustWatchConn: RBXScriptConnection? = nil

local function getFlyIntroCfg(): any
	return TutorialConfigs.FlyIntro or {}
end

local function isMobile(): boolean
	return UserInputService.TouchEnabled
end

local function getLabelText(): string
	local cfg = getFlyIntroCfg()
	if isMobile() then
		return cfg.LabelMobile or "Press Supes to Fly"
	end
	return cfg.LabelPC or "Press E to Fly"
end

local function disconnectAll(conns: { RBXScriptConnection })
	for _, conn in conns do
		conn:Disconnect()
	end
	table.clear(conns)
end

local function findHintScreenGui(playerGui: PlayerGui): ScreenGui?
	local cfg = getFlyIntroCfg()
	local name = cfg.ScreenGuiName or "TutorialFlyHintGui"
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

function TutorialFlyHint.ensureHidden()
	local playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		return
	end
	local screenGui = findHintScreenGui(playerGui)
	if screenGui then
		screenGui.Enabled = false
	end
end

local function hideLayer(layer: HintLayer?)
	if not layer then
		return
	end

	HudAnimations.stopHeartbeat(layer.heartbeatTarget)

	if layer.arrowBobConn then
		layer.arrowBobConn:Disconnect()
		layer.arrowBobConn = nil
	end

	disconnectAll(layer.dismissConns)

	layer.screenGui.Enabled = false
	setGuiPartVisible(layer.callout, false)
	setGuiPartVisible(layer.arrow, false)
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

	local cfg = getFlyIntroCfg()
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

local function dismissActive(onComplete: (() -> ())?)
	local layer = activeLayer
	if not layer then
		if onComplete then
			onComplete()
		end
		return
	end
	activeLayer = nil

	local DataService = Knit.GetService("DataService")
	if layer.mode == "main" then
		pcall(function()
			DataService:MarkTutorialFlyIntroShown()
		end)
	elseif layer.mode == "lowThrust" then
		pcall(function()
			DataService:MarkTutorialLowThrustFlyHintShown()
		end)
	end

	hideLayer(layer)
	if onComplete then
		onComplete()
	end
end

local function bindDismiss(layer: HintLayer)
	local function tryDismiss()
		if activeLayer == layer then
			dismissActive()
		end
	end

	if layer.supesButton then
		table.insert(layer.dismissConns, layer.supesButton.MouseButton1Down:Connect(tryDismiss))
	end

	table.insert(
		layer.dismissConns,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			if input.KeyCode == Enum.KeyCode.E then
				tryDismiss()
			end
		end)
	)

	table.insert(
		layer.dismissConns,
		player:GetAttributeChangedSignal(PHASE_ATTR):Connect(function()
			local phase = player:GetAttribute(PHASE_ATTR)
			if phase ~= nil and phase ~= "" and layer.mode == "main" then
				tryDismiss()
			end
		end)
	)
end

local function showHint(mode: "main" | "lowThrust", withCallout: boolean): boolean
	local cfg = getFlyIntroCfg()
	if cfg.Enabled == false then
		return false
	end

	local playerGui = player:FindFirstChild("PlayerGui") :: PlayerGui?
	if not playerGui then
		return false
	end

	local screenGui = findHintScreenGui(playerGui)
	if not screenGui then
		warn("[iseesupes][TutorialFlyHint] Missing PlayerGui." .. (cfg.ScreenGuiName or "TutorialFlyHintGui") .. " — add it under StarterGui.")
		return false
	end

	local supesFrame = SupesMobileUI.findSupesMobile(playerGui)
	if not supesFrame then
		return false
	end

	if activeLayer then
		hideLayer(activeLayer)
		activeLayer = nil
	end

	local calloutName = cfg.CalloutName or "FlyCallout"
	local arrowName = cfg.ArrowName or "FlyArrow"
	local callout = findNamedDescendant(screenGui, calloutName, "Frame") :: Frame?
	local arrow = findNamedDescendant(screenGui, arrowName, "ImageLabel") :: ImageLabel?

	if withCallout and not callout then
		warn("[iseesupes][TutorialFlyHint] Missing Frame:", calloutName, "under", screenGui:GetFullName())
		return false
	end
	if not arrow then
		warn("[iseesupes][TutorialFlyHint] Missing ImageLabel:", arrowName, "under", screenGui:GetFullName())
		return false
	end

	if callout then
		setCalloutLabel(callout)
	end

	screenGui.Enabled = true
	setGuiPartVisible(callout, withCallout)
	setGuiPartVisible(arrow, true)

	local supesButton = SupesMobileUI.findSupesImageButton(supesFrame)

	local layer: HintLayer = {
		screenGui = screenGui,
		callout = callout,
		arrow = arrow,
		supesFrame = supesFrame,
		supesButton = supesButton,
		heartbeatTarget = supesFrame,
		dismissConns = {},
		mode = mode,
	}
	activeLayer = layer

	bindDismiss(layer)
	startArrowBob(layer)

	HudAnimations.startHeartbeat(
		supesFrame,
		cfg.HeartbeatPeakScale,
		cfg.HeartbeatPeriodSeconds
	)

	return true
end

function TutorialFlyHint.showMainIntro(): boolean
	return showHint("main", true)
end

function TutorialFlyHint.showLowThrustHint(): boolean
	return showHint("lowThrust", false)
end

function TutorialFlyHint.isActive(): boolean
	return activeLayer ~= nil
end

function TutorialFlyHint.dismiss()
	dismissActive()
end

local function isFlying(): boolean
	local phase = player:GetAttribute(PHASE_ATTR)
	return phase ~= nil and phase ~= ""
end

local function isThrustLow(): boolean
	local data = DataLib.GetData()
	if not data then
		return false
	end
	local lowCfg = TutorialConfigs.LowThrustFlyHint or {}
	if lowCfg.Enabled == false then
		return false
	end
	local current = if type(data.ThrustCurrent) == "number" then data.ThrustCurrent else data.ThrustMax
	local maxFuel = if type(data.ThrustMax) == "number" and data.ThrustMax > 0 then data.ThrustMax else 60
	local minStart = ThrustConfigs.GetEffectiveMinFuelToStart(maxFuel)
	local ratio = current / maxFuel
	if lowCfg.UseMinFuelThreshold ~= false and current < minStart then
		return true
	end
	local maxRatio = lowCfg.MaxFillRatio or 0.25
	return ratio <= maxRatio
end

local function canShowLowThrustHint(): boolean
	local data = DataLib.GetData()
	if not data then
		return false
	end
	if data.TutorialLowThrustFlyHintShown == true then
		return false
	end
	if data.TutorialFlyIntroShown == true then
		return false
	end
	if isFlying() then
		return false
	end
	return isThrustLow()
end

function TutorialFlyHint.tryShowLowThrustHint()
	if activeLayer then
		return
	end
	if not canShowLowThrustHint() then
		return
	end
	showHint("lowThrust", false)
end

function TutorialFlyHint.startLowThrustWatcher()
	TutorialFlyHint.ensureHidden()

	if lowThrustWatchConn then
		return
	end
	lowThrustWatchConn = DataLib.OnChanged(function()
		TutorialFlyHint.tryShowLowThrustHint()
	end)
	task.spawn(function()
		for _ = 1, 20 do
			TutorialFlyHint.tryShowLowThrustHint()
			task.wait(1)
		end
	end)
end

return TutorialFlyHint

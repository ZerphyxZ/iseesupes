--!strict

-- Opens/closes GUI.Frames panels with Y-size animation; wires HUD buttons and Close buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HudConfigs = require(ReplicatedStorage.Shared.Configs.HudConfigs)
local HudAnimations = require(script.Parent.HudAnimations)

export type FrameNavigator = {
	Toggle: (self: FrameNavigator, frameName: string) -> (),
	Open: (self: FrameNavigator, frameName: string) -> (),
	Close: (self: FrameNavigator) -> (),
	GetOpenFrameName: (self: FrameNavigator) -> string?,
}

local FrameNavigator = {}
FrameNavigator.__index = FrameNavigator

local function resolvePath(root: Instance, segments: { string }): Instance?
	local current: Instance? = root
	for _, name in segments do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

local function findCloseButton(frame: Instance): GuiButton?
	for _, name in HudConfigs.CloseButtonNames do
		local direct = frame:FindFirstChild(name)
		if direct and direct:IsA("GuiButton") then
			return direct
		end
	end
	for _, desc in frame:GetDescendants() do
		if desc:IsA("GuiButton") then
			for _, name in HudConfigs.CloseButtonNames do
				if desc.Name == name then
					return desc
				end
			end
		end
	end
	return nil
end

function FrameNavigator.new(gui: Instance, hud: Instance): FrameNavigator
	local self = setmetatable({
		_framesRoot = nil :: Instance?,
		_framesByName = {} :: { [string]: GuiObject },
		_openFrame = nil :: GuiObject?,
		_openFrameName = nil :: string?,
		_isBusy = false,
	}, FrameNavigator)

	local frames = gui:WaitForChild("Frames", 30)
	if not frames then
		warn("[iseesupes] FrameNavigator: missing GUI.Frames (under PlayerGui.GUI).")
		return self
	end

	self._framesRoot = frames

	local excluded: { [string]: boolean } = {}
	for _, name in HudConfigs.ExcludeFromNavigator do
		excluded[name] = true
	end

	for _, child in frames:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Template" and not excluded[child.Name] then
			self._framesByName[child.Name] = child
			HudAnimations.rememberBaseSize(child)
			child.Visible = false

			local closeBtn = findCloseButton(child)
			if closeBtn then
				closeBtn.MouseButton1Click:Connect(function()
					HudAnimations.buttonPress(closeBtn, function()
						self:Close()
					end)
				end)
			end
		end
	end

	for _, link in HudConfigs.FrameLinks do
		local button = resolvePath(hud, link.ButtonPath)
		if not button then
			warn(
				"[iseesupes] FrameNavigator: HUD button not found:",
				table.concat(link.ButtonPath, "/")
			)
			continue
		end
		if not self._framesByName[link.FrameName] then
			warn("[iseesupes] FrameNavigator: frame not found:", link.FrameName)
			continue
		end
		if not button:IsA("GuiButton") then
			warn("[iseesupes] FrameNavigator: not a GuiButton:", table.concat(link.ButtonPath, "/"))
			continue
		end

		HudAnimations.rememberBaseScale(button)

		local frameName = link.FrameName
		button.MouseButton1Click:Connect(function()
			HudAnimations.buttonPress(button, function()
				self:Toggle(frameName)
			end)
		end)
	end

	return self
end

function FrameNavigator:GetOpenFrameName(): string?
	return self._openFrameName
end

function FrameNavigator:Close()
	if self._isBusy then
		return
	end
	local frame = self._openFrame
	if not frame then
		return
	end

	self._isBusy = true
	self._openFrame = nil
	self._openFrameName = nil

	HudAnimations.closeFrameY(frame, HudConfigs.CloseDuration, function()
		self._isBusy = false
	end)
end

function FrameNavigator:Open(frameName: string)
	local frame = self._framesByName[frameName]
	if not frame then
		return
	end
	if self._openFrame == frame and frame.Visible then
		return
	end
	if self._isBusy then
		return
	end

	if self._openFrame and self._openFrame ~= frame then
		local previous = self._openFrame
		self._openFrame = nil
		self._openFrameName = nil
		self._isBusy = true
		HudAnimations.closeFrameY(previous, HudConfigs.CloseDuration * 0.85, function()
			self._isBusy = false
			self:Open(frameName)
		end)
		return
	end

	self._isBusy = true
	self._openFrame = frame
	self._openFrameName = frameName

	HudAnimations.openFrameY(frame, HudConfigs.OpenDuration, function()
		self._isBusy = false
	end)
end

function FrameNavigator:Toggle(frameName: string)
	local frame = self._framesByName[frameName]
	if not frame then
		return
	end
	if self._openFrame == frame and frame.Visible then
		self:Close()
	else
		self:Open(frameName)
	end
end

return FrameNavigator

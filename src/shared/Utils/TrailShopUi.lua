--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrailConfigs = require(ReplicatedStorage.Shared.Configs.TrailConfigs)

local TrailShopUi = {}

local TEMPLATE_NAME = TrailConfigs.ShopTemplateName
local ROW_SOURCE_NAME = "_TrailRowSource"

export type TrailInfo = TrailConfigs.TrailInfo

function TrailShopUi.isReservedScrollingChild(child: Instance): boolean
	if child.Name == TEMPLATE_NAME or child.Name == ROW_SOURCE_NAME then
		return true
	end
	if child:IsA("UIListLayout") or child:IsA("UIPadding") then
		return true
	end
	return child.Name == "List"
end

local function waitPath(root: Instance, segments: { string }, timeout: number?): Instance?
	local current: Instance? = root
	for _, name in segments do
		if not current then
			return nil
		end
		current = current:WaitForChild(name, timeout or 5)
	end
	return current
end

function TrailShopUi.resolveTrailTemplate(scrolling: Instance, replicatedStorage: Instance): GuiObject?
	local inScrolling = scrolling:FindFirstChild(TEMPLATE_NAME)
	if inScrolling and inScrolling:IsA("GuiObject") then
		return inScrolling :: GuiObject
	end

	local waited = scrolling:WaitForChild(TEMPLATE_NAME, 15)
	if waited and waited:IsA("GuiObject") then
		return waited :: GuiObject
	end

	for _, segments in {
		TrailConfigs.ShopTemplatePath,
		TrailConfigs.ShopTemplatePathLegacy,
	} do
		local found = waitPath(replicatedStorage, segments, 5)
		if found and found:IsA("GuiObject") then
			return found :: GuiObject
		end
	end

	return nil
end

--- Hidden clone used for row duplication (keeps Studio TrailTemplate intact).
function TrailShopUi.ensureRowSource(scrolling: ScrollingFrame, template: GuiObject): GuiObject
	local existing = scrolling:FindFirstChild(ROW_SOURCE_NAME)
	if existing and existing:IsA("GuiObject") then
		return existing :: GuiObject
	end

	local source = template:Clone()
	source.Name = ROW_SOURCE_NAME
	source.Visible = false
	source.Parent = scrolling
	return source
end

function TrailShopUi.prepareTemplate(template: GuiObject)
	template.Visible = false
end

function TrailShopUi.updateScrollingCanvas(scrolling: ScrollingFrame)
	local list = scrolling:FindFirstChild("List")
	if not list then
		list = scrolling:FindFirstChildOfClass("UIListLayout")
	end
	if list and list:IsA("UIListLayout") then
		task.defer(function()
			if scrolling.Parent then
				scrolling.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 8)
			end
		end)
		if not list:GetAttribute("_TrailCanvasBound") then
			list:SetAttribute("_TrailCanvasBound", true)
			list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if scrolling.Parent then
					scrolling.CanvasSize = UDim2.new(0, 0, 0, list.AbsoluteContentSize.Y + 8)
				end
			end)
		end
	end
end

local function colorAt(sequence: ColorSequence, alpha: number): Color3
	local keypoints = sequence.Keypoints
	if #keypoints == 0 then
		return Color3.new(1, 1, 1)
	end
	if #keypoints == 1 then
		return keypoints[1].Value
	end
	for i = 1, #keypoints - 1 do
		local a = keypoints[i]
		local b = keypoints[i + 1]
		if alpha >= a.Time and alpha <= b.Time then
			local span = b.Time - a.Time
			local t = if span > 0 then (alpha - a.Time) / span else 0
			return a.Value:Lerp(b.Value, t)
		end
	end
	return keypoints[#keypoints].Value
end

function TrailShopUi.applyTrailRowTheme(row: Instance, info: TrailInfo)
	if not info.Color then
		return
	end

	local design = row:FindFirstChild("Design")
	if not design or not design:IsA("GuiObject") then
		return
	end

	local gradient = design:FindFirstChild("Gradient")
	if gradient and gradient:IsA("UIGradient") then
		gradient.Color = info.Color
	end

	local stroke = design:FindFirstChild("Stroke")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = colorAt(info.Color, 0)
	end

	if design:IsA("Frame") then
		design.BackgroundColor3 = colorAt(info.Color, 0.5)
	end
end

function TrailShopUi.bindTrailRowLabels(row: Instance, info: TrailInfo, layoutOrder: number)
	row.Visible = true
	if row:IsA("GuiObject") then
		(row :: GuiObject).LayoutOrder = layoutOrder
	end

	local nameLabel = row:FindFirstChild("Name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = info.Name
	end

	local speedLabel = row:FindFirstChild("SpeedBoost")
	if speedLabel and speedLabel:IsA("TextLabel") then
		speedLabel.Text = "x" .. tostring(info.SpeedBoost) .. " Speed"
	end

	local imageLabel = row:FindFirstChild("Image")
	if imageLabel and imageLabel:IsA("ImageLabel") and info.Image then
		imageLabel.Image = info.Image
	end

	TrailShopUi.applyTrailRowTheme(row, info)
end

function TrailShopUi.countTrailRows(scrolling: Instance): number
	local count = 0
	for _, child in scrolling:GetChildren() do
		if child:IsA("Frame") and TrailConfigs.IsTrailRowName(child.Name) then
			count += 1
		end
	end
	return count
end

return TrailShopUi

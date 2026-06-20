--!strict

-- Endless rolling quests HUD. Entry point is a "Quests" button injected into GUI.HUD.Left so it
-- sits with Shop / Rebirth / Trails (that column has a UIListLayout, so it auto-places). The button
-- carries a red "!" badge with the claimable count (like Rebirth's badge) for the goal-gradient
-- pull, and opens a board listing all 3 active quests with CLAIM buttons. Progress is computed
-- LOCALLY each frame from the replicated quest baselines + live profile counters (DataLib) /
-- session minutes, so bars tick up smoothly between the coarse server pushes. Claiming advances
-- that slot to the next tier; the server pushes fresh state and the board rolls to the new
-- (bigger) quest — there is always a next goal.
--
-- If a "Quests" button already exists under HUD.Left (e.g. authored in Studio for nicer art), this
-- adopts it instead of building one — just keep the name "Quests".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local QuestConfigs = require(ReplicatedStorage.Shared.Configs.QuestConfigs)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local QuestController = Knit.CreateController({ Name = "QuestController" })

local player = Players.LocalPlayer

local FREDOKA = Font.new("rbxasset://fonts/families/FredokaOne.json")
local GOTHAM_BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local BLACK = Color3.new(0, 0, 0)
local FILL_BG = Color3.fromRGB(28, 32, 50)
local FILL_BAR = Color3.fromRGB(64, 210, 120)
local READY_GREEN = Color3.fromRGB(46, 204, 96)

-- Latest server state + when it arrived (for local PlayTime extrapolation).
local state: any = { active = false, quests = {} }
local lastStateAt = os.clock()
local claiming: { [number]: boolean } = {}

-- Live progress (computed client-side from the replicated baseline + current counter).
local function questProgress(q: any): (number, boolean)
	if not q then
		return 0, false
	end
	local target = q.target
	local current: number
	if q.counter == "PlayMinutes" then
		local serverMin = if type(state.sessionMinutes) == "number" then state.sessionMinutes else 0
		current = serverMin + (os.clock() - lastStateAt) / 60
	else
		local data = DataLib.GetData()
		local v = data and data[q.counter]
		current = if type(v) == "number" then v else 0
	end
	local progress = math.clamp(current - (q.baseline or 0), 0, target)
	return progress, progress >= target
end

local function claimableCount(): number
	local n = 0
	for _, q in state.quests do
		local _, complete = questProgress(q)
		if complete then
			n += 1
		end
	end
	return n
end

-- ── UI refs ──────────────────────────────────────────────────────────────────────

type RowRefs = {
	root: Frame,
	icon: ImageLabel,
	title: TextLabel,
	count: TextLabel,
	barFill: Frame,
	claim: TextButton,
	claimText: TextLabel,
}

local questBadge: GuiObject? = nil
local questBadgeLabel: TextLabel? = nil
local board: Frame? = nil
local panelScale: UIScale? = nil
local boardDaily: TextLabel? = nil
local rows: { RowRefs } = {}
local boardOpen = false

-- ── UI build helpers ──────────────────────────────────────────────────────────────

--- Cap a TextScaled label so text stays sane on large screens (and add a min so it stays
--- legible on small ones). Keeps text from ballooning/overlapping across devices.
local function capText(label: TextLabel, maxSize: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.MinTextSize = 7
	c.Parent = label
end

local function makeProgressBar(parent: Instance): Frame
	local bg = Instance.new("Frame")
	bg.Name = "Bar"
	bg.BackgroundColor3 = FILL_BG
	bg.BorderSizePixel = 0
	bg.Size = UDim2.fromScale(1, 1)
	bg.Parent = parent
	Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = FILL_BAR
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = bg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	return fill
end

local function styleClose(btn: TextButton)
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0), Color3.fromRGB(255, 85, 127))
	grad.Rotation = 90
	grad.Parent = btn
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 0, 0)
	stroke.Thickness = 3
	stroke.Parent = btn
	local x = Instance.new("TextLabel")
	x.BackgroundTransparency = 1
	x.AnchorPoint = Vector2.new(0.5, 0.5)
	x.Position = UDim2.new(0.5, 0, 0.5, 0)
	x.Size = UDim2.new(0.85, 0, 0.85, 0)
	x.FontFace = FREDOKA
	x.TextScaled = true
	x.TextColor3 = Color3.new(1, 1, 1)
	x.Text = "X"
	x.Parent = btn
	local xs = Instance.new("UIStroke")
	xs.Color = Color3.fromRGB(100, 0, 0)
	xs.Thickness = 3
	xs.Parent = x
end

-- Row contents are laid out in SCALE bands so they never overlap at any board width:
--   icon [3%..~16%] | title [17%..49%] (top) / bar [17%..63%] (bottom) | count [49%..63%] (top)
--   | claim/reward button [67%..97%]. Text is TextScaled + capped so it can't balloon or clip.
local function buildRow(parent: Instance, index: number): RowRefs
	local root = Instance.new("Frame")
	root.Name = "Quest" .. index
	root.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	root.BackgroundTransparency = 0.06
	root.Size = UDim2.fromScale(1, 0.3)
	root.LayoutOrder = index
	root.Parent = parent
	Instance.new("UICorner", root).CornerRadius = UDim.new(0, 10)
	local rs = Instance.new("UIStroke")
	rs.Color = BLACK
	rs.Thickness = 2
	rs.Transparency = 0.2
	rs.Parent = root

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0.03, 0.5)
	icon.Size = UDim2.fromScale(0.62, 0.62)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY -- square, sized off row height
	icon.Parent = root

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.fromScale(0.17, 0.16)
	title.Size = UDim2.fromScale(0.32, 0.36)
	title.FontFace = GOTHAM_BOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(25, 28, 40)
	title.Text = ""
	title.Parent = root
	capText(title, 19)

	local count = Instance.new("TextLabel")
	count.BackgroundTransparency = 1
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.fromScale(0.63, 0.18)
	count.Size = UDim2.fromScale(0.13, 0.30)
	count.FontFace = GOTHAM_BOLD
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextScaled = true
	count.TextColor3 = Color3.fromRGB(90, 100, 120)
	count.Text = ""
	count.Parent = root
	capText(count, 15)

	local barHolder = Instance.new("Frame")
	barHolder.BackgroundTransparency = 1
	barHolder.AnchorPoint = Vector2.new(0, 1)
	barHolder.Position = UDim2.fromScale(0.17, 0.84)
	barHolder.Size = UDim2.fromScale(0.46, 0.22)
	barHolder.Parent = root
	local barFill = makeProgressBar(barHolder)

	local claim = Instance.new("TextButton")
	claim.Name = "Claim"
	claim.AnchorPoint = Vector2.new(1, 0.5)
	claim.Position = UDim2.fromScale(0.97, 0.5)
	claim.Size = UDim2.fromScale(0.30, 0.62)
	claim.BackgroundColor3 = Color3.new(1, 1, 1)
	claim.AutoButtonColor = true
	claim.Text = ""
	claim.Parent = root
	Instance.new("UICorner", claim).CornerRadius = UDim.new(0, 8)
	local claimGrad = Instance.new("UIGradient")
	claimGrad.Color = ColorSequence.new(Color3.fromRGB(64, 230, 77), Color3.fromRGB(13, 153, 31))
	claimGrad.Rotation = 90
	claimGrad.Parent = claim
	local claimStroke = Instance.new("UIStroke")
	claimStroke.Color = Color3.fromRGB(0, 77, 0)
	claimStroke.Thickness = 2.5
	claimStroke.Parent = claim
	local claimText = Instance.new("TextLabel")
	claimText.BackgroundTransparency = 1
	claimText.AnchorPoint = Vector2.new(0.5, 0.5)
	claimText.Position = UDim2.new(0.5, 0, 0.5, 0)
	claimText.Size = UDim2.fromScale(0.9, 0.58)
	claimText.FontFace = FREDOKA
	claimText.TextScaled = true
	claimText.TextColor3 = Color3.new(1, 1, 1)
	claimText.Text = "CLAIM"
	claimText.Parent = claim
	capText(claimText, 17)
	local claimTextStroke = Instance.new("UIStroke")
	claimTextStroke.Color = Color3.fromRGB(0, 77, 0)
	claimTextStroke.Thickness = 2
	claimTextStroke.Parent = claimText

	return {
		root = root,
		icon = icon,
		title = title,
		count = count,
		barFill = barFill,
		claim = claim,
		claimText = claimText,
	}
end

-- ── Claim ──────────────────────────────────────────────────────────────────────

local QuestService: any = nil

local function doClaim(slotIndex: number)
	if not slotIndex or claiming[slotIndex] or not QuestService then
		return
	end
	claiming[slotIndex] = true
	QuestService:ClaimQuest(slotIndex)
		:andThen(function()
			claiming[slotIndex] = false
		end)
		:catch(function()
			claiming[slotIndex] = false
		end)
end

-- ── Render ───────────────────────────────────────────────────────────────────────

local function render()
	local active = state.active == true and #state.quests > 0

	-- Quest button badge: red "!" with the claimable count (goal-gradient pull).
	if questBadge then
		local n = if active then claimableCount() else 0
		questBadge.Visible = n > 0
		if questBadgeLabel then
			questBadgeLabel.Text = if n > 1 then tostring(n) else "!"
		end
	end

	-- Board rows. render() must NOT open/close the board — that's setBoardOpen's job (your click).
	-- Previously a transient active=false (an empty-quests push, the initial pre-data GetState, a
	-- 1s ticker tick) force-closed it → "it opens then closes by itself" right after clicking.
	for i, refs in rows do
		local q = state.quests[i]
		if q then
			refs.root.Visible = true
			local progress, complete = questProgress(q)
			refs.icon.Image = q.icon
			refs.title.Text = q.label
			-- Abbreviate so big EarnSpeed counts (e.g. 123456/250000) stay inside the column.
			refs.count.Text = NumberFormatter.Format(math.floor(progress)) .. "/" .. NumberFormatter.Format(q.target)
			local ratio = if q.target > 0 then math.clamp(progress / q.target, 0, 1) else 0
			refs.barFill.Size = UDim2.new(ratio, 0, 1, 0)
			refs.barFill.BackgroundColor3 = if complete then READY_GREEN else FILL_BAR
			-- Button always shows the reward (preview, dimmed) → bright "CLAIM" when ready.
			if complete then
				refs.claim.BackgroundTransparency = 0
				refs.claim.AutoButtonColor = true
				refs.claimText.Text = "CLAIM"
				refs.claimText.TextTransparency = 0
			else
				refs.claim.BackgroundTransparency = 0.5
				refs.claim.AutoButtonColor = false
				refs.claimText.Text = q.rewardLabel
				refs.claimText.TextTransparency = 0.1
			end
		else
			refs.root.Visible = false
		end
	end

	if boardDaily then
		local dayCount = if type(state.dayCount) == "number" then state.dayCount else 0
		local goal = if type(state.dailyGoal) == "number" then state.dailyGoal else QuestConfigs.DailyGoal
		boardDaily.Text = string.format("Daily bonus: %d/%d quests", math.min(dayCount, goal), goal)
	end
end

local function setBoardOpen(open: boolean)
	boardOpen = open
	if not board or not panelScale then
		return
	end
	local scale = panelScale :: UIScale
	if open then
		render()
		board.Visible = true
		scale.Scale = 0
		-- Animate a UIScale (not the Size) so the responsive size + UISizeConstraint layout stays
		-- correct on every device — only the visual scale pops in.
		TweenService:Create(scale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	else
		local tween = TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
			Scale = 0,
		})
		tween:Play()
		tween.Completed:Once(function()
			if not boardOpen and board then
				board.Visible = false
			end
		end)
	end
end

-- ── HUD.Left button (built, or adopts a Studio-authored "Quests" button) ───────────

-- Red rounded-square "!" badge in the style of the other HUD buttons (Rebirth etc.). Built fresh
-- rather than cloned — cloning the native badge kept dropping the "!" (Rebirth keeps its mark as a
-- separate piece, and ZIndex inside the cloned frame was unreliable). A high ZIndex guarantees both
-- the square AND the "!" render on top of the button.
local function attachBadge(btn: GuiObject)
	local existingBadge = btn:FindFirstChild("QuestBadge")
	if existingBadge then
		questBadge = existingBadge :: GuiObject
		questBadgeLabel = existingBadge:FindFirstChildOfClass("TextLabel") :: TextLabel?
		return
	end

	local badge = Instance.new("Frame")
	badge.Name = "QuestBadge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 2, 0, -2) -- sticks just past the top-right corner, like Rebirth's
	badge.Size = UDim2.fromScale(0.34, 0.34)
	badge.SizeConstraint = Enum.SizeConstraint.RelativeYY -- square, sized off the button height
	badge.BackgroundColor3 = Color3.fromRGB(235, 33, 33)
	badge.Visible = false
	badge.ZIndex = 50
	badge.Parent = btn
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0.3, 0)
	local bs = Instance.new("UIStroke")
	bs.Color = Color3.new(1, 1, 1)
	bs.Thickness = 2
	bs.Parent = badge

	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.BackgroundTransparency = 1
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.new(0.5, 0, 0.5, 0)
	mark.Size = UDim2.new(0.9, 0, 0.9, 0)
	mark.FontFace = FREDOKA
	mark.TextScaled = true
	mark.TextColor3 = Color3.new(1, 1, 1)
	mark.Text = "!"
	mark.ZIndex = 51
	mark.Parent = badge
	local ms = Instance.new("UIStroke")
	ms.Color = Color3.fromRGB(120, 0, 0)
	ms.Thickness = 1
	ms.Parent = mark

	questBadge = badge
	questBadgeLabel = mark
end

--- Build a clean Quests button sized to match a sibling (Shop/Trails/Rebirth).
local function buildButton(left: Instance): GuiButton
	local template = left:FindFirstChild("Shop")
		or left:FindFirstChild("Trails")
		or left:FindFirstChild("Rebirth")

	local btn = Instance.new("ImageButton")
	btn.Name = "Quests"
	btn.BackgroundColor3 = Color3.fromRGB(78, 52, 150)
	btn.AutoButtonColor = true
	btn.Image = ""
	if template and template:IsA("GuiObject") then
		btn.Size = template.Size
		btn.LayoutOrder = template.LayoutOrder
		local tmplAspect = template:FindFirstChildOfClass("UIAspectRatioConstraint")
		if tmplAspect then
			tmplAspect:Clone().Parent = btn
		end
	else
		btn.Size = UDim2.new(1, 0, 0, 86)
	end

	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 12, 40)
	stroke.Thickness = 3
	stroke.Parent = btn

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0.08, 0)
	icon.Size = UDim2.new(0.62, 0, 0.62, 0)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.Image = QuestConfigs.GetIcon("PlayTime") -- gift / reward icon
	icon.Parent = btn

	-- Match the sibling buttons' name text EXACTLY by cloning their label (font, scale, bold weight,
	-- colour, outline, position all carry over) and just swapping the text → "Quests" looks like
	-- "Shop"/"Rebirth"/"Trails". Falls back to a hand-built label if the siblings bake their text
	-- into the icon art (no TextLabel to copy).
	local srcLabel: TextLabel? = nil
	if template then
		for _, d in template:GetDescendants() do
			if d:IsA("TextLabel") then
				srcLabel = d :: TextLabel
				break
			end
		end
	end
	if srcLabel then
		local lbl = srcLabel:Clone()
		lbl.Name = "Title"
		lbl.Text = "Quests"
		lbl.Parent = btn
	else
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Title"
		lbl.BackgroundTransparency = 1
		lbl.AnchorPoint = Vector2.new(0.5, 1)
		lbl.Position = UDim2.new(0.5, 0, 1, -5)
		lbl.Size = UDim2.new(1, -8, 0.26, 0)
		lbl.FontFace = FREDOKA
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.Text = "Quests"
		lbl.Parent = btn
		capText(lbl, 18)
		local ls = Instance.new("UIStroke")
		ls.Color = BLACK
		ls.Thickness = 2
		ls.Parent = lbl
	end

	return btn
end

local function ensureLeftButton(left: Instance)
	local existing = left:FindFirstChild("Quests")
	local btn: GuiButton
	if existing then
		if not existing:IsA("GuiButton") then
			return -- something else is named "Quests"; don't touch it
		end
		btn = existing
	else
		btn = buildButton(left)
		btn.Parent = left
	end
	if btn:GetAttribute("_QuestWired") then
		return
	end
	btn:SetAttribute("_QuestWired", true)
	attachBadge(btn)
	btn.MouseButton1Click:Connect(function()
		setBoardOpen(not boardOpen)
	end)
	render()
end

function QuestController:KnitStart()
	QuestService = Knit.GetService("QuestService")
	local playerGui = player:WaitForChild("PlayerGui")
	local hudGui = playerGui:WaitForChild("GUI", 120)

	-- ── Board (own ScreenGui, centered, hidden) ──────────────────────────────────────
	local gui = Instance.new("ScreenGui")
	gui.Name = "Quests"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40010
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.Name = "Board"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.45, 0)
	-- Responsive: scales with the screen but CLAMPED so it never overruns a phone nor bloats on a
	-- big monitor. Everything inside is scale-based, so the layout adapts to the resulting size.
	panel.Size = UDim2.fromScale(0.5, 0.52)
	panel.BackgroundColor3 = Color3.fromRGB(245, 247, 255)
	panel.Visible = false
	panel.Parent = gui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
	local sizeC = Instance.new("UISizeConstraint")
	sizeC.MaxSize = Vector2.new(470, 360)
	sizeC.MinSize = Vector2.new(300, 250)
	sizeC.Parent = panel
	local pStroke = Instance.new("UIStroke")
	pStroke.Color = BLACK
	pStroke.Thickness = 3
	pStroke.Parent = panel
	-- UIScale drives the open/close pop (animating Size would fight the UISizeConstraint).
	local ps = Instance.new("UIScale")
	ps.Scale = 0
	ps.Parent = panel
	panelScale = ps

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.fromScale(0.5, 0.04)
	header.Size = UDim2.fromScale(0.7, 0.13)
	header.FontFace = FREDOKA
	header.TextScaled = true
	header.TextColor3 = Color3.fromRGB(30, 34, 60)
	header.Text = "QUESTS"
	header.Parent = panel
	capText(header, 30)

	local daily = Instance.new("TextLabel")
	daily.BackgroundTransparency = 1
	daily.AnchorPoint = Vector2.new(0.5, 0)
	daily.Position = UDim2.fromScale(0.5, 0.18)
	daily.Size = UDim2.fromScale(0.85, 0.07)
	daily.FontFace = GOTHAM_BOLD
	daily.TextScaled = true
	daily.TextColor3 = Color3.fromRGB(120, 90, 20)
	daily.Text = "Daily bonus: 0/5 quests"
	daily.Parent = panel
	capText(daily, 16)
	boardDaily = daily

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.Position = UDim2.fromScale(0.5, 0.28)
	list.Size = UDim2.fromScale(0.92, 0.68)
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0.03, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for i = 1, QuestConfigs.SlotCount do
		local refs = buildRow(list, i)
		refs.claim.MouseButton1Click:Connect(function()
			doClaim(i)
		end)
		rows[i] = refs
	end

	local close = Instance.new("TextButton")
	close.Name = "Close"
	-- Scale-sized square inset into the top-right corner (no clipping anywhere now).
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(0.985, 0.03)
	close.Size = UDim2.fromScale(0.13, 0.13)
	close.SizeConstraint = Enum.SizeConstraint.RelativeYY
	close.Text = ""
	close.ZIndex = 5
	close.Parent = panel
	styleClose(close)
	close.MouseButton1Click:Connect(function()
		setBoardOpen(false)
	end)

	board = panel
	gui.Parent = playerGui

	-- ── Inject the HUD.Left button (re-inject if the HUD resets on respawn) ────────────
	local function hookLeft()
		if not hudGui then
			return
		end
		local hud = hudGui:FindFirstChild("HUD")
		local left = hud and hud:FindFirstChild("Left")
		if left then
			ensureLeftButton(left)
		end
	end
	task.spawn(function()
		if hudGui then
			local hud = hudGui:WaitForChild("HUD", 30)
			if hud then
				hud:WaitForChild("Left", 30)
			end
		end
		hookLeft()
	end)
	player.CharacterAdded:Connect(function()
		task.defer(hookLeft)
	end)

	-- ── Wiring ──────────────────────────────────────────────────────────────────────
	QuestService.StateChanged:Connect(function(newState: any)
		state = newState or { active = false, quests = {} }
		lastStateAt = os.clock()
		render()
	end)
	QuestService.QuestClaimed:Connect(function(_slot: number, rewardLabel: string, nextLabel: string)
		NotificationManager.show("Quest complete! " .. tostring(rewardLabel) .. " — Next: " .. tostring(nextLabel), "Success")
	end)
	QuestService.DailyGoalReached:Connect(function(wins: number, boostSeconds: number)
		local extra = if typeof(boostSeconds) == "number" and boostSeconds > 0 then " + Boost" else ""
		NotificationManager.show(string.format("Daily quest goal! +%d Wins%s", wins or 0, extra), "Success")
	end)
	DataLib.OnChanged(render)

	QuestService:GetState()
		:andThen(function(s: any)
			if s then
				state = s
				lastStateAt = os.clock()
				render()
			end
		end)
		:catch(function() end)

	-- 1s ticker: live progress for PlayTime + smooth bars + badge between server pushes.
	task.spawn(function()
		while gui.Parent do
			render()
			task.wait(1)
		end
	end)
end

return QuestController

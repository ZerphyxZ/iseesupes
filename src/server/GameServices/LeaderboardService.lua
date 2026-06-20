--!strict

-- Global ordered-datastore leaderboards on Workspace models.
-- Expects: Workspace/Map/Leaderboards/{Speed,Wins,Rebirth,Time}Leaderboard
--   each with Leaderboard → Board → SurfaceGui → ScrollingFrame → Template or Entry_1
-- Fallback template: ReplicatedStorage/Templates/LeaderboardEntry

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local UserService = game:GetService("UserService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local LeaderboardConfigs = require(ReplicatedStorage.Shared.Configs.LeaderboardConfigs)

local DataService: any = nil

local LeaderboardService = Knit.CreateService({
	Name = "LeaderboardService",
	Client = {
		--- ({ [boardKey]: topUserId }) — fired when any board's #1 player changes.
		TopUsersChanged = Knit.CreateSignal(),
	},
})

local orderedDataStores: { [string]: OrderedDataStore } = {}
--- boardKey → userId of the current #1 player (for showcase stands).
local topUserCache: { [string]: number } = {}
local sessionStartAt: { [Player]: number } = {}
local lastOdsWritten: { [Player]: { [string]: number } } = {}
local usernameCache: { [number]: string } = {}
local pendingNameLabels: { [number]: { TextLabel } } = {}
local usernameResolvePending: { [number]: boolean } = {}
local usernameResolveRunning = false
local refreshCoalesceThread: thread? = nil

local DEBUG_LEADERBOARD = false

local function lbPrint(...: any)
	if DEBUG_LEADERBOARD then
		print("[iseesupes][Leaderboard]", ...)
	end
end

local function isValidUserId(userId: number?): boolean
	return type(userId) == "number" and userId > 0
end

local function getCachedUsername(userId: number): string?
	local inServer = Players:GetPlayerByUserId(userId)
	if inServer then
		usernameCache[userId] = inServer.Name
		return inServer.Name
	end
	return usernameCache[userId]
end

local function fallbackUsername(userId: number): string
	return "Player"
end

local function applyResolvedName(userId: number)
	local name = getCachedUsername(userId) or fallbackUsername(userId)
	local labels = pendingNameLabels[userId]
	if not labels then
		return
	end
	pendingNameLabels[userId] = nil
	for _, label in labels do
		if label.Parent then
			label.Text = name
		end
	end
end

local function trackNameLabel(userId: number, label: TextLabel)
	if not pendingNameLabels[userId] then
		pendingNameLabels[userId] = {}
	end
	table.insert(pendingNameLabels[userId], label)
end

--- One global batch per tick — never blocks board render; retries on HTTP 429.
local function processUsernameQueue()
	if usernameResolveRunning then
		return
	end
	usernameResolveRunning = true

	task.spawn(function()
		while true do
			local missing: { number } = {}
			for userId in usernameResolvePending do
				if isValidUserId(userId) and not getCachedUsername(userId) then
					table.insert(missing, userId)
				end
				usernameResolvePending[userId] = nil
			end

			if #missing == 0 then
				break
			end

			lbPrint("resolveUsernames batch", #missing)

			local ok, infos = pcall(function()
				return UserService:GetUserInfosByUserIdsAsync(missing)
			end)
			if ok and type(infos) == "table" then
				for _, info in infos do
					if type(info.Id) == "number" and type(info.Username) == "string" and info.Username ~= "" then
						usernameCache[info.Id] = info.Username
						applyResolvedName(info.Id)
					end
				end
			else
				lbPrint("GetUserInfosByUserIdsAsync failed:", infos)
				for _, userId in missing do
					if not getCachedUsername(userId) then
						usernameResolvePending[userId] = true
					end
				end
				usernameResolveRunning = false
				task.delay(8, processUsernameQueue)
				return
			end

			task.wait(0.35)
		end

		usernameResolveRunning = false
	end)
end

local function queueUsernameResolve(userIds: { number })
	for _, userId in userIds do
		if isValidUserId(userId) and not getCachedUsername(userId) then
			usernameResolvePending[userId] = true
		end
	end
	if next(usernameResolvePending) and not usernameResolveRunning then
		processUsernameQueue()
	end
end

local function shouldFlushPlayTime(boardKeys: { string }?): boolean
	if boardKeys == nil then
		return true
	end
	for _, boardKey in boardKeys do
		if boardKey == "Time" then
			return true
		end
	end
	return false
end

local function getODS(storeName: string): OrderedDataStore?
	if orderedDataStores[storeName] then
		return orderedDataStores[storeName]
	end
	local success, ods = pcall(function()
		return DataStoreService:GetOrderedDataStore(storeName)
	end)
	if success and ods then
		orderedDataStores[storeName] = ods
		return ods
	end
	warn("[iseesupes] LeaderboardService: failed to get OrderedDataStore:", storeName)
	return nil
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

local function getLeaderboardsFolder(): Folder?
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return nil
	end

	local bestFolder: Folder? = nil
	local bestCount = -1

	-- GetDescendants (not GetChildren) so a Leaderboards folder still resolves if it
	-- gets nested deeper (e.g. accidentally dragged into Lobby) instead of breaking.
	for _, child in map:GetDescendants() do
		if not child:IsA("Folder") or child.Name ~= "Leaderboards" then
			continue
		end

		local boardCount = 0
		for _, config in LeaderboardConfigs.Boards do
			if child:FindFirstChild(config.ModelName) then
				boardCount += 1
			end
		end

		if boardCount > bestCount then
			bestCount = boardCount
			bestFolder = child
		end
	end

	return bestFolder
end

local function findStudioEntryRow(scrollingFrame: ScrollingFrame): GuiObject?
	local entry1 = scrollingFrame:FindFirstChild("Entry_1")
	if entry1 and entry1:IsA("GuiObject") then
		return entry1
	end
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("GuiObject") and string.match(child.Name, "^Entry_") then
			return child
		end
	end
	return nil
end

local function ensureEntryTemplate(scrollingFrame: ScrollingFrame): GuiObject?
	local template = scrollingFrame:FindFirstChild("Template")
	if template and template:IsA("GuiObject") then
		return template
	end

	local studioRow = findStudioEntryRow(scrollingFrame)
	if studioRow then
		local clone = studioRow:Clone()
		clone.Name = "Template"
		clone.Visible = false
		clone.Parent = scrollingFrame
		return clone
	end

	local fromStorage = waitPath(ReplicatedStorage, LeaderboardConfigs.TemplatePath, 2)
	if fromStorage and fromStorage:IsA("GuiObject") then
		return fromStorage
	end

	return nil
end

local function clearDisplay(scrollingFrame: ScrollingFrame)
	local template = scrollingFrame:FindFirstChild("Template")
	for _, child in scrollingFrame:GetChildren() do
		if child:IsA("UILayout") then
			continue
		end
		if child == template then
			continue
		end
		child:Destroy()
	end
end

local function ensureListLayoutSortOrder(scrollingFrame: ScrollingFrame): UIListLayout
	local listLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if not listLayout then
		listLayout = Instance.new("UIListLayout")
		listLayout.Name = "ListLayout"
		listLayout.FillDirection = Enum.FillDirection.Vertical
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.Padding = UDim.new(0, 2)
		listLayout.Parent = scrollingFrame
	end
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	-- We size the canvas EXPLICITLY (applyCanvasSize below) instead of relying on
	-- AutomaticCanvasSize, which can misbehave on a SurfaceGui ScrollingFrame and was leaving the
	-- board crammed. Manual sizing + fixed-height rows = deterministic, scrollable, readable.
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	scrollingFrame.ScrollingEnabled = true
	scrollingFrame.ScrollBarThickness = 14
	scrollingFrame.ScrollBarImageTransparency = 0.2
	return listLayout
end

--- Size the canvas to exactly fit `rowCount` fixed-height rows so the board scrolls to the rows
--- below the fold (top rows stay readable) and reset the scroll to the top on each refresh.
local function applyCanvasSize(scrollingFrame: ScrollingFrame, rowCount: number)
	local entryH = LeaderboardConfigs.EntryHeightPx
	if typeof(entryH) ~= "number" or entryH <= 0 then
		entryH = 48
	end
	local listLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	local pad = if listLayout then listLayout.Padding.Offset else 0
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, math.max(0, rowCount) * (entryH + pad) + pad)
	scrollingFrame.CanvasPosition = Vector2.zero
end

-- Studio layout: {Model}Leaderboard → Leaderboard → Board (Part) → SurfaceGui → ScrollingFrame.
-- A sibling [UnionOperation] Board also has SurfaceGui (title only); FindFirstChildWhichIsA("SurfaceGui")
-- often picks that one first, so ScrollingFrame lookup fails.
local function resolveLeaderboardScrollingFrame(leaderboardModel: Instance): ScrollingFrame?
	local inner = leaderboardModel:FindFirstChild("Leaderboard")
	if inner then
		local board = inner:FindFirstChild("Board")
		if board then
			local surfaceGui = board:FindFirstChild("SurfaceGui")
			if surfaceGui then
				local scrollingFrame = surfaceGui:FindFirstChild("ScrollingFrame")
				if scrollingFrame and scrollingFrame:IsA("ScrollingFrame") then
					return scrollingFrame
				end
			end
		end
	end

	for _, descendant in leaderboardModel:GetDescendants() do
		if descendant:IsA("ScrollingFrame") then
			return descendant
		end
	end

	return nil
end

local function trackSessionStart(player: Player)
	sessionStartAt[player] = os.clock()
end

local function flushPlayTimeToProfile(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile or not profile.Data then
		return
	end

	local started = sessionStartAt[player]
	if not started then
		return
	end

	local elapsed = math.floor(os.clock() - started)
	if elapsed <= 0 then
		return
	end

	local data = profile.Data
	if type(data.TotalPlayTime) ~= "number" then
		data.TotalPlayTime = 0
	end
	data.TotalPlayTime += elapsed
	sessionStartAt[player] = os.clock()
end

local function renderEntry(
	entryTemplate: GuiObject,
	scrollingFrame: ScrollingFrame,
	rank: number,
	userId: number,
	playerName: string,
	scoreText: string
): GuiObject?
	local newEntry = entryTemplate:Clone()
	newEntry.Name = "Entry_" .. tostring(rank)

	-- Force a fixed pixel height + full width so 50 rows stay readable regardless of the
	-- Studio-authored template. A scale-Y height collapses when 50 rows stack; and a
	-- UIAspectRatioConstraint / UISizeConstraint on the row would OVERRIDE the height we set, so
	-- strip those first or the fixed height won't stick (this is the likely cause of the crammed
	-- live board).
	if newEntry:IsA("GuiObject") then
		for _, c in newEntry:GetChildren() do
			if c:IsA("UIAspectRatioConstraint") or c:IsA("UISizeConstraint") then
				c:Destroy()
			end
		end
		local entryH = LeaderboardConfigs.EntryHeightPx
		if typeof(entryH) ~= "number" or entryH <= 0 then
			entryH = 48
		end
		newEntry.Size = UDim2.new(1, 0, 0, entryH)
	end

	local rankLabel = newEntry:FindFirstChild("RankLabel")
	local nameLabel = newEntry:FindFirstChild("NameLabel")
	local scoreLabel = newEntry:FindFirstChild("ScoreLabel")
	local imageLabel = newEntry:FindFirstChild("ImageLabel")

	if not rankLabel or not rankLabel:IsA("TextLabel") then
		lbPrint("renderEntry missing RankLabel rank", rank, "template", entryTemplate:GetFullName())
	end
	if not nameLabel or not nameLabel:IsA("TextLabel") then
		lbPrint("renderEntry missing NameLabel rank", rank, "template", entryTemplate:GetFullName())
	end
	if not scoreLabel or not scoreLabel:IsA("TextLabel") then
		lbPrint("renderEntry missing ScoreLabel rank", rank, "template", entryTemplate:GetFullName())
	end

	if rankLabel and rankLabel:IsA("TextLabel") then
		rankLabel.Text = "#" .. tostring(rank)
	end
	if nameLabel and nameLabel:IsA("TextLabel") then
		local resolved = getCachedUsername(userId)
		if resolved then
			nameLabel.Text = resolved
		elseif playerName ~= "" then
			nameLabel.Text = playerName
		else
			nameLabel.Text = "..."
			trackNameLabel(userId, nameLabel)
		end
	end
	if scoreLabel and scoreLabel:IsA("TextLabel") then
		scoreLabel.Text = scoreText
	end
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
	end

	newEntry.LayoutOrder = rank
	newEntry.Parent = scrollingFrame
	newEntry.Visible = true
	return newEntry
end

local function getServerFallbackRows(config: LeaderboardConfigs.LeaderboardConfig): { { userId: number, name: string, score: number } }
	local rows: { { userId: number, name: string, score: number } } = {}

	for _, player in Players:GetPlayers() do
		local profile = DataService:GetProfile(player)
		if not profile or not profile.Data then
			continue
		end
		local score = config.GetScore(profile.Data)
		if type(score) ~= "number" then
			continue
		end
		table.insert(rows, {
			userId = player.UserId,
			name = player.Name,
			score = math.floor(score),
		})
	end

	table.sort(rows, function(a, b)
		return a.score > b.score
	end)

	return rows
end

local function getBoardKey(config: LeaderboardConfigs.LeaderboardConfig): string?
	for key, cfg in LeaderboardConfigs.Boards do
		if cfg == config then
			return key
		end
	end
	return nil
end

local function setTopUser(config: LeaderboardConfigs.LeaderboardConfig, userId: number?)
	local boardKey = getBoardKey(config)
	if not boardKey or not userId or userId <= 0 then
		return
	end
	if topUserCache[boardKey] == userId then
		return
	end
	topUserCache[boardKey] = userId
	LeaderboardService.Client.TopUsersChanged:FireAll(topUserCache)
end

function LeaderboardService.Client:GetTopUsers(_player: Player): { [string]: number }
	return topUserCache
end

--- With 10+ players claiming wins, per-claim refreshes blow the OrderedDataStore
--- read budget (GetSortedAsync). One refresh per board per interval is plenty —
--- boards are ambient UI, not realtime.
local lastDisplayRefreshAt: { [string]: number } = {}
local DISPLAY_REFRESH_MIN_INTERVAL = 20

function LeaderboardService:UpdateDisplay(config: LeaderboardConfigs.LeaderboardConfig): { number }?
	local boardKey = getBoardKey(config) or config.ModelName
	local now = os.clock()
	local last = lastDisplayRefreshAt[config.StoreName]
	if last and now - last < DISPLAY_REFRESH_MIN_INTERVAL then
		lbPrint("UpdateDisplay skipped (rate limit)", boardKey)
		return nil
	end
	lastDisplayRefreshAt[config.StoreName] = now

	local folder = getLeaderboardsFolder()
	if not folder then
		warn("[iseesupes] LeaderboardService: missing Workspace." .. table.concat(LeaderboardConfigs.RootPath, "."))
		return nil
	end

	local leaderboardModel = folder:FindFirstChild(config.ModelName)
	if not leaderboardModel then
		if config.ModelName ~= "StageLeaderboard" then
			warn("[iseesupes] LeaderboardService: missing model", config.ModelName)
		end
		return nil
	end

	local scrollingFrame = resolveLeaderboardScrollingFrame(leaderboardModel)
	if not scrollingFrame then
		warn("[iseesupes] LeaderboardService: missing ScrollingFrame in", config.ModelName)
		return nil
	end

	ensureListLayoutSortOrder(scrollingFrame)

	local entryTemplate = ensureEntryTemplate(scrollingFrame)
	if not entryTemplate then
		warn(
			"[iseesupes] LeaderboardService: missing entry template (ScrollingFrame/Template, Entry_1, or ReplicatedStorage."
				.. table.concat(LeaderboardConfigs.TemplatePath, ".")
				.. ")"
		)
		return nil
	end

	local orderedDataStore = getODS(config.StoreName)
	if not orderedDataStore then
		return nil
	end

	local getSuccess, pages = pcall(function()
		return orderedDataStore:GetSortedAsync(false, LeaderboardConfigs.TopN)
	end)

	if not getSuccess or not pages then
		warn("[iseesupes] LeaderboardService: GetSortedAsync failed for", config.StoreName, pages)
		return nil
	end

	local dataPage = pages:GetCurrentPage()

	clearDisplay(scrollingFrame)
	if entryTemplate.Parent == scrollingFrame then
		entryTemplate.Visible = false
	end

	local pageUserIds: { number } = {}

	for _, entryData in dataPage do
		local userId = tonumber(entryData.key)
		if isValidUserId(userId) then
			table.insert(pageUserIds, userId :: number)
		end
	end

	for _, entryData in dataPage do
		local topUserId = tonumber(entryData.key)
		if isValidUserId(topUserId) then
			setTopUser(config, topUserId)
			break
		end
	end

	if #dataPage == 0 then
		local fallbackRows = getServerFallbackRows(config)
		if fallbackRows[1] then
			setTopUser(config, fallbackRows[1].userId)
		end
		for rank, row in ipairs(fallbackRows) do
			renderEntry(
				entryTemplate,
				scrollingFrame,
				rank,
				row.userId,
				row.name,
				config.ScoreFormatter(row.score)
			)
		end
		applyCanvasSize(scrollingFrame, #fallbackRows)
		return pageUserIds
	end

	local displayRank = 0
	for _, entryData in ipairs(dataPage) do
		local userId = tonumber(entryData.key)
		local score = entryData.value
		if not isValidUserId(userId) or type(score) ~= "number" then
			continue
		end

		displayRank += 1
		renderEntry(
			entryTemplate,
			scrollingFrame,
			displayRank,
			userId :: number,
			"",
			config.ScoreFormatter(score)
		)
	end

	applyCanvasSize(scrollingFrame, displayRank)
	queueUsernameResolve(pageUserIds)
	return pageUserIds
end

function LeaderboardService:_RefreshAllDisplaysNow()
	local allUserIds: { number } = {}
	local seen: { [number]: boolean } = {}

	for _, config in LeaderboardConfigs.Boards do
		local pageUserIds = self:UpdateDisplay(config)
		if pageUserIds then
			for _, userId in pageUserIds do
				if not seen[userId] then
					seen[userId] = true
					table.insert(allUserIds, userId)
				end
			end
		end
	end

	queueUsernameResolve(allUserIds)
end

function LeaderboardService:RefreshAllDisplays()
	if refreshCoalesceThread then
		task.cancel(refreshCoalesceThread)
	end
	refreshCoalesceThread = task.delay(2, function()
		refreshCoalesceThread = nil
		self:_RefreshAllDisplaysNow()
	end)
end

function LeaderboardService:SavePlayer(player: Player, boardKeys: { string }?)
	if shouldFlushPlayTime(boardKeys) then
		flushPlayTimeToProfile(player)
	end

	local profile = DataService:GetProfile(player)
	if not profile or not profile.Data then
		return
	end

	local data = profile.Data
	local userKey = tostring(player.UserId)
	local written = lastOdsWritten[player]
	if not written then
		written = {}
		lastOdsWritten[player] = written
	end

	local function saveBoard(boardKey: string)
		local config = LeaderboardConfigs.Boards[boardKey]
		if not config then
			return
		end
		local score = config.GetScore(data)
		if type(score) ~= "number" then
			return
		end
		local floored = math.max(0, math.floor(score))
		if written[boardKey] == floored then
			return
		end
		local ods = getODS(config.StoreName)
		if ods then
			local ok, err = pcall(function()
				ods:SetAsync(userKey, floored)
			end)
			if ok then
				written[boardKey] = floored
			else
				warn("[iseesupes][Leaderboard] SavePlayer failed", player.Name, boardKey, err)
			end
		end
	end

	if boardKeys then
		for _, boardKey in boardKeys do
			saveBoard(boardKey)
		end
	else
		for boardKey in LeaderboardConfigs.Boards do
			saveBoard(boardKey)
		end
	end
end

function LeaderboardService:SaveAllPlayers()
	for _, player in Players:GetPlayers() do
		self:SavePlayer(player)
	end
end

function LeaderboardService:KnitStart()
	DataService = Knit.GetService("DataService")

	local function onPlayerAdded(player: Player)
		trackSessionStart(player)
		task.spawn(function()
			local deadline = os.clock() + 30
			while os.clock() < deadline do
				local profile = DataService:GetProfile(player)
				if profile and profile.Data then
					self:SavePlayer(player)
					self:RefreshAllDisplays()
					break
				end
				task.wait(1)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		self:SavePlayer(player)
		sessionStartAt[player] = nil
		lastOdsWritten[player] = nil
	end)

	task.delay(5, function()
		self:SaveAllPlayers()
		task.wait(1)
		self:RefreshAllDisplays()
	end)

	task.spawn(function()
		while true do
			task.wait(LeaderboardConfigs.RefreshInterval)
			self:RefreshAllDisplays()
		end
	end)

	task.spawn(function()
		while true do
			task.wait(LeaderboardConfigs.SaveInterval)
			self:SaveAllPlayers()
		end
	end)

	game:BindToClose(function()
		self:SaveAllPlayers()
		task.wait(2)
	end)

	StudioLog.ready("LeaderboardService")
end

return LeaderboardService

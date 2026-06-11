--!strict

-- Global ordered-datastore leaderboards on Workspace models.
-- Expects: Workspace/Map/Leaderboards/{Speed,Wins,Rebirth,Time}Leaderboard
--   each with Leaderboard → Board → SurfaceGui → ScrollingFrame → Template or Entry_1
-- Fallback template: ReplicatedStorage/Templates/LeaderboardEntry

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

	for _, child in map:GetChildren() do
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
)
	local newEntry = entryTemplate:Clone()
	newEntry.Name = "Entry_" .. tostring(rank)

	local rankLabel = newEntry:FindFirstChild("RankLabel")
	local nameLabel = newEntry:FindFirstChild("NameLabel")
	local scoreLabel = newEntry:FindFirstChild("ScoreLabel")
	local imageLabel = newEntry:FindFirstChild("ImageLabel")

	if rankLabel and rankLabel:IsA("TextLabel") then
		rankLabel.Text = "#" .. tostring(rank)
	end
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = playerName
	end
	if scoreLabel and scoreLabel:IsA("TextLabel") then
		scoreLabel.Text = scoreText
	end
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
	end

	newEntry.Parent = scrollingFrame
	newEntry.Visible = true
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

function LeaderboardService:UpdateDisplay(config: LeaderboardConfigs.LeaderboardConfig)
	local now = os.clock()
	local last = lastDisplayRefreshAt[config.StoreName]
	if last and now - last < DISPLAY_REFRESH_MIN_INTERVAL then
		return
	end
	lastDisplayRefreshAt[config.StoreName] = now

	local folder = getLeaderboardsFolder()
	if not folder then
		warn(
			"[iseesupes] LeaderboardService: missing Workspace."
				.. table.concat(LeaderboardConfigs.RootPath, ".")
		)
		return
	end

	local leaderboardModel = folder:FindFirstChild(config.ModelName)
	if not leaderboardModel then
		warn("[iseesupes] LeaderboardService: missing model", config.ModelName)
		return
	end

	local scrollingFrame = resolveLeaderboardScrollingFrame(leaderboardModel)
	if not scrollingFrame then
		warn("[iseesupes] LeaderboardService: missing ScrollingFrame in", config.ModelName)
		return
	end

	local entryTemplate = ensureEntryTemplate(scrollingFrame)
	if not entryTemplate then
		warn(
			"[iseesupes] LeaderboardService: missing entry template (ScrollingFrame/Template, Entry_1, or ReplicatedStorage."
				.. table.concat(LeaderboardConfigs.TemplatePath, ".")
				.. ")"
		)
		return
	end

	local orderedDataStore = getODS(config.StoreName)
	if not orderedDataStore then
		return
	end

	local getSuccess, pages = pcall(function()
		return orderedDataStore:GetSortedAsync(false, LeaderboardConfigs.TopN)
	end)

	if not getSuccess or not pages then
		warn("[iseesupes] LeaderboardService: GetSortedAsync failed for", config.StoreName, pages)
		return
	end

	local dataPage = pages:GetCurrentPage()

	clearDisplay(scrollingFrame)
	if entryTemplate.Parent == scrollingFrame then
		entryTemplate.Visible = false
	end

	local topEntry = dataPage[1]
	if topEntry then
		setTopUser(config, tonumber(topEntry.key))
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
		return
	end

	for rank, entryData in ipairs(dataPage) do
		local userId = tonumber(entryData.key)
		local score = entryData.value
		if not userId then
			continue
		end

		task.spawn(function()
			local nameSuccess, playerName = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if not nameSuccess or type(playerName) ~= "string" then
				playerName = "Loading..."
			end

			if not scrollingFrame.Parent then
				return
			end

			renderEntry(entryTemplate, scrollingFrame, rank, userId, playerName, config.ScoreFormatter(score))
		end)
	end
end

function LeaderboardService:RefreshAllDisplays()
	for _, config in LeaderboardConfigs.Boards do
		self:UpdateDisplay(config)
	end
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
			local ok = pcall(function()
				ods:SetAsync(userKey, floored)
			end)
			if ok then
				written[boardKey] = floored
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

	print("[iseesupes] LeaderboardService ready.")
end

return LeaderboardService

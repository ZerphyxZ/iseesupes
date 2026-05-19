--!strict

-- Global ordered-datastore leaderboards on Workspace models.
-- Expects: Workspace/Leaderboards/{SpeedLeaderboard,WinsLeaderboard,RebirthLeaderboard}
--   each with a SurfaceGui → ScrollingFrame → Template (Frame)
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
	Client = {},
})

local orderedDataStores: { [string]: OrderedDataStore } = {}

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

local function resolveEntryTemplate(scrollingFrame: ScrollingFrame): GuiObject?
	local template = scrollingFrame:FindFirstChild("Template")
	if template and template:IsA("GuiObject") then
		return template
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
		if not child:IsA("UILayout") and child ~= template then
			child:Destroy()
		end
	end
end

function LeaderboardService:UpdateDisplay(config: LeaderboardConfigs.LeaderboardConfig)
	local folder = Workspace:FindFirstChild(LeaderboardConfigs.FolderName)
	if not folder then
		warn("[iseesupes] LeaderboardService: missing Workspace/" .. LeaderboardConfigs.FolderName)
		return
	end

	local leaderboardModel = folder:FindFirstChild(config.ModelName)
	if not leaderboardModel then
		warn("[iseesupes] LeaderboardService: missing model", config.ModelName)
		return
	end

	local surfaceGui = leaderboardModel:FindFirstChildWhichIsA("SurfaceGui", true)
	if not surfaceGui then
		warn("[iseesupes] LeaderboardService: missing SurfaceGui in", config.ModelName)
		return
	end

	local scrollingFrame = surfaceGui:FindFirstChildWhichIsA("ScrollingFrame", true)
	if not scrollingFrame then
		warn("[iseesupes] LeaderboardService: missing ScrollingFrame in", config.ModelName)
		return
	end

	local entryTemplate = resolveEntryTemplate(scrollingFrame)
	if not entryTemplate then
		warn(
			"[iseesupes] LeaderboardService: missing entry template (ScrollingFrame/Template or ReplicatedStorage."
				.. table.concat(LeaderboardConfigs.TemplatePath, ".")
				.. ")"
		)
		return
	end

	clearDisplay(scrollingFrame)
	if entryTemplate.Parent == scrollingFrame then
		entryTemplate.Visible = false
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
	if #dataPage == 0 then
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
				scoreLabel.Text = config.ScoreFormatter(score)
			end
			if imageLabel and imageLabel:IsA("ImageLabel") then
				imageLabel.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
			end

			newEntry.Parent = scrollingFrame
			newEntry.Visible = true
		end)
	end
end

function LeaderboardService:RefreshAllDisplays()
	for _, config in LeaderboardConfigs.Boards do
		self:UpdateDisplay(config)
	end
end

function LeaderboardService:SavePlayer(player: Player)
	local profile = DataService:GetProfile(player)
	if not profile or not profile.Data then
		return
	end

	local data = profile.Data
	local userKey = tostring(player.UserId)

	for _, config in LeaderboardConfigs.Boards do
		local score = config.GetScore(data)
		if score and score > 0 then
			local ods = getODS(config.StoreName)
			if ods then
				pcall(function()
					ods:SetAsync(userKey, score)
				end)
			end
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

	task.delay(5, function()
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

	Players.PlayerRemoving:Connect(function(player)
		self:SavePlayer(player)
	end)

	game:BindToClose(function()
		self:SaveAllPlayers()
		task.wait(2)
	end)

	print("[iseesupes] LeaderboardService ready.")
end

return LeaderboardService

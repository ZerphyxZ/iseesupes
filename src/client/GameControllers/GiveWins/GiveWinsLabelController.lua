--!strict

-- Client-only: rewrite each GiveWins stage-end button's WinAmount label to the LOCAL player's
-- rebirth-boosted payout, so the displayed price matches what the player actually receives.
--
-- WHY this is safe / never double-counts: the server (GiveWinsService) computes the grant from the
-- BASE amount (the original label text / WinAmount attribute) and applies the rebirth multiplier
-- exactly once. We only change the label TEXT on this client, and client-side instance changes do
-- NOT replicate up to the server — so the server still sees the base. Each player sees their own
-- boosted numbers; a 0-rebirth player sees (and gets) the base.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GiveWinsConfigs = require(ReplicatedStorage.Shared.Configs.GiveWinsConfigs)
local GiveDoubleWinsConfigs = require(ReplicatedStorage.Shared.Configs.GiveDoubleWinsConfigs)
local RebirthConfigs = require(ReplicatedStorage.Shared.Configs.RebirthConfigs)
local WinAmountParser = require(ReplicatedStorage.Shared.Utils.WinAmountParser)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local GiveWinsLabelController = Knit.CreateController({ Name = "GiveWinsLabelController" })

local player = Players.LocalPlayer

-- Per WinAmount label: the BASE amount and the original text template — both captured ONCE, before
-- we ever overwrite the text, so re-applies (on rebirth) always recompute from the base, never off
-- our own previous edit.
local baseByLabel: { [TextLabel]: number } = {}
local templateByLabel: { [TextLabel]: string } = {}
local boundFolders: { [Instance]: boolean } = {}
local lastRebirths = -1

-- Both the free GiveWins buttons AND the Robux "2x Wins" (GiveDoubleWins) buttons — same label
-- shape and same rebirth scaling, so display == payout on both. (FolderNames lists candidate
-- names; only the one that exists under Map resolves.)
local FOLDER_NAMES: { string } = { GiveWinsConfigs.FolderName }
for _, name in GiveDoubleWinsConfigs.FolderNames do
	table.insert(FOLDER_NAMES, name)
end

local function getRebirths(): number
	-- Prefer leaderstats (an always-present replicated Instance) over DataLib (module state that
	-- can be empty in some contexts). Both match the server's profile Rebirths.
	local ls = player:FindFirstChild("leaderstats")
	local rb = ls and ls:FindFirstChild("Rebirths")
	if rb and rb:IsA("ValueBase") and type((rb :: any).Value) == "number" then
		return math.floor((rb :: any).Value)
	end
	local data = DataLib.GetData()
	if type(data) == "table" and type(data.Rebirths) == "number" then
		return math.floor(data.Rebirths)
	end
	return 0
end

-- Same shared formula the server payout uses (RebirthConfigs.ApplyWinsBoost), so the shown number
-- == the granted number for both the free buttons and the Robux 2x buttons.
local function grantedAmount(base: number, rebirths: number): number
	return RebirthConfigs.ApplyWinsBoost(base, rebirths)
end

local function findWinLabel(button: Instance): TextLabel?
	local touch = button:FindFirstChild(GiveWinsConfigs.TouchPartName)
	for _, root in { touch, button } do
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("TextLabel") and d.Name == GiveWinsConfigs.WinAmountLabelName then
					return d
				end
			end
		end
	end
	return nil
end

local function refreshLabel(label: TextLabel)
	local base = baseByLabel[label]
	local template = templateByLabel[label]
	if not base or not template then
		return
	end
	local amount = grantedAmount(base, getRebirths())
	-- Swap the first number in the original text, preserving its "+… Wins" formatting.
	label.Text = (string.gsub(template, "%d+", tostring(amount), 1))
end

local function registerButton(button: Instance)
	if not button:IsA("Model") then
		return
	end
	local label = findWinLabel(button)
	if not label then
		return
	end
	if not baseByLabel[label] then
		-- Mirror GiveWinsService.resolveWinAmount: the label is the source of truth, attribute is
		-- the fallback. Capture BEFORE overwriting so the base is the true original.
		local base = WinAmountParser.parse(label.Text)
		if not base then
			local attr = button:GetAttribute(GiveWinsConfigs.WinAmountAttribute)
			if typeof(attr) == "number" and attr > 0 then
				base = math.floor(attr)
			end
		end
		if not base then
			return
		end
		baseByLabel[label] = base
		templateByLabel[label] = label.Text
	end
	refreshLabel(label)
end

local function scanAndBind()
	for _, folderName in FOLDER_NAMES do
		local folder = MapWorld.findChildInMap(folderName)
		if folder then
			for _, child in folder:GetChildren() do
				registerButton(child)
			end
			if not boundFolders[folder] then
				boundFolders[folder] = true
				folder.ChildAdded:Connect(function(child)
					task.defer(registerButton, child)
				end)
			end
		end
	end
end

local function refreshAll()
	for label in baseByLabel do
		refreshLabel(label)
	end
end

function GiveWinsLabelController:KnitStart()
	local function applyForCurrentRebirths()
		lastRebirths = getRebirths()
		scanAndBind()
		refreshAll()
	end

	DataLib.OnReady(applyForCurrentRebirths)
	-- Only re-apply when the rebirth count actually changes (data replicates on every wins tick).
	DataLib.OnChanged(function()
		if getRebirths() ~= lastRebirths then
			applyForCurrentRebirths()
		end
	end)

	-- React directly to the leaderstats Rebirths value (the reliable source) so labels refresh
	-- the instant the player rebirths, with no dependency on a data replication landing first.
	local rebirthsWatched = false
	local function watchRebirthsStat()
		if rebirthsWatched then
			return
		end
		local ls = player:FindFirstChild("leaderstats")
		local rb = ls and ls:FindFirstChild("Rebirths")
		if rb and rb:IsA("ValueBase") then
			rebirthsWatched = true
			rb:GetPropertyChangedSignal("Value"):Connect(applyForCurrentRebirths)
			applyForCurrentRebirths()
		end
	end
	watchRebirthsStat()
	player.ChildAdded:Connect(function(c)
		if c.Name == "leaderstats" then
			task.defer(watchRebirthsStat)
			c.ChildAdded:Connect(function(g)
				if g.Name == "Rebirths" then
					task.defer(watchRebirthsStat)
				end
			end)
		end
	end)

	-- Buttons / their billboards may stream or clone in after boot — catch late arrivals.
	for _, delaySeconds in { 1, 3, 6 } do
		task.delay(delaySeconds, scanAndBind)
	end

	StudioLog.ready("GiveWinsLabelController")
end

return GiveWinsLabelController

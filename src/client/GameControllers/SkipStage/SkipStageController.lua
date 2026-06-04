--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local SkipStageController = Knit.CreateController({ Name = "SkipStageController" })

local MIN_STAGE = 2
local MAX_STAGE = 9

local player = Players.LocalPlayer
local selectedStage = MIN_STAGE
local stageBoxRef: TextBox? = nil -- kept so DataLib callback can update it

local function clampStage(n: number): number
	return math.clamp(math.floor(n), MIN_STAGE, MAX_STAGE)
end

local function updateStageUI()
	if stageBoxRef then
		stageBoxRef.Text = tostring(selectedStage)
	end
end

--- Called whenever profile data arrives / changes (DataReplicated signal).
--- Keeps the selector pointing at the stage AFTER the player's current one.
local function syncFromData(data: any)
	if not data then
		return
	end
	local stage = type(data.Stage) == "number" and data.Stage or 0
	local want = clampStage(stage + 1)
	if want ~= selectedStage then
		selectedStage = want
		updateStageUI()
	end
end

function SkipStageController:KnitStart()
	local SkipStageService = Knit.GetService("SkipStageService")

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("GUI", 120)
	if not gui then
		warn("[SkipStageController] Timed out waiting for GUI")
		return
	end
	local hud = gui:WaitForChild("HUD", 30)
	if not hud then
		warn("[SkipStageController] HUD not found")
		return
	end
	local skipstageFrame = hud:WaitForChild("Skipstage", 30) :: Frame?
	if not skipstageFrame or not skipstageFrame:IsA("Frame") then
		warn("[SkipStageController] Skipstage frame not found in HUD")
		return
	end

	local changeStage = skipstageFrame:WaitForChild("ChangeStage") :: Frame
	local skipButton = skipstageFrame:WaitForChild("SkipButton") :: ImageButton
	local stageBox = changeStage:WaitForChild("StageNumber") :: TextBox
	local plusButton = changeStage:WaitForChild("Plus") :: ImageButton
	local minusButton = changeStage:WaitForChild("Minus") :: ImageButton

	stageBoxRef = stageBox
	stageBox.TextEditable = false

	-- Sync immediately from whatever data is already cached
	syncFromData(DataLib.GetData())

	-- Auto-update whenever profile data changes (catches checkpoint touches live)
	DataLib.OnChanged(syncFromData)

	plusButton.MouseButton1Click:Connect(function()
		selectedStage = clampStage(selectedStage + 1)
		updateStageUI()
	end)

	minusButton.MouseButton1Click:Connect(function()
		selectedStage = clampStage(selectedStage - 1)
		updateStageUI()
	end)

	skipButton.MouseButton1Click:Connect(function()
		local product = ProductConfigs.GetSkipStageProductByStage(selectedStage)
		if not product then
			NotificationManager.show("Stage " .. selectedStage .. " teleport not available.", "Error")
			return
		end
		if product.Id == 0 then
			NotificationManager.show("Stage teleport not yet configured.", "Info")
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.Id)
	end)

	-- Server signal: player physically touched a checkpoint
	-- DataLib.OnChanged above already handles the update, but this fires immediately
	-- (before the full DataReplicated round-trip) for snappier UI.
	SkipStageService.StageChanged:Connect(function(newStage: number)
		local want = clampStage(newStage + 1)
		selectedStage = want
		updateStageUI()
	end)

	updateStageUI()
	print("[SkipStageController] ready.")
end

return SkipStageController

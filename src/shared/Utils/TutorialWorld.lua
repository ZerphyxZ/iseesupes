--!strict

local TutorialConfigs = require(script.Parent.Parent.Configs.TutorialConfigs)
local MapWorld = require(script.Parent.MapWorld)
local StageCheckpointWorld = require(script.Parent.StageCheckpointWorld)

local TutorialWorld = {}

local function findTouchOnModel(model: Model, touchName: string): BasePart?
	local touch = model:FindFirstChild(touchName)
	if touch and touch:IsA("BasePart") then
		return touch
	end
	for _, desc in model:GetDescendants() do
		if desc.Name == touchName and desc:IsA("BasePart") then
			return desc
		end
	end
	return nil
end

local function pickTargetPart(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local largest: BasePart? = nil
	local largestVol = 0
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			local part = desc :: BasePart
			local vol = part.Size.X * part.Size.Y * part.Size.Z
			if vol > largestVol then
				largestVol = vol
				largest = part
			end
		end
	end
	return largest
end

local function findModelButton(folder: Instance?, buttonName: string): Model?
	if not folder then
		return nil
	end
	local direct = folder:FindFirstChild(buttonName)
	if direct and direct:IsA("Model") then
		return direct
	end
	for _, child in folder:GetChildren() do
		if child.Name == buttonName and child:IsA("Model") then
			return child
		end
	end
	-- Fallback: first button model in folder.
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			return child
		end
	end
	return nil
end

local function findTreadmillsFolder(): Folder?
	local mapFolder = MapWorld.findChildInMap(TutorialConfigs.TreadmillsFolderName)
	if mapFolder and mapFolder:IsA("Folder") then
		return mapFolder
	end

	local map = MapWorld.getMapFolder()
	if map then
		local child = map:FindFirstChild(TutorialConfigs.TreadmillsFolderName)
		if child and child:IsA("Folder") then
			return child
		end
	end

	local wsTreadmills = workspace:FindFirstChild(TutorialConfigs.TreadmillsFolderName)
	if wsTreadmills and wsTreadmills:IsA("Folder") then
		return wsTreadmills
	end

	return nil
end

function TutorialWorld.getBasicTreadmillModel(): Model?
	local treadmills = findTreadmillsFolder()
	if not treadmills then
		return nil
	end

	local modelName = TutorialConfigs.getBasicTreadmillModelName()
	local model = treadmills:FindFirstChild(modelName)
	if model and model:IsA("Model") then
		return model
	end

	-- Fallback: first treadmill model in folder (Studio naming may differ).
	for _, child in treadmills:GetChildren() do
		if child:IsA("Model") then
			return child
		end
	end

	return nil
end

function TutorialWorld.getBasicTreadmillTarget(): BasePart?
	local model = TutorialWorld.getBasicTreadmillModel()
	if not model then
		return nil
	end
	return pickTargetPart(model)
end

function TutorialWorld.getGiveWinsButton1Touch(): BasePart?
	local folder = MapWorld.findChildInMap(TutorialConfigs.GiveWinsFolderName)
	local button = findModelButton(folder, TutorialConfigs.GiveWinsButtonName)
	if not button then
		return nil
	end
	return findTouchOnModel(button, TutorialConfigs.GiveWinsTouchPartName)
end

function TutorialWorld.getUpgradeWinsButton1Touch(): BasePart?
	local folder = MapWorld.findChildInMap(TutorialConfigs.UpgradeWinsFolderName)
	local button = findModelButton(folder, TutorialConfigs.UpgradeWinsButtonName)
	if not button then
		return nil
	end
	return findTouchOnModel(button, TutorialConfigs.UpgradeWinsTouchPartName)
end

function TutorialWorld.getThrustShopHighlightModel(): Model?
	local folder = MapWorld.findChildInMap(TutorialConfigs.ThrustShopFolderName)
	if not folder then
		return nil
	end
	local touchModel = folder:FindFirstChild(TutorialConfigs.ThrustShopTouchModelName)
	if touchModel and touchModel:IsA("Model") then
		return touchModel
	end
	if folder:IsA("Model") then
		return folder
	end
	return nil
end

function TutorialWorld.getThrustShopTouch(): BasePart?
	local folder = MapWorld.findChildInMap(TutorialConfigs.ThrustShopFolderName)
	if not folder then
		return nil
	end
	local touchModel = folder:FindFirstChild(TutorialConfigs.ThrustShopTouchModelName)
	if touchModel and touchModel:IsA("Model") then
		local touch = findTouchOnModel(touchModel, TutorialConfigs.ThrustShopTouchPartName)
		if touch then
			return touch
		end
		return pickTargetPart(touchModel)
	end
	local direct = folder:FindFirstChild(TutorialConfigs.ThrustShopTouchPartName)
	if direct and direct:IsA("BasePart") then
		return direct
	end
	return nil
end

local function collectPartsUnderStage1Entry(entry: Instance?): { BasePart }
	local parts: { BasePart } = {}
	if not entry then
		return parts
	end
	if entry:IsA("BasePart") then
		table.insert(parts, entry :: BasePart)
	elseif entry:IsA("Model") or entry:IsA("Folder") then
		for _, desc in entry:GetDescendants() do
			if desc:IsA("BasePart") then
				table.insert(parts, desc :: BasePart)
			end
		end
	end
	return parts
end

local function getStageCheckpointsFolder(): Instance?
	local folder = MapWorld.findChildInMap(TutorialConfigs.StageCheckpointsFolderName)
	if folder then
		return folder
	end
	local map = MapWorld.getMapFolder()
	if map then
		local inMap = map:FindFirstChild(TutorialConfigs.StageCheckpointsFolderName)
		if inMap then
			return inMap
		end
	end
	local atRoot = workspace:FindFirstChild(TutorialConfigs.StageCheckpointsFolderName)
	if atRoot then
		return atRoot
	end
	return nil
end

function TutorialWorld.getStage1TouchParts(): { BasePart }
	local folder = getStageCheckpointsFolder()
	if not folder then
		return {}
	end
	local child = folder:FindFirstChild(TutorialConfigs.Stage1CheckpointName)
	local parts = collectPartsUnderStage1Entry(child)
	if #parts > 0 then
		return parts
	end
	-- Fallback: any BasePart named "1" under checkpoints.
	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name == TutorialConfigs.Stage1CheckpointName then
			table.insert(parts, desc :: BasePart)
		end
	end
	return parts
end

function TutorialWorld.getStage1CheckpointTarget(): BasePart?
	-- Prefer the melt gate (stable wall target); touch parts may be small/trigger-sized.
	local gate = StageCheckpointWorld.getGatePart(1)
	if gate then
		return gate
	end

	local parts = TutorialWorld.getStage1TouchParts()
	if #parts == 0 then
		return nil
	end
	local largest: BasePart? = nil
	local largestVol = 0
	for _, part in parts do
		local vol = part.Size.X * part.Size.Y * part.Size.Z
		if vol > largestVol then
			largestVol = vol
			largest = part
		end
	end
	return largest
end

function TutorialWorld.getTargetForStep(step: number): BasePart?
	if step == TutorialConfigs.Step.GoTreadmill then
		return TutorialWorld.getBasicTreadmillTarget()
	end
	if step == TutorialConfigs.Step.ClaimWins then
		return TutorialWorld.getGiveWinsButton1Touch()
	end
	if step == TutorialConfigs.Step.UpgradeAvatar then
		return TutorialWorld.getUpgradeWinsButton1Touch()
	end
	if step == TutorialConfigs.Step.GoStage1 then
		return TutorialWorld.getStage1CheckpointTarget()
	end
	return nil
end

function TutorialWorld.waitForTarget(step: number, timeout: number?): BasePart?
	local limit = timeout or TutorialConfigs.WorldResolveTimeout
	local deadline = os.clock() + limit
	while os.clock() < deadline do
		local part = TutorialWorld.getTargetForStep(step)
		if part then
			return part
		end
		task.wait(0.2)
	end
	return TutorialWorld.getTargetForStep(step)
end

return TutorialWorld

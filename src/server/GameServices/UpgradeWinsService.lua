--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local AvatarReplace = require(ReplicatedStorage.Shared.Utils.AvatarReplace)
local StepBonusParser = require(ReplicatedStorage.Shared.Utils.StepBonusParser)
local UpgradeWinsConfigs = require(ReplicatedStorage.Shared.Configs.UpgradeWinsConfigs)
local WinAmountParser = require(ReplicatedStorage.Shared.Utils.WinAmountParser)
local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)

export type UpgradeResultKind = "Unlocked" | "Equipped" | "NotEnoughWins" | "AvatarMissing" | "InvalidButton"

local UpgradeWinsService = Knit.CreateService({
	Name = "UpgradeWinsService",
	Client = {
		UpgradeResult = Knit.CreateSignal(), -- (kind: string, avatarId: string)
	},
})

local DataService: any = nil
local DoubleJumpService: any = nil
local SuperJumpService: any = nil

local touchConns: { [Instance]: RBXScriptConnection } = {}
local buttonMeta: { [Model]: { winCost: number, stepBonus: number, avatarId: string } } = {}
local cooldownUntil: { [Player]: { [Instance]: number } } = {}
local showcaseFolder: Folder? = nil
local equipMutex: { [Player]: boolean } = {}

local EQUIPPED_SHOWCASE_ATTR = AvatarReplace.EQUIPPED_SHOWCASE_ATTR

local function findLabel(root: Instance, labelName: string): TextLabel?
	for _, desc in root:GetDescendants() do
		if desc:IsA("TextLabel") and desc.Name == labelName then
			return desc
		end
	end
	return nil
end

local function formatWinCostLabel(cost: number): string
	return NumberFormatter.Format(cost) .. (if cost == 1 then " Win Required" else " Wins Required")
end

local function syncButtonLabels(button: Model, winCost: number, stepBonus: number, addonText: string?)
	local touch = button:FindFirstChild(UpgradeWinsConfigs.TouchPartName)
	local root = if touch then touch else button

	local winLabel = findLabel(root, UpgradeWinsConfigs.WinCostLabelName)
	if winLabel then
		winLabel.Text = formatWinCostLabel(winCost)
	end

	local addonLabel = findLabel(root, UpgradeWinsConfigs.AddonLabelName)
	if addonLabel then
		addonLabel.Text = addonText or StepBonusParser.format(stepBonus)
	end
end

local function resolveWinCost(button: Model, buttonIndex: number): number?
	local attr = button:GetAttribute(UpgradeWinsConfigs.WinCostAttribute)
	if typeof(attr) == "number" and attr >= 0 then
		return math.floor(attr)
	end

	local touch = button:FindFirstChild(UpgradeWinsConfigs.TouchPartName)
	if touch then
		local label = findLabel(touch, UpgradeWinsConfigs.WinCostLabelName)
		if label then
			local parsed = WinAmountParser.parseWinsRequired(label.Text)
			if parsed then
				return parsed
			end
		end
	end

	local fallback = findLabel(button, UpgradeWinsConfigs.WinCostLabelName)
	if fallback then
		local parsed = WinAmountParser.parseWinsRequired(fallback.Text)
		if parsed then
			return parsed
		end
	end

	local defaults = UpgradeWinsConfigs.getDefaults(buttonIndex)
	if defaults then
		return defaults.WinCost
	end

	return nil
end

local function resolveStepBonus(button: Model, buttonIndex: number): number?
	local attr = button:GetAttribute(UpgradeWinsConfigs.StepBonusAttribute)
	if typeof(attr) == "number" and attr > 0 then
		return math.floor(attr)
	end

	local addonTextAttr = button:GetAttribute(UpgradeWinsConfigs.AddonTextAttribute)
	if typeof(addonTextAttr) == "string" and addonTextAttr ~= "" then
		local parsed = StepBonusParser.parse(addonTextAttr)
		if parsed then
			return parsed
		end
	end

	local touch = button:FindFirstChild(UpgradeWinsConfigs.TouchPartName)
	if touch then
		local label = findLabel(touch, UpgradeWinsConfigs.AddonLabelName)
		if label then
			local parsed = StepBonusParser.parse(label.Text)
			if parsed then
				return parsed
			end
		end
	end

	local fallback = findLabel(button, UpgradeWinsConfigs.AddonLabelName)
	if fallback then
		local parsed = StepBonusParser.parse(fallback.Text)
		if parsed then
			return parsed
		end
	end

	local defaults = UpgradeWinsConfigs.getDefaults(buttonIndex)
	if defaults then
		return defaults.StepBonus
	end

	return 0
end

local function resolveButtonMeta(button: Model): { winCost: number, stepBonus: number, avatarId: string }?
	local buttonIndex = AvatarReplace.getButtonIndex(button)
	if not buttonIndex then
		warn("[iseesupes] UpgradeWins: invalid button name", button:GetFullName())
		return nil
	end

	local avatarId = AvatarReplace.getAvatarId(button)
	if not avatarId then
		return nil
	end

	local winCost = resolveWinCost(button, buttonIndex)
	if winCost == nil then
		warn("[iseesupes] UpgradeWins: could not resolve win cost for", button:GetFullName())
		return nil
	end

	local stepBonus = resolveStepBonus(button, buttonIndex) or 0

	local addonTextAttr = button:GetAttribute(UpgradeWinsConfigs.AddonTextAttribute)
	local addonText = if typeof(addonTextAttr) == "string" then addonTextAttr else nil
	syncButtonLabels(button, winCost, stepBonus, addonText)

	return {
		winCost = winCost,
		stepBonus = stepBonus,
		avatarId = avatarId,
	}
end

local function getShowcaseTemplate(avatarId: string): Model?
	if not showcaseFolder then
		showcaseFolder = Workspace:FindFirstChild(UpgradeWinsConfigs.ShowcaseFolderName) :: Folder?
	end
	if not showcaseFolder then
		return nil
	end
	local template = showcaseFolder:FindFirstChild(avatarId)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function getUnlockedAvatars(data: any): { [string]: boolean }
	if type(data.UnlockedAvatars) ~= "table" then
		data.UnlockedAvatars = {}
	end
	return data.UnlockedAvatars
end

local function isAvatarUnlocked(data: any, avatarId: string): boolean
	return getUnlockedAvatars(data)[avatarId] == true
end

local function endMovementAbilitiesBeforeMorph(player: Player)
	if DoubleJumpService and DoubleJumpService._endAbility then
		DoubleJumpService:_endAbility(player)
	end
	if SuperJumpService and SuperJumpService._endAbility then
		SuperJumpService:_endAbility(player)
	end
end

local function applyEquippedAvatar(player: Player, data: any, avatarId: string, stepBonus: number): boolean
	if equipMutex[player] then
		return false
	end

	data.EquippedAvatar = avatarId
	data.StepSpeedBonus = stepBonus

	local template = getShowcaseTemplate(avatarId)
	if not template then
		return false
	end

	if not AvatarReplace.willUseVisualOnlyEquip(player, template, avatarId) then
		endMovementAbilitiesBeforeMorph(player)
	end

	equipMutex[player] = true
	local result = AvatarReplace.equipShowcaseAvatar(player, template, avatarId)
	equipMutex[player] = nil
	return result.ok
end

local function fireResult(player: Player, kind: UpgradeResultKind, avatarId: string)
	UpgradeWinsService.Client.UpgradeResult:Fire(player, kind, avatarId)
end

function UpgradeWinsService:TryEquipFromProfile(player: Player): boolean
	if equipMutex[player] then
		return false
	end

	local data = DataService and DataService:GetData(player)
	if not data then
		return false
	end

	local avatarId = data.EquippedAvatar
	if typeof(avatarId) ~= "string" or avatarId == "" then
		return false
	end

	local character = player.Character
	if character then
		local currentId = character:GetAttribute(EQUIPPED_SHOWCASE_ATTR)
		if typeof(currentId) == "string" and currentId == avatarId then
			return true
		end
	end

	local template = getShowcaseTemplate(avatarId)
	if not template then
		return false
	end

	if not AvatarReplace.willUseVisualOnlyEquip(player, template, avatarId) then
		endMovementAbilitiesBeforeMorph(player)
	end

	equipMutex[player] = true
	local result = AvatarReplace.equipShowcaseAvatar(player, template, avatarId)
	equipMutex[player] = nil
	return result.ok
end

local function onUpgradeButtonTouched(button: Model, hit: BasePart)
	local meta = buttonMeta[button]
	if not meta then
		return
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local perPlayer = cooldownUntil[player]
	if not perPlayer then
		perPlayer = {}
		cooldownUntil[player] = perPlayer
	end
	local last = perPlayer[button]
	if last and now - last < UpgradeWinsConfigs.TouchDebounce then
		return
	end
	perPlayer[button] = now

	if not DataService then
		return
	end

	local data = DataService:GetData(player)
	if not data then
		return
	end

	local avatarId = meta.avatarId
	local unlocked = isAvatarUnlocked(data, avatarId)

	if unlocked then
		local replaced = applyEquippedAvatar(player, data, avatarId, meta.stepBonus)
		DataService:Replicate(player)
		if replaced then
			fireResult(player, "Equipped", avatarId)
		else
			fireResult(player, "AvatarMissing", avatarId)
		end
		return
	end

	if type(data.Wins) ~= "number" then
		data.Wins = 0
	end
	if data.Wins < meta.winCost then
		fireResult(player, "NotEnoughWins", avatarId)
		return
	end

	if not DataService:TrySpendWins(player, meta.winCost) then
		fireResult(player, "NotEnoughWins", avatarId)
		return
	end

	data = DataService:GetData(player)
	if not data then
		return
	end

	getUnlockedAvatars(data)[avatarId] = true

	local replaced = applyEquippedAvatar(player, data, avatarId, meta.stepBonus)
	DataService:Replicate(player)

	if replaced then
		fireResult(player, "Unlocked", avatarId)
		print("[iseesupes] UpgradeWins:", player.Name, "unlocked avatar", avatarId)
	else
		fireResult(player, "AvatarMissing", avatarId)
		warn("[iseesupes] UpgradeWins: unlocked but showcase missing for", avatarId)
	end
end

local function refreshButtonMeta(button: Model)
	local meta = resolveButtonMeta(button)
	if meta then
		buttonMeta[button] = meta
	end
end

local function bindUpgradeButton(button: Model)
	if touchConns[button] then
		return
	end

	local meta = resolveButtonMeta(button)
	if not meta then
		return
	end
	buttonMeta[button] = meta

	local touchPart = button:FindFirstChild(UpgradeWinsConfigs.TouchPartName)
	if not touchPart or not touchPart:IsA("BasePart") then
		warn("[iseesupes] UpgradeWins: missing Touch part on", button:GetFullName())
		return
	end

	touchPart.CanTouch = true
	touchConns[button] = touchPart.Touched:Connect(function(hit)
		onUpgradeButtonTouched(button, hit)
	end)

	local attrs = {
		UpgradeWinsConfigs.WinCostAttribute,
		UpgradeWinsConfigs.StepBonusAttribute,
		UpgradeWinsConfigs.AddonTextAttribute,
		UpgradeWinsConfigs.AvatarIdAttribute,
	}
	for _, attrName in attrs do
		button:GetAttributeChangedSignal(attrName):Connect(function()
			refreshButtonMeta(button)
		end)
	end

	local touch = button:FindFirstChild(UpgradeWinsConfigs.TouchPartName)
	local root = if touch then touch else button
	local winLabel = findLabel(root, UpgradeWinsConfigs.WinCostLabelName)
	local addonLabel = findLabel(root, UpgradeWinsConfigs.AddonLabelName)
	if winLabel then
		winLabel:GetPropertyChangedSignal("Text"):Connect(function()
			refreshButtonMeta(button)
		end)
	end
	if addonLabel then
		addonLabel:GetPropertyChangedSignal("Text"):Connect(function()
			refreshButtonMeta(button)
		end)
	end
end

local function unbindUpgradeButton(button: Instance)
	local conn = touchConns[button]
	if conn then
		conn:Disconnect()
		touchConns[button] = nil
	end
	if button:IsA("Model") then
		buttonMeta[button] = nil
	end
end

local function scanUpgradeWinsFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			bindUpgradeButton(child)
		end
	end
end

local function stampShowcaseRigIds(folder: Folder)
	local attrName = UpgradeWinsConfigs.ShowcaseRigIdAttribute
	local defaultRigId = UpgradeWinsConfigs.DefaultShowcaseRigId
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local current = child:GetAttribute(attrName)
			if typeof(current) ~= "string" or current == "" then
				child:SetAttribute(attrName, defaultRigId)
			end
		end
	end
end

local function initUpgradeWins()
	showcaseFolder = Workspace:FindFirstChild(UpgradeWinsConfigs.ShowcaseFolderName) :: Folder?
	if not showcaseFolder then
		warn(
			"[iseesupes] UpgradeWinsService: Workspace.",
			UpgradeWinsConfigs.ShowcaseFolderName,
			"not found."
		)
	else
		stampShowcaseRigIds(showcaseFolder)
	end

	local folder = Workspace:FindFirstChild(UpgradeWinsConfigs.FolderName)
	if not folder or not folder:IsA("Folder") then
		warn(
			"[iseesupes] UpgradeWinsService: Workspace.",
			UpgradeWinsConfigs.FolderName,
			"not found."
		)
		return
	end

	scanUpgradeWinsFolder(folder)

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(bindUpgradeButton, child)
		end
	end)

	folder.ChildRemoved:Connect(unbindUpgradeButton)
end

function UpgradeWinsService:KnitStart()
	DataService = Knit.GetService("DataService")
	DoubleJumpService = Knit.GetService("DoubleJumpService")
	SuperJumpService = Knit.GetService("SuperJumpService")
	initUpgradeWins()

	local function onCharacterAdded(player: Player, _character: Model)
		-- Spawn only: defer avoids re-entrancy when replacePlayerCharacter fires CharacterAdded again.
		task.spawn(function()
			UpgradeWinsService:TryEquipFromProfile(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end)

	for _, player in Players:GetPlayers() do
		if player.Character then
			task.spawn(function()
				UpgradeWinsService:TryEquipFromProfile(player)
			end)
		end
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		cooldownUntil[player] = nil
		equipMutex[player] = nil
	end)

	print("[iseesupes] UpgradeWinsService ready.")
end

return UpgradeWinsService

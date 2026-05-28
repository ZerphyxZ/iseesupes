--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GiveWinsConfigs = require(ReplicatedStorage.Shared.Configs.GiveWinsConfigs)
local WinAmountParser = require(ReplicatedStorage.Shared.Utils.WinAmountParser)

local GiveWinsService = Knit.CreateService({
	Name = "GiveWinsService",
	Client = {},
})

local DataService: any = nil
local MonetizationService: any = nil

local touchConns: { [Instance]: RBXScriptConnection } = {}
local buttonWinAmounts: { [Model]: number } = {}
local cooldownUntil: { [Player]: { [Instance]: number } } = {}

local function findWinAmountLabel(root: Instance): TextLabel?
	for _, desc in root:GetDescendants() do
		if desc:IsA("TextLabel") and desc.Name == GiveWinsConfigs.WinAmountLabelName then
			return desc
		end
	end
	return nil
end

local function resolveWinAmount(button: Model): number?
	local attr = button:GetAttribute(GiveWinsConfigs.WinAmountAttribute)
	if typeof(attr) == "number" and attr > 0 then
		return math.floor(attr)
	end

	local touch = button:FindFirstChild(GiveWinsConfigs.TouchPartName)
	if touch then
		local label = findWinAmountLabel(touch)
		if label then
			local parsed = WinAmountParser.parse(label.Text)
			if parsed then
				return parsed
			end
		end
	end

	local fallbackLabel = findWinAmountLabel(button)
	if fallbackLabel then
		return WinAmountParser.parse(fallbackLabel.Text)
	end

	warn("[iseesupes] GiveWins: could not read win amount for", button:GetFullName())
	return nil
end

local function getGrantAmount(player: Player, baseAmount: number): number
	if MonetizationService and MonetizationService:PlayerOwnsGamepass(player, GiveWinsConfigs.DoubleWinsGamepassKey) then
		return baseAmount * 2
	end
	return baseAmount
end

local function onWinButtonTouched(button: Model, _touchPart: BasePart, hit: BasePart)
	local winAmount = buttonWinAmounts[button]
	if not winAmount then
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
	if last and now - last < GiveWinsConfigs.TouchDebounce then
		return
	end
	perPlayer[button] = now

	if not DataService then
		return
	end

	local grant = getGrantAmount(player, winAmount)
	if DataService:AddWins(player, grant) then
		if grant ~= winAmount then
			print("[iseesupes] GiveWins:", player.Name, "+", grant, "wins (2x) from", button.Name)
		else
			print("[iseesupes] GiveWins:", player.Name, "+", grant, "wins from", button.Name)
		end
		DataService:TeleportToLobby(player)
	end
end

local function bindWinButton(button: Model)
	if touchConns[button] then
		return
	end

	local winAmount = resolveWinAmount(button)
	if not winAmount then
		return
	end
	buttonWinAmounts[button] = winAmount

	local touchPart = button:FindFirstChild(GiveWinsConfigs.TouchPartName)
	if not touchPart or not touchPart:IsA("BasePart") then
		warn("[iseesupes] GiveWins: missing Touch part on", button:GetFullName())
		return
	end

	touchPart.CanTouch = true
	touchConns[button] = touchPart.Touched:Connect(function(hit)
		onWinButtonTouched(button, touchPart, hit)
	end)

	button:GetAttributeChangedSignal(GiveWinsConfigs.WinAmountAttribute):Connect(function()
		local updated = resolveWinAmount(button)
		if updated then
			buttonWinAmounts[button] = updated
		end
	end)

	local label = findWinAmountLabel(touchPart) or findWinAmountLabel(button)
	if label then
		label:GetPropertyChangedSignal("Text"):Connect(function()
			local updated = WinAmountParser.parse(label.Text)
			if updated then
				buttonWinAmounts[button] = updated
			end
		end)
	end
end

local function unbindWinButton(button: Instance)
	local conn = touchConns[button]
	if conn then
		conn:Disconnect()
		touchConns[button] = nil
	end
	if button:IsA("Model") then
		buttonWinAmounts[button] = nil
	end
end

local function scanGiveWinsFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			bindWinButton(child)
		end
	end
end

local function initGiveWins()
	local folder = Workspace:FindFirstChild(GiveWinsConfigs.FolderName)
	if not folder or not folder:IsA("Folder") then
		warn(
			"[iseesupes] GiveWinsService: Workspace.",
			GiveWinsConfigs.FolderName,
			"not found. Add stage-end Button models (Button1, …) with Touch + WinAmount."
		)
		return
	end

	scanGiveWinsFolder(folder)

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(bindWinButton, child)
		end
	end)

	folder.ChildRemoved:Connect(unbindWinButton)
end

function GiveWinsService:KnitStart()
	DataService = Knit.GetService("DataService")
	MonetizationService = Knit.GetService("MonetizationService")
	initGiveWins()

	Players.PlayerRemoving:Connect(function(player)
		cooldownUntil[player] = nil
	end)
end

return GiveWinsService

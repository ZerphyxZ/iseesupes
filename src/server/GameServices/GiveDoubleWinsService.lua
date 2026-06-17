--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local GiveDoubleWinsConfigs = require(ReplicatedStorage.Shared.Configs.GiveDoubleWinsConfigs)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local RebirthConfigs = require(ReplicatedStorage.Shared.Configs.RebirthConfigs)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local WinAmountParser = require(ReplicatedStorage.Shared.Utils.WinAmountParser)

local GiveDoubleWinsService = Knit.CreateService({
	Name = "GiveDoubleWinsService",
	Client = {
		RequestProductPrompt = Knit.CreateSignal(),
		PurchaseGranted = Knit.CreateSignal(),
	},
})

type PendingPurchase = {
	button: Model?,
	baseAmount: number,
}

local DataService: any = nil
local SpawnIntroService: any = nil

local touchConns: { RBXScriptConnection } = {}
local boundTouches: { [BasePart]: boolean } = {}
local lastTouchAt: { [Player]: number } = {}
local buttonWinAmounts: { [Model]: number } = {}
local pendingPurchase: { [Player]: PendingPurchase } = {}

local function getProductId(): number
	local product = ProductConfigs.GetProductByKey(GiveDoubleWinsConfigs.ProductKey)
	if product and product.Id ~= 0 then
		return product.Id
	end
	return 0
end

local function findWinAmountLabel(root: Instance): TextLabel?
	for _, desc in root:GetDescendants() do
		if desc:IsA("TextLabel") and desc.Name == GiveDoubleWinsConfigs.WinAmountLabelName then
			return desc
		end
	end
	return nil
end

local function resolveWinAmount(button: Model): number?
	-- The on-screen WinAmount label is the source of truth for the payout. These
	-- Robux buttons are authored at 2x the free button beside them, so the label
	-- IS the amount to grant. A stale WinAmount *attribute* (legacy values like
	-- 1/4/8...) must never override it — that was the "got fewer wins" bug.
	local touch = button:FindFirstChild(GiveDoubleWinsConfigs.TouchPartName)
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
		local parsed = WinAmountParser.parse(fallbackLabel.Text)
		if parsed then
			return parsed
		end
	end

	local attr = button:GetAttribute(GiveDoubleWinsConfigs.WinAmountAttribute)
	if typeof(attr) == "number" and attr > 0 then
		return math.floor(attr)
	end

	return nil
end

local function returnPlayerToLobby(player: Player)
	local introCfg = CharacterConfigs.SpawnIntro
	if SpawnIntroService and introCfg and introCfg.Enabled == true and introCfg.OnWinClaimReturn == true then
		SpawnIntroService:PlayLobbyReturnIntro(player)
	elseif DataService then
		DataService:TeleportToLobby(player)
	end
end

--- Called from MonetizationService after DoubleWins developer product receipt.
function GiveDoubleWinsService:FulfillPurchase(player: Player): boolean
	local pending = pendingPurchase[player]
	-- Grant exactly the wins shown on the button's WinAmount label. These buttons
	-- are authored at 2x the free button next to them, so the label IS the final
	-- payout — do NOT multiply again here.
	local grant = if pending then pending.baseAmount else GiveDoubleWinsConfigs.DefaultGrantWins
	if grant < 1 then
		grant = GiveDoubleWinsConfigs.DefaultGrantWins
	end
	pendingPurchase[player] = nil

	-- Scale by the player's rebirth Wins multiplier, exactly like the free GiveWins buttons, so the
	-- Robux 2x stays a real multiple over the (rebirth-boosted) free amount instead of eroding (and
	-- eventually undercutting the free button) as the player rebirths. The button's authored amount
	-- is the base; ApplyWinsBoost is the same formula GiveWinsService uses.
	local data = DataService and DataService:GetData(player)
	local rebirths = (data and type(data.Rebirths) == "number") and data.Rebirths or 0
	grant = RebirthConfigs.ApplyWinsBoost(grant, rebirths)

	if not DataService or not DataService:AddWins(player, grant) then
		warn("[iseesupes][GiveDoubleWins] FulfillPurchase AddWins failed for", player.Name)
		return false
	end

	returnPlayerToLobby(player)

	GiveDoubleWinsService.Client.PurchaseGranted:Fire(player, grant)
	print("[iseesupes][GiveDoubleWins] granted", grant, "wins to", player.Name)
	return true
end

local function findTouchPart(button: Model): BasePart?
	local touch = button:FindFirstChild(GiveDoubleWinsConfigs.TouchPartName)
	if touch and touch:IsA("BasePart") then
		return touch
	end
	for _, desc in button:GetDescendants() do
		if desc.Name == GiveDoubleWinsConfigs.TouchPartName and desc:IsA("BasePart") then
			return desc
		end
	end
	return nil
end

local function bindButtonTouch(button: Model, touch: BasePart)
	if boundTouches[touch] then
		return
	end
	boundTouches[touch] = true
	touch.CanTouch = true

	table.insert(
		touchConns,
		touch.Touched:Connect(function(hit: BasePart)
			if not hit or not hit.Parent then
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
			local last = lastTouchAt[player] or 0
			if now - last < GiveDoubleWinsConfigs.TouchDebounce then
				return
			end
			lastTouchAt[player] = now

			local baseAmount = buttonWinAmounts[button] or GiveDoubleWinsConfigs.DefaultGrantWins
			pendingPurchase[player] = {
				button = button,
				baseAmount = baseAmount,
			}

			local productId = getProductId()
			GiveDoubleWinsService.Client.RequestProductPrompt:Fire(
				player,
				productId,
				GiveDoubleWinsConfigs.DisplayName,
				false
			)
			print(
				"[iseesupes][GiveDoubleWins] touch",
				button.Name,
				"→",
				player.Name,
				"productId=",
				productId,
				"baseWins=",
				baseAmount
			)
		end)
	)
end

local function bindButton(button: Model)
	local winAmount = resolveWinAmount(button)
	if winAmount then
		buttonWinAmounts[button] = winAmount
	else
		buttonWinAmounts[button] = GiveDoubleWinsConfigs.DefaultGrantWins
		warn("[iseesupes][GiveDoubleWins] using default win amount on", button:GetFullName())
	end

	local touch = findTouchPart(button)
	if not touch then
		warn("[iseesupes][GiveDoubleWins] missing Touch on", button:GetFullName())
		return
	end
	bindButtonTouch(button, touch)
	print("[iseesupes][GiveDoubleWins] bound", button.Name, "wins=", buttonWinAmounts[button])
end

local function scanFolder(folder: Folder)
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			bindButton(child)
		end
	end
end

local function initWorldButtons()
	local folder: Folder? = nil
	for _, name in GiveDoubleWinsConfigs.FolderNames do
		local found = MapWorld.findChildInMap(name)
		if found and found:IsA("Folder") then
			folder = found
			break
		end
	end

	if not folder then
		warn(
			"[iseesupes][GiveDoubleWins] Workspace.Map.",
			table.concat(GiveDoubleWinsConfigs.FolderNames, " or "),
			"not found."
		)
		return
	end

	scanFolder(folder)

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(bindButton, child)
		end
	end)
end

function GiveDoubleWinsService:KnitStart()
	DataService = Knit.GetService("DataService")
	SpawnIntroService = Knit.GetService("SpawnIntroService")
	initWorldButtons()

	Players.PlayerRemoving:Connect(function(player)
		lastTouchAt[player] = nil
		pendingPurchase[player] = nil
	end)

	StudioLog.ready("GiveDoubleWinsService")
end

return GiveDoubleWinsService

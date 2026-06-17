--!strict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local GiveWinsConfigs = require(ReplicatedStorage.Shared.Configs.GiveWinsConfigs)
local RebirthConfigs = require(ReplicatedStorage.Shared.Configs.RebirthConfigs)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local WinAmountParser = require(ReplicatedStorage.Shared.Utils.WinAmountParser)

local GiveWinsService = Knit.CreateService({
	Name = "GiveWinsService",
	Client = {
		-- (amount: number) fired on a win claim so the client can play a celebration
		-- before the lobby return.
		WinCelebration = Knit.CreateSignal(),
	},
})

local DataService: any = nil
local SpawnIntroService: any = nil
local DoubleJumpService: any = nil
local SuperJumpService: any = nil
local BoostService: any = nil
local SkipStageService: any = nil

local touchConns: { [Instance]: RBXScriptConnection } = {}
local buttonWinAmounts: { [Model]: number } = {}
--- Stage a button's claim completes (melt gates are gone — buttons ARE stage progress).
local buttonStages: { [Model]: number } = {}
local cooldownUntil: { [Player]: { [Instance]: number } } = {}
--- One grant per button until the run resets (lobby return / death / gate session reset).
local claimedThisRun: { [Player]: { [Model]: boolean } } = {}
--- Blocks repeat touches while a lobby return is in flight.
local pendingLobbyReturn: { [Player]: boolean } = {}
--- Touch parts disabled until ClearRunClaims (per player, for re-enable).
local disabledTouchByPlayer: { [Player]: { BasePart } } = {}

local function rollbackClaim(player: Player, button: Model)
	local runClaims = claimedThisRun[player]
	if runClaims then
		runClaims[button] = nil
	end
	pendingLobbyReturn[player] = nil
end

local function tryBeginClaim(player: Player, button: Model): boolean
	if pendingLobbyReturn[player] then
		return false
	end
	local runClaims = claimedThisRun[player]
	if runClaims and runClaims[button] then
		if RunService:IsStudio() then
			print("[iseesupes] GiveWins: duplicate claim blocked for", player.Name, button.Name)
		end
		return false
	end
	if not claimedThisRun[player] then
		claimedThisRun[player] = {}
	end
	claimedThisRun[player][button] = true
	pendingLobbyReturn[player] = true
	return true
end

local function disableTouchForClaim(player: Player, touchPart: BasePart)
	touchPart.CanTouch = false
	local list = disabledTouchByPlayer[player]
	if not list then
		list = {}
		disabledTouchByPlayer[player] = list
	end
	table.insert(list, touchPart)
end

local function reenableDisabledTouches(player: Player)
	local disabled = disabledTouchByPlayer[player]
	if not disabled then
		return
	end
	for _, part in disabled do
		if part.Parent then
			part.CanTouch = true
		end
	end
	disabledTouchByPlayer[player] = nil
end

local function findWinAmountLabel(root: Instance): TextLabel?
	for _, desc in root:GetDescendants() do
		if desc:IsA("TextLabel") and desc.Name == GiveWinsConfigs.WinAmountLabelName then
			return desc
		end
	end
	return nil
end

local function resolveWinAmount(button: Model): number?
	-- The on-screen WinAmount label is the source of truth for the payout. A
	-- stale WinAmount *attribute* must never override what the player sees.
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
		local parsed = WinAmountParser.parse(fallbackLabel.Text)
		if parsed then
			return parsed
		end
	end

	local attr = button:GetAttribute(GiveWinsConfigs.WinAmountAttribute)
	if typeof(attr) == "number" and attr > 0 then
		return math.floor(attr)
	end

	warn("[iseesupes] GiveWins: could not read win amount for", button:GetFullName())
	return nil
end

local CHECKPOINTS_FOLDER = "StageCheckpoints"
--- A button must sit within this distance of a gate marker to map to a stage.
local BUTTON_GATE_MAX_DIST = 150

--- Buttons sit ~50 studs before the NEXT stage's gate marker, so a button near
--- gate K marks the END of stage K-1 (ground truth: Button1@gate2, Button2@gate3).
--- Mapped by POSITION, not name — several buttons are named one stage off, and
--- Button3 (sky build area) is deliberately unmapped: 8 buttons cover stages 1-8.
local function resolveButtonStage(button: Model): number?
	local folder = MapWorld.findChildInMap(CHECKPOINTS_FOLDER)
	if not folder then
		return nil
	end

	local touch = button:FindFirstChild(GiveWinsConfigs.TouchPartName)
	local pos = if touch and touch:IsA("BasePart") then touch.Position else button:GetPivot().Position

	local bestGate: number? = nil
	local bestDist = math.huge
	for _, child in folder:GetChildren() do
		local gateNum = tonumber(child.Name)
		local part = if child:IsA("BasePart") then child else child:FindFirstChildWhichIsA("BasePart")
		if gateNum and part then
			local dist = (part.Position - pos).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestGate = gateNum
			end
		end
	end

	if bestGate and bestDist <= BUTTON_GATE_MAX_DIST then
		return math.max(bestGate - 1, 1)
	end
	return nil
end

local function onWinButtonTouched(button: Model, touchPart: BasePart, hit: BasePart)
	local winAmount = buttonWinAmounts[button]
	if not winAmount then
		return
	end
	if hit:IsDescendantOf(button) then
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

	if not tryBeginClaim(player, button) then
		return
	end

	if not DataService then
		rollbackClaim(player, button)
		return
	end

	-- Rebirth perk: permanent Wins multiplier on stage-end claims (the core grind).
	-- Only button claims scale with rebirths — gift wins (login/playtime/starter) don't.
	local data = DataService:GetData(player)
	local rebirths = (data and type(data.Rebirths) == "number") and data.Rebirths or 0
	local grant = RebirthConfigs.ApplyWinsBoost(winAmount, rebirths)
	if not DataService:AddWins(player, grant) then
		rollbackClaim(player, button)
		return
	end

	pcall(function()
		DataService:AdvanceTutorialComplete(player)
	end)

	disableTouchForClaim(player, touchPart)

	print("[iseesupes] GiveWins:", player.Name, "+", grant, "wins from", button.Name)

	-- Celebration moment on the client before we yank them back to the lobby.
	GiveWinsService.Client.WinCelebration:Fire(player, grant)

	-- Buttons are the stage-progress markers now (melt gates removed): claiming
	-- the button at stage S's end records Stage/MaxStage = S and feeds the
	-- StageProgress analytics funnel. AdvanceStageForPlayer dedupes internally.
	local stageCompleted = buttonStages[button]
	if stageCompleted and SkipStageService and SkipStageService.AdvanceStageForPlayer then
		pcall(function()
			SkipStageService:AdvanceStageForPlayer(player, stageCompleted)
		end)
	end

	-- Clear any active boost (used for 1 run only)
	if BoostService and BoostService:IsBoostActive(player) then
		BoostService:ClearBoost(player)
	end

	-- End flight on the server and signal the client.
	-- _endAbility fires AbilityEnded to the client via remote event — we MUST
	-- wait at least one network round-trip before teleporting, otherwise the
	-- client's BodyVelocity/BodyGyro (client-owned flight physics) are still
	-- active when TeleportToLobby moves the HRP → character explodes.
	if DoubleJumpService and DoubleJumpService._endAbility then
		DoubleJumpService:_endAbility(player)
	end
	if SuperJumpService and SuperJumpService._endAbility then
		SuperJumpService:_endAbility(player)
	end
	pcall(function()
		local hv = Knit.GetService("HeatVisionService")
		if hv and hv.ForceEndForLobby then
			hv:ForceEndForLobby(player)
		end
	end)
	player:SetAttribute("ForceStandUp", true)

	-- Hold ~1.5s so the win celebration can play before the lobby return (was 0.25s,
	-- which also covered the network round-trip needed before teleporting).
	task.delay(1.5, function()
		if not player.Parent then
			return
		end
		player:SetAttribute("ForceStandUp", nil)

		local introCfg = CharacterConfigs.SpawnIntro
		if SpawnIntroService and introCfg and introCfg.Enabled == true and introCfg.OnWinClaimReturn == true then
			SpawnIntroService:PlayLobbyReturnIntro(player)
		else
			DataService:TeleportToLobby(player)
		end
	end)
end

--- Cleared when a new stage run starts (lobby return, death, gate session reset).
function GiveWinsService:ClearRunClaims(player: Player)
	reenableDisabledTouches(player)
	claimedThisRun[player] = nil
	pendingLobbyReturn[player] = nil
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

	local stage = resolveButtonStage(button)
	if stage then
		buttonStages[button] = stage
	else
		warn("[iseesupes] GiveWins:", button.Name, "is not near any stage gate marker — claims will not record stage progress")
	end

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
		buttonStages[button] = nil
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
	local folder = MapWorld.findChildInMap(GiveWinsConfigs.FolderName)
	if not folder or not folder:IsA("Folder") then
		warn(
			"[iseesupes] GiveWinsService: Workspace.Map.",
			GiveWinsConfigs.FolderName,
			"not found. Add stage-end Button models (Button1, …) with Touch + WinAmount."
		)
		return
	end

	scanGiveWinsFolder(folder)

	local mapped = {}
	for button, stage in buttonStages do
		table.insert(mapped, button.Name .. "→S" .. tostring(stage))
	end
	table.sort(mapped)
	print("[iseesupes] GiveWins: button→stage map:", table.concat(mapped, "  "))

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(bindWinButton, child)
		end
	end)

	folder.ChildRemoved:Connect(unbindWinButton)
end

function GiveWinsService:KnitStart()
	DataService = Knit.GetService("DataService")
	SpawnIntroService = Knit.GetService("SpawnIntroService")
	pcall(function()
		DoubleJumpService = Knit.GetService("DoubleJumpService")
	end)
	pcall(function()
		SuperJumpService = Knit.GetService("SuperJumpService")
	end)
	pcall(function()
		BoostService = Knit.GetService("BoostService")
	end)
	pcall(function()
		SkipStageService = Knit.GetService("SkipStageService")
	end)
	initGiveWins()

	Players.PlayerRemoving:Connect(function(player)
		cooldownUntil[player] = nil
		reenableDisabledTouches(player)
		claimedThisRun[player] = nil
		pendingLobbyReturn[player] = nil
	end)
end

return GiveWinsService

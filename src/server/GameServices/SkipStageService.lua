--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ProductConfigs = require(ReplicatedStorage.Shared.Configs.ProductConfigs)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local StageCheckpointProgress = require(ReplicatedStorage.Shared.Utils.StageCheckpointProgress)
local StageCheckpointConfigs = require(ReplicatedStorage.Shared.Configs.StageCheckpointConfigs)
local StageCheckpointDebug = require(ReplicatedStorage.Shared.Utils.StageCheckpointDebug)

local SkipStageService = Knit.CreateService({
	Name = "SkipStageService",
	Client = {
		StageChanged = Knit.CreateSignal(), -- (newStage: number)
	},
})

local CHECKPOINTS_FOLDER = "StageCheckpoints"
local SPAWN_PART_NAME = "Spawn"
local TOUCH_DEBOUNCE = 2

-- Land the player this many studs above the Spawn part's top surface so they
-- don't clip into it.
local LANDING_CLEARANCE = 3
-- If no Spawn part is found, fall back to this Y offset above the checkpoint part.
local FALLBACK_Y_OFFSET = 5

local DataService: any = nil
local FunnelAnalyticsService: any = nil
local StageCheckpointService: any = nil
local touchTimes: { [number]: number } = {}

local function notifyMaxStageReached(player: Player, newMaxStage: number)
	if FunnelAnalyticsService and FunnelAnalyticsService.recordStageReached then
		FunnelAnalyticsService:recordStageReached(player, newMaxStage)
	end
end

local function getCheckpointPart(stage: number): BasePart?
	local folder = MapWorld.findChildInMap(CHECKPOINTS_FOLDER)
	if not folder then
		return nil
	end
	local part = folder:FindFirstChild(tostring(stage))
	return if part and part:IsA("BasePart") then part :: BasePart else nil
end

--- Returns the dedicated `Spawn` part inside the stage's checkpoint container.
--- Each stage has its own Spawn part — guaranteed safe ground placed by the level designer.
local function getStageSpawnPart(stage: number): BasePart?
	local folder = MapWorld.findChildInMap(CHECKPOINTS_FOLDER)
	if not folder then
		return nil
	end
	local stageEntry = folder:FindFirstChild(tostring(stage))
	if not stageEntry then
		return nil
	end
	local spawnPart = stageEntry:FindFirstChild(SPAWN_PART_NAME)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart :: BasePart
	end
	return nil
end

function SkipStageService:TeleportToStage(player: Player, stage: number): boolean
	local checkPart = getCheckpointPart(stage)
	if not checkPart then
		warn("[SkipStageService] No checkpoint part for stage", stage)
		return false
	end

	local character = player.Character
	if not character then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return false
	end

	-- Reset character stance before teleporting so player stands upright
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end

	-- Use the dedicated Spawn part inside this stage's checkpoint model — guaranteed
	-- safe ground placed by the level designer. Falls back to checkpoint+offset if missing.
	local spawnPart = getStageSpawnPart(stage)
	local landingPosition: Vector3
	if spawnPart then
		-- Top of the Spawn part + clearance so the character doesn't clip into it
		landingPosition = spawnPart.Position + Vector3.new(0, spawnPart.Size.Y * 0.5 + LANDING_CLEARANCE, 0)
	else
		landingPosition = checkPart.Position + Vector3.new(0, FALLBACK_Y_OFFSET, 0)
		warn("[SkipStageService] No Spawn part inside stage", stage, "— using checkpoint fallback")
	end
	hrp.CFrame = CFrame.new(landingPosition)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	local profile = DataService:GetProfile(player)
	if profile then
		local current = type(profile.Data.Stage) == "number" and profile.Data.Stage or 1
		if stage > current then
			profile.Data.Stage = stage
		end
		local maxStage = type(profile.Data.MaxStage) == "number" and profile.Data.MaxStage or 0
		if stage > maxStage then
			profile.Data.MaxStage = stage
			notifyMaxStageReached(player, stage)
		end
		DataService:Replicate(player)
	end

	-- Reset character stance after a small delay to ensure proper state
	task.delay(0.1, function()
		if not player.Parent then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
			humanoid.Sit = false
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
	end)

	SkipStageService.Client.StageChanged:Fire(player, stage)
	if StageCheckpointService and StageCheckpointService.ApplySkipStageSession then
		StageCheckpointService:ApplySkipStageSession(player, stage)
	end
	print("[SkipStageService] Teleported", player.Name, "to Stage", stage)
	return true
end

function SkipStageService:AdvanceStageForPlayer(player: Player, stageNum: number): boolean
	if stageNum > StageCheckpointConfigs.MaxGateStage then
		return false
	end
	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		return false
	end

	local currentStage = StageCheckpointProgress.getEffectiveStage(profile.Data)
	if stageNum <= currentStage then
		StageCheckpointDebug.log(
			string.format(
				"AdvanceStageForPlayer skip player=%s stage=%d current=%d",
				player.Name,
				stageNum,
				currentStage
			),
			player.Name .. ":advanceSkip",
			2
		)
		return false
	end

	profile.Data.Stage = stageNum
	local maxStage = type(profile.Data.MaxStage) == "number" and profile.Data.MaxStage or 0
	if stageNum > maxStage then
		profile.Data.MaxStage = stageNum
		notifyMaxStageReached(player, stageNum)
	end
	DataService:Replicate(player)
	SkipStageService.Client.StageChanged:Fire(player, stageNum)
	print("[SkipStageService]", player.Name, "reached Stage", stageNum)
	StageCheckpointDebug.logAlways(string.format("AdvanceStageForPlayer OK player=%s stage=%d", player.Name, stageNum))
	return true
end

function SkipStageService.Client:GetCurrentStage(player: Player): number
	local profile = DataService and DataService:GetProfile(player)
	if profile then
		return StageCheckpointProgress.getEffectiveStage(profile.Data)
	end
	return 0
end

-- Returns the product ID for a given stage teleport (used by MonetizationService).
function SkipStageService:GetProductIdForStage(stage: number): number
	local product = ProductConfigs.GetSkipStageProductByStage(stage)
	return if product then product.Id else 0
end

local function connectCheckpointTouches()
	local folder = MapWorld.findChildInMap(CHECKPOINTS_FOLDER)
	if not folder then
		warn("[SkipStageService] StageCheckpoints folder not found in Map")
		return
	end

	local gateCount = 0
	for _, child in folder:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local stageNum = tonumber(child.Name)
		if stageNum and stageNum <= StageCheckpointConfigs.MaxGateStage then
			gateCount += 1
		end
	end

	print("[SkipStageService]", gateCount, "stage gate part(s) — unlock with heat vision (F) only, not touch")
end

--- Print a live funnel showing how many players in this server have reached each stage.
function SkipStageService:PrintFunnel()
	local counts: { [number]: number } = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService and DataService:GetProfile(player)
		if profile then
			local max = type(profile.Data.MaxStage) == "number" and profile.Data.MaxStage or 0
			counts[max] = (counts[max] or 0) + 1
		end
	end
	local total = #Players:GetPlayers()
	print(string.format("[SkipStageService] === Stage Funnel (%d players) ===", total))
	for stage = 0, 10 do
		local n = counts[stage] or 0
		if n > 0 or stage <= 9 then
			local pct = if total > 0 then math.round(n / total * 100) else 0
			print(string.format("  Stage %2d max: %3d players (%d%%)", stage, n, pct))
		end
	end
end

function SkipStageService:KnitStart()
	DataService = Knit.GetService("DataService")
	FunnelAnalyticsService = Knit.GetService("FunnelAnalyticsService")
	StageCheckpointService = Knit.GetService("StageCheckpointService")

	task.defer(connectCheckpointTouches)

	-- Print funnel every 5 minutes for developer visibility
	task.spawn(function()
		while true do
			task.wait(300)
			SkipStageService:PrintFunnel()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		touchTimes[player.UserId] = nil
	end)

	print("[SkipStageService] ready.")
end

return SkipStageService

--!strict

-- RainbowCarpet Touch → GodSpeed Aura developer product → infinite thrust + boosted speed for one run.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GodSpeedAuraConfigs = require(ReplicatedStorage.Shared.Configs.GodSpeedAuraConfigs)
local LevelDesignConfigs = require(ReplicatedStorage.Shared.Configs.LevelDesignConfigs)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local SpeedConfigs = require(ReplicatedStorage.Shared.Configs.SpeedConfigs)
local HeatVisionConfigs = require(ReplicatedStorage.Shared.Configs.HeatVisionConfigs)

local GodSpeedAuraService = Knit.CreateService({
	Name = "GodSpeedAuraService",
	Client = {
		RequestProductPrompt = Knit.CreateSignal(),
		RunBuffGranted = Knit.CreateSignal(),
		RunBuffCleared = Knit.CreateSignal(),
	},
})

local DataService: any = nil

local touchConns: { RBXScriptConnection } = {}
local boundTouches: { [BasePart]: boolean } = {}
local lastTouchAt: { [Player]: number } = {}
local savedWalkMult: { [Player]: number? } = {}
local deathConns: { [Player]: RBXScriptConnection } = {}

local function getWalkMultAttr(): string
	return LevelDesignConfigs.Speed.MultiplierAttribute
end

local function findRainbowCarpet(): Model?
	local map = MapWorld.getMapFolder()
	if not map then
		return nil
	end
	local found = map:FindFirstChild(GodSpeedAuraConfigs.ModelName, true)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

local function findTouchPart(model: Model): BasePart?
	local touch = model:FindFirstChild(GodSpeedAuraConfigs.TouchPartName, true)
	if touch and touch:IsA("BasePart") then
		return touch
	end
	for _, desc in model:GetDescendants() do
		if desc.Name == GodSpeedAuraConfigs.TouchPartName and desc:IsA("BasePart") then
			return desc
		end
	end
	return nil
end

function GodSpeedAuraService:IsRunBuffActive(player: Player): boolean
	return player:GetAttribute(GodSpeedAuraConfigs.ActiveAttribute) == true
end

function GodSpeedAuraService:ClearRunBuff(player: Player)
	if not self:IsRunBuffActive(player) then
		savedWalkMult[player] = nil
		return
	end

	player:SetAttribute(GodSpeedAuraConfigs.ActiveAttribute, nil)
	player:SetAttribute(GodSpeedAuraConfigs.InfiniteThrustAttribute, nil)
	player:SetAttribute(GodSpeedAuraConfigs.SpeedGainMultiplierAttribute, nil)
	player:SetAttribute(GodSpeedAuraConfigs.WalkSpeedMultiplierAttribute, nil)

	local walkAttr = getWalkMultAttr()
	local restore = savedWalkMult[player]
	savedWalkMult[player] = nil
	if typeof(restore) == "number" then
		player:SetAttribute(walkAttr, restore)
	else
		player:SetAttribute(walkAttr, LevelDesignConfigs.Speed.DefaultMultiplier)
	end

	if DataService then
		DataService:Replicate(player)
	end

	GodSpeedAuraService.Client.RunBuffCleared:Fire(player)
	print("[iseesupes][GodSpeedAura] cleared run buff for", player.Name)
end

function GodSpeedAuraService:GrantRunBuff(player: Player): boolean
	local profile = DataService and DataService:GetProfile(player)
	if not profile then
		return false
	end

	local cfg = GodSpeedAuraConfigs
	local walkAttr = getWalkMultAttr()
	if not self:IsRunBuffActive(player) then
		local currentMult = player:GetAttribute(walkAttr)
		if typeof(currentMult) == "number" then
			savedWalkMult[player] = currentMult
		else
			savedWalkMult[player] = LevelDesignConfigs.Speed.DefaultMultiplier
		end
	end

	player:SetAttribute(cfg.ActiveAttribute, true)
	player:SetAttribute(cfg.InfiniteThrustAttribute, true)
	player:SetAttribute(cfg.SpeedGainMultiplierAttribute, cfg.SpeedGainMultiplier)
	player:SetAttribute(cfg.WalkSpeedMultiplierAttribute, cfg.WalkSpeedMultiplier)
	player:SetAttribute(walkAttr, cfg.WalkSpeedMultiplier)

	local data = profile.Data
	SpeedConfigs.Thrust.RefillToMax(data)
	HeatVisionConfigs.refillSolarToMax(data)
	DataService:Replicate(player)

	GodSpeedAuraService.Client.RunBuffGranted:Fire(player)
	print(
		"[iseesupes][GodSpeedAura] granted run buff to",
		player.Name,
		"speedGain=",
		cfg.SpeedGainMultiplier,
		"walkMult=",
		cfg.WalkSpeedMultiplier
	)
	return true
end

local function bindDeathClear(player: Player, character: Model)
	if deathConns[player] then
		deathConns[player]:Disconnect()
		deathConns[player] = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	deathConns[player] = humanoid.Died:Connect(function()
		GodSpeedAuraService:ClearRunBuff(player)
	end)
end

local function bindTouch(touch: BasePart)
	if boundTouches[touch] then
		return
	end
	boundTouches[touch] = true
	touch.CanTouch = true
	touch:SetAttribute(GodSpeedAuraConfigs.ProductIdAttribute, GodSpeedAuraConfigs.ProductId)

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
			if now - last < GodSpeedAuraConfigs.TouchDebounce then
				return
			end
			lastTouchAt[player] = now

			print("[iseesupes][GodSpeedAura] touch → prompt for", player.Name)
			GodSpeedAuraService.Client.RequestProductPrompt:Fire(
				player,
				GodSpeedAuraConfigs.ProductId,
				GodSpeedAuraConfigs.DisplayName
			)
		end)
	)

	print("[iseesupes][GodSpeedAura] bound touch", touch:GetFullName())
end

function GodSpeedAuraService:ScanAndBindAll(): number
	for _, conn in touchConns do
		conn:Disconnect()
	end
	table.clear(touchConns)
	table.clear(boundTouches)

	local model = findRainbowCarpet()
	if not model then
		warn("[iseesupes][GodSpeedAura] model not found:", GodSpeedAuraConfigs.ModelName)
		return 0
	end

	local touch = findTouchPart(model)
	if not touch then
		warn("[iseesupes][GodSpeedAura] Touch part not found under", model:GetFullName())
		return 0
	end

	bindTouch(touch)
	return 1
end

function GodSpeedAuraService:KnitStart()
	DataService = Knit.GetService("DataService")

	task.defer(function()
		for attempt = 1, 30 do
			if self:ScanAndBindAll() > 0 then
				break
			end
			task.wait(2)
		end
	end)

	local map = MapWorld.getMapFolder()
	if map then
		map.DescendantAdded:Connect(function(desc)
			if desc.Name == GodSpeedAuraConfigs.TouchPartName and desc:IsA("BasePart") then
				task.defer(function()
					self:ScanAndBindAll()
				end)
			end
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			bindDeathClear(player, character)
		end)
		if player.Character then
			bindDeathClear(player, player.Character)
		end
	end)

	for _, player in Players:GetPlayers() do
		if player.Character then
			bindDeathClear(player, player.Character)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTouchAt[player] = nil
		savedWalkMult[player] = nil
		if deathConns[player] then
			deathConns[player]:Disconnect()
			deathConns[player] = nil
		end
	end)

	print("[iseesupes] GodSpeedAuraService ready.")
end

return GodSpeedAuraService

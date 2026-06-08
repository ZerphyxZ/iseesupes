--!strict

-- Handles the Superman spawn-drop intro:
--   • First join  → lift player on first character load, fire SpawnIntroLifted to client.
--   • Win claim   → teleport to lobby, lift player, fire SpawnIntroLifted to client.
-- Client (SpawnIntroController) listens for SpawnIntroLifted and watches for the
-- landing to play the Superman ground-break VFX.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local CharacterStance = require(ReplicatedStorage.Shared.Utils.CharacterStance)

local SpawnIntroService = Knit.CreateService({
	Name = "SpawnIntroService",
	Client = {
		--- Fired to the owning client when they have been lifted and are about to fall.
		SpawnIntroLifted = Knit.CreateSignal(),
	},
})

local DataService: any = nil
local DoubleJumpService: any = nil
local SuperJumpService: any = nil

local function getCfg()
	return CharacterConfigs.SpawnIntro
end

--- Lift the player's character by LiftHeight studs and signal the client.
local function doLift(player: Player)
	local cfg = getCfg()
	local liftHeight = if cfg and type(cfg.LiftHeight) == "number" then cfg.LiftHeight else 8

	local character = player.Character
	if not character then
		return
	end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	-- Signal client first so it starts the landing watch before the player falls.
	SpawnIntroService.Client.SpawnIntroLifted:Fire(player)
	player:SetAttribute("SpawnIntroPending", true)

	local upright = CharacterStance.buildUprightCFrame(hrp, hrp.CFrame)
	hrp.CFrame = upright + Vector3.new(0, liftHeight, 0)
end

local function resetCharacterStance(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local upright = if hrp then CharacterStance.buildUprightCFrame(hrp, hrp.CFrame) else nil
	CharacterStance.resetToStanding(character, upright)
end

function SpawnIntroService:PlayLobbyReturnIntro(player: Player)
	local cfg = getCfg()
	if not cfg or cfg.Enabled ~= true then
		if DataService then
			DataService:TeleportToLobby(player)
		end
		return
	end

	-- Properly end any active flight/ability BEFORE teleporting.
	-- ForceEndForLobby clears the server session, fires AbilityEnded to the client
	-- (sets abilityActive=false, PlatformStand=false, stops all animation tracks).
	-- ForceStandUp attribute is a belt-and-suspenders signal for any residual client state.
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
	task.delay(0.15, function()
		player:SetAttribute("ForceStandUp", nil)
	end)

	if DataService then
		DataService:TeleportToLobby(player)
	end

	-- Minimum 0.3s so the client has time to process ForceStandUp and finish any
	-- in-flight animations before we lift and fire SpawnIntroLifted.
	local settleDelay = math.max(
		if type(cfg.LobbySettleDelay) == "number" then cfg.LobbySettleDelay else 0.08,
		0.3
	)
	local liftHeight = if type(cfg.LiftHeight) == "number" then cfg.LiftHeight else 8

	task.delay(settleDelay, function()
		if not player.Parent then
			return
		end

		local character = player.Character
		if character then
			resetCharacterStance(character)

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end

			local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				local upright = CharacterStance.buildUprightCFrame(hrp, hrp.CFrame)
				hrp.CFrame = upright + Vector3.new(0, liftHeight, 0)
			end

			-- Signal client
			SpawnIntroService.Client.SpawnIntroLifted:Fire(player)
			player:SetAttribute("SpawnIntroPending", true)
		end
	end)
end

function SpawnIntroService:KnitStart()
	DataService = Knit.GetService("DataService")
	pcall(function() DoubleJumpService = Knit.GetService("DoubleJumpService") end)
	pcall(function() SuperJumpService = Knit.GetService("SuperJumpService") end)

	local cfg = getCfg()
	if not cfg or cfg.Enabled ~= true or cfg.OnFirstJoin ~= true then
		print("[iseesupes] SpawnIntroService ready (first-join intro disabled).")
		return
	end

	local prepDelay = if type(cfg.PrepareDelay) == "number" then cfg.PrepareDelay else 0.12

	Players.PlayerAdded:Connect(function(player)
		-- Only run the drop intro on the very first character load.
		local done = false
		player.CharacterAdded:Connect(function()
			if done then
				return
			end
			done = true
			task.delay(prepDelay, function()
				if player.Parent then
					doLift(player)
				end
			end)
		end)
	end)

	print("[iseesupes] SpawnIntroService ready.")
end

return SpawnIntroService

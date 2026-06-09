--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local HeatVisionConfigs = require(ReplicatedStorage.Shared.Configs.HeatVisionConfigs)
local HeatVisionRig = require(ReplicatedStorage.Shared.Utils.HeatVisionRig)
local StageCheckpointDebug = require(ReplicatedStorage.Shared.Utils.StageCheckpointDebug)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)

local StageCheckpointService: any = nil
local DataService: any = nil

local function logHeatVisionRay(player: Player, rayResult: RaycastResult?)
	if not rayResult then
		StageCheckpointDebug.log("HeatVision ray: no hit", player.Name .. ":miss", 2)
		return
	end
	local stageNum = StageCheckpointWorld.getCheckpointFromHit(rayResult.Instance)
	if stageNum then
		StageCheckpointDebug.log(
			string.format(
				"HeatVision ray HIT checkpoint stage=%d part=%s CanQuery=%s group=%s",
				stageNum,
				rayResult.Instance:GetFullName(),
				tostring(rayResult.Instance.CanQuery),
				tostring(rayResult.Instance.CollisionGroup)
			),
			player.Name .. ":gateHit:" .. tostring(stageNum),
			0.35
		)
		return
	end
	StageCheckpointDebug.log(
		string.format("HeatVision ray hit NON-checkpoint: %s", rayResult.Instance:GetFullName()),
		player.Name .. ":nonGate",
		1.5
	)
end

local Features = CharacterConfigs.Features
local ATTR = HeatVisionConfigs.Attributes
local DJ_PHASE_ATTR = "DjAbilityPhase"
local SJ_PHASE_ATTR = "SjAbilityPhase"

type HeatVisionSession = {
	player: Player,
	character: Model,
	rig: HeatVisionRig.HeatVisionRig?,
	lastLook: Vector3,
	startedAt: number,
	lastAimAt: number,
	autoRotateWas: boolean,
}

local HeatVisionService = Knit.CreateService({
	Name = "HeatVisionService",
	Client = {
		AbilityEnded = Knit.CreateSignal(),
		Rejected = Knit.CreateSignal(),
	},
})

local sessions: { [Player]: HeatVisionSession } = {}

local aimMinInterval = 1 / math.max(HeatVisionConfigs.AimSendHz, 1)

local function isPlayerFlying(player: Player): boolean
	local djPhase = player:GetAttribute(DJ_PHASE_ATTR)
	if djPhase ~= nil and djPhase ~= "" then
		return true
	end
	local sjPhase = player:GetAttribute(SJ_PHASE_ATTR)
	return sjPhase ~= nil and sjPhase ~= ""
end

local function flatUnit(vector: Vector3): Vector3
	if vector.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return vector.Unit
end

local function getCharacter(player: Player): Model?
	local character = player.Character
	if character and character.Parent then
		return character
	end
	return nil
end

local function setAimAttributes(player: Player, lookVector: Vector3)
	local unit = flatUnit(lookVector)
	player:SetAttribute(ATTR.AimX, unit.X)
	player:SetAttribute(ATTR.AimY, unit.Y)
	player:SetAttribute(ATTR.AimZ, unit.Z)
end

local function clearAttributes(player: Player)
	player:SetAttribute(ATTR.Active, nil)
	player:SetAttribute(ATTR.AimX, nil)
	player:SetAttribute(ATTR.AimY, nil)
	player:SetAttribute(ATTR.AimZ, nil)
end

local function canStartSolarBeam(player: Player): boolean
	if not DataService or not DataService.CanStartSolar then
		return true
	end
	return DataService:CanStartSolar(player)
end

local function drainSolarForBeam(player: Player, dt: number): boolean
	if not DataService or not DataService.TryConsumeSolar then
		return true
	end
	local drain = HeatVisionConfigs.getSolarDrainPerSecond() * dt
	if drain <= 0 then
		return true
	end
	return DataService:TryConsumeSolar(player, drain)
end

function HeatVisionService:_endAbility(player: Player)
	local session = sessions[player]
	if not session then
		clearAttributes(player)
		return
	end

	local humanoid = session.character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = session.autoRotateWas
	end

	if session.rig then
		HeatVisionRig.setActive(session.rig, false)
	end
	HeatVisionRig.destroy(session.character)
	sessions[player] = nil
	clearAttributes(player)
	self.Client.AbilityEnded:Fire(player)
end

function HeatVisionService:ForceEndForLobby(player: Player)
	if sessions[player] then
		self:_endAbility(player)
	else
		clearAttributes(player)
		local character = getCharacter(player)
		if character then
			HeatVisionRig.destroy(character)
		end
	end
end

function HeatVisionService:_applyAim(session: HeatVisionSession, lookVector: Vector3): RaycastResult?
	session.lastLook = flatUnit(lookVector)
	setAimAttributes(session.player, session.lastLook)
	if session.rig then
		return HeatVisionRig.updateAim(session.rig, session.lastLook, HeatVisionConfigs.MaxRange, nil)
	end
	return nil
end

function HeatVisionService:_tryStart(player: Player): (boolean, string?)
	if not Features.UseHeatVision then
		return false, "disabled"
	end

	if sessions[player] then
		return false, "active"
	end

	if isPlayerFlying(player) then
		return false, "flying"
	end

	if not canStartSolarBeam(player) then
		return false, "no_solar"
	end

	local character = getCharacter(player)
	if not character then
		return false, "no_character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "dead"
	end

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return false, "no_head"
	end

	local rig = HeatVisionRig.mount(character)
	if not rig then
		return false, "no_rig"
	end

	local initialLook = flatUnit(head.CFrame.LookVector)
	local autoRotateWas = humanoid.AutoRotate
	humanoid.AutoRotate = false
	local session: HeatVisionSession = {
		player = player,
		character = character,
		rig = rig,
		lastLook = initialLook,
		startedAt = os.clock(),
		lastAimAt = 0,
		autoRotateWas = autoRotateWas,
	}

	sessions[player] = session
	player:SetAttribute(ATTR.Active, true)
	HeatVisionRig.setActive(rig, true)
	self:_applyAim(session, initialLook)

	if StageCheckpointService and StageCheckpointService.RefreshHeatVisionGateExcludesForPlayer then
		StageCheckpointService:RefreshHeatVisionGateExcludesForPlayer(player)
	end

	humanoid.Died:Once(function()
		self:_endAbility(player)
	end)

	return true, nil
end

function HeatVisionService.Client:RequestStart(player: Player): (boolean, string?)
	local ok, reason = HeatVisionService:_tryStart(player)
	if not ok then
		HeatVisionService.Client.Rejected:Fire(player, reason or "rejected")
	end
	return ok, reason
end

function HeatVisionService.Client:RequestCancel(player: Player): boolean
	if sessions[player] then
		HeatVisionService:_endAbility(player)
		return true
	end
	return false
end

function HeatVisionService:SetBrokenGateRayExcludes(player: Player, gateParts: { Instance })
	local session = sessions[player]
	if not session or not session.rig then
		return
	end
	HeatVisionRig.setRayExcludes(session.rig, gateParts)
end

function HeatVisionService.Client:UpdateAim(player: Player, lookVector: Vector3)
	local session = sessions[player]
	if not session then
		return
	end

	if typeof(lookVector) ~= "Vector3" then
		return
	end

	local now = os.clock()
	if now - session.lastAimAt < aimMinInterval then
		return
	end
	session.lastAimAt = now
	local rayResult = HeatVisionService:_applyAim(session, lookVector)
	logHeatVisionRay(player, rayResult)
	if StageCheckpointService and rayResult then
		StageCheckpointService:tryDamageFromHit(player, rayResult)
	end
end

function HeatVisionService:KnitStart()
	StageCheckpointService = Knit.GetService("StageCheckpointService")
	DataService = Knit.GetService("DataService")

	RunService.Heartbeat:Connect(function(dt)
		for player, session in sessions do
			if player.Parent ~= Players then
				self:_endAbility(player)
			elseif isPlayerFlying(player) then
				self:_endAbility(player)
			elseif not drainSolarForBeam(player, dt) then
				self:_endAbility(player)
			else
				local character = getCharacter(player)
				if not character or character ~= session.character then
					self:_endAbility(player)
				elseif session.rig then
					local rayResult =
						HeatVisionRig.updateAim(session.rig, session.lastLook, HeatVisionConfigs.MaxRange, dt)
					logHeatVisionRay(player, rayResult)
					if StageCheckpointService and rayResult then
						StageCheckpointService:tryDamageFromHit(player, rayResult)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			HeatVisionRig.destroy(session.character)
		end
		sessions[player] = nil
	end)
end

return HeatVisionService

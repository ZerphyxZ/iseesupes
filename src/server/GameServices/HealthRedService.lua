--!strict

-- HealthRed soft damage zones (tag "HealthRed"): lenient, recoverable, CONTINUOUS
-- HP loss while a player stands in/on a tagged part — server-authoritative. Damage
-- scales with the player's max health (percent-based) so it stays visible at any
-- level. Each part's damage is keyed to the stage it sits in (ancestor Stage<N>).
--
-- Detection is a POLLED HRP-in-zone check (TouchZone), not .Touched: .Touched fires
-- only once on entry, so the player must keep taking damage while standing in the
-- zone — polling re-checks every ScanInterval and re-applies (gated by TouchDebounce).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local HealthRedConfigs = require(ReplicatedStorage.Shared.Configs.HealthRedConfigs)
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)
local StageCheckpointWorld = require(ReplicatedStorage.Shared.Utils.StageCheckpointWorld)
local TouchZone = require(ReplicatedStorage.Shared.Utils.TouchZone)

local HealthRedService = Knit.CreateService({
	Name = "HealthRedService",
	Client = {},
})

local partStage: { [BasePart]: number } = {}
local lastHitAt: { [Player]: number } = {}
local deathCooldownUntil: { [Player]: number } = {}

local TreadmillService: any = nil

local function damagePctForStage(stage: number?): number
	if stage and HealthRedConfigs.DamagePctByStage[stage] then
		return HealthRedConfigs.DamagePctByStage[stage]
	end
	return HealthRedConfigs.DefaultDamagePct
end

local function bindPart(inst: Instance)
	if not inst:IsA("BasePart") then
		-- Tag is expected on parts; if it lands on a model, bind its parts.
		for _, desc in inst:GetDescendants() do
			if desc:IsA("BasePart") then
				bindPart(desc)
			end
		end
		return
	end
	if partStage[inst] ~= nil then
		return
	end
	local stage = StageCheckpointWorld.resolveStageFromAncestor(inst) or 0
	partStage[inst] = stage
	if HealthRedConfigs.DebugPrint and RunService:IsStudio() and StudioLog.isEnabled("HealthRed") then
		print(string.format("[iseesupes][HealthRed] bound %s → stage %d", inst:GetFullName(), stage))
	end
end

local function unbindPart(inst: Instance)
	if inst:IsA("BasePart") then
		partStage[inst] = nil
	end
end

local function applyDamage(player: Player, stage: number, hazardPart: BasePart)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if (deathCooldownUntil[player] or 0) > now then
		return
	end

	local last = lastHitAt[player]
	if last and now - last < HealthRedConfigs.TouchDebounce then
		return
	end
	lastHitAt[player] = now

	local dmg = humanoid.MaxHealth * damagePctForStage(stage)
	local newHealth = humanoid.Health - dmg

	if newHealth <= 0 then
		if TreadmillService and TreadmillService.ProcessHazardDeath then
			deathCooldownUntil[player] = now + (HealthRedConfigs.DeathCooldown or 1.5)
			TreadmillService:ProcessHazardDeath(player, hazardPart)
		end
		return
	end

	local floorFraction = HealthRedConfigs.MinHealthFractionFromTouch or 0
	if floorFraction > 0 then
		local floor = humanoid.MaxHealth * floorFraction
		newHealth = math.max(newHealth, floor)
	end
	humanoid.Health = newHealth

	if HealthRedConfigs.DebugPrint and RunService:IsStudio() and StudioLog.isEnabled("HealthRed") then
		print(string.format(
			"[iseesupes][HealthRed] %s -%.0f HP (stage %s) → %.0f / %.0f",
			player.Name, dmg, tostring(stage), humanoid.Health, humanoid.MaxHealth
		))
	end
end

--- Find the most-damaging HealthRed zone each player is standing in, and damage them.
local function scanContacts()
	local zone = HealthRedConfigs.Zone
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local inStage: number? = nil
			local inPart: BasePart? = nil
			for part, stage in partStage do
				if part.Parent and TouchZone.isRootInPartZone(hrp, part, zone) then
					if not inStage or damagePctForStage(stage) > damagePctForStage(inStage) then
						inStage = stage
						inPart = part
					end
				end
			end
			if inStage and inPart then
				applyDamage(player, inStage, inPart)
			end
		end
	end
end

local function startLoop()
	local scanInterval = HealthRedConfigs.ScanInterval or 0.2
	local regenDelay = HealthRedConfigs.RegenDelay or 3
	local regenPct = HealthRedConfigs.RegenPctPerSecond or 0.06
	local scanAccum = 0
	RunService.Heartbeat:Connect(function(dt)
		scanAccum += dt
		if scanAccum < scanInterval then
			return
		end
		local step = scanAccum
		scanAccum = 0
		scanContacts()
		local now = os.clock()
		for _, player in Players:GetPlayers() do
			local last = lastHitAt[player]
			if last and now - last >= regenDelay then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(
						humanoid.MaxHealth,
						humanoid.Health + humanoid.MaxHealth * regenPct * step
					)
				end
			end
		end
	end)
end

function HealthRedService:KnitStart()
	if HealthRedConfigs.Enabled ~= true then
		print("[iseesupes] HealthRedService disabled.")
		return
	end

	TreadmillService = Knit.GetService("TreadmillService")

	local function logSummary(when: string)
		if not StudioLog.isEnabled("HealthRed") then
			return
		end
		local byStage: { [number]: number } = {}
		local total = 0
		for _, stage in partStage do
			byStage[stage] = (byStage[stage] or 0) + 1
			total += 1
		end
		local summary = {}
		for stage, count in byStage do
			table.insert(summary, string.format("S%d=%d", stage, count))
		end
		table.sort(summary)
		print(string.format("[iseesupes] HealthRedService %s — %d HealthRed part(s): %s", when, total, table.concat(summary, " ")))
		if total == 0 then
			warn("[iseesupes] HealthRedService: no parts tagged '" .. HealthRedConfigs.Tag .. "' found — check the tag name on the Stage2-5 hazard parts in Studio (Tags panel).")
		end
	end

	for _, inst in CollectionService:GetTagged(HealthRedConfigs.Tag) do
		bindPart(inst)
	end
	CollectionService:GetInstanceAddedSignal(HealthRedConfigs.Tag):Connect(bindPart)
	CollectionService:GetInstanceRemovedSignal(HealthRedConfigs.Tag):Connect(unbindPart)

	logSummary("ready")

	-- Re-scan once more to catch parts that stream/load in after boot
	-- (already-tagged parts don't fire GetInstanceAddedSignal).
	task.delay(3, function()
		for _, inst in CollectionService:GetTagged(HealthRedConfigs.Tag) do
			bindPart(inst)
		end
		logSummary("re-scan(3s)")
	end)

	startLoop()

	Players.PlayerRemoving:Connect(function(player)
		lastHitAt[player] = nil
		deathCooldownUntil[player] = nil
	end)
end

return HealthRedService

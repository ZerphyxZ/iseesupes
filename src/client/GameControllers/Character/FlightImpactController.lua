--!strict

-- Detects surface impacts during Superman flight via HumanoidRootPart.Touched.
-- Spawns tiered wall/floor breaks when moving fast enough into a surface.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local SupermanVfxConfigs = require(ReplicatedStorage.Shared.Configs.SupermanVfxConfigs)
local SupermanGroundVfx = require(script.Parent.Parent.Parent.Modules.SupermanGroundVfx)

type BreakTier = SupermanVfxConfigs.BreakTier

local FlightImpactController = Knit.CreateController({ Name = "FlightImpactController" })

local player = Players.LocalPlayer
local abilityActive = false
local lastImpactAt = 0

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function resolvePath(root: Instance, segments: { string }): Instance?
	local current: Instance = root
	for _, seg in segments do
		local child = current:FindFirstChild(seg)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function getSoundsFolder(): Folder?
	local folder = resolvePath(ReplicatedStorage, SupermanVfxConfigs.Sounds.FolderPath)
	return if folder and folder:IsA("Folder") then folder :: Folder else nil
end

local function getHrp(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp :: BasePart else nil
end

local function playImpactSound()
	local hrp = getHrp()
	if not hrp then
		return
	end
	local folder = getSoundsFolder()
	if not folder then
		return
	end
	local template = folder:FindFirstChild(SupermanVfxConfigs.Sounds.ImpactBreak)
	if not template or not template:IsA("Sound") then
		warn("[iseesupes][FlightImpact] ImpactBreak sound not found in",
			table.concat(SupermanVfxConfigs.Sounds.FolderPath, " > "))
		return
	end
	local clone = (template :: Sound):Clone()
	clone.Parent = hrp
	clone:Play()
	Debris:AddItem(clone, SupermanVfxConfigs.Sounds.ImpactBreakLifetime)
end

local function classifyImpactTier(normal: Vector3, velocity: Vector3): BreakTier?
	if SupermanGroundVfx.isWallNormal(normal) then
		return "ImpactWall"
	end
	if SupermanGroundVfx.isFloorNormal(normal) then
		if math.abs(velocity.Unit.Y) < 0.35 then
			return nil
		end
		return "ImpactFloor"
	end
	return nil
end

-- ── Impact detection ──────────────────────────────────────────────────────────

local function tryImpact(hitPart: BasePart)
	if not abilityActive then
		return
	end

	if not hitPart.CanCollide then
		return
	end

	local now = os.clock()
	if now - lastImpactAt < SupermanVfxConfigs.Impact.Cooldown then
		return
	end

	local hrp = getHrp()
	if not hrp then
		return
	end

	local vel = hrp.AssemblyLinearVelocity
	if vel.Magnitude < SupermanVfxConfigs.MinImpactSpeed then
		return
	end

	local character = player.Character
	if character and hitPart:IsDescendantOf(character) then
		return
	end

	local rayDir: Vector3
	if vel.Magnitude > 1 then
		rayDir = vel.Unit * SupermanVfxConfigs.Impact.RaycastDistance
	else
		local toHit = hitPart.Position - hrp.Position
		if toHit.Magnitude < 0.01 then
			return
		end
		rayDir = toHit.Unit * SupermanVfxConfigs.Impact.RaycastDistance
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if character then
		params.FilterDescendantsInstances = { character }
	end

	local result = Workspace:Raycast(hrp.Position, rayDir, params)
	if not result then
		return
	end

	local tier = classifyImpactTier(result.Normal, vel)
	if not tier then
		return
	end

	lastImpactAt = now

	if SupermanGroundVfx.spawnSurfaceBreak(tier, result) then
		playImpactSound()
	end
end

-- ── Knit wiring ───────────────────────────────────────────────────────────────

function FlightImpactController:KnitStart()
	local DoubleJumpService = Knit.GetService("DoubleJumpService")

	DoubleJumpService.PhaseChanged:Connect(function(phase: string)
		if phase == "FlightTransit" or phase == "AfterTransition"
			or phase == "LeanUp" or phase == "DownSupes" or phase == "CancelFall"
		then
			abilityActive = true
		else
			abilityActive = false
		end
	end)

	DoubleJumpService.AbilityEnded:Connect(function()
		abilityActive = false
	end)

	local function setupCharacter(character: Model)
		abilityActive = false
		lastImpactAt = 0

		local hrp = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		if not hrp or not hrp:IsA("BasePart") then
			return
		end
		(hrp :: BasePart).Touched:Connect(function(hitPart: BasePart)
			pcall(tryImpact, hitPart)
		end)
	end

	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end

	print("[iseesupes] FlightImpactController ready.")
end

return FlightImpactController

--!strict

-- Tiered surface-break VFX: dark scorch patches, dust bursts, tweened landing debris.
-- Client-only; cleaned up via Debris.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RNG = Random.new()

local SupermanVfxConfigs = require(ReplicatedStorage.Shared.Configs.SupermanVfxConfigs)

type BreakTier = SupermanVfxConfigs.BreakTier

export type SurfaceStyle = {
	color: Color3,
	material: Enum.Material,
}

local SupermanGroundVfx = {}

local activeScorches: { Part } = {}
local lastBreakAt: { [BreakTier]: number } = {}
local landingVfxFolder: Folder? = nil

local function debugLog(...)
	if SupermanVfxConfigs.Debug then
		print("[iseesupes][SupermanGroundVfx]", ...)
	end
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function buildSurfaceBasis(normal: Vector3): (Vector3, Vector3)
	local up = normal.Unit
	local right: Vector3
	if math.abs(up.Y) < 0.85 then
		right = Vector3.new(0, 1, 0):Cross(up)
	else
		right = Vector3.new(1, 0, 0):Cross(up)
	end
	if right.Magnitude < 0.001 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	return right, up
end

local function scaleNumberSequence(seq: NumberSequence, scale: number): NumberSequence
	local keypoints = seq.Keypoints
	local scaled: { NumberSequenceKeypoint } = table.create(#keypoints)
	for i, kp in ipairs(keypoints) do
		scaled[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * scale, kp.Envelope * scale)
	end
	return NumberSequence.new(scaled)
end

local function trimScorchPool()
	local maxCount = SupermanVfxConfigs.MaxActiveScorches
	while #activeScorches > maxCount do
		local oldest = table.remove(activeScorches, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
end

local function registerScorch(part: Part)
	table.insert(activeScorches, part)
	trimScorchPool()
end

local function canSpawnTier(tier: BreakTier): boolean
	local cooldowns = SupermanVfxConfigs.Break.Cooldowns
	local cooldown = cooldowns[tier]
	if not cooldown then
		return true
	end
	local now = os.clock()
	local last = lastBreakAt[tier] or 0
	if now - last < cooldown then
		return false
	end
	lastBreakAt[tier] = now
	return true
end

local function tintColor(base: Color3, scale: number): Color3
	return Color3.new(
		math.clamp(base.R * scale, 0, 1),
		math.clamp(base.G * scale, 0, 1),
		math.clamp(base.B * scale, 0, 1)
	)
end

local function colorSequenceFromSurface(color: Color3): ColorSequence
	local light = tintColor(color, 1.18)
	local mid = color
	local dark = tintColor(color, 0.72)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, light),
		ColorSequenceKeypoint.new(0.45, mid),
		ColorSequenceKeypoint.new(1, dark),
	})
end

local function isVisibleFloorPart(part: BasePart): boolean
	if part.Transparency >= 0.95 then
		return false
	end
	return part.Size.X > 0.2 and part.Size.Y > 0.05 and part.Size.Z > 0.2
end

function SupermanGroundVfx.resolveSurfaceStyle(result: RaycastResult): SurfaceStyle
	local chunkCfg = SupermanVfxConfigs.Break.LandingChunks
	local inst = result.Instance

	if inst and inst:IsA("BasePart") and isVisibleFloorPart(inst) then
		return {
			color = inst.Color,
			material = inst.Material,
		}
	end

	if inst == Workspace.Terrain then
		local terrain = Workspace.Terrain
		local matColor = terrain:GetMaterialColor(result.Material)
		return {
			color = matColor,
			material = result.Material,
		}
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if inst and inst:IsA("BasePart") and inst.Transparency >= 0.95 then
		params.FilterDescendantsInstances = { inst }
	end

	local nearbyLen = chunkCfg.NearbyRayLength
	local probes = {
		Vector3.new(0, -nearbyLen, 0),
		Vector3.new(nearbyLen * 0.5, -nearbyLen, 0),
		Vector3.new(-nearbyLen * 0.5, -nearbyLen, 0),
		Vector3.new(0, -nearbyLen, nearbyLen * 0.5),
		Vector3.new(0, -nearbyLen, -nearbyLen * 0.5),
	}

	for _, dir in probes do
		local hit = Workspace:Raycast(result.Position + Vector3.new(0, 0.5, 0), dir, params)
		if hit and hit.Instance:IsA("BasePart") and isVisibleFloorPart(hit.Instance) then
			local part = hit.Instance :: BasePart
			return {
				color = part.Color,
				material = part.Material,
			}
		end
	end

	if inst and inst:IsA("BasePart") then
		return {
			color = inst.Color,
			material = inst.Material,
		}
	end

	return {
		color = chunkCfg.DefaultColor,
		material = chunkCfg.FallbackMaterial,
	}
end

local function getLandingVfxFolder(): Folder
	if landingVfxFolder and landingVfxFolder.Parent then
		return landingVfxFolder
	end
	local name = SupermanVfxConfigs.Break.LandingChunks.FolderName
	local existing = Workspace:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		landingVfxFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	landingVfxFolder = folder
	return folder
end

local function spawnScorchPatch(
	pos: Vector3,
	normal: Vector3,
	diameter: number,
	alpha: number
)
	local scorchCfg = SupermanVfxConfigs.Break.Scorch
	local right, up = buildSurfaceBasis(normal)
	local radius = diameter / 2

	local patch = Instance.new("Part")
	patch.Size = Vector3.new(1, 1, 1)
	patch.Anchored = true
	patch.CFrame = CFrame.fromMatrix(pos + up * 0.02, right, up)
	patch.Transparency = alpha
	patch.CanCollide = false
	patch.CanQuery = false
	patch.CastShadow = false
	patch.Material = Enum.Material.SmoothPlastic
	patch.Color = scorchCfg.Color
	patch.Parent = Workspace

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(radius, scorchCfg.Thickness, radius)
	mesh.Parent = patch

	registerScorch(patch)

	local fadeDuration = scorchCfg.FadeDuration
	local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(patch, tweenInfo, { Transparency = 1 }):Play()
	Debris:AddItem(patch, fadeDuration + 0.15)
end

local function spawnBurstParticles(
	parent: Part,
	tierCfg: any,
	useBlack: boolean,
	colorOverride: ColorSequence?
)
	local shared = SupermanVfxConfigs.Break
	local defaults = shared.ParticleDefaults
	local scale = tierCfg.ParticleScale or 1

	local e = Instance.new("ParticleEmitter")
	e.Texture = shared.ParticleTexture
	e.Color = if colorOverride then colorOverride elseif useBlack then shared.BlackDustColor else shared.DustColor
	e.Size = scaleNumberSequence(
		NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25 * scale),
			NumberSequenceKeypoint.new(0.4, 1.1 * scale),
			NumberSequenceKeypoint.new(1, 1.6 * scale),
		}),
		1
	)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Speed = NumberRange.new(defaults.SpeedMin * scale, defaults.SpeedMax * scale)
	e.Lifetime = NumberRange.new(defaults.LifetimeMin, defaults.LifetimeMax)
	e.SpreadAngle = defaults.Spread
	e.LightEmission = defaults.LightEmission
	e.LightInfluence = 0.6
	e.RotSpeed = NumberRange.new(-160, 160)
	e.Rotation = NumberRange.new(0, 360)
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = parent
	e:Emit(tierCfg.ParticleBurst or 8)
end

local function spawnLandingParticles(anchor: Part, surfaceStyle: SurfaceStyle)
	local cfg = SupermanVfxConfigs.Break.LandingParticles
	local colorSeq = if cfg.UseFloorTint == true
		then colorSequenceFromSurface(surfaceStyle.color)
		else cfg.DustColor

	local e = Instance.new("ParticleEmitter")
	e.Texture = cfg.Texture or "rbxassetid://243660364"
	e.Color = colorSeq
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5 * cfg.Scale),
		NumberSequenceKeypoint.new(0.35, cfg.SizePeak * cfg.Scale),
		NumberSequenceKeypoint.new(1, 0.2 * cfg.Scale),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.4, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Speed = NumberRange.new(cfg.SpeedMin, cfg.SpeedMax)
	e.Lifetime = NumberRange.new(cfg.LifetimeMin, cfg.LifetimeMax)
	e.SpreadAngle = cfg.Spread
	e.LightEmission = cfg.LightEmission or 0
	e.LightInfluence = cfg.LightInfluence or 0.15
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Rotation = NumberRange.new(0, 360)
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = anchor
	e:Emit(cfg.Burst)
end

local function spawnSurfaceRing(
	pos: Vector3,
	normal: Vector3,
	maxDiameter: number,
	duration: number,
	color: Color3
)
	local right, up = buildSurfaceBasis(normal)
	local ring = Instance.new("Part")
	ring.Size = Vector3.new(1, 1, 1)
	ring.Anchored = true
	ring.CFrame = CFrame.fromMatrix(pos + up * 0.03, right, up)
	ring.Transparency = 0.15
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Parent = Workspace

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(0.03, 0.04, 0.03)
	mesh.Parent = ring

	local maxR = maxDiameter / 2
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, tweenInfo, { Transparency = 1 }):Play()
	TweenService:Create(mesh, tweenInfo, { Scale = Vector3.new(maxR, 0.04, maxR) }):Play()
	Debris:AddItem(ring, duration + 0.1)
end

local function horizontalLookVector(character: Model?): Vector3
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local flat = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
			if flat.Magnitude > 0.05 then
				return flat.Unit
			end
		end
	end
	return Vector3.new(0, 0, -1)
end

local function horizontalRightVector(look: Vector3): Vector3
	local right = Vector3.new(0, 1, 0):Cross(look)
	if right.Magnitude < 0.05 then
		return Vector3.new(1, 0, 0)
	end
	return right.Unit
end

local function sampleFootSpawnOffsets(character: Model?, floorPos: Vector3, right: Vector3, look: Vector3): { Vector3 }
	local chunkCfg = SupermanVfxConfigs.Break.LandingChunks
	local offsets: { Vector3 } = {}

	local leftFoot = if character then character:FindFirstChild("LeftFoot") else nil
	local rightFoot = if character then character:FindFirstChild("RightFoot") else nil

	if leftFoot and leftFoot:IsA("BasePart") and rightFoot and rightFoot:IsA("BasePart") then
		local leftPos = leftFoot.Position
		local rightPos = rightFoot.Position
		local mid = (leftPos + rightPos) * 0.5
		local y = floorPos.Y + chunkCfg.FootInset
		table.insert(offsets, Vector3.new(leftPos.X, y, leftPos.Z) - floorPos)
		table.insert(offsets, Vector3.new(rightPos.X, y, rightPos.Z) - floorPos)
		table.insert(offsets, Vector3.new(mid.X, y, mid.Z) - floorPos)
		return offsets
	end

	local side = chunkCfg.FootSideOffset
	table.insert(offsets, right * side)
	table.insert(offsets, right * -side)
	table.insert(offsets, look * (side * 0.35))
	return offsets
end

local function spawnOneLandingChunk(
	floorPos: Vector3,
	floorNormal: Vector3,
	spawnOffset: Vector3,
	look: Vector3,
	right: Vector3,
	surfaceStyle: SurfaceStyle,
	lateralSign: number,
	parentFolder: Folder
)
	local chunkCfg = SupermanVfxConfigs.Break.LandingChunks
	local up = floorNormal.Unit

	local size = Vector3.new(
		RNG:NextNumber(chunkCfg.SizeMin.X, chunkCfg.SizeMax.X),
		RNG:NextNumber(chunkCfg.SizeMin.Y, chunkCfg.SizeMax.Y),
		RNG:NextNumber(chunkCfg.SizeMin.Z, chunkCfg.SizeMax.Z)
	)

	local startPos = floorPos + spawnOffset + up * chunkCfg.FootInset
	local slideDir = (right * lateralSign + look * RNG:NextNumber(-0.35, 0.35)).Unit
	local launchSpeed = chunkCfg.LaunchSpeed + RNG:NextNumber(
		-(chunkCfg.LaunchSpeedSpread or 0),
		chunkCfg.LaunchSpeedSpread or 0
	)
	local upSpeed = chunkCfg.UpLaunchSpeed + RNG:NextNumber(
		-(chunkCfg.UpLaunchSpread or 0),
		chunkCfg.UpLaunchSpread or 0
	)

	local useWedge = RNG:NextNumber() < chunkCfg.WedgeRatio
	local chip: BasePart
	if useWedge then
		chip = Instance.new("WedgePart")
	else
		chip = Instance.new("Part")
		chip.Shape = Enum.PartType.Block
	end

	chip.Name = "LandingBreakChip"
	chip.Size = size
	chip.Material = surfaceStyle.material
	chip.Color = surfaceStyle.color
	chip.Anchored = false
	chip.CanCollide = chunkCfg.CanCollide == true
	chip.CanQuery = false
	chip.CanTouch = false
	chip.Massless = true
	chip.CastShadow = true
	chip.CFrame = CFrame.new(startPos) * CFrame.Angles(
		math.rad(RNG:NextNumber(-18, 18)),
		math.rad(RNG:NextNumber(0, 360)),
		math.rad(RNG:NextNumber(-25, 25))
	)
	chip.Parent = parentFolder

	chip.AssemblyLinearVelocity = slideDir * launchSpeed + up * upSpeed
	local spin = chunkCfg.AngularSpeed or 24
	chip.AssemblyAngularVelocity = Vector3.new(
		RNG:NextNumber(-1, 1) * spin,
		RNG:NextNumber(-1, 1) * spin,
		RNG:NextNumber(-1, 1) * spin
	)

	local fadeAt = chunkCfg.Lifetime * 0.5
	task.delay(fadeAt, function()
		if chip.Parent then
			TweenService:Create(
				chip,
				TweenInfo.new(chunkCfg.Lifetime - fadeAt, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1 }
			):Play()
		end
	end)
	Debris:AddItem(chip, chunkCfg.Lifetime)
end

local function spawnLandingChunks(result: RaycastResult, character: Model?)
	local tierCfg = SupermanVfxConfigs.Break.Tiers.Landing
	if not tierCfg or tierCfg.SpawnChunks ~= true then
		return
	end

	local chunkCfg = SupermanVfxConfigs.Break.LandingChunks
	local floorPos = result.Position
	local floorNormal = result.Normal
	local look = horizontalLookVector(character)
	local right = horizontalRightVector(look)
	local surfaceStyle = SupermanGroundVfx.resolveSurfaceStyle(result)
	local footOffsets = sampleFootSpawnOffsets(character, floorPos, right, look)
	local folder = getLandingVfxFolder()

	debugLog("spawnLandingChunks color=", surfaceStyle.color, "count=", chunkCfg.Count)

	for i = 1, chunkCfg.Count do
		local stagger = (i - 1) * chunkCfg.StaggerSeconds
		local footOffset = footOffsets[((i - 1) % #footOffsets) + 1]
		local lateralSign = if i % 2 == 0 then 1 else -1
		local jitter = right * RNG:NextNumber(-0.8, 0.8) + look * RNG:NextNumber(-0.5, 0.5)

		task.delay(stagger, function()
			spawnOneLandingChunk(
				floorPos,
				floorNormal,
				footOffset + jitter,
				look,
				right,
				surfaceStyle,
				lateralSign,
				folder
			)
		end)
	end

	local staggerTotal = chunkCfg.Count * chunkCfg.StaggerSeconds
	Debris:AddItem(folder, chunkCfg.Lifetime + staggerTotal + 0.5)
end

-- ── Raycast helpers ───────────────────────────────────────────────────────────

function SupermanGroundVfx.raycastFloorFromHrp(hrp: BasePart): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = hrp.Parent
	if character then
		params.FilterDescendantsInstances = { character }
	end
	local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -SupermanVfxConfigs.FloorRayLength, 0), params)
	if result and math.abs(result.Normal.Y) >= SupermanVfxConfigs.FloorNormalMinY then
		return result
	end
	return nil
end

function SupermanGroundVfx.isFloorNormal(normal: Vector3): boolean
	return math.abs(normal.Y) >= SupermanVfxConfigs.FloorNormalMinY
end

function SupermanGroundVfx.isWallNormal(normal: Vector3): boolean
	return math.abs(normal.Y) <= SupermanVfxConfigs.WallNormalMaxY
end

-- ── Core API ──────────────────────────────────────────────────────────────────

function SupermanGroundVfx.spawnSurfaceBreak(tier: BreakTier, result: RaycastResult, character: Model?): boolean
	if not canSpawnTier(tier) then
		debugLog("spawn blocked cooldown tier=", tier)
		return false
	end

	local tiers = SupermanVfxConfigs.Break.Tiers
	local tierCfg = tiers[tier]
	if not tierCfg then
		return false
	end

	local pos = result.Position
	local normal = result.Normal
	local right, up = buildSurfaceBasis(normal)
	local surfaceStyle = if tier == "Landing" then SupermanGroundVfx.resolveSurfaceStyle(result) else nil

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CFrame = CFrame.fromMatrix(pos + up * 0.05, right, up)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Parent = Workspace
	Debris:AddItem(anchor, SupermanVfxConfigs.Break.AnchorLifetime)

	spawnScorchPatch(pos, normal, tierCfg.ScorchDiameter, tierCfg.ScorchAlpha)

	if tier == "Landing" and tierCfg.UseLandingParticles == true and surfaceStyle then
		spawnLandingParticles(anchor, surfaceStyle)
	elseif (tierCfg.ParticleBurst or 0) > 0 then
		spawnBurstParticles(anchor, tierCfg, tierCfg.UseBlackDust == true)
	end

	if tierCfg.Ring then
		spawnSurfaceRing(
			pos,
			normal,
			tierCfg.RingMaxDiameter,
			tierCfg.RingDuration,
			tierCfg.RingColor
		)
	end

	if tier == "Landing" and character then
		spawnLandingChunks(result, character)
	end

	return true
end

function SupermanGroundVfx.spawnTakeoff(hrp: BasePart)
	local result = SupermanGroundVfx.raycastFloorFromHrp(hrp)
	if result then
		SupermanGroundVfx.spawnSurfaceBreak("Takeoff", result)
	end
end

function SupermanGroundVfx.spawnLanding(hrp: BasePart)
	local result = SupermanGroundVfx.raycastFloorFromHrp(hrp)
	if result then
		local character = if hrp.Parent and hrp.Parent:IsA("Model") then hrp.Parent else nil
		SupermanGroundVfx.spawnSurfaceBreak("Landing", result, character)
	end
end

function SupermanGroundVfx.spawnImpact(impactPos: Vector3, normal: Vector3, _material: Enum.Material?)
	local tier: BreakTier = if SupermanGroundVfx.isWallNormal(normal) then "ImpactWall" else "ImpactFloor"
	local up = normal.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = Workspace:Raycast(impactPos - up * 0.25, up * 0.75, params)
	if not result then
		result = Workspace:Raycast(impactPos + up * 0.1, -up * 0.5, params)
	end
	if result then
		SupermanGroundVfx.spawnSurfaceBreak(tier, result)
	end
end

function SupermanGroundVfx.resetAbilityState()
	table.clear(lastBreakAt)
end

return SupermanGroundVfx

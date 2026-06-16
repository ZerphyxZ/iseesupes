--!strict

-- Tiered surface-break VFX: dark scorch patches, dust bursts, tweened landing debris.
-- Client-only; cleaned up via Debris.

local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RNG = Random.new()

local SupermanVfxConfigs = require(ReplicatedStorage.Shared.Configs.SupermanVfxConfigs)
local ClientPerformance = require(ReplicatedStorage.Shared.Utils.ClientPerformance)
local PerfWatch = require(ReplicatedStorage.Shared.Utils.PerfWatch)

type BreakTier = SupermanVfxConfigs.BreakTier

export type SurfaceStyle = {
	color: Color3,
	material: Enum.Material,
	textureId: string?,
	sourceInstance: Instance?,
}

local SupermanGroundVfx = {}

local activeScorches: { Part } = {}
local lastBreakAt: { [BreakTier]: number } = {}
local landingVfxFolder: Folder? = nil
local lastFloorRay: {
	character: Model,
	result: RaycastResult?,
	at: number,
	hrpPos: Vector3,
}? = nil

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

local function tierCooldownKey(tier: BreakTier): string
	if tier == "LongJumpLaunchAir" then
		return "LongJumpLaunch"
	end
	return tier
end

local function canSpawnTier(tier: BreakTier): boolean
	local cooldowns = SupermanVfxConfigs.Break.Cooldowns
	local key = tierCooldownKey(tier)
	local cooldown = cooldowns[key] or cooldowns[tier]
	if not cooldown then
		return true
	end
	local now = os.clock()
	local last = lastBreakAt[key] or 0
	if now - last < cooldown then
		return false
	end
	lastBreakAt[key] = now
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
		local part = inst :: BasePart
		local style: SurfaceStyle = {
			color = part.Color,
			material = part.Material,
			sourceInstance = part,
		}
		if part:IsA("MeshPart") and part.TextureID ~= "" then
			style.textureId = part.TextureID
		end
		return style
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
			local style: SurfaceStyle = {
				color = part.Color,
				material = part.Material,
				sourceInstance = part,
			}
			if part:IsA("MeshPart") and part.TextureID ~= "" then
				style.textureId = part.TextureID
			end
			return style
		end
	end

	if inst and inst:IsA("BasePart") then
		local part = inst :: BasePart
		local style: SurfaceStyle = {
			color = part.Color,
			material = part.Material,
			sourceInstance = part,
		}
		if part:IsA("MeshPart") and part.TextureID ~= "" then
			style.textureId = part.TextureID
		end
		return style
	end

	return {
		color = chunkCfg.DefaultColor,
		material = chunkCfg.FallbackMaterial,
	}
end

local function isVisibleSurfacePart(part: BasePart): boolean
	if part.Transparency >= 0.98 then
		return false
	end
	return part.Size.X > 0.05 and part.Size.Y > 0.05 and part.Size.Z > 0.05
end

function SupermanGroundVfx.resolveHitSurfaceStyle(result: RaycastResult): SurfaceStyle
	local chunkCfg = SupermanVfxConfigs.Break.HeatVisionChunks
	local inst = result.Instance

	if inst == Workspace.Terrain then
		return {
			color = Workspace.Terrain:GetMaterialColor(result.Material),
			material = result.Material,
		}
	end

	if inst and inst:IsA("BasePart") and isVisibleSurfacePart(inst) then
		local part = inst :: BasePart
		local style: SurfaceStyle = {
			color = part.Color,
			material = part.Material,
			sourceInstance = part,
		}
		if part:IsA("MeshPart") and part.TextureID ~= "" then
			style.textureId = part.TextureID
		end
		return style
	end

	return {
		color = chunkCfg.DefaultColor,
		material = chunkCfg.FallbackMaterial,
	}
end

local function applySurfaceStyleToChip(chip: BasePart, surfaceStyle: SurfaceStyle)
	chip.Color = surfaceStyle.color
	chip.Material = surfaceStyle.material

	if chip:IsA("MeshPart") and surfaceStyle.textureId then
		chip.TextureID = surfaceStyle.textureId
	end

	local source = surfaceStyle.sourceInstance
	if chip:IsA("MeshPart") and source and source:IsA("MeshPart") then
		local existing = chip:FindFirstChildOfClass("SurfaceAppearance")
		if existing then
			existing:Destroy()
		end
		local sourceAppearance = source:FindFirstChildOfClass("SurfaceAppearance")
		if sourceAppearance then
			sourceAppearance:Clone().Parent = chip
		end
	end
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

local function spawnScorchPatch(pos: Vector3, normal: Vector3, diameter: number, alpha: number)
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

local function spawnBurstParticles(parent: Part, tierCfg: any, useBlack: boolean, colorOverride: ColorSequence?)
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

local function spawnLandingParticles(anchor: Part, surfaceStyle: SurfaceStyle, burstOverride: number?)
	local cfg = SupermanVfxConfigs.Break.LandingParticles
	local colorSeq = if cfg.UseFloorTint == true then colorSequenceFromSurface(surfaceStyle.color) else cfg.DustColor

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
	e:Emit(burstOverride or cfg.Burst)
end

local function spawnLongJumpSmoke(anchor: Part, burstOverride: number?)
	local cfg = SupermanVfxConfigs.Break.LongJumpSmoke
	local scale = cfg.Scale or 1

	local e = Instance.new("ParticleEmitter")
	e.Name = "LongJumpSmoke"
	e.Texture = cfg.Texture or "rbxassetid://243660364"
	e.Color = cfg.DustColor
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8 * scale),
		NumberSequenceKeypoint.new(0.3, cfg.SizePeak * scale),
		NumberSequenceKeypoint.new(1, 0.35 * scale),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(0.35, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Speed = NumberRange.new(cfg.SpeedMin, cfg.SpeedMax)
	e.Lifetime = NumberRange.new(cfg.LifetimeMin, cfg.LifetimeMax)
	e.SpreadAngle = cfg.Spread
	e.LightEmission = cfg.LightEmission or 0
	e.LightInfluence = cfg.LightInfluence or 0
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Rotation = NumberRange.new(0, 360)
	e.Rate = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = anchor
	e:Emit(burstOverride or cfg.Burst)
end

local function spawnSurfaceRing(pos: Vector3, normal: Vector3, maxDiameter: number, duration: number, color: Color3)
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
	parentFolder: Folder,
	chunkCfgOverride: any?
): BasePart
	local chunkCfg = chunkCfgOverride or SupermanVfxConfigs.Break.LandingChunks
	local up = floorNormal.Unit

	local size = Vector3.new(
		RNG:NextNumber(chunkCfg.SizeMin.X, chunkCfg.SizeMax.X),
		RNG:NextNumber(chunkCfg.SizeMin.Y, chunkCfg.SizeMax.Y),
		RNG:NextNumber(chunkCfg.SizeMin.Z, chunkCfg.SizeMax.Z)
	)

	local startPos = floorPos + spawnOffset + up * chunkCfg.FootInset
	local slideDir = (right * lateralSign + look * RNG:NextNumber(-0.35, 0.35)).Unit
	local launchSpeed = chunkCfg.LaunchSpeed
		+ RNG:NextNumber(-(chunkCfg.LaunchSpeedSpread or 0), chunkCfg.LaunchSpeedSpread or 0)
	local upSpeed = chunkCfg.UpLaunchSpeed
		+ RNG:NextNumber(-(chunkCfg.UpLaunchSpread or 0), chunkCfg.UpLaunchSpread or 0)

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
	applySurfaceStyleToChip(chip, surfaceStyle)
	chip.Anchored = false
	chip.CanCollide = chunkCfg.CanCollide == true
	chip.CanQuery = false
	chip.CanTouch = false
	chip.Massless = true
	chip.CastShadow = true
	chip.CFrame = CFrame.new(startPos)
		* CFrame.Angles(
			math.rad(RNG:NextNumber(-18, 18)),
			math.rad(RNG:NextNumber(0, 360)),
			math.rad(RNG:NextNumber(-25, 25))
		)
	chip.Parent = parentFolder

	chip.AssemblyLinearVelocity = slideDir * launchSpeed + up * upSpeed
	local spin = chunkCfg.AngularSpeed or 24
	chip.AssemblyAngularVelocity =
		Vector3.new(RNG:NextNumber(-1, 1) * spin, RNG:NextNumber(-1, 1) * spin, RNG:NextNumber(-1, 1) * spin)

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
	return chip
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

local heatVfxFolder: Folder? = nil

local function getHeatVfxFolder(): Folder
	if heatVfxFolder and heatVfxFolder.Parent then
		return heatVfxFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = SupermanVfxConfigs.Break.HeatVisionChunks.FolderName
	folder.Parent = Workspace
	heatVfxFolder = folder
	return folder
end

local function spawnHeatVisionMeltFlash(hitPos: Vector3, surfaceNormal: Vector3, surfaceStyle: SurfaceStyle)
	local normal = surfaceNormal.Unit
	local right, up = buildSurfaceBasis(normal)

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CFrame = CFrame.fromMatrix(hitPos + up * 0.04, right, up)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local heatColor = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tintColor(surfaceStyle.color, 1.35)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 120, 40)),
		ColorSequenceKeypoint.new(1, tintColor(surfaceStyle.color, 0.55)),
	})

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "HeatMeltSparks"
	sparks.Texture = SupermanVfxConfigs.Break.ParticleTexture
	sparks.Color = heatColor
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.15, 0.4)
	sparks.Speed = NumberRange.new(6, 16)
	sparks.SpreadAngle = Vector2.new(55, 55)
	sparks.Acceleration = Vector3.new(0, -18, 0)
	sparks.LightEmission = 0.85
	sparks.Rate = 0
	sparks.Parent = attachment
	sparks:Emit(10)

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 110, 35)
	glow.Brightness = 2
	glow.Range = 8
	glow.Parent = anchor
	TweenService:Create(glow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
	}):Play()

	Debris:AddItem(anchor, 0.6)
end

local function spawnHeatVisionChunks(result: RaycastResult, character: Model?, count: number?, beamDirection: Vector3?)
	local tierCfg = SupermanVfxConfigs.Break.Tiers.HeatVision
	if not tierCfg or tierCfg.SpawnChunks ~= true then
		return
	end

	local chunkCfg = SupermanVfxConfigs.Break.HeatVisionChunks
	local hitPos = result.Position
	local hitNormal = result.Normal
	local surfaceRight, surfaceUp = buildSurfaceBasis(hitNormal)
	local surfaceTangent = surfaceUp:Cross(surfaceRight).Unit
	local beamDir = if beamDirection and beamDirection.Magnitude > 0.001
		then beamDirection.Unit
		else Vector3.new(0, 0, -1)
	local beamOnSurface = beamDir - hitNormal * beamDir:Dot(hitNormal)
	local look = if beamOnSurface.Magnitude > 0.05 then beamOnSurface.Unit else surfaceTangent
	local right = surfaceRight
	local surfaceStyle = SupermanGroundVfx.resolveHitSurfaceStyle(result)
	local folder = getHeatVfxFolder()
	local spawnCount = math.max(1, count or chunkCfg.Count)

	spawnHeatVisionMeltFlash(hitPos, hitNormal, surfaceStyle)

	local scorchDiameter = tierCfg.ScorchDiameter
	if type(scorchDiameter) == "number" and scorchDiameter > 0 then
		spawnScorchPatch(hitPos, hitNormal, scorchDiameter, tierCfg.ScorchAlpha or 0.5)
	end

	if (tierCfg.ParticleBurst or 0) > 0 then
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.Anchored = true
		anchor.CFrame = CFrame.fromMatrix(hitPos + surfaceUp * 0.05, surfaceRight, surfaceUp)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Parent = folder
		spawnBurstParticles(anchor, tierCfg, tierCfg.UseBlackDust == true)
		Debris:AddItem(anchor, SupermanVfxConfigs.Break.AnchorLifetime)
	end

	for i = 1, spawnCount do
		local stagger = (i - 1) * chunkCfg.StaggerSeconds
		local lateralSign = if i % 2 == 0 then 1 else -1
		local jitter = surfaceRight * RNG:NextNumber(-0.65, 0.65) + surfaceTangent * RNG:NextNumber(-0.65, 0.65)
		task.delay(stagger, function()
			spawnOneLandingChunk(hitPos, hitNormal, jitter, look, right, surfaceStyle, lateralSign, folder, chunkCfg)
		end)
	end

	local staggerTotal = spawnCount * chunkCfg.StaggerSeconds
	Debris:AddItem(folder, chunkCfg.Lifetime + staggerTotal + 0.5)
end

-- ── Raycast helpers ───────────────────────────────────────────────────────────

local function buildFloorRayParams(character: Model?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if character then
		params.FilterDescendantsInstances = { character }
	end
	return params
end

function SupermanGroundVfx.raycastFloorFromHrp(hrp: BasePart): RaycastResult?
	local character = if hrp.Parent and hrp.Parent:IsA("Model") then hrp.Parent else nil
	local params = buildFloorRayParams(character)
	local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -SupermanVfxConfigs.FloorRayLength, 0), params)
	if result and math.abs(result.Normal.Y) >= SupermanVfxConfigs.FloorNormalMinY then
		return result
	end
	return nil
end

function SupermanGroundVfx.getFootLaunchPosition(character: Model, hrp: BasePart): (Vector3, Vector3)
	local lowestY = hrp.Position.Y
	for _, name in { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			lowestY = math.min(lowestY, part.Position.Y)
		end
	end
	local floorPos = Vector3.new(hrp.Position.X, lowestY - 0.15, hrp.Position.Z)
	return floorPos, Vector3.yAxis
end

function SupermanGroundVfx.raycastFloorFromCharacter(character: Model, hrp: BasePart): RaycastResult?
	local params = buildFloorRayParams(character)
	local floorPos, _ = SupermanGroundVfx.getFootLaunchPosition(character, hrp)
	local origin = floorPos + Vector3.new(0, 4, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -12, 0), params)
	if result and math.abs(result.Normal.Y) >= SupermanVfxConfigs.FloorNormalMinY then
		return result
	end
	result = Workspace:Raycast(hrp.Position, Vector3.new(0, -SupermanVfxConfigs.FloorRayLength, 0), params)
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

local function spawnSurfaceBreakAt(
	tier: BreakTier,
	pos: Vector3,
	normal: Vector3,
	character: Model?,
	rayResult: RaycastResult?
): boolean
	if ClientPerformance.shouldReduceSupermanVfx() then
		return false
	end
	if not canSpawnTier(tier) then
		debugLog("spawn blocked cooldown tier=", tier)
		return false
	end

	local tiers = SupermanVfxConfigs.Break.Tiers
	local tierCfg = tiers[tier]
	if not tierCfg then
		return false
	end

	local right, upBasis = buildSurfaceBasis(normal)

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CFrame = CFrame.fromMatrix(pos + upBasis * 0.05, right, upBasis)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Parent = Workspace
	Debris:AddItem(anchor, SupermanVfxConfigs.Break.AnchorLifetime)

	local scorchDiameter = tierCfg.ScorchDiameter
	if type(scorchDiameter) == "number" and scorchDiameter > 0 then
		spawnScorchPatch(pos, normal, scorchDiameter, tierCfg.ScorchAlpha or 0.5)
	end

	if tierCfg.UseLongJumpSmoke == true then
		spawnLongJumpSmoke(anchor, tierCfg.LongJumpParticleBurst)
	elseif tierCfg.UseLandingParticles == true and rayResult then
		local surfaceStyle = SupermanGroundVfx.resolveSurfaceStyle(rayResult)
		spawnLandingParticles(anchor, surfaceStyle, tierCfg.LandingParticleBurst)
	elseif (tierCfg.ParticleBurst or 0) > 0 then
		spawnBurstParticles(anchor, tierCfg, tierCfg.UseBlackDust == true)
	end

	if tierCfg.Ring then
		spawnSurfaceRing(pos, normal, tierCfg.RingMaxDiameter, tierCfg.RingDuration, tierCfg.RingColor)
	end

	if tier == "Landing" and character and rayResult then
		spawnLandingChunks(rayResult, character)
	end

	if tier == "HeatVision" and rayResult then
		spawnHeatVisionChunks(rayResult, character, nil, nil)
	end

	return true
end

function SupermanGroundVfx.spawnSurfaceBreak(tier: BreakTier, result: RaycastResult, character: Model?): boolean
	return spawnSurfaceBreakAt(tier, result.Position, result.Normal, character, result)
end

function SupermanGroundVfx.spawnSurfaceBreakForCharacter(tier: BreakTier, character: Model): boolean
	return PerfWatch.measure("Vfx.spawnSurfaceBreakForCharacter", function(): boolean
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then
			return false
		end

		local reuseCfg = SupermanVfxConfigs.Break.FloorRayReuse
		local reuseSec = if reuseCfg and type(reuseCfg.Seconds) == "number" then reuseCfg.Seconds else 0.1
		local reuseDist = if reuseCfg and type(reuseCfg.MaxHrpMoveStuds) == "number" then reuseCfg.MaxHrpMoveStuds else 4

		local now = os.clock()
		local cached = lastFloorRay
		local result: RaycastResult?
		if cached
			and cached.character == character
			and now - cached.at < reuseSec
			and (hrp.Position - cached.hrpPos).Magnitude < reuseDist
		then
			result = cached.result
		else
			result = SupermanGroundVfx.raycastFloorFromCharacter(character, hrp)
			lastFloorRay = {
				character = character,
				result = result,
				at = now,
				hrpPos = hrp.Position,
			}
		end

		if result then
			return SupermanGroundVfx.spawnSurfaceBreak(tier, result, character)
		end

		local floorPos, normal = SupermanGroundVfx.getFootLaunchPosition(character, hrp)
		return spawnSurfaceBreakAt(tier, floorPos, normal, character, nil)
	end)
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

local glassVfxFolder: Folder? = nil
local glassVfxCollisionReady = false
local GLASS_VFX_COLLISION_GROUP = "GlassBreakVfx"

local function ensureGlassVfxCollisionGroup()
	if glassVfxCollisionReady then
		return
	end
	glassVfxCollisionReady = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GLASS_VFX_COLLISION_GROUP)
		PhysicsService:CollisionGroupSetCollidable(GLASS_VFX_COLLISION_GROUP, "Default", false)
	end)
end

local function applyGlassBreakVfxPhysics(part: BasePart)
	ensureGlassVfxCollisionGroup()
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CollisionGroup = GLASS_VFX_COLLISION_GROUP
end

local function getGlassVfxFolder(): Folder
	if glassVfxFolder and glassVfxFolder.Parent then
		return glassVfxFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = SupermanVfxConfigs.Break.GlassChunks.FolderName
	folder.Parent = Workspace
	glassVfxFolder = folder
	return folder
end

function SupermanGroundVfx.getGlassBreakVfxFolder(): Folder?
	if glassVfxFolder and glassVfxFolder.Parent then
		return glassVfxFolder
	end
	local existing = Workspace:FindFirstChild(SupermanVfxConfigs.Break.GlassChunks.FolderName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	return nil
end

local function buildGlassSurfaceStyle(result: RaycastResult): SurfaceStyle
	local chunkCfg = SupermanVfxConfigs.Break.GlassChunks
	local color = chunkCfg.DefaultColor
	if result.Instance and result.Instance:IsA("BasePart") then
		local part = result.Instance :: BasePart
		if part.Transparency < 0.98 then
			color = part.Color
		end
	end
	return {
		color = color,
		material = Enum.Material.Glass,
		textureId = nil,
		sourceInstance = result.Instance,
	}
end

local function buildGlassSurfaceStyleFromPart(gatePart: BasePart): SurfaceStyle
	local chunkCfg = SupermanVfxConfigs.Break.GlassChunks
	local color = chunkCfg.DefaultColor
	if gatePart.Transparency < 0.98 then
		color = gatePart.Color
	end
	return {
		color = color,
		material = Enum.Material.Glass,
		textureId = if gatePart:IsA("MeshPart") and gatePart.TextureID ~= "" then gatePart.TextureID else nil,
		sourceInstance = gatePart,
	}
end

type GateFaceFrame = {
	center: Vector3,
	right: Vector3,
	up: Vector3,
	halfWidth: number,
	halfHeight: number,
	normal: Vector3,
}

local function getGateFaceFrame(gatePart: BasePart, hitNormal: Vector3): GateFaceFrame
	local cf = gatePart.CFrame
	local normal = hitNormal.Unit
	local size = gatePart.Size

	local rightVec = cf.RightVector
	local upVec = cf.UpVector
	local lookVec = cf.LookVector

	local dotRight = math.abs(normal:Dot(rightVec))
	local dotUp = math.abs(normal:Dot(upVec))
	local dotLook = math.abs(normal:Dot(lookVec))

	local faceRight: Vector3
	local faceUp: Vector3
	local halfWidth: number
	local halfHeight: number
	local centerOffset: Vector3

	if dotRight >= dotUp and dotRight >= dotLook then
		local sign = if normal:Dot(rightVec) >= 0 then 1 else -1
		centerOffset = rightVec * (sign * size.X * 0.5)
		faceRight = lookVec
		faceUp = upVec
		halfWidth = size.Z * 0.5
		halfHeight = size.Y * 0.5
	elseif dotUp >= dotLook then
		local sign = if normal:Dot(upVec) >= 0 then 1 else -1
		centerOffset = upVec * (sign * size.Y * 0.5)
		faceRight = rightVec
		faceUp = lookVec
		halfWidth = size.X * 0.5
		halfHeight = size.Z * 0.5
	else
		local sign = if normal:Dot(lookVec) >= 0 then 1 else -1
		centerOffset = lookVec * (sign * size.Z * 0.5)
		faceRight = rightVec
		faceUp = upVec
		halfWidth = size.X * 0.5
		halfHeight = size.Y * 0.5
	end

	return {
		center = gatePart.Position + centerOffset,
		right = faceRight,
		up = faceUp,
		halfWidth = math.max(halfWidth, 0.5),
		halfHeight = math.max(halfHeight, 0.5),
		normal = normal,
	}
end

local function sampleGateFacePoint(face: GateFaceFrame, inset: number?): Vector3
	local margin = inset or 0.15
	local w = math.max(face.halfWidth - margin, 0.25)
	local h = math.max(face.halfHeight - margin, 0.25)
	local u = RNG:NextNumber(-w, w)
	local v = RNG:NextNumber(-h, h)
	return face.center + face.right * u + face.up * v
end

local function resolveSoundsFolder(): Folder?
	local function tryPath(segments: { string }): Folder?
		local current: Instance = ReplicatedStorage
		for _, seg in segments do
			local child = current:FindFirstChild(seg)
			if not child then
				return nil
			end
			current = child
		end
		return if current:IsA("Folder") then current :: Folder else nil
	end

	local folder = tryPath(SupermanVfxConfigs.Sounds.FolderPath)
	if folder then
		return folder
	end
	for _, alt in SupermanVfxConfigs.Sounds.AlternateFolderPaths do
		folder = tryPath(alt)
		if folder then
			return folder
		end
	end
	return nil
end

local warnedGlassSound = false

function SupermanGroundVfx.playGateGlassBreakSound(atPos: Vector3)
	local sounds = SupermanVfxConfigs.Sounds
	local gateCfg = SupermanVfxConfigs.Break.GateGlassBreak

	local sound: Sound
	local soundId = gateCfg.SoundId
	if typeof(soundId) == "string" and soundId ~= "" then
		sound = Instance.new("Sound")
		sound.SoundId = soundId
	else
		local folder = resolveSoundsFolder()
		if not folder then
			if not warnedGlassSound then
				warnedGlassSound = true
			end
			return
		end
		local soundName = sounds.GlassBreak or sounds.ImpactBreak
		local template = folder:FindFirstChild(soundName)
		if not template or not template:IsA("Sound") then
			return
		end
		sound = (template :: Sound):Clone()
	end

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(atPos)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = Workspace

	sound.Volume = gateCfg.SoundVolume or sounds.GlassBreakVolume or 0.85
	sound.PlaybackSpeed = gateCfg.SoundPlaybackSpeed or 1.05
	sound.RollOffMode = Enum.RollOffMode.LinearSquare
	sound.RollOffMinDistance = gateCfg.SoundRollOffMinDistance or 18
	sound.RollOffMaxDistance = gateCfg.SoundRollOffMaxDistance or 700
	local emitterSize = gateCfg.SoundEmitterSize
	if typeof(emitterSize) == "number" and emitterSize > 0 then
		sound.EmitterSize = emitterSize
	end
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, sounds.GlassBreakLifetime or sounds.ImpactBreakLifetime or 2.5)
end

local function playGlassBreakSound(atPos: Vector3)
	SupermanGroundVfx.playGateGlassBreakSound(atPos)
end

local function spawnGlassSparkleBurst(anchor: Part, burst: number, color: Color3)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local sparkColor = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.35, tintColor(color, 1.15)),
		ColorSequenceKeypoint.new(1, tintColor(color, 0.75)),
	})

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "GlassSparkle"
	sparks.Texture = "rbxassetid://243660364"
	sparks.Color = sparkColor
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.25, 0.55),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.6, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparks.Lifetime = NumberRange.new(0.2, 0.55)
	sparks.Speed = NumberRange.new(14, 32)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, -24, 0)
	sparks.LightEmission = 0.65
	sparks.RotSpeed = NumberRange.new(-240, 240)
	sparks.Rate = 0
	sparks.Parent = attachment
	sparks:Emit(burst)

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "GlassDust"
	dust.Texture = SupermanVfxConfigs.Break.ParticleTexture
	dust.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(230, 242, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 195, 220)),
	})
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.4, 1.2),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.35, 0.75)
	dust.Speed = NumberRange.new(6, 14)
	dust.SpreadAngle = Vector2.new(65, 65)
	dust.LightEmission = 0.2
	dust.Rate = 0
	dust.Parent = attachment
	dust:Emit(math.max(8, math.floor(burst * 0.55)))
end

local function spawnGateGlassFlash(face: GateFaceFrame, surfaceStyle: SurfaceStyle, gateCfg: any)
	local flashRange = (gateCfg.FlashRange or 24)
		* math.clamp(math.max(face.halfWidth, face.halfHeight) * (gateCfg.FlashRangeScale or 0.65), 1, 3)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CFrame = CFrame.fromMatrix(face.center + face.normal * 0.06, face.right, face.up)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = Workspace

	spawnGlassSparkleBurst(anchor, gateCfg.SparkleBurst or 42, surfaceStyle.color)

	local glow = Instance.new("PointLight")
	glow.Color = tintColor(surfaceStyle.color, 1.25)
	glow.Brightness = gateCfg.FlashBrightness or 5
	glow.Range = flashRange
	glow.Parent = anchor
	TweenService:Create(
		glow,
		TweenInfo.new(gateCfg.FlashDuration or 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	):Play()

	Debris:AddItem(anchor, (gateCfg.FlashDuration or 0.28) + 0.35)
end

local function computeGatePaneLayout(face: GateFaceFrame, gateCfg: any): (number, number, number, number)
	local faceW = face.halfWidth * 2
	local faceH = face.halfHeight * 2
	local target = gateCfg.TargetPaneStuds or 5.5
	local cols = math.clamp(math.round(faceW / target), gateCfg.MinGridCols or 3, gateCfg.MaxGridCols or 5)
	local rows = math.clamp(math.round(faceH / target), gateCfg.MinGridRows or 4, gateCfg.MaxGridRows or 8)
	local paneW = faceW / cols
	local paneH = faceH / rows
	return cols, rows, paneW, paneH
end

local function spawnOneGatePaneShard(
	centerPos: Vector3,
	face: GateFaceFrame,
	paneWidth: number,
	paneHeight: number,
	surfaceStyle: SurfaceStyle,
	parentFolder: Folder,
	chunkCfg: any,
	gateCfg: any,
	throughSign: number
): BasePart
	local jitter = gateCfg.PaneSizeJitter or 0.04
	local w = paneWidth * RNG:NextNumber(1 - jitter, 1)
	local h = paneHeight * RNG:NextNumber(1 - jitter, 1)
	local depth = RNG:NextNumber(gateCfg.PaneThicknessMin or 0.22, gateCfg.PaneThicknessMax or 0.55)

	local tangential = face.right * RNG:NextNumber(-1, 1) + face.up * RNG:NextNumber(-1, 1)
	if tangential.Magnitude > 0.01 then
		tangential = tangential.Unit
	else
		tangential = face.right
	end

	local paneScale = math.clamp((w + h) * 0.5 / (gateCfg.TargetPaneStuds or 5.5), 0.9, 2.4)
	local throughSpeed = (
		(chunkCfg.ThroughLaunchSpeed or 54)
		+ RNG:NextNumber(-(chunkCfg.ThroughLaunchSpread or 18), chunkCfg.ThroughLaunchSpread or 18)
	) * paneScale
	local tangSpeed = (
		(chunkCfg.TangentialLaunchSpeed or 32)
		+ RNG:NextNumber(-(chunkCfg.TangentialLaunchSpread or 16), chunkCfg.TangentialLaunchSpread or 16)
	) * math.sqrt(paneScale)
	local upSpeed = (chunkCfg.UpLaunchSpeed or 22)
		+ RNG:NextNumber(-(chunkCfg.UpLaunchSpread or 12), chunkCfg.UpLaunchSpread or 12)

	local useWedge = RNG:NextNumber() < (chunkCfg.WedgeRatio or 0.2)
	local chip: BasePart
	if useWedge then
		chip = Instance.new("WedgePart")
	else
		chip = Instance.new("Part")
		chip.Shape = Enum.PartType.Block
	end

	chip.Name = "GateGlassPane"
	chip.Size = Vector3.new(w, h, depth)
	applySurfaceStyleToChip(chip, surfaceStyle)
	chip.Material = Enum.Material.Glass
	chip.Transparency = RNG:NextNumber(0.02, 0.18)
	chip.Reflectance = RNG:NextNumber(0.12, 0.28)
	chip.Anchored = false
	applyGlassBreakVfxPhysics(chip)
	chip.CastShadow = true
	chip.CFrame = CFrame.fromMatrix(centerPos, face.right, face.up)
		* CFrame.Angles(
			math.rad(RNG:NextNumber(-18, 18)),
			math.rad(RNG:NextNumber(-12, 12)),
			math.rad(RNG:NextNumber(-18, 18))
		)
	chip.Parent = parentFolder

	chip.AssemblyLinearVelocity = face.normal * throughSign * throughSpeed
		+ tangential * tangSpeed
		+ Vector3.new(0, upSpeed, 0)

	local spin = (chunkCfg.AngularSpeed or 28) / math.sqrt(paneScale)
	chip.AssemblyAngularVelocity =
		Vector3.new(RNG:NextNumber(-1, 1) * spin, RNG:NextNumber(-1, 1) * spin, RNG:NextNumber(-1, 1) * spin)

	local fadeAt = chunkCfg.Lifetime * 0.55
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
	return chip
end

local function spawnGateGlassPaneGrid(
	face: GateFaceFrame,
	surfaceStyle: SurfaceStyle,
	folder: Folder,
	chunkCfg: any,
	gateCfg: any
): (number, number)
	local cols, rows, paneW, paneH = computeGatePaneLayout(face, gateCfg)
	local maxDist = math.sqrt(face.halfWidth * face.halfWidth + face.halfHeight * face.halfHeight)
	local waveMax = gateCfg.WaveStaggerMax or 0.09
	local spawned = 0

	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local u = -face.halfWidth + paneW * (col + 0.5)
			local v = -face.halfHeight + paneH * (row + 0.5)
			local paneCenter = face.center + face.right * u + face.up * v
			local dist01 = if maxDist > 0.01 then (paneCenter - face.center).Magnitude / maxDist else 0
			local stagger = dist01 * waveMax + RNG:NextNumber(0, waveMax * 0.25)
			local throughSign = if (col + row) % 2 == 0 then 1 else -1
			spawned += 1

			task.delay(stagger, function()
				spawnOneGatePaneShard(
					paneCenter,
					face,
					paneW,
					paneH,
					surfaceStyle,
					folder,
					chunkCfg,
					gateCfg,
					throughSign
				)
			end)
		end
	end

	return spawned, waveMax
end

local function spawnOneGlassShard(
	startPos: Vector3,
	face: GateFaceFrame,
	surfaceStyle: SurfaceStyle,
	parentFolder: Folder,
	chunkCfg: any,
	throughSign: number
): BasePart
	local size = Vector3.new(
		RNG:NextNumber(chunkCfg.SizeMin.X, chunkCfg.SizeMax.X),
		RNG:NextNumber(chunkCfg.SizeMin.Y, chunkCfg.SizeMax.Y),
		RNG:NextNumber(chunkCfg.SizeMin.Z, chunkCfg.SizeMax.Z)
	)

	local tangential = face.right * RNG:NextNumber(-1, 1) + face.up * RNG:NextNumber(-1, 1)
	if tangential.Magnitude > 0.01 then
		tangential = tangential.Unit
	else
		tangential = face.right
	end

	local throughSpeed = (chunkCfg.ThroughLaunchSpeed or 42)
		+ RNG:NextNumber(-(chunkCfg.ThroughLaunchSpread or 14), chunkCfg.ThroughLaunchSpread or 14)
	local tangSpeed = (chunkCfg.TangentialLaunchSpeed or 24)
		+ RNG:NextNumber(-(chunkCfg.TangentialLaunchSpread or 12), chunkCfg.TangentialLaunchSpread or 12)
	local upSpeed = (chunkCfg.UpLaunchSpeed or 18)
		+ RNG:NextNumber(-(chunkCfg.UpLaunchSpread or 10), chunkCfg.UpLaunchSpread or 10)

	local useWedge = RNG:NextNumber() < (chunkCfg.WedgeRatio or 0.85)
	local chip: BasePart
	if useWedge then
		chip = Instance.new("WedgePart")
	else
		chip = Instance.new("Part")
		chip.Shape = Enum.PartType.Block
	end

	chip.Name = "GlassBreakShard"
	chip.Size = size
	applySurfaceStyleToChip(chip, surfaceStyle)
	chip.Material = Enum.Material.Glass
	chip.Transparency = RNG:NextNumber(0.05, 0.28)
	chip.Reflectance = RNG:NextNumber(0.08, 0.22)
	chip.Anchored = false
	applyGlassBreakVfxPhysics(chip)
	chip.CastShadow = true
	chip.CFrame = CFrame.fromMatrix(startPos, face.right, face.up)
		* CFrame.Angles(
			math.rad(RNG:NextNumber(-35, 35)),
			math.rad(RNG:NextNumber(0, 360)),
			math.rad(RNG:NextNumber(-35, 35))
		)
	chip.Parent = parentFolder

	chip.AssemblyLinearVelocity = face.normal * throughSign * throughSpeed
		+ tangential * tangSpeed
		+ Vector3.new(0, upSpeed, 0)

	local spin = chunkCfg.AngularSpeed or 48
	chip.AssemblyAngularVelocity =
		Vector3.new(RNG:NextNumber(-1, 1) * spin, RNG:NextNumber(-1, 1) * spin, RNG:NextNumber(-1, 1) * spin)

	local fadeAt = chunkCfg.Lifetime * 0.45
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
	return chip
end

function SupermanGroundVfx.spawnGateGlassShatter(
	gatePart: BasePart,
	hitPos: Vector3,
	hitNormal: Vector3,
	chipCount: number?
): boolean
	local tier: BreakTier = "GlassBreak"
	if not canSpawnTier(tier) then
		return false
	end

	local tierCfg = SupermanVfxConfigs.Break.Tiers.GlassBreak
	if not tierCfg or tierCfg.SpawnChunks ~= true then
		return false
	end

	local chunkCfg = SupermanVfxConfigs.Break.GlassChunks
	local gateCfg = SupermanVfxConfigs.Break.GateGlassBreak
	local face = getGateFaceFrame(gatePart, hitNormal)
	gatePart.CanQuery = false
	gatePart.CanCollide = false
	gatePart.CanTouch = false
	local surfaceStyle = buildGlassSurfaceStyleFromPart(gatePart)
	local folder = getGlassVfxFolder()
	local usePaneGrid = gateCfg.UsePaneGrid ~= false and (chipCount == nil or chipCount <= 0)

	spawnGateGlassFlash(face, surfaceStyle, gateCfg)
	playGlassBreakSound(face.center)

	local ringDiameter = math.max(face.halfWidth * 2, face.halfHeight * 2) * (gateCfg.RingScale or 1.12)
	if tierCfg.Ring == true then
		spawnSurfaceRing(
			face.center,
			face.normal,
			math.max(ringDiameter, tierCfg.RingMaxDiameter or 20),
			tierCfg.RingDuration or 0.32,
			tierCfg.RingColor or Color3.fromRGB(210, 235, 255)
		)
	end

	if (tierCfg.ParticleBurst or 0) > 0 then
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.Anchored = true
		anchor.CFrame = CFrame.fromMatrix(hitPos + face.normal * 0.05, face.right, face.up)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Parent = folder
		local glassDustColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 250, 255)),
			ColorSequenceKeypoint.new(0.5, tintColor(surfaceStyle.color, 1.05)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 200, 225)),
		})
		spawnBurstParticles(anchor, tierCfg, false, glassDustColor)
		Debris:AddItem(anchor, SupermanVfxConfigs.Break.AnchorLifetime)
	end

	local staggerTotal = 0
	local spawnCount = 0

	if usePaneGrid then
		spawnCount, staggerTotal = spawnGateGlassPaneGrid(face, surfaceStyle, folder, chunkCfg, gateCfg)
	else
		spawnCount = math.max(1, chipCount or gateCfg.ShardCount or chunkCfg.Count)
		for i = 1, spawnCount do
			local stagger = (i - 1) * (gateCfg.StaggerSeconds or chunkCfg.StaggerSeconds)
			local throughSign = if i % 3 == 0 then -1 else 1
			task.delay(stagger, function()
				local shardPos = sampleGateFacePoint(face, 0.12)
				spawnOneGlassShard(shardPos, face, surfaceStyle, folder, chunkCfg, throughSign)
			end)
		end
		staggerTotal = spawnCount * (gateCfg.StaggerSeconds or chunkCfg.StaggerSeconds)
	end

	Debris:AddItem(folder, chunkCfg.Lifetime + staggerTotal + 0.5)
	return true
end

function SupermanGroundVfx.spawnGlassShatterAt(result: RaycastResult, chipCount: number?): boolean
	if result.Instance and result.Instance:IsA("BasePart") then
		return SupermanGroundVfx.spawnGateGlassShatter(
			result.Instance :: BasePart,
			result.Position,
			result.Normal,
			chipCount
		)
	end

	local tier: BreakTier = "GlassBreak"
	if not canSpawnTier(tier) then
		return false
	end

	local tierCfg = SupermanVfxConfigs.Break.Tiers.GlassBreak
	if not tierCfg or tierCfg.SpawnChunks ~= true then
		return false
	end

	local chunkCfg = SupermanVfxConfigs.Break.GlassChunks
	local hitPos = result.Position
	local hitNormal = result.Normal
	local surfaceRight, surfaceUp = buildSurfaceBasis(hitNormal)
	local surfaceTangent = surfaceUp:Cross(surfaceRight).Unit
	local look = surfaceTangent
	local right = surfaceRight
	local surfaceStyle = buildGlassSurfaceStyle(result)
	local folder = getGlassVfxFolder()
	local spawnCount = math.max(1, chipCount or chunkCfg.Count)

	if (tierCfg.ParticleBurst or 0) > 0 then
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.Anchored = true
		anchor.CFrame = CFrame.fromMatrix(hitPos + surfaceUp * 0.05, surfaceRight, surfaceUp)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Parent = folder
		spawnBurstParticles(anchor, tierCfg, false)
		Debris:AddItem(anchor, SupermanVfxConfigs.Break.AnchorLifetime)
	end

	for i = 1, spawnCount do
		local stagger = (i - 1) * chunkCfg.StaggerSeconds
		local lateralSign = if i % 2 == 0 then 1 else -1
		local jitter = surfaceRight * RNG:NextNumber(-1.2, 1.2) + surfaceTangent * RNG:NextNumber(-1.2, 1.2)
		task.delay(stagger, function()
			local chip = spawnOneLandingChunk(
				hitPos,
				hitNormal,
				jitter,
				look,
				right,
				surfaceStyle,
				lateralSign,
				folder,
				chunkCfg
			)
			chip.Transparency = RNG:NextNumber(0.1, 0.35)
			chip.Material = Enum.Material.Glass
			chip.Reflectance = 0.15
			applyGlassBreakVfxPhysics(chip)
		end)
	end

	local staggerTotal = spawnCount * chunkCfg.StaggerSeconds
	Debris:AddItem(folder, chunkCfg.Lifetime + staggerTotal + 0.5)
	return true
end

function SupermanGroundVfx.spawnHeatMeltAt(
	result: RaycastResult,
	character: Model?,
	beamDirection: Vector3?,
	chipCount: number?
): boolean
	local tier: BreakTier = "HeatVision"
	if not canSpawnTier(tier) then
		return false
	end

	spawnHeatVisionChunks(result, character, chipCount, beamDirection)
	return true
end

-- ── Metal gate melt (heat vision on stage barriers) ───────────────────────────

local metalVfxFolder: Folder? = nil
local METAL_VFX_COLLISION_GROUP = "MetalMeltVfx"
local metalVfxCollisionReady = false

local function ensureMetalVfxCollisionGroup()
	if metalVfxCollisionReady then
		return
	end
	metalVfxCollisionReady = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup(METAL_VFX_COLLISION_GROUP)
		PhysicsService:CollisionGroupSetCollidable(METAL_VFX_COLLISION_GROUP, "Default", false)
	end)
end

local function applyMetalMeltVfxPhysics(part: BasePart)
	ensureMetalVfxCollisionGroup()
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CollisionGroup = METAL_VFX_COLLISION_GROUP
end

local function getMetalVfxFolder(): Folder
	if metalVfxFolder and metalVfxFolder.Parent then
		return metalVfxFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = SupermanVfxConfigs.Break.MetalMeltChunks.FolderName
	folder.Parent = Workspace
	metalVfxFolder = folder
	return folder
end

function SupermanGroundVfx.getMetalMeltVfxFolder(): Folder?
	if metalVfxFolder and metalVfxFolder.Parent then
		return metalVfxFolder
	end
	local existing = Workspace:FindFirstChild(SupermanVfxConfigs.Break.MetalMeltChunks.FolderName)
	if existing and existing:IsA("Folder") then
		return existing
	end
	return nil
end

local function buildMetalSurfaceStyleFromPart(gatePart: BasePart): SurfaceStyle
	local gateCfg = SupermanVfxConfigs.Break.GateMetalMelt
	local color = gateCfg.ColdColor
	if gatePart.Transparency < 0.98 then
		color = gatePart.Color
	end
	return {
		color = color,
		material = Enum.Material.Metal,
		textureId = if gatePart:IsA("MeshPart") and gatePart.TextureID ~= "" then gatePart.TextureID else nil,
		sourceInstance = gatePart,
	}
end

local function spawnMetalScorchPatch(pos: Vector3, normal: Vector3, diameter: number, alpha: number, color: Color3)
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
	patch.Color = color
	patch.Parent = Workspace

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Scale = Vector3.new(radius, scorchCfg.Thickness, radius)
	mesh.Parent = patch

	registerScorch(patch)

	local fadeDuration = scorchCfg.FadeDuration
	TweenService:Create(patch, TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
	}):Play()
	Debris:AddItem(patch, fadeDuration + 0.15)
end

function SupermanGroundVfx.playGateMetalMeltSound(atPos: Vector3)
	local gateCfg = SupermanVfxConfigs.Break.GateMetalMelt
	local soundId = gateCfg.SoundId
	if typeof(soundId) ~= "string" or soundId == "" then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(atPos)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	local startVol = gateCfg.SoundVolume or 0.32
	local peakVol = math.clamp(gateCfg.SoundVolumePeak or 1, 0, 1)
	sound.Volume = startVol
	sound.PlaybackSpeed = gateCfg.SoundPlaybackSpeed or 0.84
	local rollOffMode = gateCfg.SoundRollOffMode
	if rollOffMode == "Inverse" then
		sound.RollOffMode = Enum.RollOffMode.Inverse
	elseif rollOffMode == "Linear" then
		sound.RollOffMode = Enum.RollOffMode.Linear
	else
		sound.RollOffMode = Enum.RollOffMode.LinearSquare
	end
	sound.RollOffMinDistance = gateCfg.SoundRollOffMinDistance or 24
	sound.RollOffMaxDistance = gateCfg.SoundRollOffMaxDistance or 980
	local emitterSize = gateCfg.SoundEmitterSize
	if typeof(emitterSize) == "number" and emitterSize > 0 then
		sound.EmitterSize = emitterSize
	end
	if
		typeof(gateCfg.SoundHighGain) == "number"
		or typeof(gateCfg.SoundMidGain) == "number"
		or typeof(gateCfg.SoundLowGain) == "number"
	then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.HighGain = if typeof(gateCfg.SoundHighGain) == "number" then gateCfg.SoundHighGain else 0
		eq.MidGain = if typeof(gateCfg.SoundMidGain) == "number" then gateCfg.SoundMidGain else 0
		eq.LowGain = if typeof(gateCfg.SoundLowGain) == "number" then gateCfg.SoundLowGain else 0
		eq.Parent = sound
	end
	sound.Parent = anchor
	sound:Play()

	local rampSec = gateCfg.SoundVolumeRampSeconds or 1.15
	if peakVol > startVol and rampSec > 0 then
		TweenService:Create(
			sound,
			TweenInfo.new(rampSec, Enum.EasingStyle.Exponential, Enum.EasingDirection.In),
			{ Volume = peakVol }
		):Play()
	else
		sound.Volume = peakVol
	end

	Debris:AddItem(anchor, math.max(4, rampSec + 2.5))
end

local function spawnMetalEmberBurst(anchor: Part, burst: number, hotColor: Color3)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emberColor = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)),
		ColorSequenceKeypoint.new(0.3, hotColor),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 40, 20)),
	})

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "MetalEmbers"
	embers.Texture = SupermanVfxConfigs.Break.ParticleTexture
	embers.Color = emberColor
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.35, 0.65),
		NumberSequenceKeypoint.new(1, 0.08),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.55, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(0.25, 0.65)
	embers.Speed = NumberRange.new(10, 26)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Acceleration = Vector3.new(0, -32, 0)
	embers.LightEmission = 0.9
	embers.RotSpeed = NumberRange.new(-180, 180)
	embers.Rate = 0
	embers.Parent = attachment
	embers:Emit(burst)

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "MetalSmoke"
	smoke.Texture = SupermanVfxConfigs.Break.ParticleTexture
	smoke.Color = SupermanVfxConfigs.Break.BlackDustColor
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.45, 1.4),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.4, 0.9)
	smoke.Speed = NumberRange.new(4, 12)
	smoke.SpreadAngle = Vector2.new(55, 55)
	smoke.LightEmission = 0.15
	smoke.Rate = 0
	smoke.Parent = attachment
	smoke:Emit(math.max(6, math.floor(burst * 0.5)))
end

local function spawnMetalMeltFlash(hitPos: Vector3, surfaceNormal: Vector3, hotColor: Color3)
	local normal = surfaceNormal.Unit
	local right, up = buildSurfaceBasis(normal)

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CFrame = CFrame.fromMatrix(hitPos + up * 0.04, right, up)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = Workspace

	spawnMetalEmberBurst(anchor, 8, hotColor)

	local glow = Instance.new("PointLight")
	glow.Color = hotColor
	glow.Brightness = 2.5
	glow.Range = 10
	glow.Parent = anchor
	TweenService:Create(glow, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
	}):Play()

	Debris:AddItem(anchor, 0.65)
end

local function spawnMoltenDrip(hitPos: Vector3, surfaceNormal: Vector3, gateCfg: any)
	local hotColor = gateCfg.HotColor or Color3.fromRGB(255, 106, 26)
	local slagColor = gateCfg.SlagColor or Color3.fromRGB(42, 36, 32)
	local normal = surfaceNormal.Unit

	local drip = Instance.new("Part")
	drip.Name = "MoltenDrip"
	drip.Size = Vector3.new(0.18, 0.35, 0.18)
	drip.Shape = Enum.PartType.Ball
	drip.Material = Enum.Material.Neon
	drip.Color = hotColor
	drip.Anchored = false
	applyMetalMeltVfxPhysics(drip)
	drip.CFrame = CFrame.new(hitPos + normal * 0.08)
	drip.Parent = getMetalVfxFolder()

	local dripSpeed = gateCfg.DripSpeed or 22
	drip.AssemblyLinearVelocity = Vector3.new(0, -dripSpeed, 0) + normal * RNG:NextNumber(0.5, 2.5)

	task.delay(0.35, function()
		if drip.Parent then
			TweenService:Create(
				drip,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Color = slagColor, Transparency = 1 }
			):Play()
		end
	end)
	Debris:AddItem(drip, 0.85)
end

function SupermanGroundVfx.spawnGateMetalMeltImpact(gatePart: BasePart, hitPos: Vector3, hitNormal: Vector3)
	local gateCfg = SupermanVfxConfigs.Break.GateMetalMelt
	local hotColor = gateCfg.HotColor or Color3.fromRGB(255, 106, 26)
	spawnMetalMeltFlash(hitPos, hitNormal, hotColor)
	spawnMoltenDrip(hitPos, hitNormal, gateCfg)
end

local function spawnGateMetalFlash(face: GateFaceFrame, gateCfg: any)
	local flashRange = (gateCfg.FlashRange or 26)
		* math.clamp(math.max(face.halfWidth, face.halfHeight) * (gateCfg.FlashRangeScale or 0.7), 1, 3)
	local hotColor = gateCfg.FlashColor or gateCfg.HotColor or Color3.fromRGB(255, 120, 40)

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CFrame = CFrame.fromMatrix(face.center + face.normal * 0.06, face.right, face.up)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = Workspace

	spawnMetalEmberBurst(anchor, gateCfg.EmberBurst or 36, hotColor)

	local glow = Instance.new("PointLight")
	glow.Color = hotColor
	glow.Brightness = gateCfg.FlashBrightness or 6
	glow.Range = flashRange
	glow.Parent = anchor
	TweenService:Create(
		glow,
		TweenInfo.new(gateCfg.FlashDuration or 0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	):Play()

	Debris:AddItem(anchor, (gateCfg.FlashDuration or 0.32) + 0.35)
end

local function spawnOneMetalSlagPane(
	centerPos: Vector3,
	face: GateFaceFrame,
	paneWidth: number,
	paneHeight: number,
	parentFolder: Folder,
	gateCfg: any,
	chunkCfg: any
): BasePart
	local jitter = gateCfg.PaneSizeJitter or 0.04
	local w = paneWidth * RNG:NextNumber(1 - jitter, 1)
	local h = paneHeight * RNG:NextNumber(1 - jitter, 1)
	local depth = RNG:NextNumber(gateCfg.PaneThicknessMin or 0.18, gateCfg.PaneThicknessMax or 0.42)

	local hotColor = gateCfg.HotColor or Color3.fromRGB(255, 106, 26)
	local slagColor = gateCfg.SlagColor or chunkCfg.SlagColor or Color3.fromRGB(42, 36, 32)
	local lifetime = gateCfg.SlagLifetime or chunkCfg.Lifetime or 3.2

	local tangential = face.right * RNG:NextNumber(-1, 1) + face.up * RNG:NextNumber(-1, 1)
	if tangential.Magnitude > 0.01 then
		tangential = tangential.Unit
	else
		tangential = face.right
	end

	local dripSpeed = (gateCfg.DripSpeed or 22)
		+ RNG:NextNumber(-(gateCfg.DripSpeedSpread or 8), gateCfg.DripSpeedSpread or 8)
	local outward = (gateCfg.OutwardSpeed or 4)
		+ RNG:NextNumber(-(gateCfg.OutwardSpread or 3), gateCfg.OutwardSpread or 3)
	local tangSpeed = (gateCfg.TangentialSpeed or 6)
		+ RNG:NextNumber(-(gateCfg.TangentialSpread or 4), gateCfg.TangentialSpread or 4)

	local useWedge = RNG:NextNumber() < (chunkCfg.WedgeRatio or 0.15)
	local chip: BasePart
	if useWedge then
		chip = Instance.new("WedgePart")
	else
		chip = Instance.new("Part")
		chip.Shape = Enum.PartType.Block
	end

	chip.Name = "MetalSlagPane"
	chip.Size = Vector3.new(w, h, depth)
	chip.Material = if RNG:NextNumber() < 0.35 then Enum.Material.Neon else Enum.Material.Metal
	chip.Color = hotColor
	chip.Reflectance = RNG:NextNumber(0.05, 0.18)
	chip.Anchored = false
	applyMetalMeltVfxPhysics(chip)
	chip.CastShadow = true
	chip.CFrame = CFrame.fromMatrix(centerPos, face.right, face.up)
		* CFrame.Angles(
			math.rad(RNG:NextNumber(-12, 12)),
			math.rad(RNG:NextNumber(-8, 8)),
			math.rad(RNG:NextNumber(-12, 12))
		)
	chip.Parent = parentFolder

	chip.AssemblyLinearVelocity = Vector3.new(0, -dripSpeed, 0)
		+ face.normal * outward
		+ tangential * tangSpeed

	local spin = chunkCfg.AngularSpeed or 18
	chip.AssemblyAngularVelocity =
		Vector3.new(RNG:NextNumber(-1, 1) * spin, RNG:NextNumber(-1, 1) * spin, RNG:NextNumber(-1, 1) * spin)

	local fadeAt = lifetime * 0.4
	task.delay(fadeAt, function()
		if chip.Parent then
			TweenService:Create(
				chip,
				TweenInfo.new(lifetime - fadeAt, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Color = slagColor, Transparency = 1 }
			):Play()
		end
	end)
	Debris:AddItem(chip, lifetime)
	return chip
end

local function spawnGateMetalSlagGrid(
	face: GateFaceFrame,
	folder: Folder,
	chunkCfg: any,
	gateCfg: any
): (number, number)
	local cols, rows, paneW, paneH = computeGatePaneLayout(face, gateCfg)
	local maxDist = math.sqrt(face.halfWidth * face.halfWidth + face.halfHeight * face.halfHeight)
	local waveMax = gateCfg.WaveStaggerMax or 0.12
	local spawned = 0

	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			local u = -face.halfWidth + paneW * (col + 0.5)
			local v = -face.halfHeight + paneH * (row + 0.5)
			local paneCenter = face.center + face.right * u + face.up * v
			local dist01 = if maxDist > 0.01 then (paneCenter - face.center).Magnitude / maxDist else 0
			local stagger = dist01 * waveMax + RNG:NextNumber(0, waveMax * 0.25)
			spawned += 1

			task.delay(stagger, function()
				spawnOneMetalSlagPane(paneCenter, face, paneW, paneH, folder, gateCfg, chunkCfg)
			end)
		end
	end

	return spawned, waveMax
end

function SupermanGroundVfx.spawnGateMetalMelt(
	gatePart: BasePart,
	hitPos: Vector3,
	hitNormal: Vector3,
	chipCount: number?
): boolean
	local tier: BreakTier = "MetalMelt"
	if not canSpawnTier(tier) then
		return false
	end

	local tierCfg = SupermanVfxConfigs.Break.Tiers.MetalMelt
	if not tierCfg or tierCfg.SpawnChunks ~= true then
		return false
	end

	local chunkCfg = SupermanVfxConfigs.Break.MetalMeltChunks
	local gateCfg = SupermanVfxConfigs.Break.GateMetalMelt
	local face = getGateFaceFrame(gatePart, hitNormal)
	gatePart.CanQuery = false
	gatePart.CanCollide = false
	gatePart.CanTouch = false
	local folder = getMetalVfxFolder()
	local usePaneGrid = gateCfg.UsePaneGrid ~= false and (chipCount == nil or chipCount <= 0)

	spawnGateMetalFlash(face, gateCfg)
	SupermanGroundVfx.playGateMetalMeltSound(face.center)

	local staggerTotal = 0
	if usePaneGrid then
		local _, waveMax = spawnGateMetalSlagGrid(face, folder, chunkCfg, gateCfg)
		staggerTotal = waveMax + 0.5
	else
		local spawnCount = math.max(1, chipCount or gateCfg.ShardCount or 32)
		for i = 1, spawnCount do
			local stagger = (i - 1) * (gateCfg.StaggerSeconds or 0.008)
			task.delay(stagger, function()
				local shardPos = sampleGateFacePoint(face, 0.12)
				local cols, rows, paneW, paneH = computeGatePaneLayout(face, gateCfg)
				spawnOneMetalSlagPane(shardPos, face, paneW, paneH, folder, gateCfg, chunkCfg)
			end)
		end
		staggerTotal = spawnCount * (gateCfg.StaggerSeconds or 0.008)
	end

	local ringDiameter = math.max(face.halfWidth * 2, face.halfHeight * 2) * (gateCfg.RingScale or 1.08)
	if tierCfg.Ring == true then
		spawnSurfaceRing(
			face.center,
			face.normal,
			math.max(ringDiameter, tierCfg.RingMaxDiameter or 22),
			tierCfg.RingDuration or 0.38,
			tierCfg.RingColor or Color3.fromRGB(255, 110, 35)
		)
	end

	if (tierCfg.ScorchDiameter or 0) > 0 then
		local scorchPos = face.center - face.up * (face.halfHeight * 0.85)
		spawnMetalScorchPatch(
			scorchPos,
			Vector3.new(0, 1, 0),
			tierCfg.ScorchDiameter,
			tierCfg.ScorchAlpha or 0.42,
			Color3.fromRGB(45, 28, 18)
		)
	end

	if (tierCfg.ParticleBurst or 0) > 0 then
		local anchor = Instance.new("Part")
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.Anchored = true
		anchor.CFrame = CFrame.fromMatrix(hitPos + face.normal * 0.05, face.right, face.up)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Parent = folder
		spawnBurstParticles(anchor, tierCfg, true)
		Debris:AddItem(anchor, SupermanVfxConfigs.Break.AnchorLifetime)
	end

	Debris:AddItem(folder, (gateCfg.SlagLifetime or chunkCfg.Lifetime or 3.2) + staggerTotal + 0.5)
	return true
end

function SupermanGroundVfx.spawnMetalMeltAt(result: RaycastResult, chipCount: number?): boolean
	if result.Instance and result.Instance:IsA("BasePart") then
		return SupermanGroundVfx.spawnGateMetalMelt(
			result.Instance :: BasePart,
			result.Position,
			result.Normal,
			chipCount
		)
	end
	return false
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

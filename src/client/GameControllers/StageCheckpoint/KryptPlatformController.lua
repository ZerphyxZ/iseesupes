--!strict

-- Stage 8 Krypts: platforms fade while the local player stands on them, then drop
-- the player through. Purely client-side (Transparency + CanCollide on this client
-- only), so in multiplayer each player has their own platform state.
--
-- StreamingEnabled-safe at any stream radius:
--   • Map/workspace DescendantAdded discovers Krypts when it streams in
--   • ChildAdded / DescendantAdded on the folder register parts as they appear
--   • Platform fade state is keyed by world position and survives stream-out
--   • Raycast filter rebuilds from currently registered parts only
--   • Optional RequestStreamAroundAsync near Stage 8 so tiny radii still load pads

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local CharacterConfigs = require(ReplicatedStorage.Shared.Configs.CharacterConfigs)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)

local FadeCfg = (CharacterConfigs.DoubleJump.Kryptonite or {}).FadePlatforms

local KryptPlatformController = Knit.CreateController({ Name = "KryptPlatformController" })

local player = Players.LocalPlayer

type PlatformState = {
	stableKey: string,
	model: Instance?,
	parts: { [BasePart]: number }, -- part -> original Transparency
	originalCanCollide: { [BasePart]: boolean },
	alpha: number, -- 0 = solid, 1 = fully faded (fall-through)
	fallenAt: number?, -- os.clock() when the player dropped through
	collisionOff: boolean,
}

local platformsByKey: { [string]: PlatformState } = {}
local partToPlatform: { [BasePart]: PlatformState } = {}
local boundFolders: { [Instance]: boolean } = {}
local rayParams: RaycastParams? = nil
local rayFilterParts: { BasePart } = {}
local lastStreamRequestAt = 0.0

local function getStablePlatformKey(model: Instance): string
	local ok, pivot = pcall(function()
		return model:GetPivot().Position
	end)
	if ok and typeof(pivot) == "Vector3" then
		return string.format("%d_%d", math.round(pivot.X), math.round(pivot.Z))
	end
	return model:GetFullName()
end

local function rebuildRayFilter()
	table.clear(rayFilterParts)
	for part in partToPlatform do
		if part.Parent then
			table.insert(rayFilterParts, part)
		end
	end
	if rayParams then
		rayParams.FilterDescendantsInstances = rayFilterParts
	end
end

local function applyPartAlpha(state: PlatformState, part: BasePart)
	local base = state.parts[part] or 0
	part.Transparency = base + (FadeCfg.MaxTransparency - base) * state.alpha
end

local function applyPlatformAlpha(state: PlatformState)
	for part in state.parts do
		if part.Parent then
			applyPartAlpha(state, part)
		end
	end
end

local function setPlatformCollision(state: PlatformState, enabled: boolean)
	if state.collisionOff == not enabled then
		return
	end
	state.collisionOff = not enabled
	for part in state.parts do
		if part.Parent and state.originalCanCollide[part] then
			part.CanCollide = enabled
		end
	end
end

--- Walks up from a part to the KryptoModels child of the Krypts folder, if any.
local function getPlatformModel(folder: Instance, instance: Instance): Instance?
	local current: Instance? = instance
	while current and current ~= folder do
		if current.Parent == folder and current.Name == FadeCfg.ModelName then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getOrCreatePlatformState(model: Instance): PlatformState
	local stableKey = getStablePlatformKey(model)
	local state = platformsByKey[stableKey]
	if not state then
		state = {
			stableKey = stableKey,
			model = model,
			parts = {},
			originalCanCollide = {},
			alpha = 0,
			fallenAt = nil,
			collisionOff = false,
		}
		platformsByKey[stableKey] = state
	else
		state.model = model
	end
	return state
end

local function registerPart(folder: Instance, part: BasePart)
	if partToPlatform[part] then
		return
	end
	local model = getPlatformModel(folder, part)
	if not model then
		return
	end

	local state = getOrCreatePlatformState(model)
	state.parts[part] = part.Transparency
	state.originalCanCollide[part] = part.CanCollide
	partToPlatform[part] = state

	if state.alpha > 0 then
		applyPartAlpha(state, part)
	end
	if state.collisionOff and part.CanCollide then
		part.CanCollide = false
	end

	rebuildRayFilter()
end

local function unregisterPart(part: BasePart)
	local state = partToPlatform[part]
	if not state then
		return
	end
	partToPlatform[part] = nil
	state.parts[part] = nil
	state.originalCanCollide[part] = nil
	if next(state.parts) == nil then
		state.model = nil
	end
	rebuildRayFilter()
end

local function scanModelParts(folder: Instance, model: Instance)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			registerPart(folder, desc)
		end
	end
end

local function isKryptsFolder(instance: Instance): boolean
	if instance.Name ~= FadeCfg.FolderName then
		return false
	end
	return instance:FindFirstAncestor(FadeCfg.StageModelName) ~= nil
end

local function bindKryptsFolder(folder: Instance)
	if boundFolders[folder] then
		return
	end
	boundFolders[folder] = true

	for _, child in folder:GetChildren() do
		if child.Name == FadeCfg.ModelName then
			scanModelParts(folder, child)
		end
	end
	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") then
			registerPart(folder, desc)
		end
	end

	folder.ChildAdded:Connect(function(child)
		if child.Name == FadeCfg.ModelName then
			task.defer(function()
				if child.Parent == folder then
					scanModelParts(folder, child)
				end
			end)
		end
	end)

	folder.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			task.defer(function()
				if desc:IsDescendantOf(folder) then
					registerPart(folder, desc)
				end
			end)
		end
	end)

	folder.DescendantRemoving:Connect(function(desc)
		if desc:IsA("BasePart") then
			unregisterPart(desc)
		end
	end)

	folder.AncestryChanged:Connect(function()
		if folder.Parent then
			return
		end
		boundFolders[folder] = nil
	end)
end

local function tryBindKryptsFolder(instance: Instance)
	if isKryptsFolder(instance) then
		bindKryptsFolder(instance)
	end
end

local function bindWorldStreamingWatch()
	local map = MapWorld.getMapFolder()
	if map then
		for _, desc in map:GetDescendants() do
			tryBindKryptsFolder(desc)
		end
		map.DescendantAdded:Connect(tryBindKryptsFolder)
	end

	for _, desc in workspace:GetDescendants() do
		tryBindKryptsFolder(desc)
	end
	workspace.DescendantAdded:Connect(tryBindKryptsFolder)
end

local function isNearKryptsCourse(root: BasePart): boolean
	local bounds = FadeCfg.StreamBounds
	if not bounds then
		return false
	end
	local pos = root.Position
	return math.abs(pos.X - bounds.CenterX) <= bounds.RadiusX
		and pos.Z >= bounds.MinZ
		and pos.Z <= bounds.MaxZ
end

local function maybeRequestStreamAround(root: BasePart)
	if workspace.StreamingEnabled ~= true or FadeCfg.RequestStreamAround ~= true then
		return
	end
	if not isNearKryptsCourse(root) then
		return
	end
	local interval = FadeCfg.StreamRequestInterval or 2.0
	local now = os.clock()
	if now - lastStreamRequestAt < interval then
		return
	end
	lastStreamRequestAt = now
	pcall(function()
		player:RequestStreamAroundAsync(root.Position)
	end)
end

--- Returns the platform the local character currently stands on, if any.
local function getStandingPlatform(): PlatformState?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not rayParams or #rayFilterParts == 0 then
		return nil
	end
	local result = workspace:Raycast(root.Position, Vector3.new(0, -FadeCfg.StandRayLength, 0), rayParams)
	if result and result.Instance then
		return partToPlatform[result.Instance]
	end
	return nil
end

local function onHeartbeat(dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		maybeRequestStreamAround(root)
	end

	local standingOn = getStandingPlatform()
	local now = os.clock()

	for _, state in platformsByKey do
		local previousAlpha = state.alpha

		if state.fallenAt then
			if now - state.fallenAt >= FadeCfg.RestoreDelay then
				state.fallenAt = nil
				setPlatformCollision(state, true)
			end
		elseif state == standingOn and not state.collisionOff then
			state.alpha = math.min(1, state.alpha + dt / FadeCfg.FadeDuration)
			if state.alpha >= 1 then
				setPlatformCollision(state, false)
				state.fallenAt = now
			end
		elseif state.alpha > 0 then
			state.alpha = math.max(0, state.alpha - dt / FadeCfg.RecoverDuration)
		end

		if state.alpha ~= previousAlpha then
			applyPlatformAlpha(state)
		end
	end
end

function KryptPlatformController:KnitStart()
	if not FadeCfg or FadeCfg.Enabled ~= true then
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = rayFilterParts
	rayParams = params

	bindWorldStreamingWatch()
	RunService.Heartbeat:Connect(onHeartbeat)
end

return KryptPlatformController

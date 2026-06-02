--!strict

local Workspace = game:GetService("Workspace")

local FriendStandConfigs = require(script.Parent.Parent.Configs.FriendStandConfigs)
local FriendStandDebug = require(script.Parent.FriendStandDebug)

local FriendStandWorld = {}

local function walkPath(root: Instance, segments: { string }): Instance?
	local node: Instance = root
	for _, name in segments do
		local child = node:FindFirstChild(name)
		if not child then
			return nil
		end
		node = child
	end
	return node
end

function FriendStandWorld.resolveStandModel(): Model?
	local paths: { { string } } = { FriendStandConfigs.RootPath }
	for _, alt in FriendStandConfigs.AlternateRootPaths do
		table.insert(paths, alt)
	end

	for _, segments in paths do
		local node = walkPath(Workspace, segments)
		if node and node:IsA("Model") then
			FriendStandDebug.log("resolveStand: path", table.concat(segments, "."), "→", node:GetFullName())
			return node
		end
		if node then
			FriendStandDebug.warn("resolveStand: found", table.concat(segments, "."), "but type is", node.ClassName, "not Model")
		end
	end

	for _, desc in Workspace:GetDescendants() do
		if desc:IsA("Model") and desc.Name == FriendStandConfigs.RootPath[#FriendStandConfigs.RootPath] then
			FriendStandDebug.log("resolveStand: descendant search →", desc:GetFullName())
			return desc
		end
	end

	FriendStandDebug.warn("resolveStand: FriendStand not found in Workspace")
	return nil
end

function FriendStandWorld.findPart(model: Model, partName: string, silent: boolean?): BasePart?
	local inst = model:FindFirstChild(partName, true)
	if inst and inst:IsA("BasePart") then
		return inst :: BasePart
	end
	if not silent then
		FriendStandDebug.warn("findPart: missing", partName, "under", model:GetFullName())
	end
	return nil
end

function FriendStandWorld.findSpawnPart(model: Model, silent: boolean?): BasePart?
	for _, name in FriendStandConfigs.CharacterSpawnPartAliases do
		local part = FriendStandWorld.findPart(model, name, true)
		if part then
			if not silent then
				FriendStandDebug.log("findSpawnPart: using", part:GetFullName())
			end
			return part
		end
	end
	if not silent then
		FriendStandDebug.warn("findSpawnPart: no spawn part under", model:GetFullName())
	end
	return nil
end

--- Client may see FriendStand before child parts replicate; poll until spawn exists.
function FriendStandWorld.waitForSpawnPart(model: Model, timeout: number?): BasePart?
	local limit = timeout or FriendStandConfigs.PartsReplicateTimeout
	local deadline = os.clock() + limit

	local found = FriendStandWorld.findSpawnPart(model, true)
	if found then
		return found
	end

	local childCount = #model:GetChildren()
	FriendStandDebug.log(
		"waitForSpawnPart: model has",
		childCount,
		"direct children; waiting for",
		FriendStandConfigs.CharacterSpawnPartName,
		"..."
	)

	while os.clock() < deadline do
		found = FriendStandWorld.findSpawnPart(model, true)
		if found then
			FriendStandDebug.log("waitForSpawnPart: ready →", found:GetFullName())
			return found
		end
		task.wait(0.2)
	end

	FriendStandDebug.warn(
		"waitForSpawnPart: timed out after",
		limit,
		"s (children=",
		#model:GetChildren(),
		"descendants=",
		#model:GetDescendants(),
		")"
	)
	return nil
end

function FriendStandWorld.collectTouchParts(model: Model): { BasePart }
	local seen: { [BasePart]: boolean } = {}
	local parts: { BasePart } = {}

	local function addPart(part: BasePart)
		if seen[part] then
			return
		end
		seen[part] = true
		table.insert(parts, part)
	end

	for _, name in FriendStandConfigs.TouchPartNames do
		local part = FriendStandWorld.findPart(model, name, true)
		if part then
			addPart(part)
		end
	end

	if #parts == 0 then
		for _, desc in model:GetDescendants() do
			if desc:IsA("BasePart") and desc.Name ~= FriendStandConfigs.DisplayModelName then
				addPart(desc)
			end
		end
	end

	return parts
end

return FriendStandWorld

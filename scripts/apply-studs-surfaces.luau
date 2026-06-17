--!strict
-- apply-studs-surfaces.luau
-- Run in Studio (command bar / MCP execute_luau, EDIT mode).
--
-- Gives the environment the classic Roblox "studs" look by setting legacy SurfaceType.Studs on
-- every face of each visible structural Part under Workspace.Map, and switching the part to
-- Plastic (keeping its Color3) so the studs actually render. Legacy studs are CORE-RENDERED
-- (not decals), so unlike the old 6287061221 Texture they are NOT subject to the per-GPU decal
-- cap that drops textures on low-end / mobile.
--
-- IMPORTANT: the material MUST be a stud-rendering one. `SmoothPlastic` and `Glass` are "smooth"
-- materials that IGNORE SurfaceType and show NO studs — verified in this place. Use `Plastic`.
--
-- Fully reversible via revert-studs-surfaces.luau using the attributes this writes:
--   _origSurfaces (per part, the 6 original SurfaceType names joined by ",")
--   _origMat      (per part, the original Enum.Material name)
--   _origTransp   (per Texture/Decal it hides, the original Transparency)
--
-- Toggle the constants below, then run. Start with DRY_RUN = true to preview scope.

local Workspace = game:GetService("Workspace")

-- === knobs ===================================================================
local DRY_RUN = true                                  -- true = count/report only, no mutations
local SCOPE = "ALL"                                   -- "ALL" (whole Workspace.Map) or a child name e.g. "Stage1"
local TARGET_MATERIAL = Enum.Material.Plastic         -- MUST be a stud-rendering material; SmoothPlastic/Glass show NO studs
-- =============================================================================

local STUD = Enum.SurfaceType.Studs
local SURFACE_PROPS = { "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" }
local EXCLUDED_MATERIALS = { [Enum.Material.Neon] = true, [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true }
local EXCLUDED_MODEL_NAMES = { Supes = true, AvatarsShowcase = true, SpideyEnvr = true, Supergirl = true }

local map = Workspace:FindFirstChild("Map")
if not map then
	return "ERROR: Workspace.Map not found"
end

local scopeRoot: Instance = map
if SCOPE ~= "ALL" then
	local found = map:FindFirstChild(SCOPE)
	if not found then
		return "ERROR: scope '" .. SCOPE .. "' not found under Workspace.Map"
	end
	scopeRoot = found
end

-- Inside a character / showcase / leftover subtree we must leave alone?
local function inExcludedSubtree(inst: Instance): boolean
	local n = inst.Parent
	while n and n ~= game do
		if n:IsA("Model") then
			if EXCLUDED_MODEL_NAMES[n.Name] then
				return true
			end
			if n:FindFirstChildOfClass("Humanoid") then
				return true
			end
		end
		n = n.Parent
	end
	return false
end

local function isTargetable(part: BasePart): boolean
	if not (part:IsA("Part") or part:IsA("WedgePart")) then
		return false
	end
	if part:IsA("SpawnLocation") then
		return false
	end
	if part.Transparency >= 1 then
		return false -- invisible hitboxes / trigger zones must not become visible studded blocks
	end
	if EXCLUDED_MATERIALS[part.Material] then
		return false
	end
	if inExcludedSubtree(part) then
		return false
	end
	return true
end

-- The child of `map` that owns this part (e.g. Stage6, Lobby) for the per-folder report.
local function topFolderName(part: Instance): string
	local n: Instance = part
	while n.Parent and n.Parent ~= map do
		n = n.Parent
	end
	return n.Name
end

local perFolder: { [string]: number } = {}
local targeted, decalsHidden = 0, 0

for _, desc in scopeRoot:GetDescendants() do
	if desc:IsA("BasePart") and isTargetable(desc) then
		local part = desc :: BasePart
		local folder = topFolderName(part)
		perFolder[folder] = (perFolder[folder] or 0) + 1
		targeted += 1

		if not DRY_RUN then
			-- Store originals once (a re-run must not overwrite the saved state).
			if part:GetAttribute("_origSurfaces") == nil then
				local names = {}
				for _, prop in SURFACE_PROPS do
					table.insert(names, ((part :: any)[prop] :: EnumItem).Name)
				end
				part:SetAttribute("_origSurfaces", table.concat(names, ","))
			end
			if part:GetAttribute("_origMat") == nil then
				part:SetAttribute("_origMat", part.Material.Name)
			end

			for _, prop in SURFACE_PROPS do
				(part :: any)[prop] = STUD
			end
			part.Material = TARGET_MATERIAL

			-- Hide any still-visible decal/texture so studs aren't layered over leftover texture.
			for _, d in part:GetChildren() do
				if (d:IsA("Texture") or d:IsA("Decal")) and d.Transparency < 1 then
					if d:GetAttribute("_origTransp") == nil then
						d:SetAttribute("_origTransp", d.Transparency)
					end
					d.Transparency = 1
					decalsHidden += 1
				end
			end
		end
	end
end

local folders = {}
for name, n in perFolder do
	table.insert(folders, name .. "=" .. n)
end
table.sort(folders)

local lines = {
	(DRY_RUN and "DRY RUN — no changes made" or "APPLIED studs surfaces") .. "  (scope=" .. SCOPE .. ", material=" .. TARGET_MATERIAL.Name .. ")",
	"targetable Part/WedgePart: " .. targeted,
}
if not DRY_RUN then
	table.insert(lines, "leftover decals hidden: " .. decalsHidden)
end
table.insert(lines, "by folder: " .. table.concat(folders, "  "))
return table.concat(lines, "\n")

--!strict
-- revert-studs-surfaces.luau
-- Run in Studio (command bar / MCP execute_luau, EDIT mode).
--
-- Undoes apply-studs-surfaces.luau: restores each part's original SurfaceTypes (_origSurfaces)
-- and Material (_origMat), un-hides any decals it hid (_origTransp), and clears the markers.
-- Same _orig*-attribute reversal shape as revert-mesh-material.luau.

local Workspace = game:GetService("Workspace")

-- === knobs ===================================================================
local SCOPE = "ALL" -- "ALL" (whole Workspace.Map) or a child name e.g. "Stage1"
-- =============================================================================

local SURFACE_PROPS = { "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" }

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

local revertedParts, restoredDecals, warnings = 0, 0, 0

for _, desc in scopeRoot:GetDescendants() do
	if desc:IsA("BasePart") then
		local origSurfaces = desc:GetAttribute("_origSurfaces")
		if typeof(origSurfaces) == "string" then
			local names = string.split(origSurfaces, ",")
			for i, prop in SURFACE_PROPS do
				local enumName = names[i]
				if enumName then
					local ok, val = pcall(function()
						return (Enum.SurfaceType :: any)[enumName]
					end)
					if ok and val then
						(desc :: any)[prop] = val
					else
						warnings += 1
					end
				end
			end

			local origMat = desc:GetAttribute("_origMat")
			if typeof(origMat) == "string" then
				local ok, mat = pcall(function()
					return (Enum.Material :: any)[origMat]
				end)
				if ok and mat then
					desc.Material = mat
				else
					warnings += 1
				end
			end

			desc:SetAttribute("_origSurfaces", nil)
			desc:SetAttribute("_origMat", nil)
			revertedParts += 1
		end

		for _, d in desc:GetChildren() do
			if d:IsA("Texture") or d:IsA("Decal") then
				local t = d:GetAttribute("_origTransp")
				if typeof(t) == "number" then
					d.Transparency = t
					d:SetAttribute("_origTransp", nil)
					restoredDecals += 1
				end
			end
		end
	end
end

return ("REVERTED %d parts, restored %d decals, %d warnings (scope=%s)"):format(
	revertedParts,
	restoredDecals,
	warnings,
	SCOPE
)

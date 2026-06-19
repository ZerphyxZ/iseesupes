--!strict
-- delete-redundant-textures.luau
-- Run in Studio (command bar / MCP execute_luau, EDIT mode), then SAVE + PUBLISH.
--
-- WHY: the environment was mass-stamped with a single shared Texture asset (rbxassetid://6287061221)
-- on every face of thousands of parts. apply-studs-surfaces.luau gave the map the classic "studs"
-- look and HID these textures (Transparency=1) but never removed the instances. Each hidden Texture
-- still costs DataModel memory + join-time replication on EVERY client. With StreamingEnabled=false
-- the whole world replicates at join, and on <2GB-RAM Android that payload OOM-crashes the client
-- (8.93% crash rate vs 0.98% overall). Because it is ONE shared image, deleting these frees
-- INSTANCE / replication memory (not VRAM — the image loads once regardless).
--
-- The Studs look is FINAL (user decision) — this is intentionally NOT reversible. The parts keep
-- their _origSurfaces/_origMat attributes, so the studs surfaces themselves can still be reverted;
-- only the textured look is gone. revert-studs-surfaces.luau's texture-unhide step becomes a no-op.
--
-- SAFE DEFAULT pass: hidden (Transparency>=1) textures under Workspace.Map only — already invisible,
-- fully replaced by studs, ZERO visual change. Flip the knobs for the wider (visible / template)
-- passes once their visual impact has been verified.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ASSET = "rbxassetid://6287061221"

-- === knobs ===================================================================
local DRY_RUN = true                  -- true = count/report only, no deletions
local INCLUDE_VISIBLE = false         -- false = only Transparency>=1 (safe); true = also visible ones
local SCAN_MAP = true                 -- scan Workspace.Map
local SCAN_REPLICATED_STORAGE = false -- also scan ReplicatedStorage obstacle templates
-- Subtrees to leave untouched (visible character/showcase models). Matched by Model name anywhere
-- in the ancestry — mirrors apply-studs-surfaces.luau's EXCLUDED_MODEL_NAMES.
local EXCLUDED_MODEL_NAMES = { Supes = true, AvatarsShowcase = true, SpideyEnvr = true, Supergirl = true }
-- =============================================================================

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

local roots: { Instance } = {}
if SCAN_MAP then
	local map = Workspace:FindFirstChild("Map")
	if map then
		table.insert(roots, map)
	else
		return "ERROR: Workspace.Map not found"
	end
end
if SCAN_REPLICATED_STORAGE then
	table.insert(roots, ReplicatedStorage)
end
if #roots == 0 then
	return "ERROR: nothing to scan (enable SCAN_MAP and/or SCAN_REPLICATED_STORAGE)"
end

local toDelete: { Instance } = {}
local matched, skippedVisible, skippedExcluded = 0, 0, 0

for _, root in roots do
	for _, d in root:GetDescendants() do
		if (d:IsA("Texture") or d:IsA("Decal")) and (d :: any).Texture == ASSET then
			matched += 1
			local isHidden = d.Transparency >= 1
			if not isHidden and not INCLUDE_VISIBLE then
				-- visible texture, hidden-only mode: leave it
				skippedVisible += 1
			elseif not isHidden and inExcludedSubtree(d) then
				-- visible texture inside a protected character/showcase model: leave its look intact
				skippedExcluded += 1
			else
				-- hidden (invisible → always safe to remove) OR visible-and-not-in-protected-subtree
				table.insert(toDelete, d)
			end
		end
	end
end

if not DRY_RUN then
	for _, d in toDelete do
		d:Destroy()
	end
end

local lines = {
	(DRY_RUN and "DRY RUN — no deletions" or "DELETED redundant textures")
		.. ("  (asset=%s)"):format(ASSET),
	("scanned roots: %s"):format((function()
		local names = {}
		for _, r in roots do
			table.insert(names, r:GetFullName())
		end
		return table.concat(names, ", ")
	end)()),
	("matched=%d  to-delete=%d  skipped(visible)=%d  skipped(excluded subtree)=%d"):format(
		matched,
		#toDelete,
		skippedVisible,
		skippedExcluded
	),
}
return table.concat(lines, "\n")

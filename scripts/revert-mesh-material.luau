--[[
    Revert material on MeshParts that have a non-empty TextureID back to their
    original material (stored in the _origMat attribute by the Fabric rollout).

    Run via execute_luau in Studio (Edit DM) after reconnecting the MCP.
    Returns a summary of what was fixed.
--]]

local Workspace = game:GetService("Workspace")
local map = Workspace:FindFirstChild("Map")
if not map then
    return "ERROR: Map not found — wrong Studio instance?"
end

local fixed = 0
local skipped = 0
local lines = {}

for _, desc in map:GetDescendants() do
    if not desc:IsA("MeshPart") then
        continue
    end
    local mesh = desc :: MeshPart
    -- Only touch MeshParts that (a) have a real TextureID and (b) were changed by our rollout
    if mesh.TextureID == "" or mesh.TextureID == nil then
        skipped += 1
        continue
    end
    local origMat = mesh:GetAttribute("_origMat")
    if typeof(origMat) ~= "string" or origMat == "" then
        -- No _origMat stored → wasn't touched by the rollout, skip
        skipped += 1
        continue
    end
    local ok, mat = pcall(function()
        return Enum.Material[origMat]
    end)
    if not ok or not mat then
        table.insert(lines, "WARN: unknown material '" .. origMat .. "' on " .. mesh:GetFullName())
        skipped += 1
        continue
    end
    mesh.Material = mat
    mesh:SetAttribute("_origMat", nil)  -- clear the marker so it's clean
    fixed += 1
    table.insert(lines, "FIXED: " .. mesh:GetFullName() .. " → " .. origMat)
end

table.insert(lines, string.format("\nDone: %d MeshParts reverted, %d skipped.", fixed, skipped))
return table.concat(lines, "\n")

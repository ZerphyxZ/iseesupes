--!strict

-- LowEndWorldController
--
-- Low-end-only relief valve for the <2GB Android out-of-memory crashes. The heavy fix (deleting the
-- redundant mass-stamped texture instances) shrinks the AT-JOIN replication payload; this trims the
-- ONGOING memory + GPU cost AFTER the world is up, and ONLY on devices ClientPerformance flags as
-- low-end. High-end devices are completely untouched (early return).
--
-- It runs AFTER the loading screen reveals (so it never competes with the join-time replication
-- spike) and spreads its work across frames. Reuses ClientPerformance.isLowEnd() — the same gate
-- already driving cape / Superman-VFX / steer-rate reductions; no new device detection.
--
--   * MeshPart.RenderFidelity -> Performance   lower-LOD meshes = less mesh memory. Client-only:
--                                              setting it here does NOT replicate to the server.
--   * SpotLight / SurfaceLight -> disabled     decorative fill lights; PointLights stay so the
--                                              world keeps its core illumination.
-- A throttled DescendantAdded catches obstacles / parts that clone or stream in after the sweep.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local ClientPerformance = require(ReplicatedStorage.Shared.Utils.ClientPerformance)
local StudioLog = require(ReplicatedStorage.Shared.Utils.StudioLog)

local LowEndWorldController = Knit.CreateController({ Name = "LowEndWorldController" })

-- Instances processed per frame during the initial sweep (keeps the post-reveal pass off the main
-- thread budget on weak CPUs).
local BUDGET_PER_FRAME = 250
-- Seconds to wait for the loading screen to clear before sweeping anyway (self-heal if it lingers).
local REVEAL_TIMEOUT = 25

--- Apply the low-end downgrade to one instance. Idempotent — safe to call again on the same object.
local function downgrade(inst: Instance)
	if inst:IsA("MeshPart") then
		if inst.RenderFidelity ~= Enum.RenderFidelity.Performance then
			inst.RenderFidelity = Enum.RenderFidelity.Performance
		end
	elseif inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
		if inst.Enabled then
			inst.Enabled = false
		end
	end
end

--- The ReplicatedFirst loading screen ("StreamLoadingScreen") destroys itself on reveal. Hold until
--- it is gone so our sweep never piles onto the join-time spike; bail after REVEAL_TIMEOUT regardless.
local function waitForReveal()
	local player = Players.LocalPlayer
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	local deadline = os.clock() + REVEAL_TIMEOUT
	while os.clock() < deadline do
		if not (pg and pg:FindFirstChild("StreamLoadingScreen")) then
			return
		end
		task.wait(0.25)
	end
end

--- One spread-over-frames pass over everything currently in Workspace.
local function sweep()
	local processed = 0
	for _, inst in Workspace:GetDescendants() do
		downgrade(inst)
		processed += 1
		if processed % BUDGET_PER_FRAME == 0 then
			RunService.Heartbeat:Wait()
		end
	end
end

function LowEndWorldController:KnitStart()
	if not ClientPerformance.isLowEnd() then
		return -- high-end / desktop: no-op, change nothing
	end

	task.spawn(function()
		-- Catch late arrivals (runtime-cloned obstacles, streamed parts) from here on — connected
		-- before the sweep so nothing added mid-sweep is missed; downgrade() is idempotent.
		Workspace.DescendantAdded:Connect(downgrade)

		waitForReveal()
		sweep()

		StudioLog.ready("LowEndWorldController")
	end)
end

return LowEndWorldController

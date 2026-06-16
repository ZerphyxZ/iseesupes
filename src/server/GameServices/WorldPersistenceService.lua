--!strict
-- WorldPersistenceService
--
-- Keeps gameplay-critical hub objects always-loaded on every client under
-- StreamingEnabled, so players never spawn or return into an un-streamed void
-- (the "join into empty ocean, must rejoin" bug). Set at server start, before
-- clients begin streaming, which is when ModelStreamingMode is honored.
--
-- This mirrors the same flags set directly in the place file, but as code so the
-- decision is version-controlled and survives a place rebuild — the .rbxl is not
-- in source control, so a place-only edit would otherwise be invisible/lost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)

local WorldPersistenceService = Knit.CreateService({
	Name = "WorldPersistenceService",
})

-- Hub models that should never stream out: the spawn/return area and the
-- interactable stands players touch from the lobby. Kept small on purpose —
-- the large stages still stream normally to save memory.
local PERSISTENT_MODELS = {
	"Lobby",
	"SpeedStand",
	"RebirthStand",
	"WinsStand",
	"FriendStand",
	"StarterPackStand",
	"TimeStand",
	"LikeGame",
}

-- Hub models load progressively at server start, so retry until all are found (or a
-- timeout) instead of giving up on the first pass (which left only some persisted).
local function applyPersistence()
	local done: { [string]: boolean } = {}
	local function pendingCount(): number
		local count = #PERSISTENT_MODELS
		for _, name in PERSISTENT_MODELS do
			if done[name] then
				count -= 1
			end
		end
		return count
	end

	local deadline = os.clock() + 30
	while os.clock() < deadline do
		local map = MapWorld.getMapFolder()
		if map then
			for _, name in PERSISTENT_MODELS do
				if not done[name] then
					local model = map:FindFirstChild(name) or map:FindFirstChild(name, true)
					if model and model:IsA("Model") then
						local ok = pcall(function()
							model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
						end)
						if ok then
							done[name] = true
						end
					end
				end
			end
			if pendingCount() == 0 then
				break
			end
		end
		task.wait(0.5)
	end

	local applied = #PERSISTENT_MODELS - pendingCount()
	print(string.format("[WorldPersistenceService] %d/%d hub model(s) set Persistent", applied, #PERSISTENT_MODELS))
end

function WorldPersistenceService:KnitInit()
	-- Don't block Knit startup; retry in the background until the map is ready.
	task.spawn(applyPersistence)
end

return WorldPersistenceService

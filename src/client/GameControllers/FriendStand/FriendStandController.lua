--!strict

-- Friend showcase on every Map/FriendStand model (random friend per stand, smooth look-at).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local FriendStandConfigs = require(ReplicatedStorage.Shared.Configs.FriendStandConfigs)
local FriendStandDebug = require(ReplicatedStorage.Shared.Utils.FriendStandDebug)
local FriendStandDisplay = require(ReplicatedStorage.Shared.Utils.FriendStandDisplay)
local FriendStandWorld = require(ReplicatedStorage.Shared.Utils.FriendStandWorld)

local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local FriendStandController = Knit.CreateController({ Name = "FriendStandController" })

local localPlayer = Players.LocalPlayer

type StandBinding = {
	model: Model,
	spawn: BasePart,
	displayModel: Model?,
	currentFriendId: number?,
	carouselGeneration: number,
	carouselThread: thread?,
}

local standBindings: { [Model]: StandBinding } = {}
local inviteStandModel: Model? = nil
local globalFaceConn: RBXScriptConnection? = nil
local friendListRefreshThread: thread? = nil
local standResolveThread: thread? = nil
local bindInProgress: { [Model]: boolean } = {}

local cachedFriendIds: { number } = {}
local friendListGeneration = 0

local function idsSummary(ids: { number }): string
	if #ids == 0 then
		return "(empty)"
	end
	local parts: { string } = {}
	for i = 1, math.min(5, #ids) do
		table.insert(parts, tostring(ids[i]))
	end
	if #ids > 5 then
		table.insert(parts, "...")
	end
	return table.concat(parts, ", ")
end

local function ensureFallbackFriendIds()
	if #cachedFriendIds > 0 then
		return
	end
	for _, player in Players:GetPlayers() do
		if player.UserId ~= localPlayer.UserId then
			table.insert(cachedFriendIds, player.UserId)
		end
	end
	if #cachedFriendIds == 0 then
		table.insert(cachedFriendIds, localPlayer.UserId)
	end
	FriendStandDebug.log("ensureFallbackFriendIds:", idsSummary(cachedFriendIds))
end

local function pickRandomFriendId(excludeId: number?): number?
	if #cachedFriendIds == 0 then
		ensureFallbackFriendIds()
	end
	if #cachedFriendIds == 0 then
		return nil
	end
	if #cachedFriendIds == 1 then
		return cachedFriendIds[1]
	end

	local candidate = cachedFriendIds[math.random(1, #cachedFriendIds)]
	local attempts = 0
	while candidate == excludeId and attempts < 8 do
		candidate = cachedFriendIds[math.random(1, #cachedFriendIds)]
		attempts += 1
	end
	return candidate
end

local function stopGlobalFaceLoop()
	if globalFaceConn then
		globalFaceConn:Disconnect()
		globalFaceConn = nil
	end
end

local function ensureGlobalFaceLoop()
	if globalFaceConn or not FriendStandConfigs.FaceLocalPlayer then
		return
	end

	globalFaceConn = RunService.Heartbeat:Connect(function(dt: number)
		local lookAt = FriendStandDisplay.getLocalPlayerLookTarget()
		if not lookAt then
			return
		end
		for _, binding in pairs(standBindings) do
			local model = binding.displayModel
			if model and model.Parent then
				FriendStandDisplay.updateModelFacing(model, lookAt, dt)
			end
		end
	end)
end

local function clearStandDisplay(binding: StandBinding)
	if binding.displayModel then
		FriendStandDisplay.stopRunOnModel(binding.displayModel)
		binding.displayModel = nil
	end
	local parent = FriendStandDisplay.getDisplayParent(binding.model)
	FriendStandDisplay.destroyDisplayIn(parent)
	FriendStandDisplay.destroyDisplayIn(binding.model)
	binding.currentFriendId = nil
end

function FriendStandController:ClearDisplay(stand: Model?)
	if stand then
		local binding = standBindings[stand]
		if binding then
			clearStandDisplay(binding)
		end
		return
	end
	for _, binding in pairs(standBindings) do
		clearStandDisplay(binding)
	end
end

function FriendStandController:RefreshFriendList(): boolean
	friendListGeneration += 1
	local generation = friendListGeneration

	FriendStandDebug.log("RefreshFriendList: requesting from server...")
	local FriendStandService = Knit.GetService("FriendStandService")
	local finished = false
	local success = false

	FriendStandService:GetFriendUserIds()
		:andThen(function(friendIds: { number })
			if generation ~= friendListGeneration then
				return
			end
			cachedFriendIds = friendIds
			success = #cachedFriendIds > 0
			finished = true
			FriendStandDebug.log("RefreshFriendList: got", #cachedFriendIds, "ids:", idsSummary(cachedFriendIds))
		end)
		:catch(function(err)
			FriendStandDebug.warn("RefreshFriendList failed:", err)
			finished = true
		end)

	local deadline = os.clock() + FriendStandConfigs.FriendFetchTimeout
	while not finished and os.clock() < deadline do
		task.wait()
	end

	if not finished then
		FriendStandDebug.warn("RefreshFriendList: timed out after", FriendStandConfigs.FriendFetchTimeout, "s")
	end

	if #cachedFriendIds == 0 then
		ensureFallbackFriendIds()
		success = #cachedFriendIds > 0
	end

	return success
end

function FriendStandController:ShowFriendById(stand: Model, friendId: number): boolean
	local binding = standBindings[stand]
	if not binding then
		FriendStandDebug.warn("ShowFriendById: stand not bound", stand:GetFullName())
		return false
	end

	local spawn = binding.spawn
	local generation = binding.carouselGeneration
	local displayParent = FriendStandDisplay.getDisplayParent(stand)

	clearStandDisplay(binding)

	FriendStandDebug.log("ShowFriendById:", stand.Name, "userId", friendId)

	local model = FriendStandDisplay.createFriendModel(friendId)
	if not model then
		FriendStandDebug.warn("ShowFriendById: createFriendModel failed for", friendId)
		return false
	end

	if generation ~= binding.carouselGeneration then
		model:Destroy()
		return false
	end

	model.Parent = displayParent

	if not FriendStandDisplay.waitForRigReady(model) then
		model:Destroy()
		return false
	end

	if generation ~= binding.carouselGeneration then
		model:Destroy()
		return false
	end

	local lookAt = FriendStandDisplay.getLocalPlayerLookTarget()
	if not FriendStandDisplay.prepareShowcaseModel(model, spawn, lookAt) then
		model:Destroy()
		return false
	end

	binding.displayModel = model
	binding.currentFriendId = friendId
	ensureGlobalFaceLoop()

	FriendStandDebug.log("ShowFriendById: success", stand.Name, friendId)
	return true
end

function FriendStandController:ShowNextFriend(stand: Model)
	local binding = standBindings[stand]
	if not binding then
		return
	end

	local friendId = pickRandomFriendId(binding.currentFriendId)
	if not friendId then
		FriendStandDebug.warn("ShowNextFriend: no friend id for", stand.Name)
		return
	end

	FriendStandController:ShowFriendById(stand, friendId)
end

local function stopCarouselForStand(binding: StandBinding)
	binding.carouselGeneration += 1
	if binding.carouselThread then
		task.cancel(binding.carouselThread)
		binding.carouselThread = nil
	end
end

local function startCarouselForStand(binding: StandBinding)
	stopCarouselForStand(binding)
	local generation = binding.carouselGeneration
	local stand = binding.model

	FriendStandDebug.log("startCarousel:", stand:GetFullName(), "gen", generation)

	binding.carouselThread = task.spawn(function()
		while standBindings[stand] == binding and stand.Parent and generation == binding.carouselGeneration do
			if #cachedFriendIds == 0 then
				FriendStandController:RefreshFriendList()
			end

			FriendStandController:ShowNextFriend(stand)

			local cycle = FriendStandConfigs.DisplayCycleSeconds
			if cycle <= 0 then
				break
			end
			task.wait(cycle)
		end
	end)
end

local function stopFriendListRefreshLoop()
	friendListGeneration += 1
	if friendListRefreshThread then
		task.cancel(friendListRefreshThread)
		friendListRefreshThread = nil
	end
end

local function startFriendListRefreshLoop()
	stopFriendListRefreshLoop()
	local interval = FriendStandConfigs.DisplayRefreshSeconds
	if interval <= 0 then
		return
	end

	friendListRefreshThread = task.spawn(function()
		while next(standBindings) ~= nil do
			task.wait(interval)
			if next(standBindings) ~= nil then
				FriendStandController:RefreshFriendList()
			end
		end
	end)
end

function FriendStandController:PromptInvite()
	local friendId: number? = nil
	if inviteStandModel then
		local binding = standBindings[inviteStandModel]
		if binding then
			friendId = binding.currentFriendId
		end
	end
	if not friendId then
		for _, binding in pairs(standBindings) do
			if binding.currentFriendId then
				friendId = binding.currentFriendId
				break
			end
		end
	end

	FriendStandDebug.log("PromptInvite: friendId=", friendId)
	if not friendId then
		NotificationManager.show("Add friends on Roblox to invite them!", "Info")
	end

	local ok, err = FriendStandDisplay.promptGameInvite(localPlayer, friendId)
	if not ok then
		FriendStandDebug.warn("PromptGameInvite failed:", err)
		if err == "invites_disabled" and not RunService:IsStudio() then
			NotificationManager.show("Invites are not available right now.", "Error")
		else
			NotificationManager.show("Could not open invite window.", "Error")
		end
	end
end

function FriendStandController:BindStand(model: Model): boolean
	if standBindings[model] then
		return true
	end
	if bindInProgress[model] then
		return false
	end
	bindInProgress[model] = true

	local spawn = FriendStandWorld.waitForSpawnPart(model)
	bindInProgress[model] = nil

	if not spawn then
		FriendStandDebug.warn("BindStand: CharacterSpawn missing on", model:GetFullName())
		return false
	end

	local binding: StandBinding = {
		model = model,
		spawn = spawn,
		displayModel = nil,
		currentFriendId = nil,
		carouselGeneration = 0,
		carouselThread = nil,
	}
	standBindings[model] = binding

	FriendStandDebug.log("BindStand:", model:GetFullName(), "spawn=", spawn:GetFullName())

	task.spawn(function()
		if #cachedFriendIds == 0 then
			FriendStandController:RefreshFriendList()
		else
			ensureFallbackFriendIds()
		end

		if next(standBindings) ~= nil and not friendListRefreshThread then
			startFriendListRefreshLoop()
		end

		local friendId = pickRandomFriendId(nil)
		if friendId then
			FriendStandController:ShowFriendById(model, friendId)
		end
		startCarouselForStand(binding)
	end)

	return true
end

function FriendStandController:UnbindStand(model: Model)
	local binding = standBindings[model]
	if not binding then
		return
	end

	FriendStandDebug.log("UnbindStand:", model:GetFullName())
	stopCarouselForStand(binding)
	clearStandDisplay(binding)
	standBindings[model] = nil

	if next(standBindings) == nil then
		stopFriendListRefreshLoop()
		stopGlobalFaceLoop()
	end
end

local function tryBindAllStands(): number
	local models = FriendStandWorld.collectAllStandModels()
	local bound = 0
	for _, model in models do
		if FriendStandController:BindStand(model) then
			bound += 1
		end
	end
	return bound
end

local function startStandResolveLoop()
	if standResolveThread then
		return
	end
	FriendStandDebug.log("startStandResolveLoop: polling for FriendStand models...")
	standResolveThread = task.spawn(function()
		local deadline = os.clock() + FriendStandConfigs.StandResolveTimeout
		while os.clock() < deadline do
			if tryBindAllStands() > 0 then
				break
			end
			task.wait(1)
		end
		standResolveThread = nil
		if next(standBindings) == nil then
			FriendStandDebug.warn("no FriendStand models bound after", FriendStandConfigs.StandResolveTimeout, "s")
		end
	end)
end

function FriendStandController:KnitStart()
	FriendStandDebug.log("KnitStart: client controller running")

	local FriendStandService = Knit.GetService("FriendStandService")

	FriendStandService.OpenInvitePrompt:Connect(function(touchedStand: Instance?)
		if touchedStand and touchedStand:IsA("Model") then
			inviteStandModel = touchedStand
		end
		FriendStandController:PromptInvite()
	end)

	FriendStandService.FriendInviteRewarded:Connect(function(_joinedUserId: number, newCount: number, speedGranted: number)
		local maxFriends = FriendStandConfigs.MaxInvitedFriends
		NotificationManager.show(
			string.format("Friend joined! +%d Speed (%d/%d)", speedGranted, newCount, maxFriends),
			"Success"
		)
		if newCount >= maxFriends then
			NotificationManager.show("You invited the maximum number of friends!", "Info")
		end
		FriendStandController:RefreshFriendList()
		for stand, _binding in pairs(standBindings) do
			FriendStandController:ShowNextFriend(stand)
		end
	end)

	task.defer(function()
		if tryBindAllStands() == 0 then
			startStandResolveLoop()
		end
	end)

	local standName = FriendStandConfigs.StandModelName
	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("Model") and desc.Name == standName then
			local mapFolder = FriendStandWorld.getMapFolder()
			if mapFolder and desc:IsDescendantOf(mapFolder) then
				FriendStandDebug.log("DescendantAdded: FriendStand →", desc:GetFullName())
				task.defer(function()
					FriendStandController:BindStand(desc)
				end)
			end
		end
	end)
end

return FriendStandController

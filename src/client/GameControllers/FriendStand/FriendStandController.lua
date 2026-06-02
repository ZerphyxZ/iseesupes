--!strict

-- Local friend showcase on FriendStand (run anim carousel) + invite prompt on server touch.

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

local standModel: Model? = nil
local characterSpawn: BasePart? = nil
local carouselThread: thread? = nil
local friendListRefreshThread: thread? = nil
local standResolveThread: thread? = nil
local standPartsConn: RBXScriptConnection? = nil
local faceUpdateThread: thread? = nil
local displayModel: Model? = nil
local bindInProgress = false

local cachedFriendIds: { number } = {}
local currentDisplayFriendId: number? = nil
local carouselGeneration = 0
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

local function pickNextFriendId(ids: { number }): number?
	if #ids == 0 then
		return nil
	end
	if #ids == 1 then
		return ids[1]
	end

	local current = currentDisplayFriendId
	local candidate = ids[math.random(1, #ids)]
	local attempts = 0
	while candidate == current and attempts < 8 do
		candidate = ids[math.random(1, #ids)]
		attempts += 1
	end
	return candidate
end

local function stopFaceUpdateLoop()
	if faceUpdateThread then
		task.cancel(faceUpdateThread)
		faceUpdateThread = nil
	end
	displayModel = nil
end

local function startFaceUpdateLoop(model: Model, spawn: BasePart)
	stopFaceUpdateLoop()
	if not FriendStandConfigs.FaceLocalPlayer then
		return
	end

	displayModel = model
	local generation = carouselGeneration

	faceUpdateThread = task.spawn(function()
		local interval = FriendStandConfigs.FaceUpdateInterval
		while displayModel == model and model.Parent and generation == carouselGeneration do
			local lookAt = FriendStandDisplay.getLocalPlayerLookTarget()
			if lookAt then
				FriendStandDisplay.alignModelFacing(model, spawn, lookAt)
			end
			task.wait(interval)
		end
	end)
end

function FriendStandController:ClearDisplay()
	stopFaceUpdateLoop()
	if standModel then
		local parent = FriendStandDisplay.getDisplayParent(standModel)
		FriendStandDisplay.destroyDisplayIn(parent)
	end
	if standModel then
		FriendStandDisplay.destroyDisplayIn(standModel)
	end
	currentDisplayFriendId = nil
	FriendStandDebug.log("ClearDisplay")
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

function FriendStandController:ShowFriendById(friendId: number): boolean
	local spawn = characterSpawn
	local stand = standModel
	if not spawn or not stand then
		FriendStandDebug.warn("ShowFriendById: no spawn/stand")
		return false
	end

	local generation = carouselGeneration
	local displayParent = FriendStandDisplay.getDisplayParent(stand)

	FriendStandDisplay.destroyDisplayIn(displayParent)
	FriendStandDisplay.destroyDisplayIn(stand)

	FriendStandDebug.log("ShowFriendById: loading userId", friendId)

	local model = FriendStandDisplay.createFriendModel(friendId)
	if not model then
		FriendStandDebug.warn("ShowFriendById: createFriendModel failed for", friendId)
		return false
	end

	if generation ~= carouselGeneration then
		model:Destroy()
		FriendStandDebug.log("ShowFriendById: cancelled (generation)")
		return false
	end

	model.Parent = displayParent
	FriendStandDebug.log("ShowFriendById: parented to", displayParent:GetFullName())

	if not FriendStandDisplay.waitForRigReady(model) then
		FriendStandDebug.warn("ShowFriendById: rig not ready for", friendId)
		model:Destroy()
		return false
	end

	if generation ~= carouselGeneration then
		model:Destroy()
		return false
	end

	local lookAt = FriendStandDisplay.getLocalPlayerLookTarget()
	if not FriendStandDisplay.prepareShowcaseModel(model, spawn, lookAt) then
		FriendStandDebug.warn("ShowFriendById: prepareShowcaseModel failed")
		model:Destroy()
		return false
	end

	startFaceUpdateLoop(model, spawn)

	currentDisplayFriendId = friendId
	FriendStandDebug.log("ShowFriendById: success userId", friendId, "facing player, run anim on")
	return true
end

function FriendStandController:ShowNextFriend()
	if #cachedFriendIds == 0 then
		ensureFallbackFriendIds()
	end
	if #cachedFriendIds == 0 then
		FriendStandDebug.warn("ShowNextFriend: still no friend ids")
		return
	end

	local friendId = pickNextFriendId(cachedFriendIds)
	if not friendId then
		FriendStandDebug.warn("ShowNextFriend: pickNextFriendId returned nil")
		return
	end

	FriendStandDebug.log("ShowNextFriend: picked", friendId)
	local ok = FriendStandController:ShowFriendById(friendId)
	if not ok then
		FriendStandDebug.warn("ShowNextFriend: ShowFriendById failed for", friendId)
	end
end

local function stopCarouselLoop()
	carouselGeneration += 1
	if carouselThread then
		task.cancel(carouselThread)
		carouselThread = nil
	end
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
		while standModel and standModel.Parent do
			task.wait(interval)
			if standModel and standModel.Parent then
				FriendStandController:RefreshFriendList()
			end
		end
	end)
end

local function startCarouselLoop()
	stopCarouselLoop()
	local generation = carouselGeneration

	FriendStandDebug.log("startCarouselLoop: generation", generation)

	carouselThread = task.spawn(function()
		while standModel and standModel.Parent and generation == carouselGeneration do
			if #cachedFriendIds == 0 then
				FriendStandController:RefreshFriendList()
			end

			FriendStandController:ShowNextFriend()

			local cycle = FriendStandConfigs.DisplayCycleSeconds
			if cycle <= 0 then
				break
			end
			task.wait(cycle)
		end
		FriendStandDebug.log("startCarouselLoop: ended generation", generation)
	end)
end

function FriendStandController:PromptInvite()
	local friendId = currentDisplayFriendId
	FriendStandDebug.log("PromptInvite: currentDisplayFriendId=", friendId)
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

local function disconnectStandPartsWatcher()
	if standPartsConn then
		standPartsConn:Disconnect()
		standPartsConn = nil
	end
end

function FriendStandController:BindStand(model: Model): boolean
	if standModel == model and characterSpawn then
		FriendStandDebug.log("BindStand: already bound")
		return true
	end

	if bindInProgress then
		return false
	end
	bindInProgress = true

	local spawn = FriendStandWorld.waitForSpawnPart(model)
	bindInProgress = false

	if not spawn then
		FriendStandDebug.warn("BindStand: CharacterSpawn never appeared on", model:GetFullName())
		return false
	end

	disconnectStandPartsWatcher()

	if standModel == model and characterSpawn == spawn then
		return true
	end

	FriendStandController:UnbindStand()

	standModel = model
	characterSpawn = spawn

	FriendStandDebug.log(
		"BindStand:",
		model:GetFullName(),
		"spawn=",
		spawn:GetFullName(),
		"spawnPos=",
		tostring(spawn.Position)
	)

	task.spawn(function()
		local listOk = FriendStandController:RefreshFriendList()
		FriendStandDebug.log("BindStand: RefreshFriendList ok=", listOk, "count=", #cachedFriendIds)
		startFriendListRefreshLoop()
		startCarouselLoop()
	end)

	return true
end

local function watchStandPartsUntilBound(model: Model)
	disconnectStandPartsWatcher()
	standPartsConn = model.DescendantAdded:Connect(function(desc)
		if standModel and characterSpawn then
			return
		end
		if desc:IsA("BasePart") then
			for _, alias in FriendStandConfigs.CharacterSpawnPartAliases do
				if desc.Name == alias then
					FriendStandDebug.log("watchStandParts: spawn part added →", desc:GetFullName())
					task.defer(function()
						FriendStandController:BindStand(model)
					end)
					return
				end
			end
		end
	end)
end

function FriendStandController:UnbindStand()
	FriendStandDebug.log("UnbindStand")
	disconnectStandPartsWatcher()
	stopCarouselLoop()
	stopFriendListRefreshLoop()
	FriendStandController:ClearDisplay()
	table.clear(cachedFriendIds)
	standModel = nil
	characterSpawn = nil
end

local function tryBindStand(): boolean
	local model = FriendStandWorld.resolveStandModel()
	if not model then
		if standModel then
			FriendStandController:UnbindStand()
		end
		return false
	end

	watchStandPartsUntilBound(model)

	if FriendStandController:BindStand(model) then
		return true
	end

	-- Model exists but parts still streaming; DescendantAdded + resolve loop will retry.
	return false
end

local function startStandResolveLoop()
	if standResolveThread then
		return
	end
	FriendStandDebug.log("startStandResolveLoop: polling for FriendStand...")
	standResolveThread = task.spawn(function()
		local deadline = os.clock() + FriendStandConfigs.StandResolveTimeout
		while os.clock() < deadline do
			if tryBindStand() then
				break
			end
			task.wait(1)
		end
		standResolveThread = nil
		if not standModel then
			FriendStandDebug.warn("could not find FriendStand after", FriendStandConfigs.StandResolveTimeout, "s")
		end
	end)
end

function FriendStandController:KnitStart()
	FriendStandDebug.log("KnitStart: client controller running")

	local FriendStandService = Knit.GetService("FriendStandService")

	FriendStandService.OpenInvitePrompt:Connect(function()
		FriendStandDebug.log("OpenInvitePrompt signal")
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
		FriendStandController:ShowNextFriend()
	end)

	task.defer(function()
		if not tryBindStand() then
			startStandResolveLoop()
		end
	end)

	Workspace.DescendantAdded:Connect(function(desc)
		if standModel then
			return
		end
		if desc:IsA("Model") and desc.Name == FriendStandConfigs.RootPath[#FriendStandConfigs.RootPath] then
			FriendStandDebug.log("DescendantAdded: FriendStand model appeared")
			task.defer(tryBindStand)
		end
	end)
end

return FriendStandController

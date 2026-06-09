--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Packages.Knit)
local AvatarReplace = require(ReplicatedStorage.Shared.Utils.AvatarReplace)
local DataLib = require(ReplicatedStorage.Shared.Utils.DataLib)
local MapWorld = require(ReplicatedStorage.Shared.Utils.MapWorld)
local UpgradeWinsConfigs = require(ReplicatedStorage.Shared.Configs.UpgradeWinsConfigs)
local CapeVfx = require(script.Parent.Parent.Parent.Modules.CapeVfx)
local NotificationManager = require(script.Parent.Parent.Parent.Modules.NotificationManager)

local UpgradeWinsController = Knit.CreateController({ Name = "UpgradeWinsController" })

-- Cache the original "X Wins Required" text per WinCost label so we can restore it
-- if the player loses the avatar (e.g. /devresetdata in Studio).
local originalCostText: { [TextLabel]: string } = {}

--- Walk the UpgradeWins folder, find the WinCost label on each button, and update
--- its text based on whether the local player owns that avatar. Client-side text
--- writes don't replicate, so each player sees only their own ownership state.
local function refreshOwnedLabels()
	local folder = MapWorld.findChildInMap(UpgradeWinsConfigs.FolderName)
	if not folder then
		return
	end

	local data = DataLib.GetData()
	local owned: { [string]: boolean } = {}
	if data and type(data.UnlockedAvatars) == "table" then
		for id, isOwned in data.UnlockedAvatars do
			if isOwned then
				owned[tostring(id)] = true
			end
		end
	end

	local prefix = UpgradeWinsConfigs.ButtonNamePrefix
	local labelName = UpgradeWinsConfigs.WinCostLabelName
	local lockedText = "LOCKED"

	for _, button in folder:GetChildren() do
		if not button:IsA("Model") then continue end

		local buttonIndex = AvatarReplace.getButtonIndex(button)
		local avatarId: string? = nil
		local attr = button:GetAttribute(UpgradeWinsConfigs.AvatarIdAttribute)
		if typeof(attr) == "number" and attr > 0 then
			avatarId = tostring(math.floor(attr))
		elseif buttonIndex then
			avatarId = tostring(buttonIndex)
		else
			local indexStr = string.match(button.Name, "^" .. prefix .. "(%d+)$")
			if indexStr then
				avatarId = indexStr
			end
		end
		if not avatarId then continue end

		local prerequisiteLocked = buttonIndex
			and not UpgradeWinsConfigs.isPrerequisiteUnlocked(buttonIndex, owned)
		local touch = button:FindFirstChild(UpgradeWinsConfigs.TouchPartName)
		local searchRoot = if touch then touch else button
		local winLabel: TextLabel? = nil
		for _, desc in searchRoot:GetDescendants() do
			if desc:IsA("TextLabel") and desc.Name == labelName then
				winLabel = desc :: TextLabel
				break
			end
		end
		if not winLabel then continue end

		-- Cache the original text so we can restore it if the player later loses ownership
		if not originalCostText[winLabel] then
			local cached = winLabel.Text
			if cached ~= "OWNED" and cached ~= lockedText then
				originalCostText[winLabel] = cached
			end
		end

		if owned[avatarId] then
			winLabel.Text = "OWNED"
		elseif prerequisiteLocked then
			winLabel.Text = lockedText
		else
			winLabel.Text = originalCostText[winLabel] or winLabel.Text
		end
	end
end

local function resetSteerAfterMorph()
	local ok, doubleJump = pcall(function()
		return Knit.GetController("DoubleJumpController")
	end)
	if ok and doubleJump and doubleJump.resetSteerTrackingAfterMorph then
		doubleJump:resetSteerTrackingAfterMorph()
	end
end

local function snapCameraAfterMorph()
	-- Triple snap covers every timing edge case (DjAbilityPhase clearing, humanoid not
	-- yet ready, character physics settling). Each call is cheap.
	task.spawn(AvatarReplace.waitAndSnapLocalCamera, 4)
	task.delay(0.3, function()
		task.spawn(AvatarReplace.waitAndSnapLocalCamera, 4)
	end)
	task.delay(1.0, function()
		task.spawn(AvatarReplace.waitAndSnapLocalCamera, 2)
	end)
end

function UpgradeWinsController:KnitStart()
	local UpgradeWinsService = Knit.GetService("UpgradeWinsService")
	local player = Players.LocalPlayer

	-- Full character swap fires CharacterAdded; refresh camera + cape rig here.
	player.CharacterAdded:Connect(function(character)
		resetSteerAfterMorph()
		snapCameraAfterMorph()
		task.defer(function()
			CapeVfx.refreshAfterShowcaseEquip(character)
		end)
	end)

	-- Refresh "OWNED" labels whenever data replicates (catches initial join, every
	-- unlock, rebirth/reset, and rejoins). First call is deferred so the map and
	-- profile data have time to load.
	DataLib.OnChanged(function()
		refreshOwnedLabels()
	end)
	task.delay(2, refreshOwnedLabels)
	-- Also retry a few times in case the UpgradeWins folder isn't loaded yet on first join.
	task.spawn(function()
		for _ = 1, 10 do
			task.wait(1)
			refreshOwnedLabels()
		end
	end)

	UpgradeWinsService.UpgradeResult:Connect(function(kind: string, avatarId: string)
		if kind == "Unlocked" or kind == "Equipped" then
			resetSteerAfterMorph()
			-- Full character swap also fires CharacterAdded (handled above).
			-- This block is redundant safety for any edge case where the swap doesn't fire it.
			local character = player.Character
			if character then
				task.defer(function()
					CapeVfx.refreshAfterShowcaseEquip(character)
				end)
			end
		end

		if kind == "Unlocked" or kind == "Equipped" then
			-- Flip the label to "OWNED" instantly (won't wait for next data replicate)
			task.defer(refreshOwnedLabels)
		end

		if kind == "Unlocked" then
			NotificationManager.show("Avatar " .. avatarId .. " unlocked!", "Success")
		elseif kind == "Equipped" then
			NotificationManager.show("Equipped avatar " .. avatarId, "Success")
		elseif kind == "NotEnoughWins" then
			NotificationManager.show("Not enough wins!", "Error")
		elseif kind == "PrerequisiteLocked" then
			NotificationManager.show("Unlock the previous avatar first!", "Info")
		elseif kind == "AvatarMissing" then
			NotificationManager.show("Avatar model not found in showcase.", "Error")
		elseif kind == "InvalidButton" then
			NotificationManager.show("Upgrade button is not configured.", "Error")
		end
	end)

	print("[iseesupes] UpgradeWinsController ready.")
end

return UpgradeWinsController

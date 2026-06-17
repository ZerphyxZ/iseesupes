-- Verifies login-reward code + documents Studio publish checklist.
-- Run: lune run scripts/verify-login-reward-deploy.luau (from repo root)

local fs = require("@lune/fs")

local requiredFiles = {
	"src/shared/Configs/LoginRewardConfigs.lua",
	"src/server/GameServices/LoginRewardService.lua",
	"src/client/GameControllers/LoginReward/LoginRewardController.lua",
	"src/shared/Utils/ProfileTemplate.lua",
	"scripts/build-login-ui.luau",
}

local missing = {}
for _, path in requiredFiles do
	if not fs.isFile(path) then
		table.insert(missing, path)
	end
end

if #missing > 0 then
	error("Missing login-reward files:\n  " .. table.concat(missing, "\n  "))
end

print("OK  All login-reward source files present.")

local cfg = fs.readFile("src/shared/Configs/LoginRewardConfigs.lua")
local requiredKeys = {
	"DayBoundaryUtcOffsetSeconds",
	"HudButtonPath",
	"StreakDays",
	"DailyStreak",
	"OfflineReward",
}
for _, key in requiredKeys do
	if not string.find(cfg, key, 1, true) then
		error("LoginRewardConfigs.lua missing key: " .. key)
	end
end
print("OK  LoginRewardConfigs contains required keys.")

print("")
print("Studio / live publish checklist:")
print("  1. Run scripts/build-login-ui.luau in Studio (creates GUI.Frames.DailyStreak + OfflineReward).")
print("  2. Confirm StarterGui.GUI.HUD.Left exists (HUD gift button is code-built if DailyStreak missing).")
print("  3. Sync Rojo so LoginRewardService + LoginRewardController are in the published place.")
print("  4. Publish the place after merging these changes.")
print("  5. Test: claim Day 1, wait until streak day rolls over (US Eastern by default), rejoin → Day 2 popup.")

--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormatter = require(ReplicatedStorage.Shared.Utils.NumberFormatter)
local TimeFormat = require(ReplicatedStorage.Shared.Utils.TimeFormat)

export type LeaderboardConfig = {
	StoreName: string,
	ModelName: string,
	ProfileKey: string,
	GetScore: (data: any) -> number?,
	ScoreFormatter: (score: number) -> string,
}

local LeaderboardConfigs = {}

--- When false, first join per DATA_VERSION does not import OrderedDataStore scores into the profile (test wipes).
LeaderboardConfigs.RestoreFromOdsOnJoin = false

LeaderboardConfigs.RefreshInterval = 60
LeaderboardConfigs.SaveInterval = 60
LeaderboardConfigs.TopN = 50
LeaderboardConfigs.RootPath = { "Map", "Leaderboards" }
LeaderboardConfigs.EntryTemplateName = "LeaderboardEntry"
LeaderboardConfigs.TemplatePath = { "Templates", "LeaderboardEntry" }

local function profileInt(data: any, key: string): number?
	if not data then
		return nil
	end
	local v = data[key]
	if type(v) == "number" then
		return math.floor(v)
	end
	return nil
end

LeaderboardConfigs.Boards = {
	Speed = {
		StoreName = "GlobalSpeed_v2",
		ModelName = "SpeedLeaderboard",
		ProfileKey = "Speed",
		GetScore = function(data)
			return profileInt(data, "Speed")
		end,
		ScoreFormatter = function(score)
			return NumberFormatter.Format(score) .. " Speed"
		end,
	} :: LeaderboardConfig,
	Wins = {
		StoreName = "GlobalWins_v2",
		ModelName = "WinsLeaderboard",
		ProfileKey = "Wins",
		GetScore = function(data)
			return profileInt(data, "Wins")
		end,
		ScoreFormatter = function(score)
			return NumberFormatter.Format(score) .. " Wins"
		end,
	} :: LeaderboardConfig,
	Rebirths = {
		StoreName = "GlobalRebirths_v2",
		ModelName = "RebirthLeaderboard",
		ProfileKey = "Rebirths",
		GetScore = function(data)
			return profileInt(data, "Rebirths")
		end,
		ScoreFormatter = function(score)
			return NumberFormatter.Format(score) .. " Rebirths"
		end,
	} :: LeaderboardConfig,
	Time = {
		StoreName = "GlobalPlayTime_v2",
		ModelName = "TimeLeaderboard",
		ProfileKey = "TotalPlayTime",
		GetScore = function(data)
			return profileInt(data, "TotalPlayTime")
		end,
		ScoreFormatter = function(score)
			return TimeFormat.formatPlayTime(score)
		end,
	} :: LeaderboardConfig,
	MaxStage = {
		StoreName = "GlobalMaxStage_v2",
		ModelName = "StageLeaderboard",
		ProfileKey = "MaxStage",
		GetScore = function(data)
			return profileInt(data, "MaxStage")
		end,
		ScoreFormatter = function(score)
			return "Stage " .. tostring(score)
		end,
	} :: LeaderboardConfig,
}

return LeaderboardConfigs

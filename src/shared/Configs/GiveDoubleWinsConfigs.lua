--!strict

-- Workspace.Map.GiveDounleWins (Button1 … Button9) — touch → buy permanent 2x wins.

export type GiveDoubleWinsConfig = {
	--- Studio folder name(s); first match under Map wins.
	FolderNames: { string },
	TouchPartName: string,
	WinAmountLabelName: string,
	WinAmountAttribute: string,
	ProductKey: string,
	DisplayName: string,
	TouchDebounce: number,
	--- Wins granted on purchase when button amount unknown (grant = DefaultGrantWins * 2).
	DefaultGrantWins: number,
}

local GiveDoubleWinsConfigs: GiveDoubleWinsConfig = {
	FolderNames = { "GiveDounleWins", "GiveDoubleWins" },
	TouchPartName = "Touch",
	WinAmountLabelName = "WinAmount",
	WinAmountAttribute = "WinAmount",
	ProductKey = "DoubleWins",
	DisplayName = "2x Wins",
	TouchDebounce = 1.5,
	DefaultGrantWins = 1,
}

return GiveDoubleWinsConfigs

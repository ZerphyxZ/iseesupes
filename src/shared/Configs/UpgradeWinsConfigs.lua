--!strict

-- Workspace/Map/UpgradeWins buttons + Workspace/Map/AvatarsShowcase character templates.

export type ButtonDefaults = {
	WinCost: number,
	StepBonus: number,
}

export type UpgradeWinsConfig = {
	-- When morphing (buttons 1–12), copy Humanoid movement from the character you had
	-- (only used on full character swap).
	MorphCopyPhysicsFromCurrentCharacter: boolean,
	-- All 12 showcase buttons only swap colors on the live character (never player.Character = clone).
	-- Keeps StarterPlayer / spawn physics and network ownership for every avatar.
	UseVisualOnlyShowcaseEquip: boolean,
	-- If false, only skip clone when rig signatures match (see ShowcaseRigIdAttribute).
	UseVisualOnlyMorphWhenRigMatches: boolean,
	ShowcaseRigIdAttribute: string,
	DefaultShowcaseRigId: string,
	-- Off by default: MeshPart rigs use per-part colors; BodyColors can double-tint on morph.
	ApplyBodyColorsOnVisualMorph: boolean,
	FolderName: string,
	ShowcaseFolderName: string,
	TouchPartName: string,
	WinCostLabelName: string,
	AddonLabelName: string,
	WinCostAttribute: string,
	StepBonusAttribute: string,
	AddonTextAttribute: string,
	AvatarIdAttribute: string,
	TouchDebounce: number,
	ButtonNamePrefix: string,
	DefaultButtons: { [number]: ButtonDefaults },
}

local UpgradeWinsConfigs: UpgradeWinsConfig = {
	MorphCopyPhysicsFromCurrentCharacter = true,
	-- Visual-only equip can only paint colors/textures — it CANNOT change MeshPart shape
	-- (MeshId is read-only in Roblox). The Superman showcase models have custom meshes,
	-- so we must do a full character replacement for the morph to actually transform.
	UseVisualOnlyShowcaseEquip = false,
	UseVisualOnlyMorphWhenRigMatches = false,
	ShowcaseRigIdAttribute = "ShowcaseRigId",
	DefaultShowcaseRigId = "Supes",
	ApplyBodyColorsOnVisualMorph = false,
	FolderName = "UpgradeWins",
	ShowcaseFolderName = "AvatarsShowcase",
	TouchPartName = "Touch",
	WinCostLabelName = "WinCost",
	AddonLabelName = "Addon",
	WinCostAttribute = "WinCost",
	StepBonusAttribute = "StepBonus",
	AddonTextAttribute = "AddonText",
	AvatarIdAttribute = "AvatarId",
	TouchDebounce = 1.5,
	ButtonNamePrefix = "Button",
	DefaultButtons = {
		[1] = { WinCost = 3, StepBonus = 1 },
		[2] = { WinCost = 5, StepBonus = 2 },
		[3] = { WinCost = 15, StepBonus = 5 },
		[4] = { WinCost = 50, StepBonus = 10 },
		[5] = { WinCost = 150, StepBonus = 25 },
		[6] = { WinCost = 500, StepBonus = 50 },
		[7] = { WinCost = 1000, StepBonus = 100 },
		[8] = { WinCost = 2500, StepBonus = 250 },
		[9] = { WinCost = 5000, StepBonus = 500 },
		[10] = { WinCost = 10000, StepBonus = 1000 },
		[11] = { WinCost = 25000, StepBonus = 2500 },
		[12] = { WinCost = 50000, StepBonus = 5000 },
	},
}

function UpgradeWinsConfigs.getDefaults(buttonIndex: number): ButtonDefaults?
	return UpgradeWinsConfigs.DefaultButtons[buttonIndex]
end

return UpgradeWinsConfigs

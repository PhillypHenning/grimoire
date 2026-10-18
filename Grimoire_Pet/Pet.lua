local ADDON_NAME = ...
local Grimoire = Grimoire

-- Your pet's frame and bars, a size smaller than the player's, built on core's unit
-- frames (Core/UnitFrames.lua). They show only while you have a pet, and always in
-- move mode so they can be placed. Blizzard's pet frame is hidden (ADR 0004).
--   Left-click   target the pet
--   Right-click  Blizzard's pet menu (rename, dismiss, ...)

local PetFrame = Grimoire:NewUnitPortrait("PetFrame", {
	addon = ADDON_NAME,
	label = "Pet frame",
	unit = "pet",
	size = 48,
	nameFont = "GameFontNormalSmall",
	blizzardFrame = "PetFrame",
	blizzardDropDown = "PetFrameDropDown",
	blizzardLabel = "pet frame",
	clickHelp = { "Left-click: target", "Right-click: pet options" },
	mirror = true,
	-- Under the player frame, left of the pet bars.
	defaultPosition = { "TOPRIGHT", "UIParent", "CENTER", -118, -250 },
	options = {
		Grimoire.UnitPortraitStyleOption(),
		{ type = "choice", key = "size", label = "Size", tooltip = "How large the pet frame is.", values = { { 36, "Small" }, { 48, "Medium" }, { 64, "Large" } } },
		{ type = "toggle", key = "showName", label = "Show name", tooltip = "Show your pet's name above its frame." },
		{ type = "toggle", key = "showText", label = "Show values on bar", tooltip = "Portrait bar style: show your pet's health as a number and percentage." },
		{ type = "toggle", key = "hideBlizzard", label = "Hide Blizzard pet frame", tooltip = "Hide the game's own pet frame; Grimoire's replaces it.", reload = true },
	},
})

function PetFrame:BuildExtras()
	self.frame:SetAttribute("type1", "target")
end

function PetFrame:RegisterUnitEvents()
	self:RegisterUnitEvent("UNIT_PET", "player", "UpdateAll")
end

Grimoire:NewUnitBar("PetHealth", {
	addon = ADDON_NAME,
	label = "Pet health",
	kind = "health",
	unit = "pet",
	portrait = "PetFrame",
	defaults = { width = 150, height = 12, showText = true },
	defaultPosition = { "TOPLEFT", "UIParent", "CENTER", -114, -250 },
	widths = { 120, 150, 180, 220 },
	heights = { 8, 10, 12, 16 },
})

Grimoire:NewUnitBar("PetPower", {
	addon = ADDON_NAME,
	label = "Pet power",
	kind = "power",
	unit = "pet",
	portrait = "PetFrame",
	defaults = { width = 150, height = 8, showText = false, manaColor = { r = 0, g = 0, b = 1 } },
	defaultPosition = { "TOPLEFT", "UIParent", "CENTER", -114, -270 },
	widths = { 120, 150, 180, 220 },
	heights = { 6, 8, 10, 12 },
})

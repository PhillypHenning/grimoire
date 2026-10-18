local ADDON_NAME = ...
local Grimoire = Grimoire

-- Player health and power bars, built on core's unit bars (Core/UnitFrames.lua). Each
-- is its own module and its own mover, so they can be moved, grouped, dimmed and
-- toggled separately.

Grimoire:NewUnitBar("Health", {
	addon = ADDON_NAME,
	label = HEALTH or "Health",
	kind = "health",
	unit = "player",
	portrait = "PlayerFrame",
	defaults = { width = 220, height = 16, showText = true },
	defaultPosition = { "CENTER", "UIParent", "CENTER", 0, -180 },
	widths = { 180, 220, 260, 300 },
	heights = { 12, 16, 20, 24 },
})

Grimoire:NewUnitBar("Power", {
	addon = ADDON_NAME,
	label = "Power (mana)",
	kind = "power",
	unit = "player",
	portrait = "PlayerFrame",
	defaults = { width = 220, height = 12, showText = true, manaColor = { r = 0, g = 0, b = 1 } }, -- classic mana blue
	defaultPosition = { "CENTER", "UIParent", "CENTER", 0, -204 },
	widths = { 180, 220, 260, 300 },
	heights = { 8, 10, 12, 16 },
})

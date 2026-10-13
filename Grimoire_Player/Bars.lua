local ADDON_NAME = ...
local Grimoire = Grimoire

-- Health and power bars for the player and the pet. Each bar is its own module and
-- its own mover, so they can be moved, grouped, dimmed and toggled separately.
-- Pet bars hide while there's no pet, except in move mode so they can be placed.

local HEALTH_COLOR = { r = 0, g = 1, b = 0 } -- classic player frame green

local Bar = {}

function Bar:Build()
	local inset = Grimoire.media.classicInset
	local frame = CreateFrame("Frame", "Grimoire" .. self.name .. "Bar", UIParent, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(frame)

	local bar = CreateFrame("StatusBar", nil, frame)
	bar:SetPoint("TOPLEFT", inset, -inset)
	bar:SetPoint("BOTTOMRIGHT", -inset, inset)
	bar:SetStatusBarTexture(Grimoire.media.statusbar)
	bar.text = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	bar.text:SetPoint("CENTER")

	self.frame, self.bar = frame, bar
	self:ApplySize()
	self:UpdateColor()
	self:RegisterMover(frame, self:GetLabel(), self.defaultPosition, {
		dim = true,
		isBusy = function() return self:IsBusy() end,
	})
end

-- A bar never dims in combat or while it isn't full (secret values count as busy).
function Bar:IsBusy()
	if not UnitExists(self.unit) then
		return false
	end
	if Grimoire:InCombat() or not self.lastCurrent then
		return true
	end
	return self.lastCurrent < self.lastMax
end

function Bar:ApplySize()
	local inset = Grimoire.media.classicInset
	self.frame:SetSize(self.db.width + inset * 2, self.db.height + inset * 2)
end

function Bar:ApplySettings()
	self:ApplySize()
	self.lastCurrent = nil -- redraw the text even if the value hasn't changed
	self:Update()
end

function Bar:UpdateColor()
	local color = self:GetColor()
	self.bar:SetStatusBarColor(color.r, color.g, color.b)
end

function Bar:SetValues(current, max)
	-- StatusBar accepts secret values directly.
	local bar = self.bar
	bar:SetMinMaxValues(0, max)
	bar:SetValue(current)

	local secret = Grimoire.AnySecret(current, max)
	if not self.db.showText then
		bar.text:SetText("")
	elseif secret then
		-- Can't divide secrets into a percentage; let the widget render the raw value.
		bar.text:SetText(current)
	else
		bar.text:SetFormattedText("%d%%", max > 0 and math.floor(current / max * 100) or 0)
	end

	-- Secrets can't be compared, so a secret update always counts as a change.
	if secret then
		self.lastCurrent, self.lastMax = nil, nil
		Grimoire:NotifyMoverActivity(self.name)
	elseif current ~= self.lastCurrent or max ~= self.lastMax then
		self.lastCurrent, self.lastMax = current, max
		Grimoire:NotifyMoverActivity(self.name)
	end
end

-- Shown while the unit exists, and always in move mode.
function Bar:UpdateVisibility()
	self.frame:SetShown(UnitExists(self.unit) or Grimoire.moversUnlocked)
end

-- The pet was summoned, dismissed or swapped.
function Bar:OnUnitChanged()
	self:UpdateVisibility()
	self:UpdateColor()
	self.lastCurrent = nil
	self:Update()
end

function Bar:OnEnable()
	if not self.frame then
		self:Build()
	end
	self:UpdateVisibility()
	self:RegisterBarEvents()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnUnitChanged")
	if self.unit == "pet" then
		self:RegisterUnitEvent("UNIT_PET", "player", "OnUnitChanged")
		self:RegisterCallback("MoversUnlocked", "UpdateVisibility")
		self:RegisterCallback("MoversLocked", "UpdateVisibility")
	end
	self:Update()
end

function Bar:OnDisable()
	self.frame:Hide()
end

-- Health -------------------------------------------------------------------------------

local Health = {}

function Health:GetLabel()
	return self.label
end

function Health:GetColor()
	return HEALTH_COLOR
end

function Health:RegisterBarEvents()
	self:RegisterUnitEvent("UNIT_HEALTH", self.unit, "Update")
	self:RegisterUnitEvent("UNIT_HEALTH_FREQUENT", self.unit, "Update")
	self:RegisterUnitEvent("UNIT_MAXHEALTH", self.unit, "Update")
end

function Health:Update()
	if not UnitExists(self.unit) then return end
	self:SetValues(UnitHealth(self.unit), UnitHealthMax(self.unit))
end

-- Power (mana, rage, energy, focus) --------------------------------------------------------

local Power = {}

function Power:GetLabel()
	local _, token = UnitPowerType(self.unit)
	if self.unit == "player" and token and _G[token] then
		return _G[token]
	end
	return self.label
end

function Power:GetColor()
	local _, token = UnitPowerType(self.unit)
	if token == "MANA" or not token then
		return self.db.manaColor
	end
	return (PowerBarColor and PowerBarColor[token]) or self.db.manaColor
end

function Power:RegisterBarEvents()
	self:RegisterUnitEvent("UNIT_POWER_FREQUENT", self.unit, "Update")
	self:RegisterUnitEvent("UNIT_MAXPOWER", self.unit, "Update")
	self:RegisterUnitEvent("UNIT_DISPLAYPOWER", self.unit, "OnDisplayPower")
end

-- Druid forms switch between mana, rage and energy.
function Power:OnDisplayPower()
	self:UpdateColor()
	self:Update()
end

function Power:Update()
	if not UnitExists(self.unit) then return end
	local powerType = UnitPowerType(self.unit)
	self:SetValues(UnitPower(self.unit, powerType), UnitPowerMax(self.unit, powerType))
end

-- Modules -------------------------------------------------------------------------------------

local function Choices(...)
	local values = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		values[i] = { value, tostring(value) }
	end
	return values
end

-- kind: Health or Power. widths/heights: the menu's choices.
local function NewBar(name, kind, unit, label, defaults, defaultPosition, widths, heights)
	local module = Grimoire:NewModule(name, {
		addon = ADDON_NAME,
		label = label,
		defaults = defaults,
		options = {
			{ type = "toggle", key = "showText", label = "Show %" },
			{ type = "choice", key = "width", label = "Width", values = Choices(unpack(widths)) },
			{ type = "choice", key = "height", label = "Height", values = Choices(unpack(heights)) },
		},
	})
	for key, fn in pairs(Bar) do
		module[key] = fn
	end
	for key, fn in pairs(kind) do
		module[key] = fn
	end
	module.unit, module.defaultPosition = unit, defaultPosition
	return module
end

local MANA_BLUE = { r = 0, g = 0, b = 1 } -- classic mana blue

NewBar("Health", Health, "player", HEALTH or "Health",
	{ width = 220, height = 16, showText = true },
	{ "CENTER", "UIParent", "CENTER", 0, -180 }, { 180, 220, 260, 300 }, { 12, 16, 20, 24 })

NewBar("Power", Power, "player", "Power (mana)",
	{ width = 220, height = 12, showText = true, manaColor = MANA_BLUE },
	{ "CENTER", "UIParent", "CENTER", 0, -204 }, { 180, 220, 260, 300 }, { 8, 10, 12, 16 })

-- Pet bars: smaller, under the player's.
NewBar("PetHealth", Health, "pet", "Pet health",
	{ width = 150, height = 12, showText = true },
	{ "TOPLEFT", "UIParent", "CENTER", -114, -250 }, { 120, 150, 180, 220 }, { 8, 10, 12, 16 })

NewBar("PetPower", Power, "pet", "Pet power",
	{ width = 150, height = 8, showText = false, manaColor = MANA_BLUE },
	{ "TOPLEFT", "UIParent", "CENTER", -114, -270 }, { 120, 150, 180, 220 }, { 6, 8, 10, 12 })

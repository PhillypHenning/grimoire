local Grimoire = Grimoire

-- Unit frame toolkit: health/power bars and portraits for any unit. Components build
-- their modules from these (Grimoire_Player for the player, Grimoire_Pet for the pet),
-- so they share the code without depending on each other (ADR 0002).
--
--   Grimoire:NewUnitBar(name, opts)       a movable health or power bar
--   Grimoire:NewUnitPortrait(name, opts)  a movable portrait: animated 3D model or
--                                         classic 2D, name and level
--
-- Frames for a unit that comes and goes (the pet) hide while it doesn't exist, except
-- in move mode so they can be placed.

local HEALTH_COLOR = { r = 0, g = 1, b = 0 } -- classic player frame green

local function Mix(module, ...)
	for i = 1, select("#", ...) do
		for key, fn in pairs((select(i, ...))) do
			module[key] = fn
		end
	end
	return module
end

local function Choices(values)
	local choices = {}
	for i, value in ipairs(values) do
		choices[i] = { value, tostring(value) }
	end
	return choices
end

-- Bars --------------------------------------------------------------------------------------

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

local HealthBar = {}

function HealthBar:GetLabel()
	return self.label
end

function HealthBar:GetColor()
	return HEALTH_COLOR
end

function HealthBar:RegisterBarEvents()
	self:RegisterUnitEvent("UNIT_HEALTH", self.unit, "Update")
	self:RegisterUnitEvent("UNIT_HEALTH_FREQUENT", self.unit, "Update")
	self:RegisterUnitEvent("UNIT_MAXHEALTH", self.unit, "Update")
end

function HealthBar:Update()
	if not UnitExists(self.unit) then return end
	self:SetValues(UnitHealth(self.unit), UnitHealthMax(self.unit))
end

-- Mana, rage, energy or focus.
local PowerBar = {}

function PowerBar:GetLabel()
	local _, token = UnitPowerType(self.unit)
	if self.unit == "player" and token and _G[token] then
		return _G[token]
	end
	return self.label
end

function PowerBar:GetColor()
	local _, token = UnitPowerType(self.unit)
	if token == "MANA" or not token then
		return self.db.manaColor
	end
	return (PowerBarColor and PowerBarColor[token]) or self.db.manaColor
end

function PowerBar:RegisterBarEvents()
	self:RegisterUnitEvent("UNIT_POWER_FREQUENT", self.unit, "Update")
	self:RegisterUnitEvent("UNIT_MAXPOWER", self.unit, "Update")
	self:RegisterUnitEvent("UNIT_DISPLAYPOWER", self.unit, "OnDisplayPower")
end

-- Druid forms switch between mana, rage and energy.
function PowerBar:OnDisplayPower()
	self:UpdateColor()
	self:Update()
end

function PowerBar:Update()
	if not UnitExists(self.unit) then return end
	local powerType = UnitPowerType(self.unit)
	self:SetValues(UnitPower(self.unit, powerType), UnitPowerMax(self.unit, powerType))
end

-- opts: addon, label, kind ("health" or "power"), unit, defaults (width, height,
-- showText; manaColor for power), defaultPosition, widths and heights (menu choices).
function Grimoire:NewUnitBar(name, opts)
	local module = self:NewModule(name, {
		addon = opts.addon,
		label = opts.label,
		defaults = opts.defaults,
		options = {
			{ type = "toggle", key = "showText", label = "Show %" },
			{ type = "choice", key = "width", label = "Width", values = Choices(opts.widths) },
			{ type = "choice", key = "height", label = "Height", values = Choices(opts.heights) },
		},
	})
	Mix(module, Bar, opts.kind == "power" and PowerBar or HealthBar)
	module.unit, module.defaultPosition = opts.unit, opts.defaultPosition
	return module
end

-- Portraits -------------------------------------------------------------------------------------

local Portrait = {}

function Portrait:SetRightClickMenu(frame)
	Grimoire.SetUnitRightClickMenu(frame, self.blizzardDropDown)
end

function Portrait:Build()
	local inset = Grimoire.media.classicInset
	local frame = CreateFrame("Button", "Grimoire" .. self.name, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
	frame:SetAttribute("unit", self.unit)
	frame:RegisterForClicks("AnyUp")
	self:SetRightClickMenu(frame)
	frame:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetUnit(self.unit)
		for _, line in ipairs(self.clickHelp) do
			GameTooltip:AddLine(line, 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	Grimoire.ApplyClassicBackdrop(frame)
	self.frame = frame

	local model = CreateFrame("PlayerModel", nil, frame)
	model:SetPoint("TOPLEFT", inset, -inset)
	model:SetPoint("BOTTOMRIGHT", -inset, inset)
	model:SetScript("OnShow", function() self:UpdatePortrait() end)
	self.model = model

	local portrait = frame:CreateTexture(nil, "ARTWORK")
	portrait:SetPoint("TOPLEFT", inset, -inset)
	portrait:SetPoint("BOTTOMRIGHT", -inset, inset)
	self.portrait = portrait

	-- Text and icons sit on a frame above the model, which draws over its parent.
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(model:GetFrameLevel() + 2)
	self.overlay = overlay

	self.nameText = overlay:CreateFontString(nil, "OVERLAY", self.nameFont)
	self.nameText:SetPoint("BOTTOM", frame, "TOP", 0, 2)

	self.levelText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.levelText:SetPoint("BOTTOMRIGHT", -inset - 1, inset + 1)

	if self.BuildExtras then
		self:BuildExtras()
	end
	self:ApplySettings()
	self:RegisterMover(frame, self.label, self.defaultPosition, {
		dim = true,
		isBusy = function() return Grimoire:InCombat() and UnitExists(self.unit) end,
	})
end

function Portrait:ApplySettings()
	if not self.frame then return end
	local db = self.db
	local box = db.size + Grimoire.media.classicInset * 2
	Grimoire:RunOutOfCombat(function()
		self.frame:SetSize(box, box)
	end)
	local animated = db.style == "animated"
	self.model:SetShown(animated)
	self.portrait:SetShown(not animated)
	self.nameText:SetShown(db.showName)
	self:UpdatePortrait()
	if db.hideBlizzard then
		self:HideBlizzard()
	end
end

-- ADR 0004: hide the Blizzard frame this portrait replaces.
function Portrait:HideBlizzard()
	if self.blizzardHidden then return end
	local frame = _G[self.blizzardFrame]
	if not frame then return end
	self.blizzardHidden = true
	Grimoire:RunOutOfCombat(function()
		if self.BeforeHideBlizzard then
			self:BeforeHideBlizzard(frame)
		end
		Grimoire:HideBlizzardFrame(frame)
	end)
end

function Portrait:UpdatePortrait()
	if not UnitExists(self.unit) then return end
	if self.db.style == "animated" then
		self.model:SetUnit(self.unit)
		self.model:SetPortraitZoom(1)
		self.emoting = nil
	else
		SetPortraitTexture(self.portrait, self.unit)
	end
	Grimoire:NotifyMoverActivity(self.name)
end

function Portrait:UpdateName()
	self.nameText:SetText(self:FormatName(UnitName(self.unit) or ""))
end

function Portrait:FormatName(name)
	return name
end

function Portrait:UpdateLevel(level)
	self.levelText:SetText(level or UnitLevel(self.unit))
end

function Portrait:UpdateAll()
	self:UpdatePortrait()
	self:UpdateName()
	self:UpdateLevel()
	if self.UpdateExtras then
		self:UpdateExtras()
	end
end

-- Units that come and go show through a secure state driver, which works in combat.
-- In move mode the frame stays shown so it can be placed without the unit.
function Portrait:ShowFrame()
	if self.unit == "player" then
		self.frame:Show()
	elseif Grimoire.moversUnlocked then
		UnregisterUnitWatch(self.frame)
		self.frame:Show()
	else
		RegisterUnitWatch(self.frame)
	end
end

function Portrait:OnMoveMode()
	Grimoire:RunOutOfCombat(function()
		if self:IsEnabled() then
			self:ShowFrame()
		end
	end)
end

-- Builds the frame out of combat, then lets the module register its own events.
function Portrait:OnEnable()
	Grimoire:RunOutOfCombat(function()
		if not self:IsEnabled() then return end
		if not self.frame then
			self:Build()
		end
		self:ShowFrame()
		self:UpdateAll()
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAll")
		self:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", self.unit, "UpdatePortrait")
		self:RegisterUnitEvent("UNIT_MODEL_CHANGED", self.unit, "UpdatePortrait")
		self:RegisterUnitEvent("UNIT_NAME_UPDATE", self.unit, "UpdateName")
		self:RegisterUnitEvent("UNIT_LEVEL", self.unit, function() self:UpdateLevel() end)
		if self.unit ~= "player" then
			self:RegisterCallback("MoversUnlocked", "OnMoveMode")
			self:RegisterCallback("MoversLocked", "OnMoveMode")
		end
		if self.RegisterUnitEvents then
			self:RegisterUnitEvents()
		end
	end)
end

function Portrait:OnDisable()
	Grimoire:RunOutOfCombat(function()
		if self.frame and not self:IsEnabled() then
			if self.unit ~= "player" then
				UnregisterUnitWatch(self.frame)
			end
			self.frame:Hide()
		end
	end)
	if self.blizzardHidden then
		self:Print(("Type /reload to bring back Blizzard's %s."):format(self.blizzardLabel))
	end
end

-- The "Portrait" style choice, for a portrait module's options.
function Grimoire.UnitPortraitStyleOption()
	return { type = "choice", key = "style", label = "Portrait", values = {
		{ "animated", "Animated (3D)" }, { "classic", "Classic (2D)" },
	} }
end

-- opts: addon, label, unit, size (default), options (menu), defaultPosition,
-- nameFont, clickHelp (tooltip lines), blizzardFrame / blizzardDropDown /
-- blizzardLabel (the Blizzard frame it replaces), extraDefaults (merged into defaults).
-- Modules may add BuildExtras, UpdateExtras, RegisterUnitEvents, FormatName and
-- BeforeHideBlizzard.
function Grimoire:NewUnitPortrait(name, opts)
	local defaults = { style = "animated", size = opts.size, showName = true, hideBlizzard = true }
	for key, value in pairs(opts.extraDefaults or {}) do
		defaults[key] = value
	end
	local module = self:NewModule(name, {
		addon = opts.addon,
		label = opts.label,
		defaults = defaults,
		options = opts.options,
	})
	Mix(module, Portrait)
	module.unit, module.defaultPosition = opts.unit, opts.defaultPosition
	module.nameFont = opts.nameFont or "GameFontNormal"
	module.clickHelp = opts.clickHelp or {}
	module.blizzardFrame, module.blizzardDropDown = opts.blizzardFrame, opts.blizzardDropDown
	module.blizzardLabel = opts.blizzardLabel
	return module
end

-- Shared helpers ----------------------------------------------------------------------------
-- Small pieces for frames that show several units inside one mover (party, target),
-- where each unit's portrait and bars are widgets rather than modules.

-- Right-click on a secure unit button: the unit's Blizzard menu. Older clients use a
-- UIDropDownMenu (dropdownName, e.g. "TargetFrameDropDown"); newer ones "togglemenu".
function Grimoire.SetUnitRightClickMenu(button, dropdownName)
	local dropdown = dropdownName and _G[dropdownName]
	if dropdown and ToggleDropDownMenu then
		button:SetAttribute("type2", "menu")
		button.menu = function() ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0) end
	else
		button:SetAttribute("type2", "togglemenu")
	end
end

-- A bare status bar with centred text, for laying out inside another frame.
function Grimoire.CreateStatusBar(parent, width, height)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(width, height)
	bar:SetStatusBarTexture(Grimoire.media.statusbar)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	bar.text = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarTextSmall")
	bar.text:SetPoint("CENTER")
	return bar
end

local GREY = { r = 0.5, g = 0.5, b = 0.5 }

function Grimoire.UnitPowerColor(unit, manaColor)
	local _, token = UnitPowerType(unit)
	if token == "MANA" or not token then
		return manaColor or { r = 0, g = 0, b = 1 }
	end
	return (PowerBarColor and PowerBarColor[token]) or manaColor
end

-- Fills a bar from a unit's health or power. Empty when the unit doesn't exist; grey
-- with "Dead", "Ghost" or "Offline" when that applies.
---@param kind "health"|"power"
function Grimoire.UpdateUnitBar(bar, unit, kind, showText, manaColor)
	if not UnitExists(unit) then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		bar.text:SetText("")
		return
	end
	local current, max, color
	if kind == "health" then
		current, max, color = UnitHealth(unit), UnitHealthMax(unit), HEALTH_COLOR
	else
		local powerType = UnitPowerType(unit)
		current, max = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
		color = Grimoire.UnitPowerColor(unit, manaColor)
	end
	local state
	if not UnitIsConnected(unit) then
		state = PLAYER_OFFLINE or "Offline"
	elseif UnitIsGhost(unit) then
		state = "Ghost"
	elseif UnitIsDead(unit) then
		state = DEAD or "Dead"
	end
	if state then
		color = GREY
	end
	bar:SetStatusBarColor(color.r, color.g, color.b)
	bar:SetMinMaxValues(0, max)
	bar:SetValue(current)
	if state and kind == "health" then
		bar.text:SetText(state)
	elseif not showText then
		bar.text:SetText("")
	elseif Grimoire.AnySecret(current, max) then
		bar.text:SetText(current)
	else
		bar.text:SetFormattedText("%d%%", max > 0 and math.floor(current / max * 100) or 0)
	end
end

-- Level text colour against the player's level, like Blizzard's target frame.
-- Returns text and colour; a level of -1 (too high to show) is "??" in red.
function Grimoire.UnitLevelText(unit)
	local level = UnitLevel(unit)
	if not level or level < 0 then
		return "??", { r = 1, g = 0, b = 0 }
	end
	local getColor = GetQuestDifficultyColor or GetDifficultyColor
	return tostring(level), getColor and getColor(level) or NORMAL_FONT_COLOR
end

local MODIFIER_ABBR = { ["SHIFT-"] = "s", ["CTRL-"] = "c", ["ALT-"] = "a", ["META-"] = "m" }
local KEY_ABBR = {
	MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD", BUTTON3 = "M3", BUTTON4 = "M4", BUTTON5 = "M5",
	SPACE = "Sp", ESCAPE = "Esc", BACKSPACE = "BS", INSERT = "Ins", DELETE = "Del",
	HOME = "Hm", END = "End", PAGEUP = "PU", PAGEDOWN = "PD",
}

-- The first key bound to a binding command, shortened for a badge: "F2", "s2",
-- "cN3". nil when the command isn't bound.
function Grimoire.BindingLabel(command)
	local key = GetBindingKey(command)
	if not key then return nil end
	local label = key
	for modifier, short in pairs(MODIFIER_ABBR) do
		label = label:gsub(modifier, short)
	end
	label = label:gsub("NUMPAD", "N")
	local base = label:match("(%u%w*)$")
	if base and KEY_ABBR[base] then
		label = label:sub(1, #label - #base) .. KEY_ABBR[base]
	end
	return label
end

local Grimoire = Grimoire

-- Unit frame toolkit: health/power bars and portraits for any unit. Components build
-- their modules from these (Grimoire_Player for the player, Grimoire_Pet for the pet),
-- so they share the code without depending on each other (ADR 0002).
--
--   Grimoire:NewUnitBar(name, opts)       a movable health or power bar
--   Grimoire:NewUnitPortrait(name, opts)  a movable portrait: animated 3D model,
--                                         classic 2D, or a portrait bar (the model
--                                         behind health and power); name and level
--   Grimoire.CreatePortraitBar(parent)    the portrait bar as a widget, for frames
--                                         that hold several units (target, party)
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

-- In its portrait's "Portrait bar" style the portrait shows health and power itself.
function Bar:IsCoveredByPortrait()
	local portrait = self.portrait and Grimoire:GetModule(self.portrait)
	return portrait ~= nil and portrait:IsEnabled() and portrait.db.style == "bar"
end

-- Shown while the unit exists, and always in move mode.
function Bar:UpdateVisibility()
	self.frame:SetShown((UnitExists(self.unit) or Grimoire.moversUnlocked) and not self:IsCoveredByPortrait())
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
	if self.portrait then
		self:RegisterCallback("UnitPortraitStyleChanged", "UpdateVisibility")
		self:RegisterCallback("ModuleEnabled", "UpdateVisibility")
		self:RegisterCallback("ModuleDisabled", "UpdateVisibility")
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
-- showText; manaColor for power), defaultPosition, widths and heights (menu choices),
-- portrait (the portrait module whose "Portrait bar" style replaces this bar).
function Grimoire:NewUnitBar(name, opts)
	local module = self:NewModule(name, {
		addon = opts.addon,
		label = opts.label,
		defaults = opts.defaults,
		options = {
			{ type = "toggle", key = "showText", label = "Show %", tooltip = "Show the value as a percentage on the bar." },
			{ type = "choice", key = "width", label = "Width", tooltip = "How wide the bar is.", values = Choices(opts.widths) },
			{ type = "choice", key = "height", label = "Height", tooltip = "How tall the bar is.", values = Choices(opts.heights) },
		},
	})
	Mix(module, Bar, opts.kind == "power" and PowerBar or HealthBar)
	module.unit, module.defaultPosition, module.portrait = opts.unit, opts.defaultPosition, opts.portrait
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

	-- The "Portrait bar" style: the same model behind a health fill (the frame draws
	-- the border).
	self.bar = Grimoire.CreatePortraitBar(frame, { model = model, mirror = self.mirror, backdrop = false })
	self.bar:SetAllPoints()

	-- Text and icons sit on a frame above the model, which draws over its parent.
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(self.bar.text:GetFrameLevel() + 1)
	self.overlay = overlay

	self.nameText = overlay:CreateFontString(nil, "OVERLAY", self.nameFont)
	self.nameText:SetPoint("BOTTOM", frame, "TOP", 0, 2)

	self.levelText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	Grimoire.MakeBold(self.levelText)
	self.levelText:SetPoint("BOTTOMRIGHT", -inset - 1, inset + 1)

	if self.BuildExtras then
		self:BuildExtras()
	end
	self:ApplySettings()
	self:RegisterMover(frame, self.label, self.defaultPosition, {
		dim = true,
		-- Bright in combat, and in the bar style while health isn't full.
		isBusy = function()
			return UnitExists(self.unit) and (Grimoire:InCombat() or (self.db.style == "bar" and self.barBusy))
		end,
	})
end

function Portrait:ApplySettings()
	if not self.frame then return end
	local db = self.db
	local inset = Grimoire.media.classicInset
	local style = db.style
	local isBar = style == "bar"
	local width, height, powerHeight = Grimoire.PortraitBarSize(db.size)
	if not isBar then
		width, height = db.size + inset * 2, db.size + inset * 2
	end
	Grimoire:RunOutOfCombat(function()
		self.frame:SetSize(width, height)
	end)
	self.bar.power:SetHeight(powerHeight)
	self.bar:SetShown(isBar)
	if isBar then
		Grimoire.AttachPortraitBarModel(self.bar)
	else
		self.model:ClearAllPoints()
		self.model:SetPoint("TOPLEFT", inset, -inset)
		self.model:SetPoint("BOTTOMRIGHT", -inset, inset)
	end
	self.model:SetShown(style ~= "classic")
	self.portrait:SetShown(style == "classic")
	self.nameText:SetShown(db.showName and not isBar)
	self.levelText:SetShown(not isBar)
	self.bar.name:SetShown(db.showName)
	self:UpdateAll()
	if db.hideBlizzard then
		self:HideBlizzard()
	end
	Grimoire:Fire("UnitPortraitStyleChanged", self.name)
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
	if self.db.style == "classic" then
		SetPortraitTexture(self.portrait, self.unit)
	else
		self.model:SetUnit(self.unit)
		self.model:SetPortraitZoom(1)
		self.emoting = nil
	end
	Grimoire:NotifyMoverActivity(self.name)
end

-- Health and power on the "Portrait bar" style.
function Portrait:UpdateBar()
	if not self.frame or self.db.style ~= "bar" then return end
	self.barBusy = Grimoire.UpdatePortraitBar(self.bar, self.unit, self.db.showText)
	Grimoire:NotifyMoverActivity(self.name)
end

function Portrait:UpdateName()
	local text = self:FormatName(UnitName(self.unit) or "")
	self.nameText:SetText(text)
	self.bar.name:SetText(text)
end

function Portrait:FormatName(name)
	return name
end

function Portrait:UpdateLevel(level)
	level = level or UnitLevel(self.unit)
	self.levelText:SetText(level)
	self.bar.level:SetText(level)
end

function Portrait:UpdateAll()
	self:UpdatePortrait()
	self:UpdateBar()
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
		for _, event in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH",
			"UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION" }) do
			self:RegisterUnitEvent(event, self.unit, "UpdateBar")
		end
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
	return { type = "choice", key = "style", label = "Portrait", tooltip = "Animated 3D model, the classic flat picture, or a wide bar with the 3D model behind the health.", values = {
		{ "animated", "Animated (3D)" }, { "classic", "Classic (2D)" }, { "bar", "Portrait bar" },
	} }
end

-- opts: addon, label, unit, size (default), options (menu), defaultPosition,
-- nameFont, clickHelp (tooltip lines), blizzardFrame / blizzardDropDown /
-- blizzardLabel (the Blizzard frame it replaces), extraDefaults (merged into defaults),
-- mirror (Portrait bar style: value on the left, level on the right).
-- Modules may add BuildExtras, UpdateExtras, RegisterUnitEvents, FormatName and
-- BeforeHideBlizzard.
function Grimoire:NewUnitPortrait(name, opts)
	local defaults = { style = "animated", size = opts.size, showName = true, showText = true, hideBlizzard = true }
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
	module.mirror = opts.mirror
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
	bar.text = bar:CreateFontString(nil, "OVERLAY", Grimoire.Font("TextStatusBarTextSmall", "TextStatusBarText"))
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

-- "Offline", "Ghost" or "Dead", or nil.
local function UnitState(unit)
	if not UnitIsConnected(unit) then
		return PLAYER_OFFLINE or "Offline"
	elseif UnitIsGhost(unit) then
		return "Ghost"
	elseif UnitIsDead(unit) then
		return DEAD or "Dead"
	end
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
	local state = UnitState(unit)
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

-- Portrait bar ----------------------------------------------------------------------------------
-- Phil's pick from a screenshot (2026-10-17): the unit's 3D model is the health bar's
-- background and the health fill is a see-through colour over it, so more of the face
-- shows as health drops. A thin power strip runs underneath; level, name and value sit
-- on the bar. Used by the player, pet, target and party frames' "Portrait bar" style.

local PORTRAIT_BAR_FILL_ALPHA = 0.55

-- A portrait bar's outer width and height, and its power strip's height, from a frame's
-- Size choice (the portrait edge: 48, 64, 80): four portraits wide.
function Grimoire.PortraitBarSize(size)
	local inset = Grimoire.media.classicInset
	local health, power = math.floor(size * 0.6), math.max(4, math.floor(size / 10))
	return size * 4 + inset * 2, health + power + 1 + inset * 2, power
end

-- opts.model:    an existing PlayerModel to use (a portrait module's own, so its emotes
--                still play); otherwise one is made.
-- opts.mirror:   value on the left and level on the right (the player's side).
-- opts.backdrop: false when the parent already draws the classic border.
-- Size it with Grimoire.PortraitBarSize (pb.power:SetHeight takes the strip height).
function Grimoire.CreatePortraitBar(parent, opts)
	opts = opts or {}
	local inset = Grimoire.media.classicInset
	local pb = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	if opts.backdrop ~= false then
		Grimoire.ApplyClassicBackdrop(pb)
	end
	local base = pb:GetFrameLevel()

	pb.power = Grimoire.CreateStatusBar(pb, 1, 4)
	pb.power:SetPoint("BOTTOMLEFT", inset, inset)
	pb.power:SetPoint("BOTTOMRIGHT", -inset, inset)
	pb.power.text:Hide()
	pb.health = Grimoire.CreateStatusBar(pb, 1, 1)
	pb.health:ClearAllPoints()
	pb.health:SetPoint("TOPLEFT", inset, -inset)
	pb.health:SetPoint("BOTTOMRIGHT", pb.power, "TOPRIGHT", 0, 1)
	pb.health.text:Hide()
	pb.health:GetStatusBarTexture():SetAlpha(PORTRAIT_BAR_FILL_ALPHA)

	local model = opts.model
	if not model then
		model = CreateFrame("PlayerModel", nil, pb)
		model:SetScript("OnShow", function()
			if pb.unit then Grimoire.SetPortraitBarModel(pb, pb.unit) end
		end)
	end
	pb.model = model
	Grimoire.AttachPortraitBarModel(pb)
	pb.health:SetFrameLevel(base + 2)
	pb.power:SetFrameLevel(base + 2)

	-- Text above the fill; the model draws over everything at or below its level.
	local text = CreateFrame("Frame", nil, pb)
	text:SetAllPoints(pb.health)
	text:SetFrameLevel(base + 3)
	pb.text = text
	pb.name = text:CreateFontString(nil, "OVERLAY", Grimoire.Font("GameFontNormalOutline", "GameFontNormal"))
	pb.name:SetPoint("CENTER")
	pb.name:SetWordWrap(false)
	pb.value = text:CreateFontString(nil, "OVERLAY", Grimoire.Font("TextStatusBarText"))
	pb.level = text:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	Grimoire.MakeBold(pb.level)
	local valueSide, levelSide = "RIGHT", "LEFT"
	if opts.mirror then
		valueSide, levelSide = "LEFT", "RIGHT"
	end
	local function Pad(side) return side == "LEFT" and 3 or -3 end
	pb.value:SetPoint(valueSide, Pad(valueSide), 0)
	pb.level:SetPoint(levelSide, Pad(levelSide), 0)
	return pb
end

-- Puts the model behind the health fill. A portrait module calls this again when it
-- switches to the bar style, since its model is shared with the square portrait.
function Grimoire.AttachPortraitBarModel(pb)
	local model = pb.model
	model:ClearAllPoints()
	model:SetAllPoints(pb.health)
	model:SetFrameLevel(pb:GetFrameLevel() + 1)
end

function Grimoire.SetPortraitBarModel(pb, unit)
	pb.unit = unit
	if UnitExists(unit) then
		pb.model:SetUnit(unit)
		pb.model:SetPortraitZoom(1)
	else
		pb.model:ClearModel()
	end
end

local function ShortNumber(value)
	if value >= 10000 and AbbreviateLargeNumbers then
		return AbbreviateLargeNumbers(value)
	end
	return tostring(value)
end

-- Fills a portrait bar's health, power and value ("84 - 84%", or "Dead"). Returns true
-- while it should stay bright: the unit isn't at full health, or the values are secret.
function Grimoire.UpdatePortraitBar(pb, unit, showText, manaColor)
	Grimoire.UpdateUnitBar(pb.health, unit, "health", false, manaColor)
	Grimoire.UpdateUnitBar(pb.power, unit, "power", false, manaColor)
	if not UnitExists(unit) then
		pb.value:SetText("")
		return false
	end
	local current, max = UnitHealth(unit), UnitHealthMax(unit)
	local secret = Grimoire.AnySecret(current, max)
	local state = UnitState(unit)
	if state then
		pb.value:SetText(state)
	elseif not showText then
		pb.value:SetText("")
	elseif secret then
		pb.value:SetText(current)
	else
		pb.value:SetFormattedText("%s - %d%%", ShortNumber(current), max > 0 and math.floor(current / max * 100) or 0)
	end
	return secret or current < max
end

-- Level text colour against the player's level, like Blizzard's target frame.
-- Returns text and colour; a level of -1 (too high to show) is "??" in red.
function Grimoire.UnitLevelText(unit)
	local level = UnitLevel(unit)
	if Grimoire.IsSecret(level) then
		return level, NORMAL_FONT_COLOR -- can't compare a secret; the widget can show it
	end
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

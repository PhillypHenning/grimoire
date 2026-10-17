local ADDON_NAME = ...
local Grimoire = Grimoire

-- Target frame in Grimoire's own style, matching the player frame (Phil, 2026-10-13):
-- bordered health and power bars, the name above them in the target's reaction colour,
-- and a square portrait box (animated 3D model or classic 2D) with the level in its
-- corner, mirrored so it faces the player frame. Below: the target's auras. Beside it:
-- a compact target of target. All of it is one mover, "Target", so the parts move as
-- one and can't be split up.
--   Left-click   target (the usual unit-frame click)
--   Right-click  the target's Blizzard menu
-- Blizzard's target frame is hidden in place (ADR 0004, ADR 0007).

local INSET = 4                 -- Grimoire.media.classicInset
local BAR_WIDTH = 180
local HEALTH_HEIGHT, POWER_HEIGHT = 16, 12
local NAME_HEIGHT = 14
local GAP = 2
local BUFF_SIZE, DEBUFF_SIZE, OWN_DEBUFF_SIZE, AURA_GAP = 20, 24, 30, 3
local MAX_BUFFS, MAX_DEBUFFS = 16, 16
local TOT_WIDTH, TOT_BAR_HEIGHT = 90, 8
local TOT_UPDATE_SECONDS = 0.2

local M = Grimoire:NewModule("Target", {
	addon = ADDON_NAME,
	label = "Target frame",
	defaults = {
		style = "animated",
		size = 64,
		showText = true,
		showAuras = true,
		showTargetOfTarget = true,
		hideBlizzard = true,
	},
	options = {
		Grimoire.UnitPortraitStyleOption(),
		{ type = "choice", key = "size", label = "Size", tooltip = "How large the target frame is.", values = { { 48, "Small" }, { 64, "Medium" }, { 80, "Large" } } },
		{ type = "toggle", key = "showText", label = "Show values on bars", tooltip = "Show the target's health and power numbers on its bars." },
		{ type = "toggle", key = "showAuras", label = "Show buffs and debuffs", tooltip = "Show your target's buffs above its frame and its debuffs under it; your own debuffs are larger." },
		{ type = "toggle", key = "showTargetOfTarget", label = "Show target of target", tooltip = "A small frame showing who your target is targeting." },
		{ type = "toggle", key = "hideBlizzard", label = "Hide Blizzard target frame", tooltip = "Hide the game's own target frame; Grimoire's replaces it.", reload = true },
	},
})

local function Tooltip(unit)
	return function(b)
		if not UnitExists(unit) then return end
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetUnit(unit)
		GameTooltip:Show()
	end
end

-- A status bar inside a classic bordered box, like the player's Health/Power bars.
local function CreateBoxedBar(parent, width, height)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetSize(width + INSET * 2, height + INSET * 2)
	Grimoire.ApplyClassicBackdrop(box)
	box.bar = Grimoire.CreateStatusBar(box, width, height)
	box.bar:SetPoint("TOPLEFT", INSET, -INSET)
	box.bar.text:SetFontObject(Grimoire.Font("TextStatusBarText"))
	return box
end

-- Aura data, from whichever API this client has. Forever won't hand out a target's auras
-- by index while they're secret ("GetAuraDataByIndex(): Auras cannot be accessed when
-- secret", seen 2026-10-13), so the whole-list and slot calls are tried first. Every call
-- is guarded: a refusal yields fewer auras, never an error. Fields may be secret values.
-- An empty answer moves on to the next method too: Phil saw no target auras at all on
-- 2026-10-17 with nothing in the error log. GetAuras reports which method answered.
local function ByIndex(read)
	return function(unit, filter, max)
		local auras = {}
		for i = 1, max do
			local aura = read(unit, i, filter)
			if not aura then break end
			aura.index = i
			auras[#auras + 1] = aura
		end
		return auras
	end
end

local function LegacyAura(unit, index, filter)
	local name, icon, count, debuffType, duration, expirationTime, source = UnitAura(unit, index, filter)
	if name then
		return { name = name, icon = icon, applications = count, dispelName = debuffType,
			duration = duration, expirationTime = expirationTime, sourceUnit = source }
	end
end

local function BySlot(unit, filter, max)
	local result = { C_UnitAuras.GetAuraSlots(unit, filter, max) }
	local auras = {}
	for i = 2, #result do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataBySlot, unit, result[i])
		if ok and aura then auras[#auras + 1] = aura end
	end
	return auras
end

local AURA_METHODS = {}
do
	local api = C_UnitAuras or {}
	if api.GetUnitAuras then
		AURA_METHODS[#AURA_METHODS + 1] = { "GetUnitAuras", function(unit, filter, max)
			return api.GetUnitAuras(unit, filter, max)
		end }
	end
	if api.GetAuraSlots and api.GetAuraDataBySlot then
		AURA_METHODS[#AURA_METHODS + 1] = { "slots", BySlot }
	end
	if api.GetAuraDataByIndex then
		AURA_METHODS[#AURA_METHODS + 1] = { "index", ByIndex(api.GetAuraDataByIndex) }
	end
	if UnitAura then
		AURA_METHODS[#AURA_METHODS + 1] = { "UnitAura", ByIndex(LegacyAura) }
	end
end

-- Returns the auras, the method that found them (or nil) and what each method said.
local function GetAuras(unit, filter, max)
	local tried = {}
	for _, method in ipairs(AURA_METHODS) do
		local ok, auras = pcall(method[2], unit, filter, max)
		if ok and type(auras) == "table" and #auras > 0 then
			return auras, method[1], tried
		end
		local reason = ok and " empty" or (Grimoire.IsSecret(auras) and ": <secret>" or (": " .. tostring(auras)))
		tried[#tried + 1] = method[1] .. reason
	end
	return {}, nil, tried
end

-- Frame -----------------------------------------------------------------------------------

function M:Build()
	local media = Grimoire.media
	local holder = CreateFrame("Frame", "GrimoireTargetFrame", UIParent)
	self.holder = holder

	-- The secure button covers the bars and portrait: clicks anywhere on them work.
	local button = CreateFrame("Button", "GrimoireTargetButton", holder, "SecureUnitButtonTemplate")
	button:SetAttribute("unit", "target")
	button:SetAttribute("type1", "target")
	button:RegisterForClicks("AnyUp")
	Grimoire.SetUnitRightClickMenu(button, "TargetFrameDropDown")
	button:SetScript("OnEnter", Tooltip("target"))
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetAllPoints(holder)
	self.button = button

	button.name = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.name:SetPoint("TOPLEFT", 2, 0)
	button.name:SetHeight(NAME_HEIGHT)
	button.name:SetJustifyH("LEFT")
	button.name:SetWordWrap(false)

	button.health = CreateBoxedBar(button, BAR_WIDTH, HEALTH_HEIGHT)
	button.health:SetPoint("TOPLEFT", 0, -NAME_HEIGHT)
	button.power = CreateBoxedBar(button, BAR_WIDTH, POWER_HEIGHT)
	button.power:SetPoint("TOPLEFT", button.health, "BOTTOMLEFT", 0, -GAP)

	-- Portrait box, like the player frame's.
	local box = CreateFrame("Frame", nil, button, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(box)
	box:SetPoint("TOPLEFT", button.health, "TOPRIGHT", GAP, NAME_HEIGHT)
	button.box = box

	local model = CreateFrame("PlayerModel", nil, box)
	model:SetPoint("TOPLEFT", INSET, -INSET)
	model:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	model:SetScript("OnShow", function() self:UpdatePortrait() end)
	button.model = model

	button.portrait = box:CreateTexture(nil, "ARTWORK")
	button.portrait:SetPoint("TOPLEFT", INSET, -INSET)
	button.portrait:SetPoint("BOTTOMRIGHT", -INSET, INSET)

	-- Text and icons above the model, which draws over its parent.
	local overlay = CreateFrame("Frame", nil, box)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(model:GetFrameLevel() + 2)
	button.level = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	Grimoire.MakeBold(button.level)
	button.level:SetPoint("BOTTOMRIGHT", -INSET - 1, INSET + 1)
	button.raidIcon = overlay:CreateTexture(nil, "OVERLAY")
	button.raidIcon:SetTexture(media.raidTargetIcons)
	button.raidIcon:SetSize(22, 22)
	button.raidIcon:SetPoint("CENTER", box, "TOP", 0, 0)
	button.pvp = overlay:CreateTexture(nil, "OVERLAY")
	button.pvp:SetTexCoord(0, 0.62, 0, 0.62)
	button.pvp:SetSize(24, 24)
	button.pvp:SetPoint("BOTTOMRIGHT", box, "BOTTOMLEFT", 7, -7)

	-- Buffs above the name, debuffs under the bars (Phil, 2026-10-17); children of the
	-- button so they hide with the target.
	button.buffs = CreateFrame("Frame", nil, button)
	button.buffs:SetPoint("BOTTOMLEFT", button, "TOPLEFT", 0, GAP + 1)
	button.buffs:SetSize(BAR_WIDTH + INSET * 2, 1)
	button.debuffs = CreateFrame("Frame", nil, button)
	button.debuffs:SetPoint("TOPLEFT", button.power, "BOTTOMLEFT", 0, -GAP - 1)
	button.debuffs:SetSize(BAR_WIDTH + INSET * 2, 1)
	button.buffButtons, button.debuffButtons = {}, {}

	self:BuildTargetOfTarget()
	self:ApplyLayout()
	-- Mirrors the player frame's default spot: right of the screen centre, bars level.
	self:RegisterMover(holder, "Target", { "TOPLEFT", "UIParent", "CENTER", 118, -168 }, { dim = false })
end

function M:BuildTargetOfTarget()
	local tot = CreateFrame("Button", "GrimoireTargetOfTarget", self.holder, "SecureUnitButtonTemplate")
	tot:SetSize(TOT_WIDTH + INSET * 2, NAME_HEIGHT + TOT_BAR_HEIGHT + INSET * 2)
	tot:SetAttribute("unit", "targettarget")
	tot:SetAttribute("type1", "target")
	tot:RegisterForClicks("AnyUp")
	Grimoire.SetUnitRightClickMenu(tot)
	tot:SetScript("OnEnter", Tooltip("targettarget"))
	tot:SetScript("OnLeave", GameTooltip_Hide)
	tot.name = tot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tot.name:SetPoint("TOPLEFT", 2, 0)
	tot.name:SetPoint("TOPRIGHT", -2, 0)
	tot.name:SetHeight(NAME_HEIGHT)
	tot.name:SetJustifyH("LEFT")
	tot.name:SetWordWrap(false)
	tot.health = CreateBoxedBar(tot, TOT_WIDTH, TOT_BAR_HEIGHT)
	tot.health:SetPoint("TOPLEFT", 0, -NAME_HEIGHT)
	self.tot = tot
end

function M:ApplyLayout()
	local size = self.db.size
	local box = self.button.box
	box:SetSize(size + INSET * 2, size + INSET * 2)
	local width = BAR_WIDTH + INSET * 2 + GAP + size + INSET * 2
	local height = math.max(NAME_HEIGHT + size + INSET * 2,
		NAME_HEIGHT + HEALTH_HEIGHT + POWER_HEIGHT + INSET * 4 + GAP)
	self.holder:SetSize(width, height)
	self.tot:ClearAllPoints()
	self.tot:SetPoint("TOPLEFT", self.holder, "TOPRIGHT", GAP * 2, -NAME_HEIGHT)
	local animated = self.db.style == "animated"
	self.button.model:SetShown(animated)
	self.button.portrait:SetShown(not animated)
end

-- Display -----------------------------------------------------------------------------------

local CLASSIFICATION = {
	worldboss = "Boss", elite = "Elite", rareelite = "Rare Elite", rare = "Rare",
}

function M:UpdatePortrait()
	local button = self.button
	if not UnitExists("target") then
		button.portrait:SetTexture(nil)
		return
	end
	if self.db.style == "animated" then
		button.model:SetUnit("target")
		button.model:SetPortraitZoom(1)
	else
		SetPortraitTexture(button.portrait, "target")
	end
end

function M:UpdateTarget()
	local button, unit = self.button, "target"
	if not UnitExists(unit) then
		-- Move-mode placeholder.
		button.name:SetText(TARGET or "Target")
		button.name:SetTextColor(0.6, 0.6, 0.6)
		button.level:SetText("")
		button.raidIcon:Hide()
		button.pvp:Hide()
		self:UpdatePortrait()
		self:UpdateBars()
		self:UpdateAuras()
		return
	end

	local name = UnitName(unit) or ""
	local tag = CLASSIFICATION[UnitClassification(unit)]
	button.name:SetText(tag and ("%s |cffffd100(%s)|r"):format(name, tag) or name)
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local color = Grimoire.GetClassColor(class)
		if color then
			button.name:SetTextColor(color.r, color.g, color.b)
		end
	else
		button.name:SetTextColor(UnitSelectionColor(unit))
	end

	local levelText, color = Grimoire.UnitLevelText(unit)
	button.level:SetText(levelText)
	button.level:SetTextColor(color.r, color.g, color.b)

	self:UpdatePortrait()
	self:UpdateRaidIcon()
	self:UpdatePvP()
	self:UpdateBars()
	self:UpdateAuras()
	Grimoire:NotifyMoverActivity(self.name)
end

function M:UpdateBars()
	local button = self.button
	Grimoire.UpdateUnitBar(button.health.bar, "target", "health", self.db.showText)
	Grimoire.UpdateUnitBar(button.power.bar, "target", "power", self.db.showText)
	-- Tagged by someone else: grey, like Blizzard's.
	if UnitExists("target") and UnitIsTapDenied and UnitIsTapDenied("target") then
		button.health.bar:SetStatusBarColor(0.5, 0.5, 0.5)
	end
end

function M:UpdateRaidIcon()
	local index = UnitExists("target") and GetRaidTargetIndex("target")
	if index then
		SetRaidTargetIconTexture(self.button.raidIcon, index)
	end
	self.button.raidIcon:SetShown(index and true or false)
end

function M:UpdatePvP()
	local unit, suffix = "target", nil
	if UnitIsPVPFreeForAll(unit) then
		suffix = "FFA"
	elseif UnitIsPVP(unit) then
		suffix = UnitFactionGroup(unit)
	end
	if suffix then
		self.button.pvp:SetTexture(Grimoire.media.pvpIcon .. suffix)
	end
	self.button.pvp:SetShown(suffix ~= nil)
end

-- Auras -----------------------------------------------------------------------------------------
-- Display only: buffs in rows growing up from above the name, debuffs (larger) in rows
-- growing down from under the bars. Your own debuffs (your DoTs) are larger still. Secret fields only ever go to widgets (texture, cooldown, text),
-- which accept them; they're never compared or used as table keys.

local function Usable(value)
	return value ~= nil and not Grimoire.IsSecret(value)
end

local function Aura_OnEnter(aura)
	GameTooltip:SetOwner(aura, "ANCHOR_BOTTOMRIGHT")
	local id, harmful = aura.instanceID, aura.filter == "HARMFUL"
	local byID = harmful and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
	if id and byID then
		byID(GameTooltip, "target", id, aura.filter)
	elseif aura.index then
		GameTooltip:SetUnitAura("target", aura.index, aura.filter)
	end
	GameTooltip:Show()
end

local function GetAuraButton(parent, list, i)
	local aura = list[i]
	if aura then return aura end
	aura = CreateFrame("Button", nil, parent)
	aura.icon = aura:CreateTexture(nil, "ARTWORK")
	aura.icon:SetAllPoints()
	-- Forever lacks some Blizzard templates; a plain Cooldown still draws the swipe.
	local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, aura, "CooldownFrameTemplate")
	aura.cooldown = ok and cooldown or CreateFrame("Cooldown", nil, aura)
	aura.cooldown:SetAllPoints()
	aura.cooldown:SetReverse(true)
	aura.count = aura:CreateFontString(nil, "OVERLAY", Grimoire.Font("NumberFontNormalSmall", "NumberFontNormal"))
	aura.count:SetPoint("BOTTOMRIGHT", 2, -1)
	aura.border = aura:CreateTexture(nil, "OVERLAY")
	aura.border:SetTexture(Grimoire.media.auraBorder)
	aura.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
	aura.border:SetPoint("TOPLEFT", -1, 1)
	aura.border:SetPoint("BOTTOMRIGHT", 1, -1)
	aura:SetScript("OnEnter", Aura_OnEnter)
	aura:SetScript("OnLeave", GameTooltip_Hide)
	list[i] = aura
	return aura
end

local ROW_WIDTH = BAR_WIDTH + INSET * 2 -- as wide as the bars

-- Your debuffs: asked for with the PLAYER filter (works when the caster is secret), with
-- the caster as a fallback where it's readable (that one also catches the pet's).
local function OwnAuraIDs(unit, max)
	local ids = {}
	for _, aura in ipairs(GetAuras(unit, "HARMFUL|PLAYER", max)) do
		if Usable(aura.auraInstanceID) then
			ids[aura.auraInstanceID] = true
		end
	end
	return ids
end

local function IsOwn(aura, ownIDs)
	if Usable(aura.auraInstanceID) and ownIDs[aura.auraInstanceID] then
		return true
	end
	local source = aura.sourceUnit
	return Usable(source) and (source == "player" or source == "pet")
end

local function CountText(unit, data)
	local count = data.applications
	if Usable(count) then
		return count > 1 and count or ""
	end
	local display = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
	if count ~= nil and display and Usable(data.auraInstanceID) then
		local ok, text = pcall(display, unit, data.auraInstanceID, 2)
		if ok and text then return text end
	end
	return ""
end

local function BorderColor(debuffType)
	local colors = DebuffTypeColor
	local color = colors and Usable(debuffType) and colors[debuffType] or colors and colors.none
	return color or { r = 0.8, g = 0, b = 0 }
end

local function SetAuraCooldown(cooldown, unit, data)
	local duration, expirationTime = data.duration, data.expirationTime
	if Usable(duration) and Usable(expirationTime) then
		if duration > 0 then
			cooldown:SetCooldown(expirationTime - duration, duration)
			cooldown:Show()
			return
		end
	else
		-- Secret timings: let the client hand the widget a duration it can draw.
		local getDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
		if getDuration and cooldown.SetCooldownFromDurationObject and Usable(data.auraInstanceID) then
			local ok, object = pcall(getDuration, unit, data.auraInstanceID)
			if ok and object and pcall(cooldown.SetCooldownFromDurationObject, cooldown, object) then
				cooldown:Show()
				return
			end
		end
		if cooldown.SetCooldownFromExpirationTime and pcall(cooldown.SetCooldownFromExpirationTime, cooldown, expirationTime, duration) then
			cooldown:Show()
			return
		end
	end
	cooldown:Hide()
end

-- Lays out one aura list in rows, growing down from the parent's top-left corner, or up
-- from its bottom-left one. Returns how many it showed and how it read them.
local function LayoutAuras(parent, list, filter, max, size, ownSize, growUp, ownIDs)
	local unit = "target"
	local auras, method, tried = GetAuras(unit, filter, max)
	local point, sign = growUp and "BOTTOMLEFT" or "TOPLEFT", growUp and 1 or -1
	local x, y, rowHeight, shown = 0, 0, 0, 0
	for i = 1, math.min(#auras, max) do
		local data = auras[i]
		shown = i
		local aura = GetAuraButton(parent, list, i)
		local own = ownIDs and IsOwn(data, ownIDs)
		local auraSize = own and ownSize or size
		if x + auraSize > ROW_WIDTH then
			x, y, rowHeight = 0, y + sign * (rowHeight + AURA_GAP), 0
		end
		aura.index, aura.filter = data.index, filter
		aura.instanceID = Usable(data.auraInstanceID) and data.auraInstanceID or nil
		aura:SetSize(auraSize, auraSize)
		aura:ClearAllPoints()
		aura:SetPoint(point, parent, point, x, y)
		aura.icon:SetTexture(data.icon)
		aura.count:SetText(CountText(unit, data))
		if filter == "HARMFUL" then
			local color = BorderColor(data.dispelName)
			aura.border:SetVertexColor(color.r, color.g, color.b)
			aura.border:Show()
		else
			aura.border:Hide()
		end
		SetAuraCooldown(aura.cooldown, unit, data)
		aura:Show()
		x = x + auraSize + AURA_GAP
		rowHeight = math.max(rowHeight, auraSize)
	end
	for i = shown + 1, #list do
		list[i]:Hide()
	end
	return shown, (method or "none") .. (#tried > 0 and (" (" .. table.concat(tried, ", ") .. ")") or "")
end

function M:UpdateAuras()
	local button = self.button
	local show = (self.db.showAuras and UnitExists("target")) and true or false
	button.buffs:SetShown(show)
	button.debuffs:SetShown(show)
	if not show then return end
	local buffs, buffMethod = LayoutAuras(button.buffs, button.buffButtons, "HELPFUL", MAX_BUFFS,
		BUFF_SIZE, BUFF_SIZE, true)
	local debuffs, debuffMethod = LayoutAuras(button.debuffs, button.debuffButtons, "HARMFUL", MAX_DEBUFFS,
		DEBUFF_SIZE, OWN_DEBUFF_SIZE, false, OwnAuraIDs("target", MAX_DEBUFFS))
	-- Which aura API Forever answers, logged when it changes (for /grim debug).
	local report = ("target auras: %d buffs via %s; %d debuffs via %s"):format(buffs, buffMethod, debuffs, debuffMethod)
	if report ~= self.lastAuraReport then
		self.lastAuraReport = report
		self:Log("info", "%s", report)
	end
end

-- Target of target ------------------------------------------------------------------------------
-- No event fires when the target's target changes, so it's polled while shown.

function M:UpdateTargetOfTarget()
	local tot, unit = self.tot, "targettarget"
	if UnitExists(unit) then
		local _, class = UnitClass(unit)
		tot.name:SetText(UnitIsPlayer(unit) and Grimoire.ClassColorText(UnitName(unit), class) or UnitName(unit))
	else
		tot.name:SetText(Grimoire.moversUnlocked and "Target of target" or "")
	end
	Grimoire.UpdateUnitBar(tot.health.bar, unit, "health", false)
end

-- Visibility ------------------------------------------------------------------------------------
-- Secure unit watches show the target and target-of-target frames while those units
-- exist (in combat too). Move mode shows both as placeholders.

function M:ApplyVisibility()
	local unlocked = Grimoire.moversUnlocked
	if unlocked then
		UnregisterUnitWatch(self.button)
		self.button:Show()
	else
		RegisterUnitWatch(self.button)
	end
	if not self.db.showTargetOfTarget then
		UnregisterUnitWatch(self.tot)
		self.tot:Hide()
	elseif unlocked then
		UnregisterUnitWatch(self.tot)
		self.tot:Show()
	else
		RegisterUnitWatch(self.tot)
	end
	self:RefreshAll()
end

function M:ApplySettings(key)
	if not self.holder then return end
	if key == "showText" then
		self:UpdateBars()
		return
	elseif key == "showAuras" then
		self:UpdateAuras()
		return
	end
	Grimoire:RunOutOfCombat(function()
		self:ApplyLayout()
		self:ApplyVisibility()
		if self.db.hideBlizzard then
			self:HideBlizzard()
		end
	end)
end

-- ADR 0004/0007: hide Blizzard's target frame in place. Its target-of-target frame goes
-- with it (ours replaces it); on Classic the combo points are moved over first.
function M:HideBlizzard()
	if self.blizzardHidden or not TargetFrame then return end
	self.blizzardHidden = true
	if ComboFrame and ComboFrame:GetParent() == TargetFrame then
		ComboFrame:SetParent(self.button)
		ComboFrame:ClearAllPoints()
		ComboFrame:SetPoint("BOTTOMRIGHT", self.button.box, "TOPRIGHT", 0, 2)
	end
	Grimoire:HideBlizzardFrame(TargetFrame)
end

-- Events ----------------------------------------------------------------------------------------

function M:RefreshAll()
	self:UpdateTarget()
	self:UpdateTargetOfTarget()
end

function M:OnTargetUnitEvent(_, unit)
	if unit == "target" then
		self:UpdateBars()
		Grimoire:NotifyMoverActivity(self.name)
	end
end

-- A unit event that changes how the target looks (name, level, faction, ...).
function M:OnTargetChanged(_, unit)
	if unit == "target" then
		self:RefreshAll()
	end
end

function M:OnTargetAura(_, unit)
	if unit == "target" then
		self:UpdateAuras()
	end
end

function M:OnMoveMode()
	Grimoire:RunOutOfCombat(function()
		if self:IsEnabled() then
			self:ApplyVisibility()
		end
	end)
end

function M:OnEnable()
	Grimoire:RunOutOfCombat(function()
		if not self:IsEnabled() then return end
		if not self.holder then
			self:Build()
		end
		self.holder:Show()

		self:RegisterEvent("PLAYER_TARGET_CHANGED", "RefreshAll")
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshAll")
		for _, event in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH",
			"UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION" }) do
			self:RegisterEvent(event, "OnTargetUnitEvent")
		end
		for _, event in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
			"UNIT_CLASSIFICATION_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED" }) do
			self:RegisterEvent(event, "OnTargetChanged")
		end
		self:RegisterEvent("UNIT_AURA", "OnTargetAura")
		self:RegisterEvent("RAID_TARGET_UPDATE", "UpdateRaidIcon")
		self:RegisterCallback("MoversUnlocked", "OnMoveMode")
		self:RegisterCallback("MoversLocked", "OnMoveMode")
		self.totTicker = C_Timer.NewTicker(TOT_UPDATE_SECONDS, function()
			if self.tot:IsVisible() then
				self:UpdateTargetOfTarget()
			end
		end)
		-- Last: hiding Blizzard's frame is the riskiest step, and events are already live.
		self:ApplySettings()
	end)
end

function M:OnDisable()
	if self.totTicker then
		self.totTicker:Cancel()
		self.totTicker = nil
	end
	Grimoire:RunOutOfCombat(function()
		if not self.holder or self:IsEnabled() then return end
		UnregisterUnitWatch(self.button)
		UnregisterUnitWatch(self.tot)
		self.button:Hide()
		self.tot:Hide()
		self.holder:Hide()
	end)
	if self.blizzardHidden then
		self:Print("Type /reload to bring back Blizzard's target frame.")
	end
end

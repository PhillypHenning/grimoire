local ADDON_NAME = ...
local Grimoire = Grimoire

-- Target frame: Blizzard's classic target frame look (portrait in a ring, name on a
-- reaction-coloured band, level, health and mana, elite/rare dragon border) with the
-- target's auras and a target-of-target frame, all in one mover, "Target". The parts
-- are children of that mover, so they move as one and can't be split up.
--   Left-click   target (the usual unit-frame click)
--   Right-click  the target's Blizzard menu
-- Blizzard's target frame is hidden (ADR 0004); its combo points are moved over first.
--
-- Layout numbers mirror Blizzard's player frame on the 232x100 target art. They're
-- all in LAYOUT so they can be tuned from a screenshot.

local LAYOUT = {
	width = 232, height = 100,
	portrait = { 64, 126, -12 },       -- size, x, y from the top-left
	health = { 119, 12, 7, -41 },      -- width, height, x, y
	power = { 119, 12, 7, -52 },
	nameBand = { 119, 19, 7, -22 },
	level = { 179, -66 },               -- centre of the level circle
	raidIcon = 26,
	combo = { -44, -9 },                -- ComboFrame, from the top-right
	auras = { 5, -66 },                 -- first aura's top-left
	targetOfTarget = { -35, -10 },      -- its bottom-right, from the frame's bottom-right
}
local AURA_SIZE, OWN_AURA_SIZE, AURA_GAP, AURAS_PER_ROW = 17, 21, 3, 5
local MAX_BUFFS, MAX_DEBUFFS = 16, 16
local TOT_UPDATE_SECONDS = 0.2

local M = Grimoire:NewModule("Target", {
	addon = ADDON_NAME,
	label = "Target frame",
	defaults = {
		scale = 1,
		showText = true,
		showAuras = true,
		showTargetOfTarget = true,
		hideBlizzard = true,
	},
	options = {
		{ type = "choice", key = "scale", label = "Size", values = {
			{ 0.9, "Small" }, { 1, "Normal" }, { 1.2, "Large" }, { 1.4, "Huge" },
		} },
		{ type = "toggle", key = "showText", label = "Show % on bars" },
		{ type = "toggle", key = "showAuras", label = "Show buffs and debuffs" },
		{ type = "toggle", key = "showTargetOfTarget", label = "Show target of target" },
		{ type = "toggle", key = "hideBlizzard", label = "Hide Blizzard target frame", reload = true },
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

-- Aura data, from whichever API this client has.
local function GetAura(unit, index, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
		if aura then
			return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime, aura.sourceUnit
		end
		return nil
	end
	local name, icon, count, debuffType, duration, expirationTime, source = UnitAura(unit, index, filter)
	return name, icon, count, debuffType, duration, expirationTime, source
end

-- Frame ------------------------------------------------------------------------------------------

local function BuildTargetButton(self)
	local media, L = Grimoire.media, LAYOUT
	local button = CreateFrame("Button", "GrimoireTargetButton", self.holder, "SecureUnitButtonTemplate")
	button:SetSize(L.width, L.height)
	button:SetAttribute("unit", "target")
	button:SetAttribute("type1", "target")
	button:RegisterForClicks("AnyUp")
	Grimoire.SetUnitRightClickMenu(button, "TargetFrameDropDown")
	button:SetScript("OnEnter", Tooltip("target"))
	button:SetScript("OnLeave", GameTooltip_Hide)

	button.portrait = button:CreateTexture(nil, "BACKGROUND")
	button.portrait:SetSize(L.portrait[1], L.portrait[1])
	button.portrait:SetPoint("TOPLEFT", L.portrait[2], L.portrait[3])

	button.nameBand = button:CreateTexture(nil, "BACKGROUND")
	button.nameBand:SetTexture(media.nameBackground)
	button.nameBand:SetSize(L.nameBand[1], L.nameBand[2])
	button.nameBand:SetPoint("TOPLEFT", L.nameBand[3], L.nameBand[4])

	button.health = Grimoire.CreateStatusBar(button, L.health[1], L.health[2])
	button.health:SetPoint("TOPLEFT", L.health[3], L.health[4])
	button.power = Grimoire.CreateStatusBar(button, L.power[1], L.power[2])
	button.power:SetPoint("TOPLEFT", L.power[3], L.power[4])

	local art = CreateFrame("Frame", nil, button)
	art:SetAllPoints()
	art:SetFrameLevel(button.health:GetFrameLevel() + 2)
	button.border = art:CreateTexture(nil, "ARTWORK")
	button.border:SetAllPoints()
	button.border:SetTexCoord(0.09375, 1, 0, 0.78125)

	button.name = art:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.name:SetPoint("CENTER", button.nameBand, "CENTER", 0, 0)
	button.name:SetWidth(L.nameBand[1] - 6)
	button.name:SetWordWrap(false)

	button.level = art:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.level:SetPoint("CENTER", button, "TOPLEFT", L.level[1], L.level[2])

	button.raidIcon = art:CreateTexture(nil, "OVERLAY")
	button.raidIcon:SetTexture(media.raidTargetIcons)
	button.raidIcon:SetSize(L.raidIcon, L.raidIcon)
	button.raidIcon:SetPoint("CENTER", button.portrait, "TOP", 0, 0)

	button.pvp = art:CreateTexture(nil, "OVERLAY")
	button.pvp:SetTexCoord(0, 0.62, 0, 0.62)
	button.pvp:SetSize(26, 26)
	button.pvp:SetPoint("LEFT", button.portrait, "RIGHT", -6, -6)

	-- Auras hang below the bars; children of the button so they hide with the target.
	button.auras = CreateFrame("Frame", nil, button)
	button.auras:SetPoint("TOPLEFT", L.auras[1], L.auras[2])
	button.auras:SetSize(AURAS_PER_ROW * (OWN_AURA_SIZE + AURA_GAP), 1)
	button.buffButtons, button.debuffButtons = {}, {}
	return button
end

local function BuildTargetOfTarget(self)
	local media = Grimoire.media
	local tot = CreateFrame("Button", "GrimoireTargetOfTarget", self.holder, "SecureUnitButtonTemplate")
	tot:SetSize(93, 45)
	tot:SetAttribute("unit", "targettarget")
	tot:SetAttribute("type1", "target")
	tot:RegisterForClicks("AnyUp")
	Grimoire.SetUnitRightClickMenu(tot)
	tot:SetScript("OnEnter", Tooltip("targettarget"))
	tot:SetScript("OnLeave", GameTooltip_Hide)

	tot.portrait = tot:CreateTexture(nil, "BACKGROUND")
	tot.portrait:SetSize(35, 35)
	tot.portrait:SetPoint("TOPLEFT", 6, -5)
	tot.health = Grimoire.CreateStatusBar(tot, 46, 7)
	tot.health:SetPoint("TOPRIGHT", -2, -15)
	tot.power = Grimoire.CreateStatusBar(tot, 46, 7)
	tot.power:SetPoint("TOPRIGHT", -2, -23)

	local art = CreateFrame("Frame", nil, tot)
	art:SetAllPoints()
	art:SetFrameLevel(tot.health:GetFrameLevel() + 2)
	local border = art:CreateTexture(nil, "ARTWORK")
	border:SetTexture(media.targetOfTargetFrame)
	border:SetSize(128, 64)
	border:SetPoint("TOPLEFT", 0, 0)
	tot.name = art:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	tot.name:SetPoint("BOTTOMLEFT", 42, 6)
	tot.name:SetWidth(48)
	tot.name:SetJustifyH("LEFT")
	tot.name:SetWordWrap(false)
	return tot
end

function M:Build()
	local holder = CreateFrame("Frame", "GrimoireTargetFrame", UIParent)
	self.holder = holder
	self.button = BuildTargetButton(self)
	self.tot = BuildTargetOfTarget(self)
	self:ApplyLayout()
	-- Where Blizzard's target frame sits, right of the player frame.
	self:RegisterMover(holder, "Target", { "TOPLEFT", "UIParent", "TOPLEFT", 250, -4 }, { dim = false })
end

function M:ApplyLayout()
	local L, scale = LAYOUT, self.db.scale
	self.button:SetScale(scale)
	self.button:ClearAllPoints()
	self.button:SetPoint("TOPLEFT", self.holder, "TOPLEFT", 0, 0)
	self.tot:SetScale(scale)
	self.tot:ClearAllPoints()
	self.tot:SetPoint("BOTTOMRIGHT", self.button, "BOTTOMRIGHT", L.targetOfTarget[1], L.targetOfTarget[2] - 45)
	self.holder:SetSize(L.width * scale, L.height * scale)
end

-- Display ------------------------------------------------------------------------------------------

local CLASSIFICATION_ART = {
	worldboss = "targetFrameElite",
	elite = "targetFrameElite",
	rareelite = "targetFrameRareElite",
	rare = "targetFrameRare",
}

function M:UpdateTarget()
	local button, unit = self.button, "target"
	if not UnitExists(unit) then
		-- Move-mode placeholder.
		button.border:SetTexture(Grimoire.media.targetFrame)
		button.portrait:SetTexture(nil)
		button.name:SetText(TARGET or "Target")
		button.level:SetText("")
		button.nameBand:SetVertexColor(0.5, 0.5, 0.5)
		button.raidIcon:Hide()
		button.pvp:Hide()
		self:UpdateBars()
		self:UpdateAuras()
		return
	end
	local art = CLASSIFICATION_ART[UnitClassification(unit)] or "targetFrame"
	button.border:SetTexture(Grimoire.media[art])
	SetPortraitTexture(button.portrait, unit)
	button.name:SetText(UnitName(unit))

	local r, g, b = UnitSelectionColor(unit)
	button.nameBand:SetVertexColor(r, g, b)

	local levelText, color = Grimoire.UnitLevelText(unit)
	button.level:SetText(levelText)
	button.level:SetTextColor(color.r, color.g, color.b)

	self:UpdateRaidIcon()
	self:UpdatePvP()
	self:UpdateBars()
	self:UpdateAuras()
	Grimoire:NotifyMoverActivity(self.name)
end

function M:UpdateBars()
	local button = self.button
	Grimoire.UpdateUnitBar(button.health, "target", "health", self.db.showText)
	Grimoire.UpdateUnitBar(button.power, "target", "power", self.db.showText)
	-- Tagged by someone else: grey, like Blizzard's.
	if UnitExists("target") and UnitIsTapDenied and UnitIsTapDenied("target") then
		button.health:SetStatusBarColor(0.5, 0.5, 0.5)
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

-- Auras ----------------------------------------------------------------------------------------------
-- Display only: buffs first, then debuffs, rows of AURAS_PER_ROW. Your own debuffs (your
-- DoTs) are larger, as on Blizzard's classic frame.

local function Aura_OnEnter(aura)
	GameTooltip:SetOwner(aura, "ANCHOR_BOTTOMRIGHT")
	GameTooltip:SetUnitAura("target", aura.index, aura.filter)
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

-- Lays out one aura list from (x, y); returns where the next one starts.
local function LayoutAuras(parent, list, filter, max, x, y, rowHeight)
	local shown = 0
	for i = 1, max do
		local name, icon, count, debuffType, duration, expirationTime, source = GetAura("target", i, filter)
		if not name then break end
		shown = shown + 1
		local aura = GetAuraButton(parent, list, i)
		local own = filter == "HARMFUL" and (source == "player" or source == "pet")
		local size = own and OWN_AURA_SIZE or AURA_SIZE
		if x + size > AURAS_PER_ROW * (AURA_SIZE + AURA_GAP) + (OWN_AURA_SIZE - AURA_SIZE) then
			x, y, rowHeight = 0, y - rowHeight - AURA_GAP, 0
		end
		aura.index, aura.filter = i, filter
		aura:SetSize(size, size)
		aura:ClearAllPoints()
		aura:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
		aura.icon:SetTexture(icon)
		aura.count:SetText((not Grimoire.IsSecret(count) and count and count > 1) and count or "")
		if filter == "HARMFUL" then
			local color = (DebuffTypeColor and DebuffTypeColor[debuffType or "none"]) or { r = 0.8, g = 0, b = 0 }
			aura.border:SetVertexColor(color.r, color.g, color.b)
			aura.border:Show()
		else
			aura.border:Hide()
		end
		if not Grimoire.AnySecret(duration, expirationTime) and duration and duration > 0 then
			aura.cooldown:SetCooldown(expirationTime - duration, duration)
			aura.cooldown:Show()
		else
			aura.cooldown:Hide()
		end
		aura:Show()
		x = x + size + AURA_GAP
		rowHeight = math.max(rowHeight, size)
	end
	for i = shown + 1, #list do
		list[i]:Hide()
	end
	return x, y, rowHeight, shown
end

function M:UpdateAuras()
	local button = self.button
	local show = self.db.showAuras and UnitExists("target")
	button.auras:SetShown(show and true or false)
	if not show then return end
	local x, y, rowHeight, buffs = LayoutAuras(button.auras, button.buffButtons, "HELPFUL", MAX_BUFFS, 0, 0, 0)
	if buffs > 0 then
		-- Debuffs start on a new row under the buffs.
		x, y, rowHeight = 0, y - rowHeight - AURA_GAP, 0
	end
	LayoutAuras(button.auras, button.debuffButtons, "HARMFUL", MAX_DEBUFFS, x, y, rowHeight)
end

-- Target of target --------------------------------------------------------------------------------
-- No event fires when the target's target changes, so it's polled while shown.

function M:UpdateTargetOfTarget()
	local tot, unit = self.tot, "targettarget"
	if UnitExists(unit) then
		local _, class = UnitClass(unit)
		tot.name:SetText(UnitIsPlayer(unit) and Grimoire.ClassColorText(UnitName(unit), class) or UnitName(unit))
		SetPortraitTexture(tot.portrait, unit)
	else
		tot.name:SetText(Grimoire.moversUnlocked and "ToT" or "")
		tot.portrait:SetTexture(nil)
	end
	Grimoire.UpdateUnitBar(tot.health, unit, "health", false)
	Grimoire.UpdateUnitBar(tot.power, unit, "power", false)
end

-- Visibility ------------------------------------------------------------------------------------------
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
	self:UpdateTarget()
	self:UpdateTargetOfTarget()
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

-- ADR 0004: hide Blizzard's target frame. Its target-of-target frame goes with it (ours
-- replaces it); the combo points are moved over first, so other classes keep them.
function M:HideBlizzard()
	if self.blizzardHidden or not TargetFrame then return end
	self.blizzardHidden = true
	if ComboFrame and ComboFrame:GetParent() == TargetFrame then
		ComboFrame:SetParent(self.button)
		ComboFrame:ClearAllPoints()
		ComboFrame:SetPoint("TOPRIGHT", self.button, "TOPRIGHT", LAYOUT.combo[1], LAYOUT.combo[2])
	end
	Grimoire:HideBlizzardFrame(TargetFrame)
end

-- Events -----------------------------------------------------------------------------------------------

function M:OnTargetUnitEvent(_, unit)
	if unit == "target" then
		self:UpdateBars()
		Grimoire:NotifyMoverActivity(self.name)
	end
end

function M:RefreshAll()
	self:UpdateTarget()
	self:UpdateTargetOfTarget()
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
		self:ApplySettings()

		self:RegisterEvent("PLAYER_TARGET_CHANGED", "RefreshAll")
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "RefreshAll")
		for _, event in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH",
			"UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION" }) do
			self:RegisterEvent(event, "OnTargetUnitEvent")
		end
		for _, event in ipairs({ "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
			"UNIT_CLASSIFICATION_CHANGED", "UNIT_PORTRAIT_UPDATE" }) do
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

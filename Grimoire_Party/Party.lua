local ADDON_NAME = ...
local Grimoire = Grimoire

-- Party frames: up to four members in one mover, "Party". Each member is Blizzard's
-- classic party frame look (ring portrait, health and mana bars) on a secure unit
-- button: left-click targets, right-click opens the unit menu. The members are
-- children laid out inside the mover, not movers themselves, so they move as one and
-- can't be split up. Each portrait shows the key bound to "Target Party Member N".
--
-- No SecureGroupHeaderTemplate: Forever may lack it (it ships beside the aura header
-- it doesn't have). Party units fill in order, so four fixed slots shown with
-- RegisterUnitWatch always show members 1..n.

local MEMBERS = 4
local MEMBER_WIDTH, MEMBER_HEIGHT = 128, 53
local SPACING = { normal = 10, compact = 2 }
local OUT_OF_RANGE_ALPHA = 0.55
local RANGE_CHECK_SECONDS = 0.5

local M = Grimoire:NewModule("Party", {
	addon = ADDON_NAME,
	label = "Party frames",
	defaults = {
		scale = 1,
		showText = false,
		spacing = "normal",
		showInRaid = false,
		hideBlizzard = true,
	},
	options = {
		{ type = "choice", key = "scale", label = "Size", tooltip = "How large the party frames are.", values = {
			{ 0.9, "Small" }, { 1, "Normal" }, { 1.2, "Large" }, { 1.4, "Huge" },
		} },
		{ type = "choice", key = "spacing", label = "Spacing", tooltip = "How far apart the party frames sit.", values = { { "compact", "Compact" }, { "normal", "Normal" } } },
		{ type = "toggle", key = "showText", label = "Show % on bars", tooltip = "Show health and power as percentages." },
		{ type = "toggle", key = "showInRaid", label = "Show in raid", tooltip = "Keep showing the party frames while you are in a raid." },
		{ type = "toggle", key = "hideBlizzard", label = "Hide Blizzard party frames", tooltip = "Hide the game's own party frames; Grimoire's replace them.", reload = true },
	},
})

local UNIT_INDEX = {}
for i = 1, MEMBERS do
	UNIT_INDEX["party" .. i] = i
end

-- Members --------------------------------------------------------------------------------

local function CreateMember(self, index)
	local media = Grimoire.media
	local unit = "party" .. index
	local button = CreateFrame("Button", "GrimoirePartyMember" .. index, self.holder, "SecureUnitButtonTemplate")
	button:SetSize(MEMBER_WIDTH, MEMBER_HEIGHT)
	button:SetAttribute("unit", unit)
	button:SetAttribute("type1", "target")
	button:RegisterForClicks("AnyUp")
	Grimoire.SetUnitRightClickMenu(button, "PartyMemberFrame" .. index .. "DropDown")
	button:SetScript("OnEnter", function(b)
		if not UnitExists(unit) then return end
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetUnit(unit)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button.unit, button.index = unit, index

	-- Portrait under the ring, bars in the art's slots, the art on top.
	button.portrait = button:CreateTexture(nil, "BACKGROUND")
	button.portrait:SetSize(37, 37)
	button.portrait:SetPoint("TOPLEFT", 7, -6)

	button.health = Grimoire.CreateStatusBar(button, 70, 7)
	button.health:SetPoint("TOPLEFT", 47, -12)
	button.power = Grimoire.CreateStatusBar(button, 70, 7)
	button.power:SetPoint("TOPLEFT", 47, -20)

	local art = CreateFrame("Frame", nil, button)
	art:SetAllPoints()
	art:SetFrameLevel(button.health:GetFrameLevel() + 2)
	local border = art:CreateTexture(nil, "ARTWORK")
	border:SetTexture(media.partyFrame)
	border:SetSize(128, 64)
	border:SetPoint("TOPLEFT", 0, -2)

	button.name = art:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.name:SetPoint("BOTTOMLEFT", button.health, "TOPLEFT", 0, 2)
	button.name:SetWidth(90)
	button.name:SetJustifyH("LEFT")
	button.name:SetWordWrap(false)

	button.leader = art:CreateTexture(nil, "OVERLAY")
	button.leader:SetTexture(media.leaderIcon)
	button.leader:SetSize(16, 16)
	button.leader:SetPoint("TOPLEFT", 0, 0)

	-- Keybinding badge (Phil's request): the key that targets this member.
	button.binding = art:CreateFontString(nil, "OVERLAY", Grimoire.Font("NumberFontNormalSmall", "NumberFontNormal"))
	button.binding:SetPoint("BOTTOM", button.portrait, "BOTTOM", 0, 1)
	button.binding:SetTextColor(1, 1, 1)

	return button
end

function M:UpdateMember(button)
	local unit = button.unit
	local exists = UnitExists(unit)
	if exists then
		local _, class = UnitClass(unit)
		button.name:SetText(Grimoire.ClassColorText(UnitName(unit) or "", class))
		SetPortraitTexture(button.portrait, unit)
		button.portrait:SetDesaturated(not UnitIsConnected(unit))
	else
		-- Move-mode placeholder.
		button.name:SetText(PARTY and (PARTY .. " " .. button.index) or ("Party " .. button.index))
		button.portrait:SetTexture(nil)
	end
	local isLeader = exists and UnitIsGroupLeader and UnitIsGroupLeader(unit)
	button.leader:SetShown(isLeader and true or false)
	self:UpdateBars(button)
	self:UpdateBinding(button)
end

function M:UpdateBars(button)
	Grimoire.UpdateUnitBar(button.health, button.unit, "health", self.db.showText)
	Grimoire.UpdateUnitBar(button.power, button.unit, "power", self.db.showText)
end

function M:UpdateBinding(button)
	button.binding:SetText(Grimoire.BindingLabel("TARGETPARTYMEMBER" .. button.index) or "")
end

function M:UpdateAll()
	for _, button in ipairs(self.members) do
		self:UpdateMember(button)
	end
	Grimoire:NotifyMoverActivity(self.name)
end

-- Out-of-range members fade, like Blizzard's. This is the member's own alpha; the
-- mover's alpha (idle dimming) stays with core.
function M:UpdateRange()
	for _, button in ipairs(self.members) do
		local alpha = 1
		if UnitExists(button.unit) and UnitInRange then
			local inRange, checked = UnitInRange(button.unit)
			if checked and not inRange then
				alpha = OUT_OF_RANGE_ALPHA
			end
		end
		button:SetAlpha(alpha)
	end
end

-- Layout and visibility ----------------------------------------------------------------------

function M:ApplyLayout()
	local db = self.db
	local step = MEMBER_HEIGHT + SPACING[db.spacing]
	for i, button in ipairs(self.members) do
		button:SetScale(db.scale)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", self.holder, "TOPLEFT", 0, -(i - 1) * step)
	end
	self.holder:SetSize(MEMBER_WIDTH * db.scale, (MEMBERS * step - SPACING[db.spacing]) * db.scale)
end

-- Members show while their unit exists (secure unit watch, works in combat); in move
-- mode all four show as placeholders. The whole frame hides in raids unless enabled.
function M:ApplyVisibility()
	local unlocked = Grimoire.moversUnlocked
	for _, button in ipairs(self.members) do
		if unlocked then
			UnregisterUnitWatch(button)
			button:Show()
		else
			RegisterUnitWatch(button)
		end
	end
	if unlocked or self.db.showInRaid then
		UnregisterStateDriver(self.holder, "visibility")
		self.holder:Show()
	else
		RegisterStateDriver(self.holder, "visibility", "[group:raid] hide; show")
	end
	self:UpdateAll()
end

function M:ApplySettings(key)
	if not self.holder then return end
	if key == "showText" then
		for _, button in ipairs(self.members) do
			self:UpdateBars(button)
		end
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

-- ADR 0004: hide Blizzard's party frames (Classic: PartyMemberFrame1-4; newer: PartyFrame).
-- Their party-pet frames are children and go with them.
function M:HideBlizzard()
	if self.blizzardHidden then return end
	self.blizzardHidden = true
	for i = 1, MEMBERS do
		Grimoire:HideBlizzardFrame(_G["PartyMemberFrame" .. i])
	end
	Grimoire:HideBlizzardFrame(PartyFrame)
end

function M:Build()
	local holder = CreateFrame("Frame", "GrimoirePartyFrame", UIParent)
	self.holder = holder
	self.members = {}
	for i = 1, MEMBERS do
		self.members[i] = CreateMember(self, i)
	end
	self:ApplyLayout()
	self:RegisterMover(holder, "Party", { "TOPLEFT", "UIParent", "TOPLEFT", 20, -160 }, { dim = false })
end

-- Events ---------------------------------------------------------------------------------------

function M:OnUnitEvent(_, unit)
	local index = UNIT_INDEX[unit]
	if index then
		self:UpdateBars(self.members[index])
		Grimoire:NotifyMoverActivity(self.name)
	end
end

function M:OnUnitChanged(_, unit)
	local index = UNIT_INDEX[unit]
	if index then
		self:UpdateMember(self.members[index])
	end
end

function M:OnBindingsChanged()
	for _, button in ipairs(self.members) do
		self:UpdateBinding(button)
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
		for _, event in ipairs({ "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH",
			"UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
			self:RegisterEvent(event, "OnUnitEvent")
		end
		for _, event in ipairs({ "UNIT_PORTRAIT_UPDATE", "UNIT_NAME_UPDATE", "UNIT_CONNECTION", "UNIT_FLAGS" }) do
			self:RegisterEvent(event, "OnUnitChanged")
		end
		self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateAll")
		self:RegisterEvent("PARTY_MEMBERS_CHANGED", "UpdateAll") -- older clients
		self:RegisterEvent("PARTY_LEADER_CHANGED", "UpdateAll")
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAll")
		self:RegisterEvent("UPDATE_BINDINGS", "OnBindingsChanged")
		self:RegisterCallback("MoversUnlocked", "OnMoveMode")
		self:RegisterCallback("MoversLocked", "OnMoveMode")
		self.rangeTicker = C_Timer.NewTicker(RANGE_CHECK_SECONDS, function() self:UpdateRange() end)
		-- Last: hiding Blizzard's frames is the riskiest step, and events are already live.
		self:ApplySettings()
	end)
end

function M:OnDisable()
	if self.rangeTicker then
		self.rangeTicker:Cancel()
		self.rangeTicker = nil
	end
	Grimoire:RunOutOfCombat(function()
		if not self.holder or self:IsEnabled() then return end
		for _, button in ipairs(self.members) do
			UnregisterUnitWatch(button)
			button:Hide()
		end
		UnregisterStateDriver(self.holder, "visibility")
		self.holder:Hide()
	end)
	if self.blizzardHidden then
		self:Print("Type /reload to bring back Blizzard's party frames.")
	end
end

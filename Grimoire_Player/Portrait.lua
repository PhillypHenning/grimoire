local ADDON_NAME = ...
local Grimoire = Grimoire

-- Unit portraits for the player and the pet: a movable box with an animated 3D model
-- (or classic 2D portrait), name and level. They replace Blizzard's player and pet
-- frames, which they hide (ADR 0004); health and power are the separate bars in
-- Bars.lua. Each portrait is a secure unit button, so it's only created, sized or
-- moved out of combat.
--
-- Player:  left-click  menu: the micro-menu panels (Character Info ... Game Menu) + Grimoire
--          right-click Blizzard's player menu; emotes and status icons
-- Pet:     left-click  target the pet; right-click Blizzard's pet menu (rename, dismiss)

local EMOTE_SECONDS = 3
local ANIM_STAND, ANIM_WAVE, ANIM_CHEER, ANIM_LAUGH, ANIM_CRY = 0, 67, 68, 70, 77

-- Shared portrait -------------------------------------------------------------------------

local Portrait = {}

-- Right-click: the unit's Blizzard menu. Older clients use a UIDropDownMenu.
function Portrait:SetRightClickMenu(frame)
	local dropdown = self.blizzardDropDown and _G[self.blizzardDropDown]
	if dropdown and ToggleDropDownMenu then
		frame:SetAttribute("type2", "menu")
		frame.menu = function() ToggleDropDownMenu(1, nil, dropdown, "cursor", 0, 0) end
	else
		frame:SetAttribute("type2", "togglemenu")
	end
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

-- Builds the frame out of combat, then lets the module register its events.
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
		self:RegisterUnitEvents()
	end)
end

function Portrait:ShowFrame()
	self.frame:Show()
end

function Portrait:OnDisable()
	Grimoire:RunOutOfCombat(function()
		if self.frame and not self:IsEnabled() then
			if self.HideFrame then
				self:HideFrame()
			end
			self.frame:Hide()
		end
	end)
	if self.blizzardHidden then
		self:Print(("Type /reload to bring back Blizzard's %s."):format(self.blizzardLabel))
	end
end

local function NewPortrait(name, opts)
	local module = Grimoire:NewModule(name, {
		addon = ADDON_NAME,
		label = opts.label,
		defaults = {
			style = "animated",
			size = opts.size,
			showName = true,
			emotes = opts.emotes and true or nil,
			hideBlizzard = true,
		},
		options = opts.options,
	})
	for key, fn in pairs(Portrait) do
		module[key] = fn
	end
	for key, value in pairs(opts) do
		if key ~= "options" then
			module[key] = value
		end
	end
	return module
end

local function StyleOption()
	return { type = "choice", key = "style", label = "Portrait", values = {
		{ "animated", "Animated (3D)" }, { "classic", "Classic (2D)" },
	} }
end

-- Player ------------------------------------------------------------------------------------

local Player = NewPortrait("PlayerFrame", {
	label = "Player frame",
	unit = "player",
	size = 64,
	emotes = true,
	nameFont = "GameFontNormal",
	blizzardFrame = "PlayerFrame",
	blizzardDropDown = "PlayerFrameDropDown",
	blizzardLabel = "player frame",
	clickHelp = { "Left-click: menu", "Right-click: player options" },
	-- Left of the Health/Mana bars, top edges level.
	defaultPosition = { "TOPRIGHT", "UIParent", "CENTER", -118, -168 },
	options = {
		StyleOption(),
		{ type = "choice", key = "size", label = "Size", values = { { 48, "Small" }, { 64, "Medium" }, { 80, "Large" } } },
		{ type = "toggle", key = "showName", label = "Show name" },
		{ type = "toggle", key = "emotes", label = "Emotes (level up, death, party)" },
		{ type = "toggle", key = "hideBlizzard", label = "Hide Blizzard player frame", reload = true },
	},
})

-- Left-click menu: one entry per micro-menu button this client has. IsShown, not
-- IsVisible: entries stay after Grimoire hides the micro menu itself (the button keeps
-- its shown flag inside a hidden parent). Talents only shows from level 10.

local function ShowGameMenu()
	if GameMenuFrame:IsShown() then
		HideUIPanel(GameMenuFrame)
	else
		ShowUIPanel(GameMenuFrame)
	end
end

local MICRO_MENU = {
	{ "CharacterMicroButton", CHARACTER_BUTTON or "Character Info", function() ToggleCharacter("PaperDollFrame") end },
	{ "SpellbookMicroButton", SPELLBOOK_ABILITIES_BUTTON or "Spellbook & Abilities", function() ToggleSpellBook(BOOKTYPE_SPELL) end },
	{ "TalentMicroButton", TALENTS_BUTTON or "Talents", function() ToggleTalentFrame() end },
	{ "QuestLogMicroButton", QUESTLOG_BUTTON or "Quest Log", function() ToggleQuestLog() end },
	{ "SocialsMicroButton", SOCIAL_BUTTON or "Social", function() ToggleFriendsFrame() end },
	{ "GuildMicroButton", GUILD or "Guild" },
	{ "LFGMicroButton", DUNGEONS_BUTTON or "Group Finder" },
	{ "WorldMapMicroButton", WORLDMAP_BUTTON or "World Map", function() ToggleWorldMap() end },
	{ "MainMenuMicroButton", MAINMENU_BUTTON or "Game Menu", ShowGameMenu },
	{ "HelpMicroButton", HELP_BUTTON or "Help Request", function() ToggleHelpFrame() end },
}

function Player:GetClickMenu()
	local entries = { { text = UnitName("player"), isTitle = true } }
	for _, item in ipairs(MICRO_MENU) do
		local button = _G[item[1]]
		if button and button:IsShown() then
			-- Prefer the toggle function; clicking the micro button is the fallback.
			local open = item[3] or function() button:Click() end
			entries[#entries + 1] = { text = item[2], func = open, disabled = not button:IsEnabled() }
		end
	end
	entries[#entries + 1] = { isDivider = true }
	entries[#entries + 1] = { text = "Grimoire", children = Grimoire:GetMainMenu() }
	return entries
end

function Player:BuildExtras()
	local media = Grimoire.media
	-- No type1: the secure click does nothing, and the hook opens our menu.
	self.frame:HookScript("OnClick", function(b, mouseButton)
		if mouseButton == "LeftButton" then
			Grimoire.OpenMenu(b, self:GetClickMenu())
		end
	end)
	if self.model:HasScript("OnAnimFinished") then
		self.model:SetScript("OnAnimFinished", function(m)
			if self.emoting then
				self.emoting = nil
				m:SetAnimation(ANIM_STAND)
			end
		end)
	end

	local overlay = self.overlay
	self.stateIcon = overlay:CreateTexture(nil, "OVERLAY")
	self.stateIcon:SetTexture(media.stateIcon)
	self.stateIcon:SetSize(20, 20)
	self.stateIcon:SetPoint("TOPLEFT", -5, 5)

	self.leaderIcon = overlay:CreateTexture(nil, "OVERLAY")
	self.leaderIcon:SetTexture(media.leaderIcon)
	self.leaderIcon:SetSize(16, 16)
	self.leaderIcon:SetPoint("TOPRIGHT", 4, 4)

	self.pvpIcon = overlay:CreateTexture(nil, "OVERLAY")
	self.pvpIcon:SetTexCoord(0, 0.62, 0, 0.62)
	self.pvpIcon:SetSize(24, 24)
	self.pvpIcon:SetPoint("BOTTOMLEFT", -7, -7)
end

function Player:FormatName(name)
	local _, class = UnitClass("player")
	return Grimoire.ClassColorText(name, class)
end

-- On Classic the pet frame is a child of the player frame, so hiding one would hide
-- both. Unless the Pet frame module has already taken over, move it out first.
function Player:BeforeHideBlizzard()
	if PetFrame and PetFrame:GetParent() == PlayerFrame then
		local left, top = PetFrame:GetLeft(), PetFrame:GetTop()
		PetFrame:SetParent(UIParent)
		if left and top then
			PetFrame:ClearAllPoints()
			PetFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
	end
end

function Player:UpdateStatus()
	local coords
	if Grimoire:InCombat() then
		coords = Grimoire.media.stateIconCombat
	elseif IsResting() then
		coords = Grimoire.media.stateIconResting
	end
	if coords then
		self.stateIcon:SetTexCoord(unpack(coords))
	end
	self.stateIcon:SetShown(coords ~= nil)
	Grimoire:NotifyMoverActivity(self.name)
end

function Player:UpdateLeader()
	local isLeader = UnitIsGroupLeader and UnitIsGroupLeader("player") or (IsPartyLeader and IsPartyLeader())
	self.leaderIcon:SetShown(isLeader and true or false)
end

function Player:UpdatePvP()
	local suffix
	if UnitIsPVPFreeForAll("player") then
		suffix = "FFA"
	elseif UnitIsPVP("player") then
		suffix = UnitFactionGroup("player")
	end
	if suffix then
		self.pvpIcon:SetTexture(Grimoire.media.pvpIcon .. suffix)
	end
	self.pvpIcon:SetShown(suffix ~= nil)
end

function Player:UpdateExtras()
	self:UpdateStatus()
	self:UpdateLeader()
	self:UpdatePvP()
end

-- Emotes: played on the 3D model only. The model returns to standing when the
-- animation ends, or after EMOTE_SECONDS on clients without OnAnimFinished.

function Player:PlayEmote(animation)
	if not (self.db.emotes and self.db.style == "animated" and self.model:IsVisible()) then return end
	self.model:SetAnimation(animation)
	self.emoting = true
	local token = {}
	self.emoteToken = token
	C_Timer.After(EMOTE_SECONDS, function()
		if self.emoteToken == token and self.emoting then
			self.emoting = nil
			self.model:SetAnimation(ANIM_STAND)
		end
	end)
	Grimoire:NotifyMoverActivity(self.name)
end

local function GroupSize()
	return GetNumGroupMembers and GetNumGroupMembers() or (GetNumPartyMembers and GetNumPartyMembers()) or 0
end

function Player:OnLevelUp(_, level)
	self:UpdateLevel(level)
	self:PlayEmote(ANIM_CHEER)
end

function Player:OnDeath()
	self:PlayEmote(math.random(2) == 1 and ANIM_LAUGH or ANIM_CRY)
end

function Player:OnGroupChanged()
	local size = GroupSize()
	if size > (self.groupSize or size) then
		self:PlayEmote(ANIM_WAVE)
	end
	self.groupSize = size
	self:UpdateLeader()
end

function Player:OnPetChanged()
	local hasPet = UnitExists("pet")
	if hasPet and not self.hadPet then
		self:PlayEmote(ANIM_WAVE)
	end
	self.hadPet = hasPet
end

function Player:RegisterUnitEvents()
	self.groupSize = GroupSize()
	self.hadPet = UnitExists("pet")
	self:RegisterEvent("PLAYER_LEVEL_UP", "OnLevelUp")
	self:RegisterEvent("PLAYER_UPDATE_RESTING", "UpdateStatus")
	self:RegisterEvent("PLAYER_DEAD", "OnDeath")
	self:RegisterEvent("PLAYER_ALIVE", "UpdatePortrait")
	self:RegisterEvent("PLAYER_UNGHOST", "UpdatePortrait")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupChanged")
	self:RegisterEvent("PARTY_MEMBERS_CHANGED", "OnGroupChanged") -- older clients
	self:RegisterEvent("PARTY_LEADER_CHANGED", "UpdateLeader")
	self:RegisterUnitEvent("UNIT_FACTION", "player", "UpdatePvP")
	self:RegisterUnitEvent("UNIT_PET", "player", "OnPetChanged")
	self:RegisterCallback("CombatStart", "UpdateStatus")
	self:RegisterCallback("CombatEnd", "UpdateStatus")
end

-- Pet ------------------------------------------------------------------------------------------

local Pet = NewPortrait("PetFrame", {
	label = "Pet frame",
	unit = "pet",
	size = 48,
	nameFont = "GameFontNormalSmall",
	blizzardFrame = "PetFrame",
	blizzardDropDown = "PetFrameDropDown",
	blizzardLabel = "pet frame",
	clickHelp = { "Left-click: target", "Right-click: pet options" },
	-- Left of the pet bars, under the player frame.
	defaultPosition = { "TOPRIGHT", "UIParent", "CENTER", -118, -250 },
	options = {
		StyleOption(),
		{ type = "choice", key = "size", label = "Size", values = { { 36, "Small" }, { 48, "Medium" }, { 64, "Large" } } },
		{ type = "toggle", key = "showName", label = "Show name" },
		{ type = "toggle", key = "hideBlizzard", label = "Hide Blizzard pet frame", reload = true },
	},
})

function Pet:BuildExtras()
	self.frame:SetAttribute("type1", "target")
end

-- The pet comes and goes, in combat too, so a secure state driver shows the frame
-- while the pet exists. In move mode it stays shown so it can be placed.
function Pet:ShowFrame()
	if Grimoire.moversUnlocked then
		UnregisterUnitWatch(self.frame)
		self.frame:Show()
	else
		RegisterUnitWatch(self.frame)
	end
end

function Pet:HideFrame()
	UnregisterUnitWatch(self.frame)
end

function Pet:OnMoveMode()
	Grimoire:RunOutOfCombat(function()
		if self:IsEnabled() then
			self:ShowFrame()
		end
	end)
end

function Pet:OnPetChanged()
	self:UpdateAll()
end

function Pet:RegisterUnitEvents()
	self:RegisterUnitEvent("UNIT_PET", "player", "OnPetChanged")
	self:RegisterCallback("MoversUnlocked", "OnMoveMode")
	self:RegisterCallback("MoversLocked", "OnMoveMode")
end

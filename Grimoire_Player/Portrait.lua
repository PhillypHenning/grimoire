local ADDON_NAME = ...
local Grimoire = Grimoire

-- Grimoire's player frame, built on core's unit portrait (Core/UnitFrames.lua): an
-- animated 3D model (or classic 2D portrait) with name, level and status icons. It
-- replaces Blizzard's player frame, which it hides (ADR 0004); health and mana are the
-- separate bars in Bars.lua.
--   Left-click   menu: the micro-menu panels (Character Info ... Game Menu) + Grimoire
--   Right-click  Blizzard's player menu (loot, leave party, ...)

local EMOTE_SECONDS = 3
local ANIM_STAND, ANIM_WAVE, ANIM_CHEER, ANIM_LAUGH, ANIM_CRY = 0, 67, 68, 70, 77

local Player = Grimoire:NewUnitPortrait("PlayerFrame", {
	addon = ADDON_NAME,
	label = "Player frame",
	unit = "player",
	size = 64,
	extraDefaults = { emotes = true },
	nameFont = "GameFontNormal",
	blizzardFrame = "PlayerFrame",
	blizzardDropDown = "PlayerFrameDropDown",
	blizzardLabel = "player frame",
	clickHelp = { "Left-click: menu", "Right-click: player options" },
	-- Left of the Health/Mana bars, top edges level.
	defaultPosition = { "TOPRIGHT", "UIParent", "CENTER", -118, -168 },
	options = {
		Grimoire.UnitPortraitStyleOption(),
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
-- both. Unless Grimoire_Pet has already hidden it, move it out first.
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

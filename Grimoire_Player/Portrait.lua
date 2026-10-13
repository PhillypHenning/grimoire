local ADDON_NAME = ...
local Grimoire = Grimoire

-- Grimoire's player frame: a movable portrait (animated 3D model or classic 2D) with
-- name, level and status icons. It replaces Blizzard's player frame, which it hides
-- (ADR 0004); health and mana are the separate Health/Power bars.
--   Left-click   menu: the micro-menu panels (Character Info ... Game Menu) + Grimoire
--   Right-click  Blizzard's player menu (loot, leave party, ...)
-- The frame is a secure unit button, so it's only created, sized or moved out of combat.

local EMOTE_SECONDS = 3
local ANIM_STAND, ANIM_WAVE, ANIM_CHEER, ANIM_LAUGH, ANIM_CRY = 0, 67, 68, 70, 77

local M = Grimoire:NewModule("PlayerFrame", {
	addon = ADDON_NAME,
	label = "Player frame",
	defaults = {
		style = "animated",
		size = 64,
		showName = true,
		emotes = true,
		hideBlizzard = true,
	},
	options = {
		{ type = "choice", key = "style", label = "Portrait", values = {
			{ "animated", "Animated (3D)" }, { "classic", "Classic (2D)" },
		} },
		{ type = "choice", key = "size", label = "Size", values = { { 48, "Small" }, { 64, "Medium" }, { 80, "Large" } } },
		{ type = "toggle", key = "showName", label = "Show name" },
		{ type = "toggle", key = "emotes", label = "Emotes (level up, death, party)" },
		{ type = "toggle", key = "hideBlizzard", label = "Hide Blizzard player frame", reload = true },
	},
})

-- Left-click menu ------------------------------------------------------------------------
-- One entry per micro-menu button this client has. IsShown, not IsVisible: the entry
-- stays even after Grimoire hides the micro menu itself (the button keeps its shown
-- flag inside a hidden parent). Talents only shows once the button does (level 10).

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

function M:GetClickMenu()
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

-- Frame ------------------------------------------------------------------------------------

local function SetRightClickMenu(frame)
	if PlayerFrameDropDown and ToggleDropDownMenu then
		-- Older clients: Blizzard's UIDropDownMenu player menu.
		frame:SetAttribute("type2", "menu")
		frame.menu = function() ToggleDropDownMenu(1, nil, PlayerFrameDropDown, "cursor", 0, 0) end
	else
		frame:SetAttribute("type2", "togglemenu")
	end
end

function M:Build()
	local media = Grimoire.media
	local frame = CreateFrame("Button", "GrimoirePlayerFrame", UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
	frame:SetAttribute("unit", "player")
	frame:RegisterForClicks("AnyUp")
	SetRightClickMenu(frame)
	-- No type1: the secure click does nothing, and the hook opens our menu.
	frame:HookScript("OnClick", function(b, mouseButton)
		if mouseButton == "LeftButton" then
			Grimoire.OpenMenu(b, self:GetClickMenu())
		end
	end)
	frame:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetUnit("player")
		GameTooltip:AddLine("Left-click: menu", 1, 1, 1)
		GameTooltip:AddLine("Right-click: player options", 1, 1, 1)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	Grimoire.ApplyClassicBackdrop(frame)
	self.frame = frame

	local inset = media.classicInset
	local model = CreateFrame("PlayerModel", nil, frame)
	model:SetPoint("TOPLEFT", inset, -inset)
	model:SetPoint("BOTTOMRIGHT", -inset, inset)
	model:SetScript("OnShow", function() self:UpdatePortrait() end)
	if model:HasScript("OnAnimFinished") then
		model:SetScript("OnAnimFinished", function(m)
			if self.emoting then
				self.emoting = nil
				m:SetAnimation(ANIM_STAND)
			end
		end)
	end
	self.model = model

	local portrait = frame:CreateTexture(nil, "ARTWORK")
	portrait:SetPoint("TOPLEFT", inset, -inset)
	portrait:SetPoint("BOTTOMRIGHT", -inset, inset)
	self.portrait = portrait

	-- Text and icons sit on a frame above the model, which draws over its parent.
	local overlay = CreateFrame("Frame", nil, frame)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(model:GetFrameLevel() + 2)

	self.nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	self.nameText:SetPoint("BOTTOM", frame, "TOP", 0, 2)

	self.levelText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.levelText:SetPoint("BOTTOMRIGHT", -inset - 1, inset + 1)

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

	self:ApplySettings()
	-- Left of the Health/Mana bars, top edges level.
	self:RegisterMover(frame, "Player frame", { "TOPRIGHT", "UIParent", "CENTER", -118, -168 }, {
		dim = true,
		isBusy = function() return Grimoire:InCombat() end,
	})
end

function M:ApplySettings()
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
		self:HideBlizzardPlayerFrame()
	end
end

-- Hides Blizzard's player frame, its health and mana bars included. On Classic the pet
-- frame is a child of it, so the pet frame is first moved to UIParent at the same spot.
function M:HideBlizzardPlayerFrame()
	if self.blizzardHidden or not PlayerFrame then return end
	self.blizzardHidden = true
	Grimoire:RunOutOfCombat(function()
		if PetFrame and PetFrame:GetParent() == PlayerFrame then
			local left, top = PetFrame:GetLeft(), PetFrame:GetTop()
			PetFrame:SetParent(UIParent)
			if left and top then
				PetFrame:ClearAllPoints()
				PetFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			end
		end
		Grimoire:HideBlizzardFrame(PlayerFrame)
	end)
end

-- Display ------------------------------------------------------------------------------------

function M:UpdatePortrait()
	if self.db.style == "animated" then
		self.model:SetUnit("player")
		self.model:SetPortraitZoom(1)
		self.emoting = nil
	else
		SetPortraitTexture(self.portrait, "player")
	end
	Grimoire:NotifyMoverActivity(self.name)
end

function M:UpdateName()
	local _, class = UnitClass("player")
	self.nameText:SetText(Grimoire.ClassColorText(UnitName("player"), class))
end

function M:UpdateLevel(level)
	self.levelText:SetText(level or UnitLevel("player"))
end

function M:UpdateStatus()
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

function M:UpdateLeader()
	local isLeader = UnitIsGroupLeader and UnitIsGroupLeader("player") or (IsPartyLeader and IsPartyLeader())
	self.leaderIcon:SetShown(isLeader and true or false)
end

function M:UpdatePvP()
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

function M:UpdateAll()
	self:UpdatePortrait()
	self:UpdateName()
	self:UpdateLevel()
	self:UpdateStatus()
	self:UpdateLeader()
	self:UpdatePvP()
end

-- Emotes ----------------------------------------------------------------------------------------
-- Played on the 3D model only. The model returns to standing when the animation ends,
-- or after EMOTE_SECONDS on clients without OnAnimFinished.

function M:PlayEmote(animation)
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

function M:OnLevelUp(_, level)
	self:UpdateLevel(level)
	self:PlayEmote(ANIM_CHEER)
end

function M:OnDeath()
	self:PlayEmote(math.random(2) == 1 and ANIM_LAUGH or ANIM_CRY)
end

function M:OnGroupChanged()
	local size = GroupSize()
	if size > (self.groupSize or size) then
		self:PlayEmote(ANIM_WAVE)
	end
	self.groupSize = size
	self:UpdateLeader()
end

function M:OnPetChanged()
	local hasPet = UnitExists("pet")
	if hasPet and not self.hadPet then
		self:PlayEmote(ANIM_WAVE)
	end
	self.hadPet = hasPet
end

-- Lifecycle --------------------------------------------------------------------------------------

function M:OnEnable()
	Grimoire:RunOutOfCombat(function()
		if not self:IsEnabled() then return end
		if not self.frame then
			self:Build()
		end
		self.frame:Show()
		self.groupSize = GroupSize()
		self.hadPet = UnitExists("pet")
		self:UpdateAll()

		self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAll")
		self:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", "player", "UpdatePortrait")
		self:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player", "UpdatePortrait")
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
	end)
end

function M:OnDisable()
	Grimoire:RunOutOfCombat(function()
		if self.frame and not self:IsEnabled() then
			self.frame:Hide()
		end
	end)
	if self.blizzardHidden then
		self:Print("Type /reload to bring back Blizzard's player frame.")
	end
end

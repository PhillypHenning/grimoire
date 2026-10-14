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

-- Left-click menu: one entry per micro-menu button this client actually has, in its
-- on-screen order. Found at runtime, so Forever's own buttons (Legacy, Shop, its Group
-- Finder) appear without being listed here. IsShown, not IsVisible: entries stay after
-- Grimoire hides the micro menu itself. Talents only shows from level 10.

local function ShowGameMenu()
	if GameMenuFrame:IsShown() then
		HideUIPanel(GameMenuFrame)
	else
		ShowUIPanel(GameMenuFrame)
	end
end

-- Known buttons: a nicer label and a direct toggle (function or global name, argument).
-- Toggles are looked up when clicked; Forever lacks some (no ToggleSpellBook), and a
-- missing or failing one falls back to clicking the button, as does every unknown one.
local KNOWN = {
	CharacterMicroButton = { CHARACTER_BUTTON, "ToggleCharacter", "PaperDollFrame" },
	SpellbookMicroButton = { SPELLBOOK_ABILITIES_BUTTON, "ToggleSpellBook", BOOKTYPE_SPELL },
	TalentMicroButton = { TALENTS_BUTTON, "ToggleTalentFrame" },
	QuestLogMicroButton = { QUESTLOG_BUTTON, "ToggleQuestLog" },
	SocialsMicroButton = { SOCIAL_BUTTON, "ToggleFriendsFrame" },
	WorldMapMicroButton = { WORLDMAP_BUTTON, "ToggleWorldMap" },
	MainMenuMicroButton = { MAINMENU_BUTTON, ShowGameMenu },
	HelpMicroButton = { HELP_BUTTON, "ToggleHelpFrame" },
}

-- Older clients' fixed list, used only if the client has no list or container.
local FALLBACK_NAMES = {
	"CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
	"SocialsMicroButton", "GuildMicroButton", "LFGMicroButton", "WorldMapMicroButton",
	"MainMenuMicroButton", "HelpMicroButton",
}

local function MicroButtons()
	local buttons = {}
	if type(MICRO_BUTTONS) == "table" then
		for _, name in ipairs(MICRO_BUTTONS) do
			if _G[name] then buttons[#buttons + 1] = _G[name] end
		end
	end
	local container = MicroMenu or MicroMenuContainer
	if #buttons == 0 and container then
		for _, child in ipairs({ container:GetChildren() }) do
			if child:IsObjectType("Button") then buttons[#buttons + 1] = child end
		end
		table.sort(buttons, function(a, b) return (a:GetLeft() or 0) < (b:GetLeft() or 0) end)
	end
	if #buttons == 0 then
		for _, name in ipairs(FALLBACK_NAMES) do
			if _G[name] then buttons[#buttons + 1] = _G[name] end
		end
	end
	return buttons
end

-- "Character Info |cffffd200(C)|r" -> "Character Info"; else the frame name, spaced.
local function MicroLabel(button)
	local name = button:GetName() or ""
	local known = KNOWN[name]
	if known and known[1] then return known[1] end
	local text = button.tooltipText
	if type(text) == "string" and text ~= "" then
		text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s*%(.-%)%s*$", "")
		if text ~= "" then return text end
	end
	return (name:gsub("MicroButton$", ""):gsub("(%l)(%u)", "%1 %2"))
end

local function OpenMicro(button)
	local known = KNOWN[button:GetName() or ""]
	local toggle = known and known[2]
	if type(toggle) == "string" then
		toggle = _G[toggle]
	end
	if not (toggle and pcall(toggle, known[3])) then
		button:Click()
	end
end

function Player:GetClickMenu()
	local entries = { { text = UnitName("player"), isTitle = true } }
	for _, button in ipairs(MicroButtons()) do
		if button:IsShown() then
			entries[#entries + 1] = {
				text = MicroLabel(button),
				func = function() OpenMicro(button) end,
				disabled = not button:IsEnabled(),
			}
		end
	end
	entries[#entries + 1] = { isDivider = true }
	-- Other add-ons' minimap buttons (Core/AddOnButtons.lua).
	entries[#entries + 1] = { text = ADDONS or "Add-ons", children = Grimoire:GetAddOnButtonMenu() }
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

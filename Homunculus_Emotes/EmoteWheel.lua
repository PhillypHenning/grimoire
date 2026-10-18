local ADDON_NAME = ...
local Homunculus = Homunculus

-- The emote wheel (Phil, 2026-10-16): hold its key (Key Bindings ▸ Homunculus ▸ Emote wheel)
-- and a ring of emotes opens at the mouse; point toward one and let go to do it. Letting
-- go near the centre does nothing. /hom emotes opens the wheel without the key: click an
-- emote, or press Esc to close it. Emotes go to your target when you have one, like the
-- chat commands ("You wave at ...").

local RADIUS = 92        -- centre of the wheel to the centre of each emote
local SLICE_SIZE = 40
local DEAD_ZONE = 26     -- the pointer this close to the centre picks nothing
local atan2 = math.atan2 or math.atan -- Lua 5.1 has atan2; later versions take two arguments to atan

-- { emote token (DoEmote), label, icon }. First at the top, then clockwise.
local EMOTES = {
	{ "WAVE", "Wave", "Interface\\Icons\\INV_Gauntlets_04" },
	{ "CHEER", "Cheer", "Interface\\Icons\\Ability_Warrior_BattleShout" },
	{ "DANCE", "Dance", "Interface\\Icons\\Ability_Rogue_Sprint" },
	{ "LAUGH", "Laugh", "Interface\\Icons\\Spell_Nature_Polymorph" },
	{ "BOW", "Bow", "Interface\\Icons\\Spell_Holy_HolyBolt" },
	{ "THANK", "Thank", "Interface\\Icons\\INV_Misc_Gift_01" },
	{ "CRY", "Cry", "Interface\\Icons\\Spell_Frost_FrostShock" },
	{ "ROAR", "Roar", "Interface\\Icons\\Ability_Druid_DemoralizingRoar" },
}

local M = Homunculus:NewModule("EmoteWheel", {
	addon = ADDON_NAME,
	label = "Emote wheel",
})

-- Names in Key Bindings.
BINDING_HEADER_HOMUNCULUS = "Homunculus"
BINDING_NAME_HOMUNCULUS_EMOTE_WHEEL = "Emote wheel (hold)"

-- Frame ------------------------------------------------------------------------------------

function M:Build()
	local size = (RADIUS + SLICE_SIZE) * 2
	local wheel = CreateFrame("Frame", "HomunculusEmoteWheel", UIParent)
	wheel:SetSize(size, size)
	wheel:SetFrameStrata("DIALOG")
	wheel:SetClampedToScreen(true)
	wheel:Hide()
	self.wheel = wheel

	-- A faint disc behind the ring, from the minimap button's own background art.
	local disc = wheel:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(Homunculus.media.roundButtonBackground)
	disc:SetSize(RADIUS * 2 + SLICE_SIZE, RADIUS * 2 + SLICE_SIZE)
	disc:SetPoint("CENTER")
	disc:SetAlpha(0.55)

	wheel.label = wheel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	wheel.label:SetPoint("CENTER")

	wheel.slices = {}
	local step = 2 * math.pi / #EMOTES
	for i, emote in ipairs(EMOTES) do
		local angle = math.pi / 2 - (i - 1) * step
		local slice = Homunculus.CreateRoundButton(nil, wheel, SLICE_SIZE)
		slice:SetFrameStrata("DIALOG")
		slice:SetPoint("CENTER", wheel, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
		slice.icon:SetTexture(emote[3])
		slice.name = slice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		slice.name:SetPoint("TOP", slice, "BOTTOM", 0, -1)
		slice.name:SetText(emote[2])
		slice:SetScript("OnClick", function() self:Do(i) end)
		wheel.slices[i] = slice
	end

	wheel:SetScript("OnUpdate", function() self:Track() end)
	wheel:SetScript("OnHide", function() self:Pick(nil) end)
	tinsert(UISpecialFrames, wheel:GetName()) -- Esc closes it
end

-- The emote the pointer is aiming at: by angle from the centre, outside the dead zone.
function M:Track()
	local wheel = self.wheel
	local x, y = GetCursorPosition()
	local scale = wheel:GetEffectiveScale()
	local cx, cy = wheel:GetCenter()
	local dx, dy = x / scale - cx, y / scale - cy
	if dx * dx + dy * dy < DEAD_ZONE * DEAD_ZONE then
		self:Pick(nil)
		return
	end
	local step = 2 * math.pi / #EMOTES
	local index = math.floor((math.pi / 2 - atan2(dy, dx)) / step + 0.5) % #EMOTES + 1
	self:Pick(index)
end

function M:Pick(index)
	if index == self.picked then return end
	local slices = self.wheel.slices
	if self.picked then slices[self.picked]:UnlockHighlight() end
	if index then slices[index]:LockHighlight() end
	self.picked = index
	self.wheel.label:SetText(index and EMOTES[index][2] or "")
end

-- Opening and choosing ---------------------------------------------------------------------

function M:Open(held)
	if not self.wheel then self:Build() end
	local x, y = GetCursorPosition()
	local scale = UIParent:GetEffectiveScale()
	self.wheel:ClearAllPoints()
	self.wheel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	self.held = held
	self.wheel:Show()
end

-- Key released: do the emote being pointed at, if any.
function M:Release()
	if not self.held or not self.wheel then return end
	self.held = false
	local picked = self.picked
	self.wheel:Hide()
	if picked then self:Do(picked) end
end

function M:Do(index)
	self.wheel:Hide()
	DoEmote(EMOTES[index][1])
end

-- Called by the key binding (Bindings.xml) with "down" or "up".
function HomunculusEmoteWheel_OnKey(keystate)
	if not M:IsEnabled() then return end
	if keystate == "down" then
		M:Open(true)
	else
		M:Release()
	end
end

-- Lifecycle ----------------------------------------------------------------------------------

function M:Toggle()
	if self.wheel and self.wheel:IsShown() then
		self.wheel:Hide()
	else
		self:Open(false)
	end
end

function M:OnInitialize()
	Homunculus:RegisterCommand("emotes", "emotes - open the emote wheel (or hold its key: Key Bindings, Homunculus)", function()
		if self:IsEnabled() then self:Toggle() end
	end)
end

function M:OnDisable()
	if self.wheel then self.wheel:Hide() end
end

local ADDON_NAME = ...
local Grimoire = Grimoire

-- Blizzard's own buff and debuff frames, made into Grimoire movers: drag, group,
-- dim and scale them like any other frame. Forever has no SecureAuraHeaderTemplate,
-- so building our own buttons would lose right-click-to-cancel in combat. Keeping
-- Blizzard's buttons keeps it (and weapon enchants, tooltips, timers) exactly as is.
--
-- Each Blizzard frame is reparented to a Grimoire holder (so it follows the holder's
-- position and alpha) and pinned to the holder's top-right corner. If Blizzard
-- re-anchors it later, the SetPoint hook pins it back.

local ICON_STEP = 35 -- roughly one Blizzard aura button plus its gap
local ROW_HEIGHT = 50 -- icon plus the duration text under it

local Aura = {}

function Aura:IsAvailable()
	if not self:GetBlizzardFrames()[1] then
		return false, self.missingReason
	end
	return true
end

function Aura:GetBlizzardFrames()
	local frames = {}
	for _, name in ipairs(self.frameNames) do
		if _G[name] then
			frames[#frames + 1] = _G[name]
		end
	end
	return frames
end

function Aura:Pin(frame)
	frame:SetParent(self.holder)
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", self.holder, "TOPRIGHT")
end

function Aura:Build()
	-- The holder only gives the mover a size; Blizzard lays out the buttons.
	local holder = CreateFrame("Frame", "Grimoire" .. self.name .. "Holder", UIParent)
	self.holder = holder
	self:ApplySettings()
	self:RegisterMover(holder, self.label, self.defaultPosition)

	for _, frame in ipairs(self:GetBlizzardFrames()) do
		self:Pin(frame)
		hooksecurefunc(frame, "SetPoint", function(f, _, relativeTo)
			if self:IsEnabled() and relativeTo ~= self.holder then
				self:Pin(f)
			end
		end)
	end
end

-- Scale goes on Blizzard's frames, not the holder: the holder's position is saved
-- in its own units, so scaling it would move it.
function Aura:ApplySettings()
	local scale = self.db.scale
	self.holder:SetSize(BUFFS_PER_ROW and BUFFS_PER_ROW * ICON_STEP * scale or 280 * scale, self.rows * ROW_HEIGHT * scale)
	for _, frame in ipairs(self:GetBlizzardFrames()) do
		frame:SetScale(scale)
	end
end

function Aura:OnUnitAura()
	Grimoire:NotifyMoverActivity(self.name)
end

function Aura:OnEnable()
	if not self.holder then
		self:Build()
	end
	self.holder:Show()
	for _, frame in ipairs(self:GetBlizzardFrames()) do
		self:Pin(frame)
	end
	self:RegisterUnitEvent("UNIT_AURA", "player", "OnUnitAura")
end

function Aura:OnDisable()
	self.holder:Hide()
	self:Print("Type /reload to put the default buff frame back in its place.")
end

local function NewAuraModule(name, label, frameNames, rows, missingReason, defaultPosition)
	local module = Grimoire:NewModule(name, {
		addon = ADDON_NAME,
		label = label,
		defaults = { scale = 1 },
		options = {
			{ type = "choice", key = "scale", label = "Size", tooltip = "How large the buff and debuff icons are.", values = {
				{ 0.8, "Small" }, { 1, "Normal" }, { 1.2, "Large" }, { 1.4, "Huge" },
			} },
		},
	})
	for key, fn in pairs(Aura) do
		module[key] = fn
	end
	module.frameNames, module.rows, module.missingReason = frameNames, rows, missingReason
	module.defaultPosition = defaultPosition
	return module
end

-- Newer clients give debuffs their own DebuffFrame. On Classic they're laid out
-- inside BuffFrame, under the buffs, so they move with Buffs.
local separateDebuffs = DebuffFrame ~= nil

-- Default spots match Blizzard's, next to the minimap.
NewAuraModule("Buffs", separateDebuffs and "Buffs" or "Buffs and debuffs",
	{ "BuffFrame", "TemporaryEnchantFrame" }, separateDebuffs and 2 or 3, "no BuffFrame on this client",
	{ "TOPRIGHT", "UIParent", "TOPRIGHT", -180, -13 })
NewAuraModule("Debuffs", "Debuffs", { "DebuffFrame" }, 1, "debuffs move with Buffs on this client",
	{ "TOPRIGHT", "UIParent", "TOPRIGHT", -180, -110 })

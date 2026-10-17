local ADDON_NAME = ...
local Grimoire = Grimoire

-- Forever uses classic-era rules: soul shards are bag items, not a power type.
local SOUL_SHARD_ITEM = 6265
local SOUL_SHARD_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"

-- Warlock class resources: a soul shard icon with the count beside it.
-- Health and mana live in Grimoire_Player; group them in move mode to move together.
local M = Grimoire:NewModule("WarlockResources", {
	addon = ADDON_NAME,
	label = "Warlock Resources",
	class = "WARLOCK",
	defaults = {
		iconSize = 26,
	},
	options = {
		{ type = "choice", key = "iconSize", label = "Icon size", tooltip = "How large the soul shard icons are.", values = {
			{ 20, "Small" }, { 26, "Medium" }, { 32, "Large" },
		} },
	},
})

local COUNT_WIDTH = 30

function M:Build()
	local frame = CreateFrame("Frame", "GrimoireWarlockResources", UIParent)
	self.frame = frame

	self.icon = frame:CreateTexture(nil, "ARTWORK")
	self.icon:SetPoint("LEFT")
	self.icon:SetTexture(C_Item.GetItemIconByID(SOUL_SHARD_ITEM) or SOUL_SHARD_ICON_FALLBACK)

	self.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	self.count:SetPoint("LEFT", self.icon, "RIGHT", 4, 0)

	self:ApplySettings()
	self:RegisterMover(frame, "Warlock Resources",
		{ "TOPLEFT", "UIParent", "CENTER", -114, -216 }, { dim = true })
end

function M:ApplySettings()
	local size = self.db.iconSize
	self.frame:SetSize(size + 4 + COUNT_WIDTH, size)
	self.icon:SetSize(size, size)
end

function M:UpdateShards()
	local count = C_Item.GetItemCount(SOUL_SHARD_ITEM)
	self.count:SetText(count)
	if Grimoire.IsSecret(count) then
		-- Can't compare a secret: leave the icon lit and treat it as a change.
		self.icon:SetDesaturated(false)
		Grimoire:NotifyMoverActivity("WarlockResources")
		return
	end
	self.icon:SetDesaturated(count == 0)
	if count ~= self.lastCount then
		self.lastCount = count
		Grimoire:NotifyMoverActivity("WarlockResources")
	end
end

function M:OnEnable()
	if not self.frame then
		self:Build()
	end
	self.frame:Show()
	self:RegisterEvent("BAG_UPDATE_DELAYED", "UpdateShards")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateShards")
	self:UpdateShards()
end

function M:OnDisable()
	self.frame:Hide()
end

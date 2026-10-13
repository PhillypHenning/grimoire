local Grimoire = Grimoire

-- Forever uses classic-era rules: soul shards are bag items, not a power type.
local SOUL_SHARD_ITEM = 6265
local SOUL_SHARD_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
local POWER_MANA = Enum.PowerType.Mana

local M = Grimoire:NewModule("WarlockResourceBar", {
	class = "WARLOCK",
	defaults = {
		width = 220,
		manaHeight = 12,
		shardSlots = 10, -- icons shown; the exact count is always shown as text
		shardSpacing = 2,
		showManaText = true,
		alphaInCombat = 1,
		alphaOutOfCombat = 0.4,
		manaColor = { r = 0, g = 0, b = 1 }, -- classic mana blue
	},
})

function M:Build()
	local db = self.db
	local inset = Grimoire.media.classicInset
	local shardSize = (db.width - (db.shardSlots - 1) * db.shardSpacing) / db.shardSlots

	local frame = CreateFrame("Frame", "GrimoireWarlockResourceBar", UIParent)
	frame:SetSize(db.width + inset * 2, db.manaHeight + inset * 2 + db.shardSpacing + shardSize)
	self.frame = frame

	local manaBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	manaBorder:SetPoint("TOPLEFT")
	manaBorder:SetPoint("TOPRIGHT")
	manaBorder:SetHeight(db.manaHeight + inset * 2)
	Grimoire.ApplyClassicBackdrop(manaBorder)

	local mana = CreateFrame("StatusBar", nil, manaBorder)
	mana:SetPoint("TOPLEFT", inset, -inset)
	mana:SetPoint("BOTTOMRIGHT", -inset, inset)
	mana:SetStatusBarTexture(Grimoire.media.statusbar)
	mana:SetStatusBarColor(db.manaColor.r, db.manaColor.g, db.manaColor.b)
	mana.text = mana:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	mana.text:SetPoint("CENTER")
	self.mana = mana

	local icon = C_Item.GetItemIconByID(SOUL_SHARD_ITEM) or SOUL_SHARD_ICON_FALLBACK
	self.shards = {}
	for i = 1, db.shardSlots do
		local shard = frame:CreateTexture(nil, "ARTWORK")
		shard:SetTexture(icon)
		shard:SetSize(shardSize, shardSize)
		shard:SetPoint("TOPLEFT", manaBorder, "BOTTOMLEFT", inset + (i - 1) * (shardSize + db.shardSpacing), -db.shardSpacing)
		self.shards[i] = shard
	end

	self.shardText = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	self.shardText:SetPoint("LEFT", self.shards[db.shardSlots], "RIGHT", 4, 0)

	Grimoire:RegisterMover(frame, "WarlockResourceBar", "Warlock Resources", { "CENTER", "UIParent", "CENTER", 0, -200 })
end

function M:UpdateMana()
	local current, max = UnitPower("player", POWER_MANA), UnitPowerMax("player", POWER_MANA)
	local bar = self.mana
	-- StatusBar accepts secret values directly.
	bar:SetMinMaxValues(0, max)
	bar:SetValue(current)

	if not self.db.showManaText then
		bar.text:SetText("")
	elseif Grimoire.AnySecret(current, max) then
		-- Can't divide secrets into a percentage; let the widget render the raw value.
		bar.text:SetText(current)
	else
		bar.text:SetFormattedText("%d%%", max > 0 and math.floor(current / max * 100) or 0)
	end
end

local function SetShardFilled(shard, filled)
	shard:SetDesaturated(not filled)
	shard:SetAlpha(filled and 1 or 0.35)
end

function M:UpdateShards()
	local count = C_Item.GetItemCount(SOUL_SHARD_ITEM)
	self.shardText:SetText(count)

	if Grimoire.IsSecret(count) then
		-- Lighting individual icons needs comparisons, which secrets forbid.
		for _, shard in ipairs(self.shards) do
			SetShardFilled(shard, false)
		end
		return
	end

	for i, shard in ipairs(self.shards) do
		SetShardFilled(shard, i <= count)
	end
end

function M:UpdateVisibility()
	local alpha
	if Grimoire.moversUnlocked then
		alpha = 1
	elseif Grimoire:InCombat() then
		alpha = self.db.alphaInCombat
	else
		alpha = self.db.alphaOutOfCombat
	end
	self.frame:SetAlpha(alpha)
end

function M:Refresh()
	self:UpdateMana()
	self:UpdateShards()
	self:UpdateVisibility()
end

function M:OnPowerEvent(_, _, powerType)
	if powerType == "MANA" then
		self:UpdateMana()
	end
end

function M:OnEnable()
	if not self.frame then
		self:Build()
	end
	self.frame:Show()

	self:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "OnPowerEvent")
	self:RegisterUnitEvent("UNIT_MAXPOWER", "player", "OnPowerEvent")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "UpdateShards")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")

	self:RegisterCallback("CombatStart", "UpdateVisibility")
	self:RegisterCallback("CombatEnd", "UpdateVisibility")
	self:RegisterCallback("MoversUnlocked", "UpdateVisibility")
	self:RegisterCallback("MoversLocked", "UpdateVisibility")

	self:Refresh()
end

function M:OnDisable()
	self.frame:Hide()
end

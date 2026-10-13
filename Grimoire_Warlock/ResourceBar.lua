local Grimoire = Grimoire

-- Forever uses classic-era rules: soul shards are bag items, not a power type.
local SOUL_SHARD_ITEM = 6265
local SOUL_SHARD_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
local POWER_MANA = Enum.PowerType.Mana

-- Classic player frame health green.
local HEALTH_COLOR = { r = 0, g = 1, b = 0 }

local M = Grimoire:NewModule("WarlockResourceBar", {
	class = "WARLOCK",
	defaults = {
		width = 220,
		healthHeight = 16,
		manaHeight = 12,
		barSpacing = 2,
		shardSize = 26,
		showBarText = true,
		alphaWhenFull = 0.4, -- a full bar fades out of combat; anything else stays bright
		manaColor = { r = 0, g = 0, b = 1 }, -- classic mana blue
	},
})

local function CreateBar(parent, height, color)
	local inset = Grimoire.media.classicInset
	local border = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	border:SetHeight(height + inset * 2)
	Grimoire.ApplyClassicBackdrop(border)

	local bar = CreateFrame("StatusBar", nil, border)
	bar:SetPoint("TOPLEFT", inset, -inset)
	bar:SetPoint("BOTTOMRIGHT", -inset, inset)
	bar:SetStatusBarTexture(Grimoire.media.statusbar)
	bar:SetStatusBarColor(color.r, color.g, color.b)
	bar.text = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	bar.text:SetPoint("CENTER")
	bar.border = border
	return bar
end

function M:Build()
	local db = self.db
	local inset = Grimoire.media.classicInset

	local frame = CreateFrame("Frame", "GrimoireWarlockResourceBar", UIParent)
	frame:SetSize(db.width + inset * 2,
		db.healthHeight + db.manaHeight + inset * 4 + db.barSpacing * 2 + db.shardSize)
	self.frame = frame

	self.health = CreateBar(frame, db.healthHeight, HEALTH_COLOR)
	self.health.border:SetPoint("TOPLEFT")
	self.health.border:SetPoint("TOPRIGHT")

	self.mana = CreateBar(frame, db.manaHeight, db.manaColor)
	self.mana.border:SetPoint("TOPLEFT", self.health.border, "BOTTOMLEFT", 0, -db.barSpacing)
	self.mana.border:SetPoint("TOPRIGHT", self.health.border, "BOTTOMRIGHT", 0, -db.barSpacing)

	-- One shard icon with the count beside it.
	local shard = CreateFrame("Frame", nil, frame)
	shard:SetSize(db.shardSize, db.shardSize)
	shard:SetPoint("TOPLEFT", self.mana.border, "BOTTOMLEFT", inset, -db.barSpacing)
	shard.icon = shard:CreateTexture(nil, "ARTWORK")
	shard.icon:SetAllPoints()
	shard.icon:SetTexture(C_Item.GetItemIconByID(SOUL_SHARD_ITEM) or SOUL_SHARD_ICON_FALLBACK)
	shard.count = shard:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	shard.count:SetPoint("LEFT", shard, "RIGHT", 4, 0)
	self.shard = shard

	Grimoire:RegisterMover(frame, "WarlockResourceBar", "Warlock Resources", { "CENTER", "UIParent", "CENTER", 0, -200 })
end

-- Fills the bar and its % text. Records whether it's full for fading; a secret
-- value can't be compared, so it counts as not full and the bar stays bright.
function M:SetBarValue(bar, current, max)
	-- StatusBar accepts secret values directly.
	bar:SetMinMaxValues(0, max)
	bar:SetValue(current)

	local secret = Grimoire.AnySecret(current, max)
	bar.full = not secret and current >= max

	if not self.db.showBarText then
		bar.text:SetText("")
	elseif secret then
		-- Can't divide secrets into a percentage; let the widget render the raw value.
		bar.text:SetText(current)
	else
		bar.text:SetFormattedText("%d%%", max > 0 and math.floor(current / max * 100) or 0)
	end
	self:UpdateVisibility()
end

function M:UpdateHealth()
	self:SetBarValue(self.health, UnitHealth("player"), UnitHealthMax("player"))
end

function M:UpdateMana()
	self:SetBarValue(self.mana, UnitPower("player", POWER_MANA), UnitPowerMax("player", POWER_MANA))
end

function M:UpdateShards()
	local count = C_Item.GetItemCount(SOUL_SHARD_ITEM)
	self.shard.count:SetText(count)
	-- Grey out at zero; a secret count can't be compared, so leave it lit.
	self.shard.icon:SetDesaturated(not Grimoire.IsSecret(count) and count == 0)
end

-- Each bar fades on its own once full, out of combat. The shard icon fades only
-- when both bars have, so the whole thing goes quiet while resting.
function M:UpdateVisibility()
	local forceShow = Grimoire.moversUnlocked or Grimoire:InCombat()
	local dimmed = self.db.alphaWhenFull
	local healthDim = not forceShow and self.health.full
	local manaDim = not forceShow and self.mana.full
	self.health.border:SetAlpha(healthDim and dimmed or 1)
	self.mana.border:SetAlpha(manaDim and dimmed or 1)
	self.shard:SetAlpha((healthDim and manaDim) and dimmed or 1)
end

function M:Refresh()
	self:UpdateHealth()
	self:UpdateMana()
	self:UpdateShards()
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

	self:RegisterUnitEvent("UNIT_HEALTH", "player", "UpdateHealth")
	self:RegisterUnitEvent("UNIT_HEALTH_FREQUENT", "player", "UpdateHealth")
	self:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "UpdateHealth")
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

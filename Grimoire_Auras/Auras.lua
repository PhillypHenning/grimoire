local Grimoire = Grimoire

-- Buffs and Debuffs are separate modules with separate movers. Each uses Blizzard's
-- SecureAuraHeaderTemplate, which lays out the buttons securely so right-click to
-- cancel a buff still works in combat. This code only draws icon, count, timer.

local BUTTON_SIZE = 30 -- matches Templates.xml
local SPACING = 4
local TIMER_HEIGHT = 14 -- duration text under each icon, classic style
local UPDATE_SECONDS = 0.2

-- Aura data ---------------------------------------------------------------------------

local function GetAura(index, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local aura = C_UnitAuras.GetAuraDataByIndex("player", index, filter)
		if aura then
			return aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime
		end
		return nil
	end
	local _, icon, count, debuffType, duration, expirationTime = UnitAura("player", index, filter)
	return icon, count, debuffType, duration, expirationTime
end

local function SetExpiration(button, duration, expirationTime)
	if Grimoire.AnySecret(duration, expirationTime) or not duration or duration <= 0 then
		button.expiration = nil
		button.timer:SetText("")
	else
		button.expiration = expirationTime
	end
end

local function UpdateAura(button, index)
	local filter = button:GetParent():GetAttribute("filter")
	local icon, count, debuffType, duration, expirationTime = GetAura(index, filter)
	button.slot = nil
	button.filter = filter
	button.icon:SetTexture(icon)
	button.count:SetText((not Grimoire.IsSecret(count) and count and count > 1) and count or "")
	if filter == "HARMFUL" then
		local color = (DebuffTypeColor and DebuffTypeColor[debuffType or "none"]) or { r = 0.8, g = 0, b = 0 }
		button.border:SetVertexColor(color.r, color.g, color.b)
		button.border:Show()
	else
		button.border:Hide()
	end
	SetExpiration(button, duration, expirationTime)
end

-- Weapon enchants (poisons, sharpening stones, Firestone/Spellstone) live on the
-- weapon slot, not in the aura list.
local function UpdateTempEnchant(button, slot)
	button.slot = slot
	button.icon:SetTexture(GetInventoryItemTexture("player", slot))
	button.count:SetText("")
	button.border:Hide()
	local hasMain, mainExpires, _, _, hasOff, offExpires = GetWeaponEnchantInfo()
	local expiresMs
	if slot == INVSLOT_OFFHAND or slot == 17 then
		expiresMs = hasOff and offExpires
	else
		expiresMs = hasMain and mainExpires
	end
	SetExpiration(button, expiresMs and 1 or 0, expiresMs and (GetTime() + expiresMs / 1000))
end

local function RefreshButton(button)
	if not button.icon then return end
	if button.slot then
		UpdateTempEnchant(button, button.slot)
	elseif button:GetID() > 0 then
		UpdateAura(button, button:GetID())
	end
end

-- Button template ------------------------------------------------------------------------

local function Button_OnAttributeChanged(button, name, value)
	if name == "index" then
		UpdateAura(button, value)
	elseif name == "target-slot" then
		UpdateTempEnchant(button, value)
	end
end

local function Button_OnUpdate(button, elapsed)
	button.elapsed = (button.elapsed or 0) + elapsed
	if button.elapsed < UPDATE_SECONDS then return end
	button.elapsed = 0
	if button.expiration then
		local remaining = button.expiration - GetTime()
		if remaining > 0 then
			button.timer:SetFormattedText(SecondsToTimeAbbrev(remaining))
		else
			button.timer:SetText("")
		end
	end
end

local function Button_OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_BOTTOMLEFT")
	if button.slot then
		GameTooltip:SetInventoryItem("player", button.slot)
	else
		GameTooltip:SetUnitAura("player", button:GetID(), button.filter)
	end
	GameTooltip:Show()
end

function GrimoireAuraButton_OnLoad(button)
	button:RegisterForClicks("RightButtonUp")
	button.icon = button:CreateTexture(nil, "BORDER")
	button.icon:SetAllPoints()

	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetPoint("BOTTOMRIGHT", -2, 2)

	button.timer = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.timer:SetPoint("TOP", button, "BOTTOM", 0, -2)

	-- Classic debuff border, colored by type (magic blue, curse purple, ...).
	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
	button.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
	button.border:SetSize(BUTTON_SIZE + 3, BUTTON_SIZE + 2)
	button.border:SetPoint("CENTER")
	button.border:Hide()

	button:SetScript("OnAttributeChanged", Button_OnAttributeChanged)
	button:SetScript("OnUpdate", Button_OnUpdate)
	button:SetScript("OnEnter", Button_OnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

-- Modules ---------------------------------------------------------------------------------

-- The default BuffFrame holds both buffs and debuffs on Classic, so it's hidden as
-- soon as either module is on.
local function HideBlizzardAuras()
	Grimoire:HideBlizzardFrame(BuffFrame)
	Grimoire:HideBlizzardFrame(TemporaryEnchantFrame)
	Grimoire:HideBlizzardFrame(DebuffFrame) -- separate frame on newer clients
end

local Aura = {}

function Aura:Build()
	local db = self.db
	local step = BUTTON_SIZE + SPACING
	local rowHeight = BUTTON_SIZE + TIMER_HEIGHT

	-- The mover is a plain holder; the secure header hangs off its top-right corner.
	local holder = CreateFrame("Frame", "Grimoire" .. self.name .. "Holder", UIParent)
	holder:SetSize(db.perRow * step - SPACING, db.rows * rowHeight)
	self.holder = holder

	local header = CreateFrame("Frame", "Grimoire" .. self.name .. "Header", holder, "SecureAuraHeaderTemplate")
	header:SetAttribute("unit", "player")
	header:SetAttribute("filter", self.filter)
	header:SetAttribute("template", "GrimoireAuraButtonTemplate")
	if self.filter == "HELPFUL" then
		header:SetAttribute("includeWeapons", 1)
		header:SetAttribute("weaponTemplate", "GrimoireAuraButtonTemplate")
	end
	header:SetAttribute("point", "TOPRIGHT")
	header:SetAttribute("xOffset", -step)
	header:SetAttribute("yOffset", 0)
	header:SetAttribute("wrapAfter", db.perRow)
	header:SetAttribute("wrapXOffset", 0)
	header:SetAttribute("wrapYOffset", -rowHeight)
	header:SetAttribute("maxWraps", db.rows)
	header:SetAttribute("sortMethod", "TIME")
	header:SetAttribute("sortDirection", "-")
	header:SetPoint("TOPRIGHT", holder, "TOPRIGHT")
	self.header = header

	Grimoire:RegisterMover(holder, self.name, self.label, self.defaultPosition)
end

-- Picks up stack and timer changes on auras that kept their index.
function Aura:Refresh()
	for _, child in ipairs({ self.header:GetChildren() }) do
		if child:IsShown() then
			RefreshButton(child)
		end
	end
	Grimoire:NotifyMoverActivity(self.name)
end

function Aura:OnUnitAura()
	-- The header re-sorts on the same event; read the result on the next frame.
	C_Timer.After(0, function() self:Refresh() end)
end

function Aura:OnEnable()
	-- Secure headers can't be created or shown in combat.
	Grimoire:RunOutOfCombat(function()
		if not self:IsEnabled() then return end
		if not self.header then
			self:Build()
		end
		HideBlizzardAuras()
		self.holder:Show()
		self.header:Show()
	end)
	self:RegisterUnitEvent("UNIT_AURA", "player", "OnUnitAura")
end

function Aura:OnDisable()
	Grimoire:RunOutOfCombat(function()
		if self.header and not self:IsEnabled() then
			self.header:Hide()
			self.holder:Hide()
		end
	end)
	self:Print("Type /reload to bring back the default buff frame.")
end

local function NewAuraModule(name, label, filter, defaults, defaultPosition)
	local module = Grimoire:NewModule(name, { defaults = defaults })
	for key, fn in pairs(Aura) do
		module[key] = fn
	end
	module.label, module.filter, module.defaultPosition = label, filter, defaultPosition
	return module
end

-- Default spots match Blizzard's buff frame, next to the minimap.
NewAuraModule("Buffs", "Buffs", "HELPFUL", { perRow = 16, rows = 2 },
	{ "TOPRIGHT", "UIParent", "TOPRIGHT", -205, -13 })
NewAuraModule("Debuffs", "Debuffs", "HARMFUL", { perRow = 16, rows = 1 },
	{ "TOPRIGHT", "UIParent", "TOPRIGHT", -205, -110 })

local ADDON_NAME = ...
local Grimoire = Grimoire

-- Player health and power bars. Each is its own module and its own mover, so they
-- can be moved, grouped, dimmed and toggled separately.

local HEALTH_COLOR = { r = 0, g = 1, b = 0 } -- classic player frame green

local Bar = {}

function Bar:Build()
	local inset = Grimoire.media.classicInset
	local frame = CreateFrame("Frame", "Grimoire" .. self.name .. "Bar", UIParent, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(frame)

	local bar = CreateFrame("StatusBar", nil, frame)
	bar:SetPoint("TOPLEFT", inset, -inset)
	bar:SetPoint("BOTTOMRIGHT", -inset, inset)
	bar:SetStatusBarTexture(Grimoire.media.statusbar)
	bar.text = bar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	bar.text:SetPoint("CENTER")

	self.frame, self.bar = frame, bar
	self:ApplySize()
	self:UpdateColor()
	self:RegisterMover(frame, self:GetLabel(), self.defaultPosition, {
		dim = true,
		isBusy = function() return self:IsBusy() end,
	})
end

-- A bar never dims in combat or while it isn't full (secret values count as busy).
function Bar:IsBusy()
	if Grimoire:InCombat() or not self.lastCurrent then
		return true
	end
	return self.lastCurrent < self.lastMax
end

function Bar:ApplySize()
	local inset = Grimoire.media.classicInset
	self.frame:SetSize(self.db.width + inset * 2, self.db.height + inset * 2)
end

function Bar:ApplySettings()
	self:ApplySize()
	self.lastCurrent = nil -- redraw the text even if the value hasn't changed
	self:Update()
end

function Bar:UpdateColor()
	local color = self:GetColor()
	self.bar:SetStatusBarColor(color.r, color.g, color.b)
end

function Bar:SetValues(current, max)
	-- StatusBar accepts secret values directly.
	local bar = self.bar
	bar:SetMinMaxValues(0, max)
	bar:SetValue(current)

	local secret = Grimoire.AnySecret(current, max)
	if not self.db.showText then
		bar.text:SetText("")
	elseif secret then
		-- Can't divide secrets into a percentage; let the widget render the raw value.
		bar.text:SetText(current)
	else
		bar.text:SetFormattedText("%d%%", max > 0 and math.floor(current / max * 100) or 0)
	end

	-- Secrets can't be compared, so a secret update always counts as a change.
	if secret then
		self.lastCurrent, self.lastMax = nil, nil
		Grimoire:NotifyMoverActivity(self.name)
	elseif current ~= self.lastCurrent or max ~= self.lastMax then
		self.lastCurrent, self.lastMax = current, max
		Grimoire:NotifyMoverActivity(self.name)
	end
end

function Bar:OnEnable()
	if not self.frame then
		self:Build()
	end
	self.frame:Show()
	self:RegisterBarEvents()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Update")
	self:Update()
end

function Bar:OnDisable()
	self.frame:Hide()
end

local function Choices(...)
	local values = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		values[i] = { value, tostring(value) }
	end
	return values
end

local function NewBar(name, label, defaults, defaultPosition, heights)
	local module = Grimoire:NewModule(name, {
		addon = ADDON_NAME,
		label = label,
		defaults = defaults,
		options = {
			{ type = "toggle", key = "showText", label = "Show %" },
			{ type = "choice", key = "width", label = "Width", values = Choices(180, 220, 260, 300) },
			{ type = "choice", key = "height", label = "Height", values = Choices(unpack(heights)) },
		},
	})
	for key, fn in pairs(Bar) do
		module[key] = fn
	end
	module.defaultPosition = defaultPosition
	return module
end

-- Health -----------------------------------------------------------------------------

local Health = NewBar("Health", HEALTH or "Health", {
	width = 220,
	height = 16,
	showText = true,
}, { "CENTER", "UIParent", "CENTER", 0, -180 }, { 12, 16, 20, 24 })

function Health:GetLabel()
	return HEALTH or "Health"
end

function Health:GetColor()
	return HEALTH_COLOR
end

function Health:RegisterBarEvents()
	self:RegisterUnitEvent("UNIT_HEALTH", "player", "Update")
	self:RegisterUnitEvent("UNIT_HEALTH_FREQUENT", "player", "Update")
	self:RegisterUnitEvent("UNIT_MAXHEALTH", "player", "Update")
end

function Health:Update()
	self:SetValues(UnitHealth("player"), UnitHealthMax("player"))
end

-- Power (mana, rage, energy) ------------------------------------------------------------

local Power = NewBar("Power", "Power (mana)", {
	width = 220,
	height = 12,
	showText = true,
	manaColor = { r = 0, g = 0, b = 1 }, -- classic mana blue
}, { "CENTER", "UIParent", "CENTER", 0, -204 }, { 8, 10, 12, 16 })

function Power:GetLabel()
	local _, token = UnitPowerType("player")
	return _G[token] or "Power"
end

function Power:GetColor()
	local _, token = UnitPowerType("player")
	if token == "MANA" then
		return self.db.manaColor
	end
	return (PowerBarColor and PowerBarColor[token]) or self.db.manaColor
end

function Power:RegisterBarEvents()
	self:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "Update")
	self:RegisterUnitEvent("UNIT_MAXPOWER", "player", "Update")
	self:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player", "OnDisplayPower")
end

-- Druid forms switch between mana, rage and energy.
function Power:OnDisplayPower()
	self:UpdateColor()
	self:Update()
end

function Power:Update()
	local powerType = UnitPowerType("player")
	self:SetValues(UnitPower("player", powerType), UnitPowerMax("player", powerType))
end

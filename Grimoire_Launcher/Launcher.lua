local ADDON_NAME = ...
local Grimoire = Grimoire

local CLICK_AFTER_DRAG_SECONDS = 0.2

-- A free-floating round button (not attached to the minimap).
--   Left-click   the Grimoire menu (Grimoire:GetMainMenu, built in core)
--   Right-click  toggle move mode for every Grimoire frame
--   Drag         move the button itself (works any time, it isn't protected)

-- Tome icons that ship with the game, for /grimoire icon to cycle through.
local ICON_CHOICES = {
	"INV_Misc_Book_09", "INV_Misc_Book_06", "INV_Misc_Book_07", "INV_Misc_Book_11",
	"INV_Misc_Book_01", "INV_Misc_Book_02", "INV_Misc_Book_03", "INV_Misc_Book_04",
	"INV_Misc_Book_05", "INV_Misc_Book_08", "INV_Misc_Book_10",
}

local M = Grimoire:NewModule("Launcher", {
	addon = ADDON_NAME,
	label = "Grimoire button",
	defaults = {
		position = { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 120 },
		icon = ICON_CHOICES[1],
		scale = 1.4,
	},
	options = {
		{ type = "choice", key = "scale", label = "Button size", values = {
			{ 1, "Small" }, { 1.25, "Medium" }, { 1.4, "Large" }, { 1.75, "Huge" },
		} },
	},
})

-- Point offsets are in the button's own (scaled) units, so a saved position is
-- converted to the new scale to keep the button where it was on screen.
function M:ApplySettings()
	local scale = self.db.scale
	local pos = self.db.position
	local savedScale = self.db.positionScale or 1
	if savedScale ~= scale then
		pos[3], pos[4] = pos[3] * savedScale / scale, pos[4] * savedScale / scale
		self.db.positionScale = scale
	end
	self.button:SetScale(scale)
	self:ApplyPosition()
end

function M:ResetPosition()
	self.db.position = nil
	self.db.positionScale = nil
	Grimoire.CopyDefaults(self.defaults, self.db)
	self:ApplySettings()
end

function M:SavePosition()
	local point, _, relativePoint, x, y = self.button:GetPoint(1)
	self.db.position = { point, relativePoint, x, y }
	self.db.positionScale = self.button:GetScale()
end

function M:ApplyPosition()
	local pos = self.db.position
	self.button:ClearAllPoints()
	self.button:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end

function M:ApplyIcon()
	self.icon:SetTexture("Interface\\Icons\\" .. self.db.icon)
end

-- No name: step to the next built-in choice. With a name: use any icon file name.
function M:SetIcon(name)
	if name == "" then
		local nextIndex = 1
		for i, choice in ipairs(ICON_CHOICES) do
			if choice == self.db.icon then
				nextIndex = i % #ICON_CHOICES + 1
			end
		end
		name = ICON_CHOICES[nextIndex]
	end
	self.db.icon = name
	self:ApplyIcon()
	self:Print("Icon: " .. name)
end

function M:ShowTooltip()
	local tooltip = GameTooltip
	tooltip:SetOwner(self.button, "ANCHOR_LEFT")
	tooltip:AddLine("Grimoire")
	tooltip:AddLine("Left-click: menu", 1, 1, 1)
	tooltip:AddLine(Grimoire.moversUnlocked and "Right-click: lock frames" or "Right-click: move frames", 1, 1, 1)
	tooltip:AddLine("Drag: move this button", 1, 1, 1)
	tooltip:Show()
end

function M:UpdateState()
	if Grimoire.moversUnlocked then
		self.button:LockHighlight()
	else
		self.button:UnlockHighlight()
	end
	if GameTooltip:IsOwned(self.button) then
		self:ShowTooltip()
	end
end

function M:Build()
	local button = Grimoire.CreateRoundButton("GrimoireLauncherButton")
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForDrag("LeftButton")
	self.button = button
	self.icon = button.icon
	self:ApplyIcon()

	button:SetScript("OnDragStart", function(b)
		b:StartMoving()
	end)
	button:SetScript("OnDragStop", function(b)
		b:StopMovingOrSizing()
		self:SavePosition()
		self.lastDrag = GetTime()
	end)
	button:SetScript("OnClick", function(b, mouseButton)
		-- Some clients still send a click when a drag ends; ignore it.
		if self.lastDrag and GetTime() - self.lastDrag < CLICK_AFTER_DRAG_SECONDS then return end
		if mouseButton == "RightButton" then
			Grimoire:ToggleMoveMode()
		else
			Grimoire.OpenMenu(b, Grimoire:GetMainMenu())
		end
	end)
	button:SetScript("OnEnter", function() self:ShowTooltip() end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	self:ApplySettings() -- scale, then position
end

function M:OnInitialize()
	Grimoire:RegisterCommand("icon", "icon [name] - cycle the launcher icon, or set one by file name", function(arg)
		if self:IsEnabled() then self:SetIcon(arg) end
	end)
end

function M:OnEnable()
	if not self.button then
		self:Build()
	end
	self.button:Show()
	self:RegisterCallback("MoversUnlocked", "UpdateState")
	self:RegisterCallback("MoversLocked", "UpdateState")
	self:RegisterCallback("PositionsReset", "ResetPosition")
	self:UpdateState()
end

function M:OnDisable()
	self.button:Hide()
end

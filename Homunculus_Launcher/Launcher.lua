local ADDON_NAME = ...
local Homunculus = Homunculus

local CLICK_AFTER_DRAG_SECONDS = 0.2

-- A free-floating round button (not attached to the minimap).
--   Left-click   the Homunculus menu (Homunculus:GetMainMenu, built in core)
--   Right-click  toggle move mode for every Homunculus frame
--   Drag         move the button itself (works any time, it isn't protected)

-- Tome icons that ship with the game, for /homunculus icon to cycle through.
local ICON_CHOICES = {
	"INV_Misc_Book_09", "INV_Misc_Book_06", "INV_Misc_Book_07", "INV_Misc_Book_11",
	"INV_Misc_Book_01", "INV_Misc_Book_02", "INV_Misc_Book_03", "INV_Misc_Book_04",
	"INV_Misc_Book_05", "INV_Misc_Book_08", "INV_Misc_Book_10",
}

local M = Homunculus:NewModule("Launcher", {
	addon = ADDON_NAME,
	label = "Homunculus button",
	defaults = {
		position = { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 120 },
		icon = ICON_CHOICES[1],
	},
})

-- The button's size is the shared Layout ▸ Button size (Homunculus.CreateRoundButton).
-- It used to have its own scale; a position saved at that scale is converted once to
-- screen units, so the button stays where it was (2026-10-16).
function M:ApplySettings()
	local pos = self.db.position
	local savedScale = self.db.positionScale or self.db.scale -- never dragged: the old scale applied
	if savedScale and savedScale ~= 1 then
		pos[3], pos[4] = pos[3] * savedScale, pos[4] * savedScale
	end
	self.db.positionScale, self.db.scale = nil, nil
	self:ApplyPosition()
end

function M:ResetPosition()
	self.db.position = nil
	self.db.positionScale = nil
	Homunculus.CopyDefaults(self.defaults, self.db)
	self:ApplySettings()
end

function M:SavePosition()
	local point, _, relativePoint, x, y = self.button:GetPoint(1)
	self.db.position = { point, relativePoint, x, y }
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
	tooltip:AddLine("Homunculus")
	tooltip:AddLine("Left-click: menu", 1, 1, 1)
	tooltip:AddLine(Homunculus.moversUnlocked and "Right-click: lock frames" or "Right-click: move frames", 1, 1, 1)
	tooltip:AddLine("Drag: move this button", 1, 1, 1)
	local errors = self:ErrorCount()
	if errors > 0 then
		tooltip:AddLine(("%d new Lua error%s: Debug ▸ Show log"):format(errors, errors == 1 and "" or "s"), 1, 0.25, 0.25)
	end
	tooltip:Show()
end

-- Errors logged this session that the Debug log hasn't shown yet (learned from BugSack:
-- you notice errors without opening anything). Only while Debug is on, since that's where
-- they're read.
function M:ErrorCount()
	local debug = Homunculus:GetModule("Debug")
	if not (debug and debug:IsEnabled()) then return 0 end
	return Homunculus:GetUnseenErrorCount()
end

function M:UpdateErrorBadge()
	local errors = self:ErrorCount()
	self.badge:SetShown(errors > 0)
	self.badge.text:SetText(errors > 99 and "99+" or errors)
	if GameTooltip:IsOwned(self.button) then
		self:ShowTooltip()
	end
end

function M:UpdateState()
	if Homunculus.moversUnlocked then
		self.button:LockHighlight()
	else
		self.button:UnlockHighlight()
	end
	if GameTooltip:IsOwned(self.button) then
		self:ShowTooltip()
	end
end

function M:Build()
	local button = Homunculus.CreateRoundButton("HomunculusLauncherButton")
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForDrag("LeftButton")
	self.button = button
	self.icon = button.icon
	self:ApplyIcon()

	-- Unseen error count: a small red badge on the button's top-right.
	local badge = CreateFrame("Frame", nil, button)
	badge:SetSize(18, 14)
	badge:SetPoint("TOPRIGHT", 2, 2)
	badge:SetFrameLevel(button:GetFrameLevel() + 5)
	local bg = badge:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.75, 0, 0, 0.9)
	badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	badge.text:SetPoint("CENTER")
	badge:Hide()
	self.badge = badge

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
			Homunculus:ToggleMoveMode()
		else
			Homunculus.OpenMenu(b, Homunculus:GetMainMenu())
		end
	end)
	button:SetScript("OnEnter", function() self:ShowTooltip() end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	self:ApplySettings()
end

function M:OnInitialize()
	Homunculus:RegisterCommand("icon", "icon [name] - cycle the launcher icon, or set one by file name", function(arg)
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
	self:RegisterCallback("ErrorCountChanged", "UpdateErrorBadge")
	self:RegisterCallback("ModuleEnabled", "UpdateErrorBadge") -- Debug turned on or off
	self:RegisterCallback("ModuleDisabled", "UpdateErrorBadge")
	self:UpdateState()
	self:UpdateErrorBadge()
end

function M:OnDisable()
	self.button:Hide()
end

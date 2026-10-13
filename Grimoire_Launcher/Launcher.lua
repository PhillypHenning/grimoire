local Grimoire = Grimoire

local SIZE = 31
local CLICK_AFTER_DRAG_SECONDS = 0.2

-- A free-floating round button (not attached to the minimap).
--   Left-click   toggle move mode for every Grimoire frame
--   Right-click  menu: move mode, reset positions, group selected frames, open windows
--   Drag         move the button itself (works any time, it isn't protected)

-- Tome icons that ship with the game, for /grimoire icon to cycle through.
local ICON_CHOICES = {
	"INV_Misc_Book_09", "INV_Misc_Book_06", "INV_Misc_Book_07", "INV_Misc_Book_11",
	"INV_Misc_Book_01", "INV_Misc_Book_02", "INV_Misc_Book_03", "INV_Misc_Book_04",
	"INV_Misc_Book_05", "INV_Misc_Book_08", "INV_Misc_Book_10",
}

local M = Grimoire:NewModule("Launcher", {
	defaults = {
		position = { "BOTTOMRIGHT", "BOTTOMRIGHT", -40, 120 },
		icon = ICON_CHOICES[1],
	},
})

local function ToggleMoveMode()
	if Grimoire.moversUnlocked then
		Grimoire:LockMovers()
	else
		Grimoire:UnlockMovers()
	end
end

-- Every enabled module with a window (anything that has a Toggle method).
function M:BuildMenu()
	local entries = {
		{ text = "Grimoire", isTitle = true },
		{ text = "Move frames", checked = function() return Grimoire.moversUnlocked end, func = ToggleMoveMode },
		{ text = "Reset frame positions", func = function() self:ResetPositions() end },
	}
	local selected = Grimoire:GetSelectedMovers()
	if #selected >= 2 then
		entries[#entries + 1] = { text = "Group selected frames", func = function() Grimoire:GroupMovers(selected) end }
	end
	if #selected >= 1 then
		entries[#entries + 1] = { text = "Clear selection", func = function() Grimoire:ClearMoverSelection() end }
	end
	local windows = {}
	for _, name in ipairs(Grimoire.moduleOrder) do
		local module = Grimoire.modules[name]
		if module ~= self and module.Toggle and module:IsEnabled() then
			windows[#windows + 1] = { text = name, func = function() module:Toggle() end }
		end
	end
	if #windows > 0 then
		entries[#entries + 1] = { isDivider = true }
		for _, entry in ipairs(windows) do
			entries[#entries + 1] = entry
		end
	end
	return entries
end

function M:ResetPositions()
	Grimoire:ResetMover()
	self.db.position = nil
	Grimoire.CopyDefaults(self.defaults, self.db)
	self:ApplyPosition()
	Grimoire:Print("Frame positions reset.")
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
	tooltip:AddLine("Grimoire")
	tooltip:AddLine(Grimoire.moversUnlocked and "Left-click: lock frames" or "Left-click: move frames", 1, 1, 1)
	tooltip:AddLine("Right-click: menu", 1, 1, 1)
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
	local media = Grimoire.media
	local button = CreateFrame("Button", "GrimoireLauncherButton", UIParent)
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetMovable(true)
	button:SetClampedToScreen(true)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture(media.roundButtonHighlight, "ADD")
	self.button = button

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture(media.roundButtonBackground)
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	self.icon = icon
	self:ApplyIcon()

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture(media.roundButtonBorder)
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

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
			Grimoire.OpenMenu(b, self:BuildMenu())
		else
			ToggleMoveMode()
		end
	end)
	button:SetScript("OnEnter", function() self:ShowTooltip() end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	self:ApplyPosition()
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
	self:UpdateState()
end

function M:OnDisable()
	self.button:Hide()
end

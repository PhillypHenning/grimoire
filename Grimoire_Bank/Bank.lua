local ADDON_NAME = ...
local Grimoire = Grimoire

local SLOT_SIZE = 37
local SLOT_SPACING = 4
local COLUMNS = 12
local VIEW_HEIGHT = 340
local SCROLLBAR_WIDTH = 24
local STATUS_HEIGHT = 30

local M = Grimoire:NewModule("Bank", { addon = ADDON_NAME, label = "Bank" })

-- Recording ------------------------------------------------------------------
-- Bank contents can only be read while talking to a banker. Snapshot them on
-- open and on every change while open; the viewer shows the last snapshot anywhere.

function M:Scan()
	local containers = {}
	for _, bag in ipairs(Grimoire.GetBankIDs()) do
		containers[#containers + 1] = { bag = bag, slots = Grimoire.ReadContainer(bag) }
	end
	Grimoire:GetCharacterStore().bank = { scannedAt = time(), containers = containers }
	Grimoire:Fire("BankScanned")
	self:Refresh()
end

local function IsBanker(interactionType)
	return Enum.PlayerInteractionType and interactionType == Enum.PlayerInteractionType.Banker
end

function M:OnInteractionShow(_, interactionType)
	if IsBanker(interactionType) then
		self.atBank = true
		self:Scan()
	end
end

function M:OnInteractionHide(_, interactionType)
	if IsBanker(interactionType) then
		self.atBank = false
		self:Refresh()
	end
end

function M:OnBankChanged()
	if self.atBank then
		self:Scan()
	end
end

-- Viewer -----------------------------------------------------------------------

function M:Build()
	local width = COLUMNS * (SLOT_SIZE + SLOT_SPACING) - SLOT_SPACING
	local frame = Grimoire:CreateWindow("Bank", BANK or "Bank", self)
	frame:SetContentSize(width + SCROLLBAR_WIDTH, STATUS_HEIGHT + VIEW_HEIGHT)
	frame:SetScript("OnShow", function() self:Refresh() end)
	self.frame = frame

	-- Whose bank this is, class-colored (ADR 0003).
	self.picker = Grimoire.CreateCharacterPicker(frame.content, "bank", function(charKey)
		self.charKey = charKey
		self:Refresh()
	end)
	self.picker:SetPoint("TOPLEFT")
	self.status = frame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.status:SetPoint("LEFT", self.picker, "RIGHT", 8, 0)
	self.count = frame.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.count:SetPoint("RIGHT", frame.content, "TOPRIGHT", -SCROLLBAR_WIDTH, -11)

	local scroll, child = Grimoire.CreateScrollArea(frame.content, "GrimoireBankScroll")
	scroll:SetPoint("TOPLEFT", 0, -STATUS_HEIGHT)
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH, 0)
	self.grid = child
	self.slots = {}
end

function M:GetSlot(index)
	local slot = self.slots[index]
	if not slot then
		slot = Grimoire.CreateDisplaySlot(self.grid)
		local step = SLOT_SIZE + SLOT_SPACING
		local i = index - 1
		slot:SetPoint("TOPLEFT", (i % COLUMNS) * step, -math.floor(i / COLUMNS) * step)
		self.slots[index] = slot
	end
	return slot
end

function M:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	local isCurrent = self.charKey == Grimoire.db.charKey
	local bank = Grimoire:GetCharacterStore(self.charKey).bank

	if isCurrent and self.atBank then
		self.status:SetText("|cff20ff20Live|r: at the bank")
	elseif bank then
		self.status:SetText("Updated " .. Grimoire.FormatAgo(bank.scannedAt))
	else
		self.status:SetText(isCurrent and "Visit a banker to record." or "No bank recorded.")
	end

	-- Only occupied slots are shown, so a mostly-empty bank stays compact.
	local index = 0
	for _, container in ipairs(bank and bank.containers or {}) do
		for _, item in ipairs(container.slots) do
			if item then
				index = index + 1
				local slot = self:GetSlot(index)
				Grimoire.SetDisplaySlotItem(slot, item)
				slot:Show()
			end
		end
	end
	for i = index + 1, #self.slots do
		self.slots[i]:Hide()
	end

	self.count:SetText(index == 1 and "1 item" or (index .. " items"))
	self.grid:SetHeight(math.max(1, math.ceil(index / COLUMNS) * (SLOT_SIZE + SLOT_SPACING)))
end

function M:Toggle()
	if not self.frame then
		self:Build()
		self.picker:SetCharacter(Grimoire.db.charKey)
	end
	self.frame:SetShown(not self.frame:IsShown())
end

-- Lifecycle --------------------------------------------------------------------

function M:OnInitialize()
	Grimoire:RegisterCommand("bank", "bank - view your saved bank contents", function()
		if self:IsEnabled() then self:Toggle() end
	end)
end

function M:OnEnable()
	self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "OnInteractionShow")
	self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "OnInteractionHide")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBankChanged")
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", "OnBankChanged")
end

function M:OnDisable()
	self.atBank = false
	if self.frame then
		self.frame:Hide()
	end
end

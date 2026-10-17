local ADDON_NAME, ns = ...
local Grimoire = Grimoire
local Search = ns.Search

local SLOT_SIZE = 37
local SLOT_SPACING = 4
local TOOLBAR_HEIGHT = 30
local FOOTER_HEIGHT = 22
local DIMMED_ALPHA = 0.25

local M = Grimoire:NewModule("Bags", {
	addon = ADDON_NAME,
	label = "Bags",
	conflicts = { "Bagnon", "Baganator", "AdiBags", "ArkInventory" },
	defaults = {
		columns = 10,
		ownerTooltips = true,
		iconInfo = true,
	},
	options = {
		{ type = "toggle", key = "ownerTooltips", label = "Show who owns an item in tooltips", tooltip = "Item tooltips list each of your characters that has it, with how many in bags and bank (learned from Syndicator)." },
		{ type = "toggle", key = "iconInfo", label = "Item level and BoE on icons", tooltip = "Equipment shows its item level in the corner; items that bind when equipped show BoE (learned from Baganator)." },
		{ type = "choice", key = "columns", label = "Columns", tooltip = "How many item slots each row of the bag window has.", values = {
			{ 8, "8" }, { 10, "10" }, { 12, "12" }, { 14, "14" },
		} },
	},
})

-- Taking over the default bag keybinds -----------------------------------------
-- Blizzard's Open/Close/Toggle bag functions are hooked (not replaced, which would
-- taint them). Several can fire for one key press, e.g. ToggleAllBags calling
-- OpenBag, so requests are collected and resolved once on the next frame.
-- A toggle wins over open/close because it represents the player's key press.

local pending

local function HideBlizzardBags()
	if ContainerFrameCombinedBags then
		ContainerFrameCombinedBags:Hide()
	end
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local frame = _G["ContainerFrame" .. i]
		-- Leave bank bag frames alone; only player bags are replaced.
		if frame and frame:IsShown() and Grimoire.IsPlayerBag(frame:GetID()) then
			frame:Hide()
		end
	end
end

local function Resolve()
	local action = pending
	pending = nil
	if not M:IsEnabled() then return end
	HideBlizzardBags()
	if action == "toggle" then
		M:Toggle()
	elseif action == "open" then
		M:Open()
	else
		M:Close()
	end
end

local function Request(action)
	if not M:IsEnabled() then return end
	HideBlizzardBags()
	if not pending then
		C_Timer.After(0, Resolve)
	end
	if pending ~= "toggle" then
		pending = action
	end
end

local function Hook(name, action, bagArgument)
	if not _G[name] then return end
	hooksecurefunc(name, function(bag)
		if not bagArgument or Grimoire.IsPlayerBag(bag) then
			Request(action)
		end
	end)
end

function M:InstallHooks()
	if self.hooked then return end
	self.hooked = true
	Hook("ToggleAllBags", "toggle")
	Hook("ToggleBackpack", "toggle")
	Hook("ToggleBag", "toggle", true)
	Hook("OpenAllBags", "open")
	Hook("OpenBackpack", "open")
	Hook("OpenBag", "open", true)
	Hook("CloseAllBags", "close")
	Hook("CloseBackpack", "close")
end

-- Window -----------------------------------------------------------------------

local function CreateToolbarButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(70, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function ToggleComponent(moduleName)
	local module = Grimoire:GetModule(moduleName)
	if module and module:IsEnabled() then
		module:Toggle()
	end
end

function M:Build()
	local frame = Grimoire:CreateWindow("Bags", INVENTORY_TOOLTIP or "Inventory", self)
	frame:SetScript("OnShow", function()
		if SOUNDKIT then PlaySound(SOUNDKIT.IG_BACKPACK_OPEN) end
		self:Refresh()
	end)
	frame:SetScript("OnHide", function()
		if SOUNDKIT then PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE) end
		self:ClearNewItems()
	end)
	self.frame = frame
	local content = frame.content

	local search = CreateFrame("EditBox", "GrimoireBagsSearch", content, "SearchBoxTemplate")
	search:SetHeight(20)
	search:SetPoint("TOPLEFT", 6, -1) -- right edge follows the buttons (UpdateToolbar)
	search:HookScript("OnTextChanged", function(box)
		self:SetSearch(box:GetText())
	end)
	search:HookScript("OnEnter", function(box)
		GameTooltip:SetOwner(box, "ANCHOR_TOP")
		GameTooltip:AddLine("Search")
		GameTooltip:AddLine("Words match names and item types: linen, cloth, potion", 1, 1, 1)
		GameTooltip:AddLine("junk, common, uncommon, rare, epic · boe, bop", 1, 1, 1)
		GameTooltip:AddLine("Slots: head, chest, feet, finger, trinket, ranged, bag ...", 1, 1, 1)
		GameTooltip:AddLine("Item level: >20  <10  10-15", 1, 1, 1)
		GameTooltip:AddLine("Combine: space or & = and, | = or, ! = not", 1, 1, 1)
		GameTooltip:Show()
	end)
	search:HookScript("OnLeave", GameTooltip_Hide)
	self.search = search

	self.sortButton = CreateToolbarButton(content, "Sort", function()
		C_Container.SortBags()
	end)
	if not (C_Container and C_Container.SortBags) then
		self.sortButton:Disable()
	end
	-- Bank and Auctions are separate add-ons (ADR 0002); their buttons only show
	-- when those components are loaded and enabled.
	self.bankButton = CreateToolbarButton(content, "Bank", function()
		ToggleComponent("Bank")
	end)
	self.auctionsButton = CreateToolbarButton(content, "Auctions", function()
		ToggleComponent("Auctions")
	end)

	self.grid = CreateFrame("Frame", nil, content)
	self.grid:SetPoint("TOPLEFT", 0, -TOOLBAR_HEIGHT)
	self.holders = {}

	self.freeText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.freeText:SetPoint("BOTTOMLEFT", 2, 4)
	self.moneyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	self.moneyText:SetPoint("BOTTOMRIGHT", -2, 4)
end

function M:UpdateToolbar()
	local anchor
	for _, entry in ipairs({
		{ self.auctionsButton, "Auctions" },
		{ self.bankButton, "Bank" },
		{ self.sortButton },
	}) do
		local button, moduleName = entry[1], entry[2]
		local module = moduleName and Grimoire:GetModule(moduleName)
		local visible = not moduleName or (module and module:IsEnabled())
		button:SetShown(visible)
		if visible then
			button:ClearAllPoints()
			if anchor then
				button:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
			else
				button:SetPoint("TOPRIGHT", self.frame.content, "TOPRIGHT", 0, 0)
			end
			anchor = button
		end
	end
	-- The search box takes whatever width the buttons leave.
	self.search:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
end

-- New items ----------------------------------------------------------------------
-- The client keeps "new" flags (C_NewItems) until a bag UI clears them; nothing did,
-- so every item ever looted glowed (Phil, 2026-10-16). Like Blizzard's bags: an item
-- glows while new, hovering it marks it seen, and closing the window marks all seen.

local function IsNewItem(bag, slot, hasItem)
	return hasItem and C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) or false
end

local function SetNewGlow(button, isNew, quality)
	local texture, flash, glow = button.NewItemTexture, button.flashAnim, button.newitemglowAnim
	if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end
	if not texture then return end
	if isNew then
		local atlas = NEW_ITEM_ATLAS_BY_QUALITY and quality and NEW_ITEM_ATLAS_BY_QUALITY[quality]
		texture:SetAtlas(atlas or "bags-glow-white")
		texture:Show()
		if flash and glow and not flash:IsPlaying() and not glow:IsPlaying() then
			flash:Play()
			glow:Play()
		end
	else
		texture:Hide()
		if flash then flash:Stop() end
		if glow then glow:Stop() end
	end
end

local function Button_OnEnter(button)
	local bag, slot = button:GetParent():GetID(), button:GetID()
	if IsNewItem(bag, slot, true) then
		C_NewItems.RemoveNewItem(bag, slot)
	end
	SetNewGlow(button, false)
end

function M:ClearNewItems()
	if C_NewItems and C_NewItems.ClearAll then
		C_NewItems.ClearAll()
	end
	for _, holder in pairs(self.holders) do
		for _, button in ipairs(holder.buttons) do
			SetNewGlow(button, false)
		end
	end
end

-- Slots ------------------------------------------------------------------------
-- Each bag gets a holder frame whose ID is the bag ID; each button's ID is its
-- slot. ContainerFrameItemButtonTemplate reads both to use/move the right item,
-- which keeps right-click-to-use working through Blizzard's secure code.

function M:GetHolder(bag)
	local holder = self.holders[bag]
	if not holder then
		holder = CreateFrame("Frame", nil, self.grid)
		holder:SetID(bag)
		holder:SetAllPoints()
		holder.buttons = {}
		self.holders[bag] = holder
	end
	return holder
end

function M:GetButton(holder, slot)
	local button = holder.buttons[slot]
	if not button then
		self.buttonCount = (self.buttonCount or 0) + 1
		button = CreateFrame("ItemButton", "GrimoireBagsItem" .. self.buttonCount, holder, "ContainerFrameItemButtonTemplate")
		local bg = button:CreateTexture(nil, "BACKGROUND", nil, -1)
		bg:SetTexture(Grimoire.media.emptySlot)
		bg:SetAllPoints()
		button:SetID(slot)
		button:HookScript("OnEnter", Button_OnEnter)
		-- Item level (bottom-left) and BoE (top-left), like Baganator's icon corners.
		button.ilvlText = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		button.ilvlText:SetPoint("BOTTOMLEFT", 2, 2)
		button.boeText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.boeText:SetPoint("TOPLEFT", 2, -2)
		button.boeText:SetText("BoE")
		button.boeText:SetTextColor(0.1, 1, 0.1)
		holder.buttons[slot] = button
	end
	return button
end

local function LayoutSignature()
	local parts = {}
	for _, bag in ipairs(Grimoire.GetBagIDs()) do
		parts[#parts + 1] = C_Container.GetContainerNumSlots(bag)
	end
	return table.concat(parts, ",")
end

-- Creating and moving item buttons is blocked in combat, so it's deferred.
function M:Layout()
	if InCombatLockdown() then
		if not self.layoutQueued then
			self.layoutQueued = true
			Grimoire:RunOutOfCombat(function()
				self.layoutQueued = false
				self:Layout()
				self:UpdateItems()
			end)
		end
		return
	end

	local columns = self.db.columns
	local step = SLOT_SIZE + SLOT_SPACING
	local index = 0
	for _, bag in ipairs(Grimoire.GetBagIDs()) do
		local holder = self:GetHolder(bag)
		holder.numSlots = C_Container.GetContainerNumSlots(bag)
		for slot = 1, holder.numSlots do
			local button = self:GetButton(holder, slot)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", self.grid, "TOPLEFT", (index % columns) * step, -math.floor(index / columns) * step)
			button:Show()
			index = index + 1
		end
		for slot = holder.numSlots + 1, #holder.buttons do
			holder.buttons[slot]:Hide()
		end
	end

	local width = columns * step - SLOT_SPACING
	local height = math.max(1, math.ceil(index / columns)) * step - SLOT_SPACING
	self.grid:SetSize(width, height)
	self.frame:SetContentSize(width, TOOLBAR_HEIGHT + height + FOOTER_HEIGHT)
	self.layoutSignature = LayoutSignature()
end

local function UpdateCooldown(button, bag, slot, hasItem)
	local cooldown = button.Cooldown or _G[button:GetName() .. "Cooldown"]
	if not cooldown then return end
	if not hasItem then
		cooldown:Clear()
		return
	end
	local start, duration, enable = C_Container.GetContainerItemCooldown(bag, slot)
	if Grimoire.AnySecret(start, duration, enable) then
		-- CooldownFrame_Set compares values, which secrets forbid; the widget itself accepts them.
		cooldown:SetCooldown(start, duration)
	else
		CooldownFrame_Set(cooldown, start, duration, enable)
	end
end

-- What the search and icon corners know about an item. Item info may not be cached yet;
-- GET_ITEM_INFO_RECEIVED refreshes the window when it arrives.
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetDetailedItemLevelInfo = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo

local function ItemRecord(info)
	local link = info.hyperlink
	local name, ilvl, itemType, subType, equipLoc, bindType
	if link then
		local _
		name, _, _, ilvl, _, itemType, subType, _, equipLoc, _, _, _, _, bindType = GetItemInfo(link)
		local detailed = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)
		ilvl = detailed or ilvl
	end
	local bind
	if info.isBound or bindType == 1 then
		bind = "bop"
	elseif bindType == 2 then
		bind = "boe"
	end
	return {
		name = name or Grimoire.ItemNameFromLink(link),
		quality = info.quality,
		itemType = itemType,
		subType = subType,
		slot = (equipLoc and equipLoc ~= "") and equipLoc or nil,
		ilvl = ilvl,
		bind = bind,
	}
end

function M:UpdateIconInfo(button)
	local item = self.db.iconInfo and button.searchItem
	local equipment = item and item.slot and item.slot ~= "INVTYPE_BAG" and item.ilvl
	button.ilvlText:SetText(equipment and item.ilvl or "")
	button.boeText:SetShown(item and item.bind == "boe" or false)
end

function M:UpdateButton(button, bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	SetItemButtonTexture(button, info and info.iconFileID or nil)
	SetItemButtonCount(button, info and info.stackCount or 0)
	SetItemButtonDesaturated(button, info and info.isLocked or false)
	SetItemButtonQuality(button, info and info.quality or nil, info and info.hyperlink or nil)
	SetNewGlow(button, IsNewItem(bag, slot, info ~= nil), info and info.quality)
	UpdateCooldown(button, bag, slot, info ~= nil)
	button.searchItem = info and ItemRecord(info) or nil
	self:UpdateIconInfo(button)
	self:ApplySearch(button)
end

function M:UpdateItems()
	local free, total = 0, 0
	for bag, holder in pairs(self.holders) do
		for slot = 1, holder.numSlots or 0 do
			self:UpdateButton(holder.buttons[slot], bag, slot)
		end
		total = total + (holder.numSlots or 0)
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
	end
	self.freeText:SetFormattedText("%d / %d free", free, total)
end

function M:UpdateMoney()
	self.moneyText:SetText(Grimoire.FormatMoney(GetMoney()))
end

-- Search -----------------------------------------------------------------------

-- The query language is in Search.lua (names, quality, boe/bop, slots, item level; & | !).
function M:SetSearch(text)
	self.matcher = Search.Compile(text)
	for _, holder in pairs(self.holders) do
		for slot = 1, holder.numSlots or 0 do
			self:ApplySearch(holder.buttons[slot])
		end
	end
end

function M:ApplySearch(button)
	local match = self.matcher
	local matches = not match or (button.searchItem ~= nil and match(button.searchItem))
	button:SetAlpha(matches and 1 or DIMMED_ALPHA)
end

-- Who owns an item ---------------------------------------------------------------
-- Item tooltips list every character holding the item, from core's shared item data
-- (Grimoire:GetItemCounts; bank counts are from the last bank visit).

local function AddOwners(tooltip, itemID)
	if not (M:IsEnabled() and M.db.ownerTooltips) or not itemID or Grimoire.IsSecret(itemID) then return end
	local owners = Grimoire:GetItemCounts(itemID)
	if #owners == 0 then return end
	tooltip:AddLine(" ")
	for _, owner in ipairs(owners) do
		local parts = {}
		if owner.bags > 0 then parts[#parts + 1] = "bags " .. owner.bags end
		if owner.bank > 0 then parts[#parts + 1] = "bank " .. owner.bank end
		tooltip:AddDoubleLine(Grimoire:FormatCharacterName(owner.charKey),
			("%d (%s)"):format(owner.bags + owner.bank, table.concat(parts, ", ")), nil, nil, nil, 1, 1, 1)
	end
end

function M:HookTooltips()
	if self.tooltipsHooked then return end
	self.tooltipsHooked = true
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			AddOwners(tooltip, data and data.id)
		end)
	else
		local function OnSetItem(tooltip)
			local _, link = tooltip:GetItem()
			AddOwners(tooltip, link and GetItemInfoInstant(link))
		end
		GameTooltip:HookScript("OnTooltipSetItem", OnSetItem)
		if ItemRefTooltip then ItemRefTooltip:HookScript("OnTooltipSetItem", OnSetItem) end
	end
end

-- Lifecycle --------------------------------------------------------------------

function M:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	if LayoutSignature() ~= self.layoutSignature then
		self:Layout()
	end
	self:UpdateToolbar()
	self:UpdateItems()
	self:UpdateMoney()
end

function M:ApplySettings()
	self.layoutSignature = nil
	if self.frame:IsShown() then
		self:Refresh()
	end
end

function M:OnItemLockChanged(_, bag, slot)
	local holder = slot and self.holders[bag]
	if holder and holder.buttons[slot] and self.frame:IsShown() then
		self:UpdateButton(holder.buttons[slot], bag, slot)
	end
end

-- Item details arrived from the server: refresh once they stop coming.
function M:OnItemInfoReceived()
	if not self.frame:IsShown() or self.itemInfoQueued then return end
	self.itemInfoQueued = true
	C_Timer.After(0.3, function()
		self.itemInfoQueued = false
		self:Refresh()
	end)
end

function M:Open()
	self.frame:Show()
end

function M:Close()
	self.frame:Hide()
end

function M:Toggle()
	self.frame:SetShown(not self.frame:IsShown())
end

function M:OnInitialize()
	Grimoire:RegisterCommand("bags", "bags - toggle the combined bag window", function()
		if self:IsEnabled() then self:Toggle() end
	end)
end

function M:OnEnable()
	if not self.frame then
		self:Build()
	end
	self:InstallHooks()
	self:HookTooltips() -- hooks can't be removed; AddOwners checks IsEnabled()
	self:RegisterEvent("BAG_UPDATE_DELAYED", "Refresh")
	self:RegisterEvent("BAG_UPDATE_COOLDOWN", "Refresh")
	self:RegisterEvent("ITEM_LOCK_CHANGED", "OnItemLockChanged")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnItemInfoReceived")
	self:RegisterEvent("PLAYER_MONEY", "Refresh")
	Grimoire:RegisterCallback("ModuleEnabled", self, "Refresh")
	Grimoire:RegisterCallback("ModuleDisabled", self, "Refresh")
end

function M:OnDisable()
	self:Close()
end

local ADDON_NAME, ns = ...
local Homunculus = Homunculus

local ROW_HEIGHT = 36
local ICON_SIZE = 30
local VIEW_WIDTH = 400
local VIEW_HEIGHT = 340
local SCROLLBAR_WIDTH = 24
local STATUS_HEIGHT = 30
local FOOTER_HEIGHT = 28

local M = Homunculus:NewModule("Auctions", {
	addon = ADDON_NAME,
	label = "Auctions",
	defaults = {
		priceTooltips = true,
	},
	options = {
		{ type = "toggle", key = "priceTooltips", label = "Auction prices in tooltips", tooltip = "Item tooltips show the lowest auction price from your last scan or search, and how old it is (learned from Auctionator)." },
	},
})
ns.M = M -- Prices.lua and Shopping.lua add to it

-- The Mainline client exposes C_AuctionHouse; classic-era rules might use the
-- legacy owner-list API instead. Support whichever this client has.
local function HasModernAPI()
	return C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions ~= nil
end

-- Recording ------------------------------------------------------------------

function M:Query()
	if HasModernAPI() then
		C_AuctionHouse.QueryOwnedAuctions({})
	elseif GetOwnerAuctionItems then
		GetOwnerAuctionItems()
	end
end

local function ReadModern(now)
	local list = {}
	for i = 1, C_AuctionHouse.GetNumOwnedAuctions() do
		local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
		if info then
			local itemID = info.itemKey and info.itemKey.itemID
			list[#list + 1] = {
				itemID = itemID,
				name = itemID and C_Item.GetItemNameByID(itemID) or Homunculus.ItemNameFromLink(info.itemLink),
				link = info.itemLink or (itemID and select(2, C_Item.GetItemInfo(itemID))),
				icon = itemID and C_Item.GetItemIconByID(itemID),
				count = info.quantity,
				buyout = info.buyoutAmount,
				bid = info.bidAmount,
				expiresAt = info.timeLeftSeconds and (now + info.timeLeftSeconds),
				sold = info.status == Enum.AuctionStatus.Sold,
			}
		end
	end
	return list
end

local function ReadLegacy()
	local list = {}
	for i = 1, GetNumAuctionItems("owner") do
		local name, texture, count, quality, _, _, _, minBid, _, buyout, bidAmount, _, _, _, _, saleStatus, itemID = GetAuctionItemInfo("owner", i)
		list[#list + 1] = {
			itemID = itemID,
			name = name,
			link = GetAuctionItemLink("owner", i),
			icon = texture,
			count = count,
			quality = quality,
			buyout = buyout,
			bid = (bidAmount and bidAmount > 0) and bidAmount or minBid,
			timeLeft = GetAuctionItemTimeLeft("owner", i), -- 1 (short) .. 4 (very long)
			sold = saleStatus == 1,
		}
	end
	return list
end

function M:Record()
	local now = time()
	local list = HasModernAPI() and ReadModern(now) or ReadLegacy()
	Homunculus:GetCharacterStore().auctions = { scannedAt = now, list = list }
	Homunculus:Fire("AuctionsScanned")
	self:Refresh()
end

-- Mail -------------------------------------------------------------------------
-- Auction results arrive by mail. Sale invoices and "Auction expired/cancelled"
-- mails that arrived after the snapshot mark matching auctions, so the viewer stays
-- accurate without going back to the auction house.
--
-- The inbox is re-read many times, so marking must be idempotent: for each item name
-- we only ever top up to the number of matching mails, and marks are never removed
-- (the mail may be collected later, but the auction is still over).

local MAIL_LIFETIME = 30 * 86400 -- auction house mail lasts 30 days

-- Turns a Blizzard format string like "Auction expired: %s" into a Lua pattern.
local function SubjectPattern(format)
	if not format then return nil end
	local escaped = format:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	return "^" .. escaped:gsub("%%%%s", "(.+)") .. "$"
end

local EXPIRED_PATTERNS = {
	SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT),
	SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT),
}

local function EndedItemName(subject)
	for _, pattern in ipairs(EXPIRED_PATTERNS) do
		local name = subject and subject:match(pattern)
		if name then
			return name
		end
	end
end

-- Returns { sold = { [itemName] = n }, expired = { [itemName] = n } } for mail
-- that arrived after `since`. Arrival is estimated from the mail's days left.
local function ReadMailOutcomes(since)
	local outcomes = { sold = {}, expired = {} }
	local now = time()
	for i = 1, GetInboxNumItems() do
		local _, _, _, subject, _, _, daysLeft = GetInboxHeaderInfo(i)
		local arrivedAt = now + (daysLeft or 0) * 86400 - MAIL_LIFETIME
		if arrivedAt >= since then
			local invoiceType, itemName = GetInboxInvoiceInfo(i)
			local outcome
			if itemName and (invoiceType == "seller" or invoiceType == "seller_temp_invoice") then
				outcome = "sold"
			else
				itemName = EndedItemName(subject)
				outcome = itemName and "expired"
			end
			if outcome then
				outcomes[outcome][itemName] = (outcomes[outcome][itemName] or 0) + 1
			end
		end
	end
	return outcomes
end

local function ApplyOutcome(list, counts, outcome)
	local changed = false
	for itemName, wanted in pairs(counts) do
		local marked = 0
		for _, auction in ipairs(list) do
			if auction.name == itemName and auction.mailOutcome == outcome then
				marked = marked + 1
			end
		end
		for _, auction in ipairs(list) do
			if marked >= wanted then break end
			if auction.name == itemName and not auction.mailOutcome and not auction.sold then
				auction.mailOutcome = outcome
				auction.sold = outcome == "sold" or nil
				auction.expired = outcome == "expired" or nil
				marked = marked + 1
				changed = true
			end
		end
	end
	return changed
end

function M:OnMailUpdate()
	local auctions = Homunculus:GetCharacterStore().auctions
	if not auctions then return end
	local outcomes = ReadMailOutcomes(auctions.scannedAt)
	local soldChanged = ApplyOutcome(auctions.list, outcomes.sold, "sold")
	local expiredChanged = ApplyOutcome(auctions.list, outcomes.expired, "expired")
	auctions.mailCheckedAt = time()
	if soldChanged or expiredChanged then
		Homunculus:Fire("AuctionsScanned")
	end
	self:Refresh()
end

local function IsAuctioneer(interactionType)
	return Enum.PlayerInteractionType and interactionType == Enum.PlayerInteractionType.Auctioneer
end

function M:OnInteractionShow(_, interactionType)
	if IsAuctioneer(interactionType) then
		self.atAuctionHouse = true
		self:Query()
		self:Refresh()
	end
end

function M:OnInteractionHide(_, interactionType)
	if IsAuctioneer(interactionType) then
		self.atAuctionHouse = false
		self.shopping = nil -- a search can only run at the auction house
		self:Refresh()
	end
end

function M:OnAuctionsChanged()
	if self.atAuctionHouse then
		self:Query()
	end
end

-- Viewer -----------------------------------------------------------------------

local function TimeLeftText(auction)
	if auction.sold then
		return "|cff20ff20Sold|r"
	elseif auction.expired then
		return "|cffff2020Expired|r"
	elseif auction.expiresAt then
		local remaining = auction.expiresAt - time()
		if remaining <= 0 then
			return "|cffff2020Expired|r"
		end
		return SecondsToTime(remaining, true)
	elseif auction.timeLeft then
		return _G["AUCTION_TIME_LEFT" .. auction.timeLeft] or ""
	end
	return ""
end

function M:Build()
	local frame = Homunculus:CreateWindow("Auctions", AUCTIONS or "Auctions", self)
	frame:SetContentSize(VIEW_WIDTH + SCROLLBAR_WIDTH, STATUS_HEIGHT + VIEW_HEIGHT + FOOTER_HEIGHT)
	frame:SetScript("OnShow", function() self:Refresh() end)
	self.frame = frame

	-- Whose auctions these are, class-colored (ADR 0003).
	self.picker = Homunculus.CreateCharacterPicker(frame.content, "auctions", function(charKey)
		self.charKey = charKey
		self:Refresh()
	end)
	self.picker:SetPoint("TOPLEFT")
	self.status = frame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.status:SetPoint("LEFT", self.picker, "RIGHT", 8, 0)

	local scroll, child = Homunculus.CreateScrollArea(frame.content, "HomunculusAuctionsScroll")
	scroll:SetPoint("TOPLEFT", 0, -STATUS_HEIGHT)
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH, FOOTER_HEIGHT)
	self.list = child
	self.rows = {}

	self.total = frame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	self.total:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH, 6)

	-- Price scan and shopping lists (Prices.lua, Shopping.lua).
	self.scanButton = CreateFrame("Button", nil, frame.content, "UIPanelButtonTemplate")
	self.scanButton:SetSize(100, 22)
	self.scanButton:SetPoint("BOTTOMLEFT")
	self.scanButton:SetText("Scan prices")
	self.scanButton:SetScript("OnClick", function() self:StartScan() end)
	self.shoppingButton = CreateFrame("Button", nil, frame.content, "UIPanelButtonTemplate")
	self.shoppingButton:SetSize(110, 22)
	self.shoppingButton:SetPoint("LEFT", self.scanButton, "RIGHT", 6, 0)
	self.shoppingButton:SetText("Shopping lists")
	self.shoppingButton:SetScript("OnClick", function() self:ToggleShopping() end)
end

function M:GetRow(index)
	local row = self.rows[index]
	if not row then
		row = CreateFrame("Frame", nil, self.list)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT")

		row.slot = Homunculus.CreateDisplaySlot(row)
		row.slot:SetSize(ICON_SIZE, ICON_SIZE)
		row.slot:SetPoint("LEFT", 2, 0)

		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.name:SetPoint("TOPLEFT", row.slot, "TOPRIGHT", 8, -2)
		row.name:SetPoint("RIGHT", -120, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)

		row.timeLeft = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.timeLeft:SetPoint("BOTTOMLEFT", row.slot, "BOTTOMRIGHT", 8, 2)

		row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.price:SetPoint("RIGHT", -4, 0)
		row.price:SetJustifyH("RIGHT")

		self.rows[index] = row
	end
	return row
end

function M:Refresh()
	self:UpdateShopping()
	if not self.frame or not self.frame:IsShown() then return end
	self.scanButton:SetEnabled((self:CanScan()))
	self.scanButton:SetText(self.scan and "Scanning..." or "Scan prices")
	local isCurrent = self.charKey == Homunculus.db.charKey
	local auctions = Homunculus:GetCharacterStore(self.charKey).auctions

	if isCurrent and self.atAuctionHouse then
		self.status:SetText("|cff20ff20Live|r: at the auction house")
	elseif auctions then
		local text = "Updated " .. Homunculus.FormatAgo(auctions.scannedAt)
		if auctions.mailCheckedAt and auctions.mailCheckedAt > auctions.scannedAt then
			text = text .. " · mail " .. Homunculus.FormatAgo(auctions.mailCheckedAt)
		end
		self.status:SetText(text)
	else
		self.status:SetText(isCurrent and "Visit an auctioneer to record." or "No auctions recorded.")
	end

	local list = auctions and auctions.list or {}
	local total = 0
	for i, auction in ipairs(list) do
		local row = self:GetRow(i)
		Homunculus.SetDisplaySlotItem(row.slot, auction)
		row.name:SetText(auction.link or "?")
		row.timeLeft:SetText(TimeLeftText(auction))
		local price = (auction.buyout and auction.buyout > 0) and auction.buyout or auction.bid or 0
		row.price:SetText(Homunculus.FormatMoney(price))
		row:Show()
		if not auction.sold and not auction.expired then
			total = total + price
		end
	end
	for i = #list + 1, #self.rows do
		self.rows[i]:Hide()
	end

	self.list:SetHeight(math.max(1, #list * ROW_HEIGHT))
	self.total:SetText(#list > 0 and ("Listed value: " .. Homunculus.FormatMoney(total)) or "")
end

function M:Toggle()
	if not self.frame then
		self:Build()
		self.picker:SetCharacter(Homunculus.db.charKey)
	end
	self.frame:SetShown(not self.frame:IsShown())
end

-- Lifecycle --------------------------------------------------------------------

function M:OnInitialize()
	Homunculus:RegisterCommand("auctions", "auctions [shopping] - your saved auctions, or your shopping lists", function(arg)
		if not self:IsEnabled() then return end
		if (arg or ""):lower() == "shopping" then
			self:ToggleShopping()
		else
			self:Toggle()
		end
	end)
end

function M:OnEnable()
	self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "OnInteractionShow")
	self:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "OnInteractionHide")
	-- Modern API
	self:RegisterEvent("OWNED_AUCTIONS_UPDATED", "Record")
	self:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED", "OnAuctionsChanged")
	self:RegisterEvent("AUCTION_CANCELED", "OnAuctionsChanged")
	-- Legacy API
	self:RegisterEvent("AUCTION_OWNED_LIST_UPDATE", "Record")
	self:RegisterEvent("AUCTION_ITEM_LIST_UPDATE", "OnItemList") -- price scan and shopping searches
	-- Sales and expiries arriving by mail
	self:RegisterEvent("MAIL_INBOX_UPDATE", "OnMailUpdate")
	self:HookPriceTooltips() -- hooks can't be removed; AddPrice checks IsEnabled()
end

function M:OnDisable()
	self.atAuctionHouse = false
	self.scan, self.shopping = nil, nil
	if self.shoppingWindow then self.shoppingWindow:Hide() end
	if self.frame then
		self.frame:Hide()
	end
end

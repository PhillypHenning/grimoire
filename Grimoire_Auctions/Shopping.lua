local _, ns = ...
local Grimoire = Grimoire
local M = ns.M

-- Shopping lists (learned from Auctionator, 2026-10-16): named lists of item names. At the
-- auction house, Search looks up each item in turn and shows its cheapest price per unit
-- and how many are listed; prices found are saved for tooltips too.
--
-- GrimoireAuctionsDB.lists = { { name, items = { "Peacebloom", ... } }, ... }
-- GrimoireAuctionsDB.results[realm][lower-case item name] = { price, quantity, time } (price nil: none listed)

local WIDTH, HEIGHT = 420, 360
local ROW_HEIGHT = 22
local SCROLLBAR = 28
local QUERY_TIMEOUT = 10  -- seconds before giving up on one item
local QUERY_GAP = 0.4     -- pause between searches

local function Key(name) return name:lower() end

function M:Results()
	local results = self:Store().results
	local realm = GetRealmName()
	results[realm] = results[realm] or {}
	return results[realm]
end

function M:CurrentList()
	local lists = self:Store().lists
	for _, list in ipairs(lists) do
		if list.name == self.listName then return list end
	end
	self.listName = lists[1] and lists[1].name
	return lists[1]
end

-- Searching ------------------------------------------------------------------------------------

local function ModernSearch()
	return C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and C_AuctionHouse.GetBrowseResults
end

function M:SearchList()
	local list = self:CurrentList()
	if not self.atAuctionHouse then
		self:Print("Open the auction house first.")
		return
	end
	if not list or #list.items == 0 or self.shopping or self.scan then return end
	self.shopping = { items = { unpack(list.items) }, index = 0 }
	self:Log("info", "shopping search: %d items (%s API)", #list.items, ModernSearch() and "modern" or "legacy")
	self:NextShoppingQuery()
end

function M:SaveResult(name, price, quantity, itemID)
	self:Results()[Key(name)] = { price = price, quantity = quantity, time = time() }
	if itemID and price then self:SavePrice(itemID, price) end
end

function M:NextShoppingQuery()
	local shopping = self.shopping
	if not shopping then return end
	shopping.index = shopping.index + 1
	local name = shopping.items[shopping.index]
	self:UpdateShopping()
	if not name then
		self.shopping = nil
		self:UnregisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		self:UpdateShopping()
		return
	end
	shopping.current, shopping.sent = name, nil
	local token = {}
	shopping.token = token
	C_Timer.After(QUERY_TIMEOUT, function()
		if self.shopping and self.shopping.token == token then
			self:Log("warn", "shopping: no answer for %s", name)
			self:NextShoppingQuery()
		end
	end)
	self:SendShoppingQuery()
end

-- Waits until the auction house takes a query, then sends it.
function M:SendShoppingQuery()
	local shopping = self.shopping
	if not shopping or shopping.sent then return end
	if ModernSearch() then
		self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "OnBrowseResults")
		local sorts = Enum.AuctionHouseSortOrder and { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } } or {}
		shopping.sent = true
		C_AuctionHouse.SendBrowseQuery({ searchString = shopping.current, sorts = sorts, filters = {} })
	elseif CanSendAuctionQuery and CanSendAuctionQuery() then
		shopping.sent = true
		QueryAuctionItems(shopping.current, nil, nil, 0, nil, nil, false, true, nil)
	else
		C_Timer.After(0.3, function() self:SendShoppingQuery() end)
	end
end

local function Next(self)
	C_Timer.After(QUERY_GAP, function() self:NextShoppingQuery() end)
end

-- Modern results: one row per item kind, with its lowest price.
function M:OnBrowseResults()
	local shopping = self.shopping
	if not (shopping and shopping.sent) then return end
	local wanted = Key(shopping.current)
	local price, quantity, itemID
	for _, result in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
		local id = result.itemKey and result.itemKey.itemID
		local name = id and C_Item.GetItemNameByID(id)
		if name and Key(name) == wanted and result.minPrice and (not price or result.minPrice < price) then
			price, quantity, itemID = result.minPrice, result.totalQuantity, id
		end
	end
	self:SaveResult(shopping.current, price, quantity, itemID)
	shopping.token = nil
	Next(self)
end

-- Legacy results: every listed auction on the first page with that exact name.
function M:OnShoppingList()
	local shopping = self.shopping
	if not (shopping and shopping.sent and shopping.token) then return end
	local wanted = Key(shopping.current)
	local price, quantity, itemID = nil, 0, nil
	for i = 1, GetNumAuctionItems("list") do
		local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = GetAuctionItemInfo("list", i)
		if name and Key(name) == wanted then
			quantity = quantity + (count or 1)
			local unit = buyout and buyout > 0 and buyout / math.max(count or 1, 1)
			if unit and (not price or unit < price) then price, itemID = unit, id end
		end
	end
	self:SaveResult(shopping.current, price and math.floor(price + 0.5), quantity > 0 and quantity or nil, itemID)
	shopping.token = nil
	Next(self)
end

-- Window ---------------------------------------------------------------------------------------

function M:BuildShopping()
	local frame = Grimoire:CreateWindow("Shopping", "Shopping lists", self)
	frame:SetContentSize(WIDTH, HEIGHT)
	frame:HookScript("OnShow", function() self:UpdateShopping() end)
	self.shoppingWindow = frame
	local content = frame.content

	local function Button(text, width, onClick)
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetSize(width, 22)
		button:SetText(text)
		button:SetScript("OnClick", onClick)
		return button
	end

	frame.picker = Button("", 200, function(b)
		local entries = { { text = "Lists", isTitle = true } }
		for _, list in ipairs(self:Store().lists) do
			entries[#entries + 1] = { text = list.name, radio = true,
				checked = function() return self.listName == list.name end,
				func = function() self.listName = list.name; self:UpdateShopping() end }
		end
		Grimoire.OpenMenu(b, entries)
	end)
	frame.picker:SetPoint("TOPLEFT")
	frame.delete = Button("Delete list", 96, function()
		local lists = self:Store().lists
		for i, list in ipairs(lists) do
			if list.name == self.listName then table.remove(lists, i) break end
		end
		self.listName = nil
		self:UpdateShopping()
	end)
	frame.delete:SetPoint("TOPRIGHT")

	local box = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	box:SetSize(190, 20)
	box:SetPoint("TOPLEFT", 6, -30)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	frame.box = box
	frame.add = Button("Add item", 96, function() self:AddShoppingItem(box:GetText()) end)
	frame.add:SetPoint("LEFT", box, "RIGHT", 6, 0)
	box:SetScript("OnEnterPressed", function() self:AddShoppingItem(box:GetText()) end)
	frame.new = Button("New list", 96, function() self:NewShoppingList(box:GetText()) end)
	frame.new:SetPoint("LEFT", frame.add, "RIGHT", 6, 0)

	local listBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(listBg)
	listBg:SetPoint("TOPLEFT", 0, -58)
	listBg:SetPoint("BOTTOMRIGHT", 0, 30)
	local scroll, child = Grimoire.CreateScrollArea(listBg, "GrimoireShoppingScroll")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 6)
	frame.listChild = child
	frame.rows = {}

	frame.search = Button("Search", 96, function() self:SearchList() end)
	frame.search:SetPoint("BOTTOMLEFT")
	frame.status = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.status:SetPoint("LEFT", frame.search, "RIGHT", 8, 0)
	frame.status:SetPoint("RIGHT")
	frame.status:SetJustifyH("LEFT")
end

function M:NewShoppingList(name)
	name = (name or ""):match("^%s*(.-)%s*$")
	if name == "" then
		self:Print("Type the new list's name in the box first.")
		return
	end
	local lists = self:Store().lists
	lists[#lists + 1] = { name = name, items = {} }
	self.listName = name
	self.shoppingWindow.box:SetText("")
	self:UpdateShopping()
end

function M:AddShoppingItem(name)
	name = (name or ""):match("^%s*(.-)%s*$")
	-- A shift-clicked item link becomes its name.
	name = Grimoire.ItemNameFromLink(name) or name
	if name == "" then return end
	local list = self:CurrentList()
	if not list then
		self:Print("Make a list first: type its name and press New list.")
		return
	end
	list.items[#list.items + 1] = name
	self.shoppingWindow.box:SetText("")
	self:UpdateShopping()
end

local function ShoppingRow(frame, index)
	local row = frame.rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, frame.listChild)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT")
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.name:SetPoint("LEFT", 4, 0)
	row.price = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.price:SetPoint("RIGHT", -28, 0)
	row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
	row.remove:SetSize(22, 22)
	row.remove:SetPoint("RIGHT")
	frame.rows[index] = row
	return row
end

function M:UpdateShopping()
	local frame = self.shoppingWindow
	if not frame or not frame:IsShown() then return end
	local list = self:CurrentList()
	frame.picker:SetText(list and list.name or "(no lists yet)")
	frame.delete:SetEnabled(list ~= nil)
	local results = self:Results()
	local items = list and list.items or {}
	for i, name in ipairs(items) do
		local row = ShoppingRow(frame, i)
		row.name:SetText(name)
		local result = results[Key(name)]
		if self.shopping and self.shopping.current == name then
			row.price:SetText("|cffffd200searching...|r")
		elseif not result then
			row.price:SetText("|cff9d9d9dnot searched|r")
		elseif not result.price then
			row.price:SetText(("|cff9d9d9dnone listed (%s)|r"):format(Grimoire.FormatAgo(result.time)))
		else
			row.price:SetText(("%s  x%d |cff9d9d9d(%s)|r"):format(Grimoire.FormatMoney(result.price), result.quantity or 0,
				Grimoire.FormatAgo(result.time)))
		end
		row.remove:SetScript("OnClick", function()
			table.remove(list.items, i)
			self:UpdateShopping()
		end)
		row:Show()
	end
	for i = #items + 1, #frame.rows do frame.rows[i]:Hide() end
	frame.listChild:SetHeight(math.max(1, #items * ROW_HEIGHT))

	frame.search:SetEnabled(self.atAuctionHouse and list ~= nil and #items > 0 and not self.shopping and not self.scan)
	if self.shopping then
		frame.status:SetText(("Searching %d of %d..."):format(math.min(self.shopping.index, #self.shopping.items), #self.shopping.items))
	elseif not self.atAuctionHouse then
		frame.status:SetText("Search works at the auction house.")
	else
		frame.status:SetText("Prices are per item, cheapest listed.")
	end
end

function M:ToggleShopping()
	if not self.shoppingWindow then self:BuildShopping() end
	self.shoppingWindow:SetShown(not self.shoppingWindow:IsShown())
end

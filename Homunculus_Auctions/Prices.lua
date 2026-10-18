local _, ns = ...
local Homunculus = Homunculus
local M = ns.M

-- Auction prices (learned from Auctionator, 2026-10-16). At the auction house, "Scan
-- prices" reads every auction and saves the lowest buyout per item (per unit, per realm,
-- with the time). Item tooltips then show that price and how old it is. Shopping searches
-- (Shopping.lua) save prices too.
--
-- A full scan is allowed once every 15 minutes and can take a while on a big auction
-- house, so it's a button rather than automatic. Both auction APIs are supported:
--   modern  C_AuctionHouse.ReplicateItems -> REPLICATE_ITEM_LIST_UPDATE
--   legacy  QueryAuctionItems(..., getAll) -> AUCTION_ITEM_LIST_UPDATE
-- The Debug log records which one ran.
--
-- HomunculusAuctionsDB.prices[realm][itemID] = { price = copper per unit, time }

local CHUNK = 500 -- auctions read per frame, so a big scan doesn't freeze the game

function M:Store()
	HomunculusAuctionsDB = Homunculus.CopyDefaults({ prices = {}, lists = {}, results = {} }, HomunculusAuctionsDB or {})
	return HomunculusAuctionsDB
end

function M:Prices()
	local prices = self:Store().prices
	local realm = GetRealmName()
	prices[realm] = prices[realm] or {}
	return prices[realm]
end

function M:SavePrice(itemID, price)
	if itemID and price and price > 0 then
		self:Prices()[itemID] = { price = math.floor(price + 0.5), time = time() }
	end
end

local function UnitPrice(buyout, count)
	if buyout and buyout > 0 then
		return buyout / math.max(count or 1, 1)
	end
end

-- Keeps the lowest unit price seen per item.
local function Keep(found, itemID, price)
	if itemID and price and (not found[itemID] or price < found[itemID]) then
		found[itemID] = price
	end
end

-- Full scan ---------------------------------------------------------------------------------

function M:CanScan()
	if not self.atAuctionHouse then return false, "Open the auction house first." end
	if self.scan then return false, "Already scanning." end
	if C_AuctionHouse and C_AuctionHouse.ReplicateItems then return true end
	if QueryAuctionItems and CanSendAuctionQuery then
		local _, canQueryAll = CanSendAuctionQuery()
		if canQueryAll then return true end
		return false, "The auction house allows a full scan every 15 minutes."
	end
	return false, "This client can't scan the auction house."
end

function M:StartScan()
	local ok, why = self:CanScan()
	if not ok then
		self:Print(why)
		return
	end
	self.scan = { found = {} }
	if C_AuctionHouse and C_AuctionHouse.ReplicateItems then
		self.scan.api = "modern"
		self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", "OnReplicateList")
		C_AuctionHouse.ReplicateItems()
	else
		self.scan.api = "legacy"
		QueryAuctionItems("", nil, nil, 0, nil, nil, true, false, nil)
	end
	self:Log("info", "price scan started (%s API)", self.scan.api)
	self:Print("Scanning auction prices...")
	self:Refresh()
end

-- Reads total entries a chunk per frame, then calls done.
local function ReadInChunks(total, readOne, done)
	local index = 0
	local function Step()
		local last = math.min(index + CHUNK, total)
		for i = index + 1, last do
			pcall(readOne, i)
		end
		index = last
		if index < total then
			C_Timer.After(0, Step)
		else
			done()
		end
	end
	Step()
end

function M:OnReplicateList()
	self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	local scan = self.scan
	if not scan or scan.reading then return end
	scan.reading = true
	ReadInChunks(C_AuctionHouse.GetNumReplicateItems(), function(i)
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
		Keep(scan.found, itemID, UnitPrice(buyout, count))
	end, function() self:FinishScan() end)
end

-- Legacy full scan results (called from the shared AUCTION_ITEM_LIST_UPDATE handler).
function M:ReadLegacyScan()
	local scan = self.scan
	if scan.reading then return end
	scan.reading = true
	ReadInChunks(GetNumAuctionItems("list"), function(i)
		local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
		Keep(scan.found, itemID, UnitPrice(buyout, count))
	end, function() self:FinishScan() end)
end

function M:FinishScan()
	local scan = self.scan
	self.scan = nil
	local items = 0
	for itemID, price in pairs(scan.found) do
		self:SavePrice(itemID, price)
		items = items + 1
	end
	self:Store().lastScan = time()
	self:Log("info", "price scan done (%s API): %d items", scan.api, items)
	self:Print(("Prices saved for %d items."):format(items))
	self:Refresh()
end

-- AUCTION_ITEM_LIST_UPDATE serves the legacy scan and legacy shopping searches.
function M:OnItemList()
	if self.scan and self.scan.api == "legacy" then
		self:ReadLegacyScan()
	elseif self.shopping then
		self:OnShoppingList()
	end
end

-- Tooltips ------------------------------------------------------------------------------------

local function AddPrice(tooltip, itemID)
	if not (M:IsEnabled() and M.db.priceTooltips) then return end
	local entry = M:Prices()[itemID]
	if not entry then return end
	tooltip:AddDoubleLine("Auction", ("%s |cff9d9d9d(%s)|r"):format(Homunculus.FormatMoney(entry.price), Homunculus.FormatAgo(entry.time)),
		nil, nil, nil, 1, 1, 1)
end

function M:HookPriceTooltips()
	if self.priceTooltipsHooked then return end
	self.priceTooltipsHooked = true
	Homunculus.AddItemTooltipLines(AddPrice)
end

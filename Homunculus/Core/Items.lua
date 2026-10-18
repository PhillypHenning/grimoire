local Homunculus = Homunculus

-- Shared item data (learned from Syndicator, 2026-10-16): how many of each item every
-- character has, so any component can answer "who has this?". Core keeps each character's
-- bag counts current; bank counts come from the snapshot the Bank component saves.
--
--   HomunculusDB.global.characters["Name - Realm"].bagCounts = { [itemID] = count }
--   Homunculus:GetItemCounts(itemID) -> { { charKey, bags, bank }, ... } (current character
--     first, then by name; only characters that have some)

local SCAN_DELAY = 0.5 -- bag changes come in bursts: count once they settle

function Homunculus:ScanBagCounts()
	if not self.db then return end
	local counts = {}
	for _, bag in ipairs(self.GetBagIDs()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
			end
		end
	end
	self:GetCharacterStore().bagCounts = counts
end

-- Bank counts from the Bank component's snapshot, worked out once per snapshot.
local bankCache = {}

local function BankCounts(charKey, store)
	local bank = store.bank
	if not (bank and bank.containers) then return nil end
	local cached = bankCache[charKey]
	if cached and cached.scannedAt == bank.scannedAt then return cached.counts end
	local counts = {}
	for _, container in ipairs(bank.containers) do
		for _, item in ipairs(container.slots or {}) do
			if item and item.itemID then
				counts[item.itemID] = (counts[item.itemID] or 0) + (item.count or 1)
			end
		end
	end
	bankCache[charKey] = { scannedAt = bank.scannedAt, counts = counts }
	return counts
end

function Homunculus:GetItemCounts(itemID)
	local result = {}
	if not (self.db and itemID) then return result end
	for charKey, store in pairs(self.db.global.characters) do
		local bags = store.bagCounts and store.bagCounts[itemID] or 0
		local bankCounts = BankCounts(charKey, store)
		local bank = bankCounts and bankCounts[itemID] or 0
		if bags + bank > 0 then
			result[#result + 1] = { charKey = charKey, bags = bags, bank = bank }
		end
	end
	local current = self.db.charKey
	table.sort(result, function(a, b)
		if (a.charKey == current) ~= (b.charKey == current) then return a.charKey == current end
		return a.charKey < b.charKey
	end)
	return result
end

-- Keeping the current character's counts up to date.
local queued = false
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:SetScript("OnEvent", function()
	if queued then return end
	queued = true
	C_Timer.After(SCAN_DELAY, function()
		queued = false
		Homunculus:ScanBagCounts()
	end)
end)

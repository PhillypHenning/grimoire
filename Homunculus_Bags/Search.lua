-- Bag search (learned from Baganator, 2026-10-16). Plain Lua 5.1 with no WoW API, so
-- scripts/bags/test.lua tests it outside the game.
--
--   local match = Search.Compile(query)   -- nil for an empty query (everything matches)
--   match(item) -> true / false
--   item = { name, quality (0-5), itemType, subType, slot (e.g. "INVTYPE_HEAD"),
--            ilvl, bind ("boe", "bop" or nil) }      -- any field may be missing
--
-- Terms:
--   words         the name, item type or subtype contains it ("linen", "cloth", "potion")
--   junk / poor, common, uncommon, rare, epic, legendary      quality
--   boe, bop      binds when equipped / already bound or binds on pickup
--   head, neck, shoulder, back, chest, wrist, hands, waist, legs, feet, finger, trinket,
--   mainhand, offhand, shield, ranged, twohand, bag           equipment slot
--   >20  <10  10-15                                            item level
-- Combine: a space or & means "and", | means "or" (looser than and), ! means "not".

local _, ns = ...
local Search = {}

local QUALITY = { junk = 0, poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

local SLOTS = {
	head = { INVTYPE_HEAD = true }, neck = { INVTYPE_NECK = true },
	shoulder = { INVTYPE_SHOULDER = true }, back = { INVTYPE_CLOAK = true },
	chest = { INVTYPE_CHEST = true, INVTYPE_ROBE = true }, wrist = { INVTYPE_WRIST = true },
	hands = { INVTYPE_HAND = true }, waist = { INVTYPE_WAIST = true },
	legs = { INVTYPE_LEGS = true }, feet = { INVTYPE_FEET = true },
	finger = { INVTYPE_FINGER = true }, trinket = { INVTYPE_TRINKET = true },
	mainhand = { INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPON = true },
	offhand = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true },
	shield = { INVTYPE_SHIELD = true },
	ranged = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true },
	twohand = { INVTYPE_2HWEAPON = true }, bag = { INVTYPE_BAG = true },
}
SLOTS.ring, SLOTS.cloak = SLOTS.finger, SLOTS.back

local function Contains(text, word)
	return text ~= nil and text:lower():find(word, 1, true) ~= nil
end

-- One term -> a test.
local function Term(word)
	local negate = false
	while word:sub(1, 1) == "!" do
		negate = not negate
		word = word:sub(2)
	end
	if word == "" then return nil end
	local test
	local low, high = word:match("^(%d+)%-(%d+)$")
	local above = word:match("^>(%d+)$")
	local below = word:match("^<(%d+)$")
	if low then
		low, high = tonumber(low), tonumber(high)
		test = function(item) return item.ilvl ~= nil and item.ilvl >= low and item.ilvl <= high end
	elseif above then
		above = tonumber(above)
		test = function(item) return item.ilvl ~= nil and item.ilvl > above end
	elseif below then
		below = tonumber(below)
		test = function(item) return item.ilvl ~= nil and item.ilvl < below end
	elseif QUALITY[word] then
		local quality = QUALITY[word]
		test = function(item) return item.quality == quality end
	elseif word == "boe" or word == "bop" then
		test = function(item) return item.bind == word end
	elseif SLOTS[word] then
		local slots = SLOTS[word]
		test = function(item) return item.slot ~= nil and slots[item.slot] == true end
	else
		test = function(item)
			return Contains(item.name, word) or Contains(item.itemType, word) or Contains(item.subType, word)
		end
	end
	if negate then
		return function(item) return not test(item) end
	end
	return test
end

function Search.Compile(query)
	query = (query or ""):lower()
	local alternatives = {}
	for alternative in (query .. "|"):gmatch("([^|]*)|") do
		local terms = {}
		for word in alternative:gsub("&", " "):gmatch("%S+") do
			terms[#terms + 1] = Term(word)
		end
		if #terms > 0 then alternatives[#alternatives + 1] = terms end
	end
	if #alternatives == 0 then return nil end
	return function(item)
		for _, terms in ipairs(alternatives) do
			local all = true
			for _, test in ipairs(terms) do
				if not test(item) then
					all = false
					break
				end
			end
			if all then return true end
		end
		return false
	end
end

if type(ns) == "table" then
	ns.Search = Search
end
return Search

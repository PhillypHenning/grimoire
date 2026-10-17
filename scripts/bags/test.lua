-- Tests the bag search outside the game.
--   lua scripts/bags/test.lua
-- Exits 1 on the first failure.

local here = arg[0]:match("^(.*)[/\\]") or "."
local Search = dofile(here .. "/../../Grimoire_Bags/Search.lua")

local failures = 0
local function check(cond, message)
	if not cond then
		failures = failures + 1
		print("FAIL: " .. message)
	end
end

local linen = { name = "Linen Cloth", quality = 1, itemType = "Trade Goods", subType = "Cloth" }
local helm = { name = "Feet of the Lynx", quality = 2, itemType = "Armor", subType = "Leather", slot = "INVTYPE_FEET", ilvl = 18, bind = "boe" }
local robe = { name = "Robe of Power", quality = 3, itemType = "Armor", subType = "Cloth", slot = "INVTYPE_ROBE", ilvl = 25, bind = "bop" }
local shard = { name = "Soul Shard", quality = 1, itemType = "Miscellaneous" }
local gray = { name = "Broken Fang", quality = 0, itemType = "Miscellaneous" }
local unknown = { name = "Mystery" } -- item info not cached yet

local function matches(query, item)
	local match = Search.Compile(query)
	return match == nil or match(item)
end

check(Search.Compile("") == nil and Search.Compile("   ") == nil, "empty query matches everything")
check(matches("linen", linen) and not matches("linen", shard), "name words")
check(matches("cloth", linen) and matches("cloth", robe), "subtype words")
check(matches("armor", helm) and not matches("armor", linen), "type words")
check(matches("junk", gray) and matches("poor", gray) and not matches("junk", shard), "junk / poor")
check(matches("uncommon", helm) and not matches("uncommon", robe), "quality words")
check(matches("boe", helm) and not matches("boe", robe) and matches("bop", robe), "binding")
check(matches("feet", helm) and matches("chest", robe) and not matches("feet", robe), "slots, robes count as chest")
check(matches(">20", robe) and not matches(">20", helm), "item level above")
check(matches("<20", helm) and not matches("<20", unknown), "item level below; unknown level never matches")
check(matches("15-20", helm) and not matches("15-20", robe), "item level range")
check(matches("armor boe", helm) and not matches("armor boe", robe), "space is and")
check(matches("armor&boe", helm), "& is and")
check(matches("junk|soul", gray) and matches("junk|soul", shard) and not matches("junk|soul", linen), "| is or")
check(matches("!junk", shard) and not matches("!junk", gray), "! is not")
check(matches("armor !boe", robe) and not matches("armor !boe", helm), "not inside and")
check(matches("LINEN", linen), "case-insensitive")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("All bag search tests pass.")

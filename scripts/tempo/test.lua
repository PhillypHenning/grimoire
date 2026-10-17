-- Tests Tempo's analysis and share format outside the game.
--   lua scripts/tempo/test.lua
-- Exits 1 on the first failure.

local here = arg[0]:match("^(.*)[/\\]") or "."
local Cycles = dofile(here .. "/../../Grimoire_Tempo/Cycles.lua")
local Share = dofile(here .. "/../../Grimoire_Tempo/Share.lua")

local failures = 0
local function check(cond, message)
	if not cond then
		failures = failures + 1
		print("FAIL: " .. message)
	end
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

local function cast(t, name, spell) return { t = t, name = name, spell = spell or 1 } end

-- A Warlock fight: opener, then Corruption re-cast starts a cycle, then again.
local fight = {
	duration = 30,
	unit = "damage",
	casts = {
		cast(0, "Shadow Bolt"), cast(2, "Corruption"), cast(4, "Curse of Agony"),
		cast(6, "Shadow Bolt"), cast(8, "Shadow Bolt"),
		cast(12, "Corruption"), cast(14, "Shadow Bolt"), cast(16, "Shadow Bolt"),
		cast(20, "Corruption"), cast(22, "Shadow Bolt"),
	},
	damage = {
		{ t = 1, amount = 100 }, { t = 7, amount = 100 },   -- opener: 200 over 12 s
		{ t = 13, amount = 400 },                           -- cycle 1: 400 over 8 s
		{ t = 21, amount = 100 }, { t = 30, amount = 80 },  -- cycle 2: 180 over 10 s (end included)
	},
}

local segments = Cycles.Split(fight, "WARLOCK")
check(#segments == 3, "three segments, got " .. #segments)
check(segments[1].kind == "opener" and segments[2].kind == "cycle", "opener then cycles")
check(#segments[1].steps == 5, "opener has 5 casts")
check(near(segments[1].length, 12) and segments[1].damage == 200, "opener 12 s, 200 damage")
check(near(segments[2].dps, 50), "cycle 1 is 50 dps, got " .. segments[2].dps)
check(segments[3].damage == 180, "last cycle includes damage at the fight's end")
check(segments[2].steps[1].at == 0 and segments[2].steps[2].at == 2, "steps timed from the segment start")
check(not segments[3].scored, "a 2-cast cycle isn't scored")

local best = Cycles.BestOf(segments)
check(best.cycle == segments[2], "best cycle is cycle 1")
check(best.opener == segments[1], "best opener")

-- Real damage beats percent-of-health, whatever the numbers.
check(Cycles.IsBetter({ scored = true, unit = "damage", dps = 1 }, { scored = true, unit = "health", dps = 50 }),
	"damage outranks health")
check(not Cycles.IsBetter({ scored = false, unit = "damage", dps = 99 }, nil), "unscored never best")

-- A class without upkeep spells: the first spell marks the cycle.
local mage = Cycles.Split({ duration = 10, unit = "damage", damage = {},
	casts = { cast(0, "Frostbolt"), cast(2, "Fire Blast"), cast(4, "Frostbolt") } }, "MAGE")
check(#mage == 2, "mage fight splits on its first spell")

-- Ranks: matching is by name, case-insensitive.
local ranks = Cycles.Split({ duration = 10, unit = "damage", damage = {},
	casts = { cast(0, "Corruption", 172), cast(2, "Shadow Bolt"), cast(4, "corruption", 6222) } }, "WARLOCK")
check(#ranks == 2, "another rank of Corruption still starts a cycle")

-- Pets: sending the pet and its abilities are steps, but never start a cycle.
local petFight = Cycles.Split({ duration = 12, unit = "damage", damage = {},
	casts = {
		{ t = 0, name = "Pet Attack" }, cast(1, "Shadow Bolt"), { t = 2, name = "Firebolt", spell = 3110, pet = true },
		cast(3, "Corruption"), { t = 5, name = "Pet Attack" }, { t = 6, name = "Firebolt", spell = 3110, pet = true },
		cast(8, "Shadow Bolt"),
	} }, "MAGE") -- MAGE: no upkeep list, so the first own spell (Shadow Bolt) marks cycles
check(#petFight == 2 and petFight[2].steps[1].name == "Shadow Bolt", "pet steps don't start cycles; first own spell does")
check(petFight[1].steps[3].pet == true, "pet flag kept on steps")
check(Cycles.ResetSet("MAGE", { { name = "Pet Attack" }, { name = "Frostbolt" } })["frostbolt"], "Pet Attack isn't the fallback reset")

-- Share: round trip.
local rotation = segments[2]
rotation.name, rotation.class, rotation.notes = "Shadow cycle", "WARLOCK", { "Refresh Corruption early." }
local text = Share.Export(rotation)
local back, err = Share.Import(text)
check(back ~= nil, "import of an export works: " .. tostring(err))
if back then
	check(back.name == "Shadow cycle" and back.class == "WARLOCK" and back.kind == "cycle", "fields survive")
	check(#back.steps == #rotation.steps and back.steps[2].name == "Shadow Bolt", "steps survive")
	check(back.unit == "damage" and near(back.dps, 50), "score survives")
	check(back.notes[1] == "Refresh Corruption early.", "notes survive")
end
local petBack = Share.Import(Share.Export({ name = "Pet", kind = "opener", length = 4, steps = {
	{ at = 0, name = "Pet Attack" }, { at = 1.5, spell = 3110, name = "Firebolt", pet = true }, { at = 2, spell = 686, name = "Shadow Bolt" },
} }))
check(petBack and petBack.steps[1].name == "Pet Attack" and petBack.steps[1].spell == nil, "Pet Attack round trip (no spell)")
check(petBack and petBack.steps[2].pet and petBack.steps[2].name == "Firebolt", "pet ability round trip")
check(petBack and not petBack.steps[3].pet, "own spell isn't marked pet")
check(Share.Import("hello") == nil, "text without the header is refused")
check(Share.Import(Share.HEADER .. "\nname: x") == nil, "a rotation without steps is refused")
check(Share.Import(Share.HEADER .. "\nprint('hi')") == nil, "unknown lines are refused")
local crlf = Share.Import(Share.HEADER .. "\r\n0.0 686 Shadow Bolt\r\n")
check(crlf and crlf.steps[1].name == "Shadow Bolt" and crlf.length == 2, "Windows line endings; default length")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("All Tempo tests pass.")

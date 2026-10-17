-- Tempo's analysis: a fight is split into an opener and cycles, and each is scored.
--
-- Plain Lua 5.1 with no WoW API, so the same file runs in the game (loaded by
-- Grimoire_Tempo.toc) and on the command line (scripts/tempo/test.lua).
--
--   fight = { duration, unit = "damage" | "health",   -- what the damage amounts measure
--             casts  = { { t, spell, name }, ... },   -- seconds from the fight's start
--             damage = { { t, amount }, ... } }
--   segment / rotation = { kind = "opener" | "cycle", steps = { { at, spell, name } },
--                          length, damage, dps, unit, scored }
--
-- A cycle ends when an upkeep spell (a DoT, for a Warlock) that's already in it is cast
-- again: that re-cast starts the next cycle. Scores are damage per second, so short and
-- long cycles compare fairly.

local _, ns = ...
local Cycles = {}

-- Spells whose re-cast starts a new cycle. Names, not IDs: every rank of a spell has its
-- own ID, and a rotation should survive learning a new rank.
Cycles.RESET_SPELLS = {
	WARLOCK = { "Corruption", "Curse of Agony", "Immolate", "Siphon Life", "Curse of Doom" },
	PRIEST = { "Shadow Word: Pain", "Devouring Plague", "Vampiric Touch" },
	DRUID = { "Moonfire", "Insect Swarm", "Rake", "Rip" },
	HUNTER = { "Serpent Sting" },
	ROGUE = { "Slice and Dice", "Rupture" },
	WARRIOR = { "Rend" },
	SHAMAN = { "Flame Shock" },
}

Cycles.MIN_CASTS = 3    -- shorter segments are shown but never become "best"
Cycles.MIN_LENGTH = 3   -- seconds

-- "damage" (real numbers) always beats "health" (percent of the target's health lost).
Cycles.UNIT_RANK = { damage = 2, health = 1 }

function Cycles.Key(name)
	return name and name:lower() or ""
end

-- The class's upkeep spells; a class without any uses the fight's first spell instead.
function Cycles.ResetSet(class, casts)
	local set = {}
	for _, name in ipairs(Cycles.RESET_SPELLS[class] or {}) do
		set[Cycles.Key(name)] = true
	end
	if next(set) == nil and casts[1] then
		set[Cycles.Key(casts[1].name)] = true
	end
	return set
end

-- Indexes into casts where a segment starts; the first is always 1.
function Cycles.Boundaries(casts, resetSet)
	local starts, seen = {}, {}
	for i, cast in ipairs(casts) do
		local key = Cycles.Key(cast.name)
		if i == 1 then
			starts[1] = 1
		elseif resetSet[key] and seen[key] then
			starts[#starts + 1] = i
			seen = {}
		end
		seen[key] = true
	end
	return starts
end

-- Damage from `from` up to `to`; the last segment also takes what lands right at the end.
function Cycles.DamageBetween(damage, from, to, inclusive)
	local total = 0
	for _, entry in ipairs(damage or {}) do
		if entry.t >= from and (entry.t < to or (inclusive and entry.t <= to)) then
			total = total + entry.amount
		end
	end
	return total
end

function Cycles.Split(fight, class)
	local casts, segments = fight.casts or {}, {}
	if #casts == 0 then return segments end
	local starts = Cycles.Boundaries(casts, Cycles.ResetSet(class, casts))
	for n, first in ipairs(starts) do
		local nextStart = starts[n + 1]
		local last = (nextStart or #casts + 1) - 1
		-- The opener starts with the fight, so damage landing before the first cast counts.
		local from = n == 1 and math.min(0, casts[1].t) or casts[first].t
		local to = nextStart and casts[nextStart].t or math.max(fight.duration or 0, casts[last].t)
		local steps = {}
		for i = first, last do
			steps[#steps + 1] = { at = casts[i].t - casts[first].t, spell = casts[i].spell, name = casts[i].name }
		end
		local length = to - from
		local damage = Cycles.DamageBetween(fight.damage, from, to, nextStart == nil)
		segments[#segments + 1] = {
			kind = n == 1 and "opener" or "cycle",
			steps = steps,
			length = length,
			damage = damage,
			dps = length > 0 and damage / length or 0,
			unit = fight.unit,
			scored = #steps >= Cycles.MIN_CASTS and length >= Cycles.MIN_LENGTH and fight.unit ~= nil,
		}
	end
	return segments
end

-- Is rotation a better than b (b may be nil)?
function Cycles.IsBetter(a, b)
	if not a or not a.scored then return false end
	if not b then return true end
	local ra, rb = Cycles.UNIT_RANK[a.unit] or 0, Cycles.UNIT_RANK[b.unit] or 0
	if ra ~= rb then return ra > rb end
	return a.dps > b.dps
end

-- The best scored opener and cycle of one fight.
function Cycles.BestOf(segments)
	local best = {}
	for _, segment in ipairs(segments) do
		if Cycles.IsBetter(segment, best[segment.kind]) then
			best[segment.kind] = segment
		end
	end
	return best
end

function Cycles.FormatScore(rotation)
	if not rotation or not rotation.unit then return "no score" end
	if rotation.unit == "health" then
		return ("%.1f%% health/s"):format(rotation.dps or 0)
	end
	return ("%.1f dps"):format(rotation.dps or 0)
end

if type(ns) == "table" then
	ns.Cycles = Cycles -- in game: shared with the rest of Grimoire_Tempo
end
return Cycles

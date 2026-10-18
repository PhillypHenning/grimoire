-- Prophecy plan parser, format version 1 (docs/prophecy/FORMAT.md).
--
-- Plain Lua 5.1 with no WoW API, so the same file runs in the game (loaded by
-- Homunculus_Prophecy.toc) and on the command line (scripts/prophecy/check.lua). It turns
-- plan text into a table and lists errors and warnings with line numbers; it never runs
-- anything from the plan (ADR 0006).
--
--   local plan, errors, warnings = Parser.Parse(text)
--   -- errors / warnings: { { line = n, message = "..." }, ... }; plan is nil on errors
--   -- every step has an `id` and every gate `check` a `key`, for saved progress

local _, ns = ...
local Parser = {}

local KNOWN_ZONES = {}
for zone in ([[
Durotar;Orgrimmar;The Barrens;Mulgore;Thunder Bluff;Stonetalon Mountains;Ashenvale;
Thousand Needles;Desolace;Dustwallow Marsh;Feralas;Tanaris;Un'Goro Crater;Azshara;
Felwood;Winterspring;Moonglade;Silithus;Darkshore;Teldrassil;Darnassus;
Tirisfal Glades;Undercity;Silverpine Forest;Hillsbrad Foothills;Alterac Mountains;
Arathi Highlands;Wetlands;Loch Modan;Dun Morogh;Ironforge;Elwynn Forest;Stormwind City;
Westfall;Redridge Mountains;Duskwood;Stranglethorn Vale;Swamp of Sorrows;
Blasted Lands;Badlands;Searing Gorge;Burning Steppes;Deadwind Pass;The Hinterlands;
Western Plaguelands;Eastern Plaguelands]]):gmatch("[^;]+") do
	KNOWN_ZONES[(zone:gsub("^%s+", ""):gsub("%s+$", ""))] = true
end

local HEADER_KEYWORDS = {
	title = true, subtitle = true, author = true, class = true, race = true, faction = true,
	skills = true, note = true, source = true,
}
local STEP_KINDS = { q = true, p = true, c = true, o = true, n = true }
local QUEST_CONDITIONS = { accept = true, complete = true, turnin = true }

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Short, stable hash of a step's main line (FORMAT.md, "Progress and identity").
-- Plain arithmetic: WoW's Lua has no 5.3 bit operators.
function Parser.Hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967291 -- largest prime below 2^32
	end
	return ("%08x"):format(h)
end

-- Inline markup -------------------------------------------------------------------------------

-- Reads [Quest], {Name} and @coordinates out of a piece of text.
-- Returns { quests = {...}, names = {...}, coords = {...} } or nil, error message.
local function ParseInline(text, zone)
	local found = { quests = {}, names = {}, coords = {} }
	local i, n = 1, #text
	while i <= n do
		local c = text:sub(i, i)
		if c == "\\" then
			i = i + 2
		elseif c == "[" then
			local close = text:find("]", i + 1, true)
			if not close then return nil, "unclosed [ (escape a literal [ as \\[)" end
			local body = text:sub(i + 1, close - 1)
			local name, id = body:match("^(.-)#(%d+)$")
			name = Trim(name or body)
			if name == "" then return nil, "empty quest name []" end
			found.quests[#found.quests + 1] = { name = name, id = tonumber(id) }
			i = close + 1
		elseif c == "{" then
			local close = text:find("}", i + 1, true)
			if not close then return nil, "unclosed { (escape a literal { as \\{)" end
			found.names[#found.names + 1] = Trim(text:sub(i + 1, close - 1))
			i = close + 1
		elseif c == "@" then
			local rest = text:sub(i)
			local x, y, len
			local whole, cx, cy = rest:match("^(@(%d+%.?%d*),(%d+%.?%d*))")
			local coordZone = zone
			if whole then
				x, y, len = cx, cy, #whole
			else
				local whole2, z, zx, zy = rest:match("^(@([^:@%[%]{}]+):(%d+%.?%d*),(%d+%.?%d*))")
				if not whole2 then
					return nil, "malformed coordinate (use @x,y or @Zone Name:x,y; escape a literal @ as \\@)"
				end
				x, y, len, coordZone = zx, zy, #whole2, Trim(z)
			end
			x, y = tonumber(x), tonumber(y)
			if x > 100 or y > 100 then
				return nil, "coordinate out of range (0-100): " .. rest:sub(1, len)
			end
			if not coordZone then
				return nil, "coordinate with no zone: add a `zone` line or write @Zone Name:x,y"
			end
			found.coords[#found.coords + 1] = { zone = coordZone, x = x, y = y }
			i = i + len
		else
			i = i + 1
		end
	end
	return found
end

-- Conditions ------------------------------------------------------------------------------------

-- Parses a completion condition or gate requirement. allowGateOnly lets `check`,
-- `note` and the `soft` modifiers through.
local function ParseCondition(body, zone, allowGateOnly)
	local word, rest = body:match("^(%S+)%s*(.*)$")
	if not word then return nil, "empty condition" end

	if QUEST_CONDITIONS[word] then
		local inline, err = ParseInline(rest, zone)
		if not inline then return nil, err end
		if #inline.quests == 0 then return nil, word .. " needs at least one [Quest Name]" end
		return { type = word, quests = inline.quests }
	elseif word == "level" then
		local n = tonumber(rest:match("^(%d+)%s*$"))
		if not n then return nil, "level needs a number" end
		return { type = "level", value = n }
	elseif word == "skill" then
		local name, value, mods = rest:match("^(.-)%s+(%d+)%s*(.*)$")
		if not name or name == "" then return nil, "skill needs a profession and a number" end
		local condition = { type = "skill", name = name, value = tonumber(value) }
		if mods ~= "" then
			if not allowGateOnly then return nil, "`soft` only applies to gate targets" end
			local min = mods:match("^soft%s+min%s+(%d+)$")
			if min then
				condition.soft, condition.min = true, tonumber(min)
			elseif mods == "soft" then
				condition.soft = true
			else
				return nil, "unknown skill modifier: " .. mods .. " (use soft or soft min <n>)"
			end
		end
		return condition
	elseif word == "item" then
		local name, count = rest:match("^(.-)%s+(%d+)%s*$")
		if not name or name == "" then return nil, "item needs a name and a count" end
		return { type = "item", name = name, value = tonumber(count) }
	elseif word == "learn" then
		if rest == "" then return nil, "learn needs a spell or recipe name" end
		return { type = "learn", name = rest }
	elseif word == "reach" then
		local inline, err = ParseInline(rest, zone)
		if not inline then return nil, err end
		if #inline.coords ~= 1 then return nil, "reach needs one @coordinate" end
		return { type = "reach", coord = inline.coords[1] }
	elseif word == "zone" then
		if rest == "" then return nil, "zone needs a map name" end
		return { type = "zone", name = rest }
	elseif allowGateOnly and word == "check" then
		if rest == "" then return nil, "check needs text" end
		return { type = "check", text = rest }
	elseif allowGateOnly and word == "note" then
		return { type = "note", text = rest }
	end
	return nil, "unknown condition: " .. word
end

-- Plan --------------------------------------------------------------------------------------------

function Parser.Parse(text)
	local errors, warnings = {}, {}
	local function Err(line, message) errors[#errors + 1] = { line = line, message = message } end
	local function Warn(line, message) warnings[#warnings + 1] = { line = line, message = message } end

	local plan = { intro = {}, notes = {}, sources = {}, skills = {}, chapters = {} }
	local chapter, item -- item: the current step or gate, for attribute lines
	local zone
	local ids = {}
	local lineNo = 0

	local function AddParagraph(list, value)
		if value == "" then
			list[#list + 1] = ""
		elseif #list > 0 and list[#list] ~= "" then
			list[#list] = list[#list] .. " " .. value
		else
			list[#list + 1] = value
		end
	end

	for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
		lineNo = lineNo + 1
		local line = raw:gsub("\r$", "")
		local indented = line:match("^[ \t]") ~= nil
		local content = Trim(line)

		if lineNo == 1 then
			if content ~= "prophecy 1" then
				Err(1, "first line must be `prophecy 1`")
				return nil, errors, warnings
			end
			plan.version = 1
		elseif content == "" or content:sub(1, 2) == "--" then
			-- blank or comment
		elseif indented then
			local word, rest = content:match("^(%S+)%s*(.*)$")
			if not item then
				Err(lineNo, "attribute line with no step or gate above it")
			elseif item.isGate then
				local condition, err = ParseCondition(content, zone, true)
				if condition then
					item.requirements[#item.requirements + 1] = condition
				else
					Err(lineNo, err)
				end
			elseif word == "detail" then
				item.details[#item.details + 1] = rest
			elseif word == "reward" then
				item.rewards[#item.rewards + 1] = rest
			elseif word == "verify" then
				item.verify[#item.verify + 1] = rest
			elseif word == "minlevel" then
				item.minlevel = tonumber(rest:match("^(%d+)$"))
				if not item.minlevel then Err(lineNo, "minlevel needs a number") end
			elseif word == "done" then
				local condition, err = ParseCondition(rest, zone, false)
				if condition then
					item.done[#item.done + 1] = condition
				else
					Err(lineNo, err)
				end
			else
				Err(lineNo, "unknown step attribute: " .. word)
			end
		else
			local word, rest = content:match("^(%S+)%s*(.*)$")
			if word == ">" or content:sub(1, 1) == ">" then
				local value = Trim(content:sub(2))
				AddParagraph(chapter and chapter.why or plan.intro, value)
			elseif word == "chapter" then
				local badge, title, levels = rest:match("^(.-)%s*|%s*(.-)%s*|%s*(.-)$")
				if not badge or title == "" then
					Err(lineNo, "chapter needs `chapter <badge> | <title> | <levels>`")
				else
					chapter = {
						badge = badge, title = title, levels = levels, type = "route",
						id = "ch-" .. badge, why = {}, steps = {}, line = lineNo,
					}
					plan.chapters[#plan.chapters + 1] = chapter
					item = nil
				end
			elseif word == "id" or word == "type" then
				if not chapter then
					Err(lineNo, word .. " outside a chapter")
				elseif #chapter.steps > 0 or chapter.gate then
					Err(lineNo, word .. " must come right after the chapter line")
				elseif word == "id" then
					if not rest:match("^[%w_%-]+$") then
						Err(lineNo, "id may only use letters, digits, - and _")
					else
						chapter.id = rest
					end
				elseif rest == "route" or rest == "reference" then
					chapter.type = rest
				else
					Err(lineNo, "type must be route or reference")
				end
			elseif word == "zone" then
				if rest == "" then
					Err(lineNo, "zone needs a map name")
				else
					zone = rest
					if not KNOWN_ZONES[zone] then Warn(lineNo, "unknown zone: " .. zone) end
				end
			elseif word == "gate" then
				if not chapter then
					Err(lineNo, "gate before the first chapter")
				elseif chapter.gate then
					Err(lineNo, "a chapter has at most one gate")
				else
					chapter.gate = { title = rest, requirements = {}, isGate = true, line = lineNo }
					item = chapter.gate
				end
			elseif STEP_KINDS[word] then
				if not chapter then
					Err(lineNo, "step before the first chapter")
				elseif rest == "" then
					Err(lineNo, "empty step")
				else
					local inline, err = ParseInline(rest, zone)
					if not inline then
						Err(lineNo, err)
						inline = { quests = {}, names = {}, coords = {} } -- keep its attributes attached
					end
					item = {
						kind = word, text = rest, line = lineNo,
						quests = inline.quests, names = inline.names, coords = inline.coords,
						details = {}, rewards = {}, verify = {}, done = {},
					}
					chapter.steps[#chapter.steps + 1] = item
					if #rest > 120 then Warn(lineNo, "step main line over 120 characters") end
				end
			elseif HEADER_KEYWORDS[word] then
				if chapter then
					Err(lineNo, word .. " belongs in the header, before the first chapter")
				elseif word == "note" then
					plan.notes[#plan.notes + 1] = rest
				elseif word == "source" then
					local url, label = rest:match("^(%S+)%s*(.*)$")
					plan.sources[#plan.sources + 1] = { url = url, label = label }
				elseif word == "skills" then
					for skill in rest:gmatch("[^,]+") do
						plan.skills[#plan.skills + 1] = Trim(skill)
					end
				else
					plan[word] = rest
				end
			else
				Err(lineNo, "unknown keyword: " .. tostring(word))
			end
		end
	end

	if not plan.title then Err(1, "missing `title`") end
	for _, ch in ipairs(plan.chapters) do
		if ids[ch.id] then
			Err(ch.line, "duplicate chapter id: " .. ch.id .. " (first on line " .. ids[ch.id] .. ")")
		else
			ids[ch.id] = ch.line
		end
		local seen = {}
		for _, step in ipairs(ch.steps) do
			if seen[step.text] then
				Warn(step.line, "same main line as line " .. seen[step.text] .. " in this chapter; their progress would be shared")
			end
			seen[step.text] = step.line
			step.id = ch.id .. ":" .. Parser.Hash(step.text)
		end
		for _, req in ipairs(ch.gate and ch.gate.requirements or {}) do
			if req.type == "check" then
				req.key = ch.id .. ":check:" .. Parser.Hash(req.text)
			end
		end
	end

	if #errors > 0 then return nil, errors, warnings end
	return plan, errors, warnings
end

-- Display -----------------------------------------------------------------------------------------

-- Rewrites a validated piece of text for display: style.quest(name), style.name(name)
-- and style.coord(x, y, zone) replace the markup; escapes become the literal character.
function Parser.FormatText(text, style)
	local out, i, n = {}, 1, #text
	while i <= n do
		local c = text:sub(i, i)
		local close
		if c == "\\" then
			out[#out + 1] = text:sub(i + 1, i + 1)
			i = i + 2
		elseif c == "[" then
			close = text:find("]", i + 1, true)
		elseif c == "{" then
			close = text:find("}", i + 1, true)
		elseif c == "@" then
			local whole, x, y = text:match("^(@(%d+%.?%d*),(%d+%.?%d*))", i)
			local zone
			if not whole then
				whole, zone, x, y = text:match("^(@([^:@%[%]{}]+):(%d+%.?%d*),(%d+%.?%d*))", i)
			end
			if whole then
				out[#out + 1] = style.coord(x, y, zone and Trim(zone))
				i = i + #whole
			else
				out[#out + 1] = c
				i = i + 1
			end
		else
			local plain = text:find("[\\%[{@]", i) or n + 1
			out[#out + 1] = text:sub(i, plain - 1)
			i = plain
		end
		if close then
			local body = Trim(text:sub(i + 1, close - 1))
			if c == "[" then
				out[#out + 1] = style.quest(Trim(body:match("^(.-)#%d+$") or body))
			else
				out[#out + 1] = style.name(body)
			end
			i = close + 1
		elseif c == "[" or c == "{" then
			out[#out + 1] = c -- unclosed; can't happen after validation
			i = i + 1
		end
	end
	return table.concat(out)
end

if type(ns) == "table" then
	ns.Parser = Parser -- in game: shared with the rest of Homunculus_Prophecy
end
return Parser

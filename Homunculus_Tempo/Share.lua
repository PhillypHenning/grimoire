-- Rotations as text, for handing one to another player (teaching). Plain Lua 5.1 with no
-- WoW API (tested by scripts/tempo/test.lua). Import only reads data; nothing in the text
-- is ever run.
--
--   # Tempo rotation v1
--   name: Shadow cycle
--   class: WARLOCK
--   kind: cycle
--   length: 12.5
--   score: 140.2 damage
--   note: Refresh Corruption when it has under 3 s left.
--   0.0 172 Corruption
--   0.0 0 Pet Attack
--   1.6 686 Shadow Bolt
--   2.1 3110 pet: Firebolt
--
-- Step lines are "<seconds from the start> <spell ID> <spell name>". Names are what the
-- playback matches on, so any rank of a spell counts. "pet: " before the name marks an
-- ability your pet cast; Pet Attack (sending the pet in) has no spell, so its ID is 0.

local _, ns = ...
local Share = {}

Share.HEADER = "# Tempo rotation v1"

local function Trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Share.Export(rotation)
	local lines = { Share.HEADER, "name: " .. (rotation.name or "Rotation") }
	if rotation.class then lines[#lines + 1] = "class: " .. rotation.class end
	lines[#lines + 1] = "kind: " .. (rotation.kind or "cycle")
	lines[#lines + 1] = ("length: %.1f"):format(rotation.length or 0)
	if rotation.unit then
		lines[#lines + 1] = ("score: %.1f %s"):format(rotation.dps or 0, rotation.unit)
	end
	for _, note in ipairs(rotation.notes or {}) do
		lines[#lines + 1] = "note: " .. note
	end
	for _, step in ipairs(rotation.steps) do
		lines[#lines + 1] = ("%.1f %d %s%s"):format(step.at, step.spell or 0, step.pet and "pet: " or "", step.name)
	end
	return table.concat(lines, "\n")
end

-- Returns a rotation, or nil and an error message.
function Share.Import(text)
	local rotation = { kind = "cycle", steps = {}, notes = {} }
	local sawHeader = false
	local lineNumber = 0
	for raw in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
		lineNumber = lineNumber + 1
		local line = Trim(raw)
		if line == Share.HEADER then
			sawHeader = true
		elseif line ~= "" and line:sub(1, 1) ~= "#" then
			if not sawHeader then
				return nil, "the text must start with \"" .. Share.HEADER .. "\""
			end
			local key, value = line:match("^(%a+):%s*(.-)$")
			local at, spell, name = line:match("^(%d+%.?%d*)%s+(%d+)%s+(.+)$")
			if at then
				name = Trim(name)
				local petName = name:match("^pet:%s*(.+)$")
				spell = tonumber(spell)
				rotation.steps[#rotation.steps + 1] = { at = tonumber(at), spell = spell ~= 0 and spell or nil,
					name = petName or name, pet = petName and true or nil }
			elseif key == "name" or key == "class" then
				rotation[key] = value
			elseif key == "kind" then
				if value ~= "opener" and value ~= "cycle" then
					return nil, ("line %d: kind must be opener or cycle"):format(lineNumber)
				end
				rotation.kind = value
			elseif key == "length" then
				rotation.length = tonumber(value)
			elseif key == "score" then
				local dps, unit = value:match("^(%d+%.?%d*)%s+(%a+)$")
				rotation.dps, rotation.unit = tonumber(dps), unit
			elseif key == "note" then
				rotation.notes[#rotation.notes + 1] = value
			else
				return nil, ("line %d: not a step or a known field: %s"):format(lineNumber, line)
			end
		end
	end
	if not sawHeader then
		return nil, "the text must start with \"" .. Share.HEADER .. "\""
	end
	if #rotation.steps == 0 then
		return nil, "the rotation has no steps"
	end
	table.sort(rotation.steps, function(a, b) return a.at < b.at end)
	local lastAt = rotation.steps[#rotation.steps].at
	if not rotation.length or rotation.length < lastAt then
		rotation.length = lastAt + 2
	end
	rotation.name = rotation.name or "Imported rotation"
	return rotation
end

if type(ns) == "table" then
	ns.Share = Share
end
return Share

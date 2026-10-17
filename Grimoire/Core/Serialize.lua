-- Tables as text and back, for sharing settings (layout export). The text looks like Lua
-- table syntax but is only ever read by this parser, never run: it accepts strings,
-- numbers, booleans and nested tables, and nothing else (like ADR 0006 for plans).
--
-- Plain Lua 5.1 with no WoW API, so scripts/core/test.lua can test it outside the game.
--
--   local text = Serialize.Write(value)
--   local value, err = Serialize.Read(text)

local _, ns = ...
local Serialize = {}

local MAX_DEPTH = 20

local function Quote(s)
	return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
end

local function WriteNumber(n)
	if n == math.floor(n) and math.abs(n) < 2 ^ 53 then
		return ("%d"):format(n)
	end
	local short = ("%.14g"):format(n) -- shortest form that reads back exactly
	if tonumber(short) == n then return short end
	return ("%.17g"):format(n)
end

local function IsArray(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	for i = 1, n do
		if t[i] == nil then return false end
	end
	return true, n
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == "number" -- numbers first
	end)
	return keys
end

local function Write(value, depth)
	local kind = type(value)
	if kind == "string" then return Quote(value) end
	if kind == "number" then return WriteNumber(value) end
	if kind == "boolean" then return tostring(value) end
	if kind ~= "table" then error("can't write a " .. kind) end
	if depth > MAX_DEPTH then error("too deeply nested") end
	local parts = {}
	local array, n = IsArray(value)
	if array then
		for i = 1, n do parts[i] = Write(value[i], depth + 1) end
	else
		for _, k in ipairs(SortedKeys(value)) do
			if type(k) == "string" or type(k) == "number" then
				parts[#parts + 1] = "[" .. Write(k, depth + 1) .. "]=" .. Write(value[k], depth + 1)
			end
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function Serialize.Write(value)
	return Write(value, 0)
end

-- Reading ------------------------------------------------------------------------------------

local ESCAPES = { ["\\"] = "\\", ['"'] = '"', n = "\n", r = "\r" }

function Serialize.Read(text)
	local pos = 1
	local function Fail(message)
		error({ message = ("%s at character %d"):format(message, pos) }, 0)
	end
	local function Skip()
		pos = text:find("[^%s]", pos) or #text + 1
	end
	local Value
	local function String()
		pos = pos + 1 -- the opening quote
		local parts = {}
		while true do
			local c = text:sub(pos, pos)
			if c == "" then Fail("unfinished string") end
			if c == '"' then
				pos = pos + 1
				return table.concat(parts)
			elseif c == "\\" then
				local e = ESCAPES[text:sub(pos + 1, pos + 1)]
				if not e then Fail("unknown escape") end
				parts[#parts + 1] = e
				pos = pos + 2
			else
				parts[#parts + 1] = c
				pos = pos + 1
			end
		end
	end
	local function Table(depth)
		if depth > MAX_DEPTH then Fail("too deeply nested") end
		pos = pos + 1 -- {
		local result, index = {}, 1
		Skip()
		while text:sub(pos, pos) ~= "}" do
			if text:sub(pos, pos) == "[" then
				pos = pos + 1
				Skip()
				local key = Value(depth + 1)
				if type(key) ~= "string" and type(key) ~= "number" then Fail("table keys must be strings or numbers") end
				Skip()
				if text:sub(pos, pos) ~= "]" then Fail("expected ]") end
				pos = pos + 1
				Skip()
				if text:sub(pos, pos) ~= "=" then Fail("expected =") end
				pos = pos + 1
				Skip()
				result[key] = Value(depth + 1)
			else
				result[index] = Value(depth + 1)
				index = index + 1
			end
			Skip()
			local c = text:sub(pos, pos)
			if c == "," then
				pos = pos + 1
				Skip()
			elseif c ~= "}" then
				Fail("expected , or }")
			end
		end
		pos = pos + 1 -- }
		return result
	end
	Value = function(depth)
		Skip()
		local c = text:sub(pos, pos)
		if c == "{" then return Table(depth) end
		if c == '"' then return String() end
		if text:sub(pos, pos + 3) == "true" then pos = pos + 4 return true end
		if text:sub(pos, pos + 4) == "false" then pos = pos + 5 return false end
		local number = text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
		if number and number ~= "" and tonumber(number) then
			pos = pos + #number
			return tonumber(number)
		end
		Fail("unexpected text")
	end

	if type(text) ~= "string" then return nil, "no text" end
	local ok, result = pcall(function()
		local value = Value(0)
		Skip()
		if pos <= #text then Fail("unexpected text after the end") end
		return value
	end)
	if ok then return result end
	return nil, type(result) == "table" and result.message or tostring(result)
end

if type(ns) == "table" and ns.Grimoire then
	ns.Grimoire.Serialize = Serialize -- in game: Grimoire.Serialize
end
return Serialize

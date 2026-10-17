-- Tests core's pure-Lua parts outside the game.
--   lua scripts/core/test.lua
-- Exits 1 on the first failure.

local here = arg[0]:match("^(.*)[/\\]") or "."
local Serialize = dofile(here .. "/../../Grimoire/Core/Serialize.lua")

local failures = 0
local function check(cond, message)
	if not cond then
		failures = failures + 1
		print("FAIL: " .. message)
	end
end

local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not same(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

-- Round trips.
local layout = {
	movers = { Target = { "TOPLEFT", "UIParent", "CENTER", 118, -168.5 } },
	moverDim = { Health = true, Mana = false },
	dimAlpha = 0.4,
	buttonSize = 44,
	modules = { Bags = { columns = 10, enabled = true }, Notes = { note = 'quote " and \\ and\nnewline' } },
	[1] = "mixed keys",
}
local text = Serialize.Write(layout)
local back, err = Serialize.Read(text)
check(back ~= nil, "read what was written: " .. tostring(err))
check(same(back, layout), "round trip keeps every value")
check(Serialize.Write(back) == text, "writing is stable (sorted keys)")
check(same(Serialize.Read("{1,2,3}"), { 1, 2, 3 }), "arrays")
check(Serialize.Read(" -1.5e3 ") == -1500, "numbers with exponent and spaces")
check(Serialize.Read('"a\\"b"') == 'a"b', "escaped quote")

-- Nothing that isn't data gets through.
for _, bad in ipairs({ "os.exit()", "{a=1}", "{[x]=1}", "function() end", '"unfinished', "{1,2", "{1}{2}", "nil", "" }) do
	local value, message = Serialize.Read(bad)
	check(value == nil and message, "refused: " .. bad)
end
check(Serialize.Read(string.rep("{", 30) .. string.rep("}", 30)) == nil, "refuses deep nesting")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("All core tests pass.")

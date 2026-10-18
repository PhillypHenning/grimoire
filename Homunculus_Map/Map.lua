local _, ns = ...
local Homunculus = Homunculus

-- Shared parts of Homunculus_Map: saved data. Hearth.lua and Flights.lua are its modules.
--
-- HomunculusMapDB = {
--     characters = { ["Name - Realm"] = { hearth = { name, mapID, x, y, continent, wx, wy, time } } },
--     flights = { ["From > To"] = seconds },   -- learned flight times, account-wide
-- }

function ns.Store()
	HomunculusMapDB = Homunculus.CopyDefaults({ characters = {}, flights = {} }, HomunculusMapDB or {})
	return HomunculusMapDB
end

function ns.Character()
	local chars = ns.Store().characters
	local key = Homunculus.db.charKey
	chars[key] = chars[key] or {}
	return chars[key]
end

function ns.FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

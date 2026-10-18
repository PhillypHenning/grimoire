local Homunculus = Homunculus

-- Per-character data and how characters are shown (ADR 0003).
-- HomunculusDB.global.characters["Name - Realm"] = {
--     info = { name, realm, class, level, faction, lastSeen },
--     bank = {...}, auctions = {...}, …   -- written by components
-- }

-- Account-wide, per-character storage. Defaults to the current character.
function Homunculus:GetCharacterStore(charKey)
	local characters = self.db.global.characters
	charKey = charKey or self.db.charKey
	characters[charKey] = characters[charKey] or {}
	return characters[charKey]
end

-- Called at login so every stored character has a name and class to display.
function Homunculus:RecordCharacter()
	local _, class = UnitClass("player")
	self:GetCharacterStore().info = {
		name = UnitName("player"),
		realm = GetRealmName(),
		class = class,
		level = UnitLevel("player"),
		faction = UnitFactionGroup("player"),
		lastSeen = time(),
	}
end

function Homunculus:GetCharacterInfo(charKey)
	local store = self.db.global.characters[charKey or self.db.charKey]
	return store and store.info
end

function Homunculus:GetPlayerClass()
	local _, class = UnitClass("player")
	return class
end

-- Class colors ---------------------------------------------------------------
-- Blizzard's own class colors, so names look the same as in chat, raid frames, etc.

function Homunculus.GetClassColor(class)
	if not class then return nil end
	if C_ClassColor and C_ClassColor.GetClassColor then
		return C_ClassColor.GetClassColor(class)
	end
	return RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
end

function Homunculus.ClassColorText(text, class)
	local color = Homunculus.GetClassColor(class)
	if not color then
		return text
	end
	if color.WrapTextInColorCode then
		return color:WrapTextInColorCode(text)
	end
	return "|c" .. color.colorStr .. text .. "|r"
end

-- Class-colored character name. The realm is added only when it differs from
-- the current one. Falls back to the "Name - Realm" key for unknown characters.
function Homunculus:FormatCharacterName(charKey)
	charKey = charKey or self.db.charKey
	local info = self:GetCharacterInfo(charKey)
	local name, realm = charKey:match("^(.-) %- (.+)$")
	name = info and info.name or name or charKey
	realm = info and info.realm or realm
	if realm and realm ~= GetRealmName() then
		name = name .. " - " .. realm
	end
	return Homunculus.ClassColorText(name, info and info.class)
end

-- Characters that have stored data under `field` (e.g. "bank"), current character
-- first, then alphabetical. The current character is always included.
function Homunculus:GetCharactersWith(field)
	local current = self.db.charKey
	local keys = {}
	for charKey, store in pairs(self.db.global.characters) do
		if charKey ~= current and store[field] then
			keys[#keys + 1] = charKey
		end
	end
	table.sort(keys)
	table.insert(keys, 1, current)
	return keys
end

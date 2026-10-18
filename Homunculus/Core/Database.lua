local Homunculus = Homunculus

local DB_VERSION = 1

-- Fills in any keys missing from dst using src, recursively. Existing values win.
local function copyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			copyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end
Homunculus.CopyDefaults = copyDefaults

-- HomunculusDB layout:
--   version      schema version, for future migrations
--   global       account-wide settings
--   profileKeys  ["Name - Realm"] = profileName
--   profiles     [profileName] = { movers = {}, modules = { [moduleName] = {...} } }
function Homunculus:InitializeDatabase()
	HomunculusDB = HomunculusDB or {}
	local raw = HomunculusDB
	raw.version = raw.version or DB_VERSION
	raw.global = copyDefaults(self.defaults.global, raw.global or {})
	raw.profiles = raw.profiles or {}
	raw.profileKeys = raw.profileKeys or {}

	local charKey = UnitName("player") .. " - " .. GetRealmName()
	local profileName = raw.profileKeys[charKey] or charKey
	raw.profileKeys[charKey] = profileName
	raw.profiles[profileName] = copyDefaults(self.defaults.profile, raw.profiles[profileName] or {})

	-- A short-lived build grouped the player frames into "Player" automatically. Undo
	-- that once (groups you make are named "Group N", so they're untouched).
	local profile = raw.profiles[profileName]
	if profile.moverDefaultsApplied then
		for key in pairs(profile.moverDefaultsApplied) do
			if profile.moverGroups[key] == "Player" then
				profile.moverGroups[key] = nil
			end
		end
		profile.moverDefaultsApplied = nil
	end

	self.db = {
		raw = raw,
		global = raw.global,
		profile = raw.profiles[profileName],
		profileName = profileName,
		charKey = charKey,
	}
end

-- Switching profiles takes effect after a reload so every module rebuilds cleanly.
function Homunculus:SetProfile(name)
	self.db.raw.profileKeys[self.db.charKey] = name
	self:Print(("Profile set to '%s'. Type /reload to apply."):format(name))
end

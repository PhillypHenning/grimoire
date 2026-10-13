local ADDON_NAME = ...
local Grimoire = Grimoire

-- Graphics settings (CVars) that Blizzard's options menu doesn't offer, or caps lower.
-- Each tweak is a menu choice; "Game setting" leaves the CVar alone. Chosen values are
-- applied at every login, because moving a graphics slider can overwrite them. The
-- value a CVar had before Grimoire first changed it is kept in db.original, so picking
-- "Game setting" again (or turning the module off) puts it back.

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar

local TWEAKS = {
	{ key = "sharpen", cvar = "ResampleAlwaysSharpen", label = "Sharpen image",
		values = { { "1", "On" } }, default = "1" },
	{ key = "groundDensity", cvar = "groundEffectDensity", label = "Grass density",
		values = { { "128", "128" }, { "256", "256" } }, default = "256" },
	{ key = "groundDistance", cvar = "groundEffectDist", label = "Grass distance",
		values = { { "320", "320" }, { "500", "500" } }, default = "500" },
	{ key = "terrainDistance", cvar = "terrainLodDist", label = "Terrain detail distance",
		values = { { "650", "650" }, { "1000", "1000" } }, default = "1000" },
	{ key = "reflections", cvar = "reflectionMode", label = "Water reflections",
		values = { { "3", "Highest (3)" } }, default = "3" },
	{ key = "weather", cvar = "weatherDensity", label = "Weather",
		values = { { "3", "Highest (3)" } }, default = "3" },
	{ key = "cameraZoom", cvar = "cameraDistanceMaxZoomFactor", label = "Max camera zoom",
		values = { { "2.6", "2.6" }, { "4", "4" } }, default = "4" },
}

local defaults = { original = {} }
local options = {}
for _, tweak in ipairs(TWEAKS) do
	defaults[tweak.key] = tweak.default
	local values = { { false, "Game setting" } }
	for _, choice in ipairs(tweak.values) do
		values[#values + 1] = choice
	end
	options[#options + 1] = { type = "choice", key = tweak.key, label = tweak.label, values = values }
end

local M = Grimoire:NewModule("Graphics", {
	addon = ADDON_NAME,
	label = "Graphics",
	defaults = defaults,
	options = options,
})

-- "4.0" and "4" are the same setting.
local function Same(a, b)
	if tonumber(a) and tonumber(b) then
		return tonumber(a) == tonumber(b)
	end
	return a == b
end

function M:ApplyTweak(tweak)
	local current = GetCVar(tweak.cvar)
	local wanted = self.db[tweak.key]
	local original = self.db.original
	if current == nil then
		if wanted then
			self:Print(("%s: this client has no %s setting."):format(tweak.label, tweak.cvar))
		end
		return
	end
	if wanted then
		if original[tweak.cvar] == nil then
			original[tweak.cvar] = current
		end
		if not Same(current, wanted) then
			SetCVar(tweak.cvar, wanted)
			local now = GetCVar(tweak.cvar)
			if not Same(now, wanted) then
				self:Print(("%s: the game capped it at %s."):format(tweak.label, tostring(now)))
			end
		end
	elseif original[tweak.cvar] ~= nil then
		SetCVar(tweak.cvar, original[tweak.cvar])
		original[tweak.cvar] = nil
	end
end

function M:ApplySettings(key)
	for _, tweak in ipairs(TWEAKS) do
		if not key or tweak.key == key then
			self:ApplyTweak(tweak)
		end
	end
end

function M:OnEnable()
	self:ApplySettings()
end

-- Puts back every CVar Grimoire changed. The choices stay, so enabling reapplies them.
function M:OnDisable()
	for cvar, value in pairs(self.db.original) do
		SetCVar(cvar, value)
	end
	wipe(self.db.original)
end

-- /grim cvars: every setting this client knows, for finding more tweaks ----------------

local function DumpCVars()
	if not (C_Console and C_Console.GetAllCommands) then
		Grimoire:Print("This client can't list its settings (no C_Console.GetAllCommands).")
		return
	end
	local getDefault = C_CVar and C_CVar.GetCVarDefault
	local list = {}
	for _, info in ipairs(C_Console.GetAllCommands()) do
		local ok, value = pcall(GetCVar, info.command)
		if ok and value ~= nil then
			local default = getDefault and getDefault(info.command)
			list[#list + 1] = ("%s = %s (default %s)%s"):format(info.command, value, tostring(default),
				(info.help and info.help ~= "") and (" -- " .. info.help) or "")
		end
	end
	table.sort(list, function(a, b) return a:lower() < b:lower() end)
	local version, build = GetBuildInfo()
	GrimoireTweaksDB = GrimoireTweaksDB or {}
	GrimoireTweaksDB.cvarDump = { time = date("%Y-%m-%d %H:%M"), build = version .. "." .. build, list = list }
	Grimoire:Print(("Saved %d settings. /reload or log out to write them to SavedVariables\\Grimoire_Tweaks.lua."):format(#list))
end

function M:OnInitialize()
	Grimoire:RegisterCommand("cvars", "cvars - save every game setting to Grimoire_Tweaks.lua (after /reload)", DumpCVars)
end

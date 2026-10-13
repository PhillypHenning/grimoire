local ADDON_NAME, ns = ...

-- Grimoire is exposed globally so feature add-ons (Grimoire_Warlock, …) and third-party
-- add-ons can register modules and listen to callbacks without a hard dependency
-- on internals.
---@class Grimoire
local Grimoire = {
	name = ADDON_NAME,
	modules = {},
	moduleOrder = {},
	callbacks = {},
	defaults = {
		profile = { movers = {}, moverGroups = {}, moverDim = {}, dimAlpha = 0.4, modules = {} },
		global = { characters = {} },
	},
}
_G.Grimoire = Grimoire
ns.Grimoire = Grimoire

local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
Grimoire.version = (version and not version:find("^@")) and version or "dev"

function Grimoire:Print(...)
	print("|cff8788eeGrimoire|r:", ...)
end

local function safecall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		geterrorhandler()(err)
	end
end
Grimoire.SafeCall = safecall

-- Callback bus ---------------------------------------------------------------
-- fn may be a function(owner, ...) or the name of a method on owner.

function Grimoire:RegisterCallback(name, owner, fn)
	self.callbacks[name] = self.callbacks[name] or {}
	self.callbacks[name][owner] = fn
end

function Grimoire:UnregisterCallback(name, owner)
	if self.callbacks[name] then
		self.callbacks[name][owner] = nil
	end
end

function Grimoire:UnregisterAllCallbacks(owner)
	for _, list in pairs(self.callbacks) do
		list[owner] = nil
	end
end

function Grimoire:Fire(name, ...)
	local list = self.callbacks[name]
	if not list then return end
	for owner, fn in pairs(list) do
		if type(fn) == "string" then
			fn = owner[fn]
		end
		safecall(fn, owner, ...)
	end
end

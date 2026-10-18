local ADDON_NAME, ns = ...

-- Homunculus is exposed globally so feature add-ons (Homunculus_Warlock, …) and third-party
-- add-ons can register modules and listen to callbacks without a hard dependency
-- on internals.
---@class Homunculus
local Homunculus = {
	name = ADDON_NAME,
	modules = {},
	moduleOrder = {},
	callbacks = {},
	defaults = {
		profile = { movers = {}, moverGroups = {}, moverDim = {}, dimAlpha = 0.4, idleSeconds = 1.5, buttonSize = 44, addonButtons = { hidden = {}, hideAll = false }, modules = {} },
		global = { characters = {}, logLevels = {} },
	},
}
_G.Homunculus = Homunculus
ns.Homunculus = Homunculus

local version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
Homunculus.version = (version and not version:find("^@")) and version or "dev"

function Homunculus:Print(...)
	print("|cff8788eeHomunculus|r:", ...)
end

local function safecall(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		geterrorhandler()(err)
	end
end
Homunculus.SafeCall = safecall

-- Callback bus ---------------------------------------------------------------
-- fn may be a function(owner, ...) or the name of a method on owner.

function Homunculus:RegisterCallback(name, owner, fn)
	self.callbacks[name] = self.callbacks[name] or {}
	self.callbacks[name][owner] = fn
end

function Homunculus:UnregisterCallback(name, owner)
	if self.callbacks[name] then
		self.callbacks[name][owner] = nil
	end
end

function Homunculus:UnregisterAllCallbacks(owner)
	for _, list in pairs(self.callbacks) do
		list[owner] = nil
	end
end

function Homunculus:Fire(name, ...)
	local list = self.callbacks[name]
	if not list then return end
	for owner, fn in pairs(list) do
		if type(fn) == "string" then
			fn = owner[fn]
		end
		safecall(fn, owner, ...)
	end
end

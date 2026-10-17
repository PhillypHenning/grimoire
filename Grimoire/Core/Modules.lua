local Grimoire = Grimoire

-- Module lifecycle:
--   registered  -> NewModule() called, waiting for the database
--   initialized -> OnInitialize() ran, module.db is available
--   enabled     -> OnEnable() ran
--   disabled    -> OnDisable() ran (events and callbacks are released automatically)

---@class GrimoireModule
local Module = {}
Module.__index = Module

-- opts.addon:   the add-on folder the module ships in (pass `...`'s first value);
--               the in-game menu groups modules under their add-on.
-- opts.label:   display name in menus (defaults to the module name).
-- opts.options: settings the menu offers (see docs/adr/0005):
--   { type = "toggle", key = "showText", label = "Show %" }
--   { type = "choice", key = "width", label = "Width", values = { { 180, "180" }, ... } }
--   either may set reload = true when the change needs a /reload.
---@param name string
---@param opts? { addon?: string, label?: string, options?: table[], defaults?: table, class?: string, conflicts?: string[], enabledByDefault?: boolean }
---@return GrimoireModule
function Grimoire:NewModule(name, opts)
	assert(not self.modules[name], "Grimoire: duplicate module " .. tostring(name))
	opts = opts or {}
	local module = setmetatable({
		name = name,
		addon = opts.addon,
		label = opts.label or name,
		options = opts.options or {},
		moverKeys = {},
		defaults = opts.defaults or {},
		class = opts.class,
		conflicts = opts.conflicts,
		enabledByDefault = opts.enabledByDefault ~= false,
		state = "registered",
	}, Module)
	self.modules[name] = module
	self.moduleOrder[#self.moduleOrder + 1] = name
	return module
end

function Grimoire:GetModule(name)
	return self.modules[name]
end

-- Safe to call repeatedly; only touches modules that haven't been set up yet.
-- Runs after login and after any later add-on loads, so plugins can register late.
function Grimoire:InitializeModules()
	if not self.db then return end
	for _, name in ipairs(self.moduleOrder) do
		local module = self.modules[name]
		if module.state == "registered" then
			self:SetupModule(module)
		end
	end
end

function Grimoire:SetupModule(module)
	local store = self.db.profile.modules
	store[module.name] = self.CopyDefaults(module.defaults, store[module.name] or {})
	module.db = store[module.name]
	if module.db.enabled == nil then
		module.db.enabled = module.enabledByDefault
	end
	module.state = "initialized"
	module:Call("OnInitialize")
	if module.db.enabled then
		self:EnableModule(module.name)
	end
end

-- Changes one setting from the menu and lets the module apply it live.
function Grimoire:SetModuleSetting(module, key, value)
	module.db[key] = value
	module:Log("info", "setting %s = %s", key, tostring(value))
	if module.ApplySettings then
		if module:IsEnabled() then
			module:Call("ApplySettings", key)
		else
			module.settingsChanged = true -- applied the next time it's enabled
		end
	end
	for _, option in ipairs(module.options) do
		if option.key == key and option.reload then
			self:Print(("%s: type /reload to apply."):format(module.label))
		end
	end
end

function Grimoire:EnableModule(name)
	local module = self.modules[name]
	if not module or module.state == "registered" then return false, "unknown or not loaded" end
	module.db.enabled = true
	if module.state == "enabled" then return true end
	local available, reason = module:IsAvailable()
	if not available then
		module:Log("warn", "not available: %s", reason)
		return false, reason
	end
	module.state = "enabled"
	module:Log("info", "enabled")
	module:Call("OnEnable")
	if module.settingsChanged then
		module.settingsChanged = nil
		module:Call("ApplySettings")
	end
	self:Fire("ModuleEnabled", name)
	return true
end

function Grimoire:DisableModule(name)
	local module = self.modules[name]
	if not module or module.state == "registered" then return false, "unknown or not loaded" end
	module.db.enabled = false
	if module.state ~= "enabled" then return true end
	module:UnregisterAllEvents()
	self:UnregisterAllCallbacks(module)
	module.state = "disabled"
	module:Log("info", "disabled")
	module:Call("OnDisable")
	self:Fire("ModuleDisabled", name)
	return true
end

-- Loads every LoadOnDemand add-on tagged "## X-Grimoire-Class: <CLASS>" for the
-- player's class. Lets each class package stay out of memory for other classes.
function Grimoire:LoadClassAddOns()
	local _, playerClass = UnitClass("player")
	for i = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(i)
		local classes = C_AddOns.GetAddOnMetadata(name, "X-Grimoire-Class")
		if classes and C_AddOns.IsAddOnLoadOnDemand(name) and not C_AddOns.IsAddOnLoaded(name) then
			for class in classes:gmatch("[^,%s]+") do
				if class == playerClass then
					local loaded, reason = C_AddOns.LoadAddOn(name)
					if not loaded and reason ~= "DISABLED" then
						self:Print(("Could not load %s: %s"):format(name, tostring(reason)))
					end
					break
				end
			end
		end
	end
end

-- Module methods -------------------------------------------------------------

function Module:Call(method, ...)
	if self[method] then
		Grimoire.SafeCall(self[method], self, ...)
	end
end

function Module:Print(...)
	Grimoire:Print("[" .. self.name .. "]", ...)
end

-- level: "error", "warn", "info" or "debug" (Core/Log.lua).
function Module:Log(level, fmt, ...)
	Grimoire:Log(self.name, level, fmt, ...)
end

function Module:IsAvailable()
	if self.class then
		local _, playerClass = UnitClass("player")
		if playerClass ~= self.class then
			return false, "wrong class"
		end
	end
	for _, addon in ipairs(self.conflicts or {}) do
		if C_AddOns.IsAddOnLoaded(addon) then
			return false, "conflicts with " .. addon
		end
	end
	return true
end

function Module:IsEnabled()
	return self.state == "enabled"
end

-- Each module owns one event frame, so disabling a module releases all its events.
function Module:GetEventFrame()
	if not self.eventFrame then
		local frame = CreateFrame("Frame")
		frame.handlers = {}
		frame:SetScript("OnEvent", function(_, event, ...)
			local handler = frame.handlers[event]
			if type(handler) == "string" then
				self[handler](self, event, ...)
			else
				handler(self, event, ...)
			end
		end)
		self.eventFrame = frame
	end
	return self.eventFrame
end

-- Forever is a Classic-family client with its own API mix, so some events may not
-- exist. Registering an unknown event is a hard error; skip it instead.
local function IsEventValid(event)
	return not (C_EventUtils and C_EventUtils.IsEventValid) or C_EventUtils.IsEventValid(event)
end

-- handler: function(self, event, ...) or method name; defaults to a method named after the event.
-- Returns false if the event doesn't exist on this client.
function Module:RegisterEvent(event, handler)
	if not IsEventValid(event) then
		self:Log("debug", "event %s doesn't exist on this client; skipped", event)
		return false
	end
	local frame = self:GetEventFrame()
	frame.handlers[event] = handler or event
	frame:RegisterEvent(event)
	return true
end

function Module:RegisterUnitEvent(event, unit, handler)
	if not IsEventValid(event) then
		self:Log("debug", "event %s doesn't exist on this client; skipped", event)
		return false
	end
	local frame = self:GetEventFrame()
	frame.handlers[event] = handler or event
	frame:RegisterUnitEvent(event, unit)
	return true
end

function Module:UnregisterEvent(event)
	if self.eventFrame then
		self.eventFrame:UnregisterEvent(event)
		self.eventFrame.handlers[event] = nil
	end
end

function Module:UnregisterAllEvents()
	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
		wipe(self.eventFrame.handlers)
	end
end

-- Registers a mover owned by this module, so the menu can offer its position
-- options. The key is the module name, plus opts.suffix for a module's extra frames.
function Module:RegisterMover(frame, label, default, opts)
	local key = self.name .. (opts and opts.suffix or "")
	Grimoire:RegisterMover(frame, key, label, default, opts)
	self.moverKeys[#self.moverKeys + 1] = key
	return key
end

function Module:RegisterCallback(name, fn)
	Grimoire:RegisterCallback(name, self, fn or name)
end

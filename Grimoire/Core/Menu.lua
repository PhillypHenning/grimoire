local Grimoire = Grimoire

-- The in-game manager: one nested menu built from what's installed. Each
-- Grimoire_* add-on gets a submenu, and each of its modules lists Enabled, the
-- settings it declares (opts.options, docs/adr/0005) and its frames' position
-- options. The Launcher button opens it; so does /grimoire menu.

-- Add-on list -------------------------------------------------------------------------

local REASONS = {
	DISABLED = "turned off",
	DEP_DISABLED = "needs Grimoire",
	DEP_MISSING = "needs Grimoire",
	MISSING = "missing",
	CORRUPT = "corrupt",
	INCOMPATIBLE = "incompatible",
	INTERFACE_VERSION = "out of date",
}

local function StripCodes(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Every Grimoire_* add-on the client knows about, sorted by title.
function Grimoire:GetComponents()
	local components = {}
	for i = 1, C_AddOns.GetNumAddOns() do
		local name, title, _, loadable, reason = C_AddOns.GetAddOnInfo(i)
		if name:match("^Grimoire_") then
			components[#components + 1] = {
				name = name,
				label = StripCodes(title or name):gsub("^Grimoire%s*", ""),
				loaded = C_AddOns.IsAddOnLoaded(name),
				loadable = loadable,
				reason = reason,
				classes = C_AddOns.GetAddOnMetadata(name, "X-Grimoire-Class"),
			}
		end
	end
	table.sort(components, function(a, b) return a.label < b.label end)
	return components
end

-- nil when loaded; otherwise why not, e.g. "turned off" or "Warlock only".
local function StatusText(component)
	if component.loaded then return nil end
	if component.loadable or component.reason == "DEMAND_LOADED" then
		if component.classes then
			return (component.classes:lower():gsub("%f[%a]%a", string.upper)) .. " only"
		end
		return "not loaded"
	end
	return REASONS[component.reason] or (component.reason and component.reason:lower()) or "not loaded"
end

local function SetAddOnEnabled(name, enabled)
	if enabled then
		C_AddOns.EnableAddOn(name)
	else
		C_AddOns.DisableAddOn(name)
	end
	Grimoire:Print(("%s %s. Use Reload UI to apply."):format(name, enabled and "enabled" or "disabled"))
end

-- Module entries ---------------------------------------------------------------------

-- An option's hover text (learned from Leatrix Plus: every setting explains itself).
local function OptionTooltip(option)
	if option.reload then
		return (option.tooltip and (option.tooltip .. " ") or "") .. "Needs /reload."
	end
	return option.tooltip
end

local function OptionEntry(module, option)
	if option.type == "toggle" then
		return {
			text = option.label,
			tooltip = OptionTooltip(option),
			checked = function() return module.db[option.key] and true or false end,
			func = function() Grimoire:SetModuleSetting(module, option.key, not module.db[option.key]) end,
		}
	end
	if option.type ~= "choice" then return nil end -- unknown types are skipped
	local children = {}
	for _, choice in ipairs(option.values) do
		local value, label = choice[1], choice[2]
		children[#children + 1] = {
			text = label,
			radio = true,
			checked = function() return module.db[option.key] == value end,
			func = function() Grimoire:SetModuleSetting(module, option.key, value) end,
		}
	end
	return { text = option.label, tooltip = OptionTooltip(option), children = children }
end

local function MoverEntries(key, prefix)
	local group = Grimoire:GetMoverGroup(key)
	local entries = {
		{
			text = prefix .. (group and "Dim group when idle" or "Dim when idle"),
			checked = function() return Grimoire.db.profile.moverDim[key] and true or false end,
			func = function() Grimoire:SetMoverDim(key, not Grimoire.db.profile.moverDim[key]) end,
		},
		{ text = prefix .. "Reset position", func = function() Grimoire:ResetMover(key) end },
	}
	if group then
		entries[#entries + 1] = { text = prefix .. "Remove from " .. group, func = function() Grimoire:UngroupMover(key) end }
	end
	return entries
end

function Grimoire:GetModuleMenu(module)
	local entries = {
		{
			text = "Enabled",
			checked = function() return module:IsEnabled() end,
			func = function()
				local ok, reason
				if module:IsEnabled() then
					ok, reason = self:DisableModule(module.name)
				else
					ok, reason = self:EnableModule(module.name)
				end
				if not ok then
					self:Print(("Could not change %s: %s"):format(module.label, tostring(reason)))
				end
			end,
		},
	}
	local available, reason = module:IsAvailable()
	if not available then
		entries[#entries + 1] = { text = "(" .. reason .. ")", isTitle = true }
	end

	for _, option in ipairs(module.options) do
		entries[#entries + 1] = OptionEntry(module, option) -- nil appends nothing
	end

	-- Log level per component, while the Debug component is on (ADR 0002).
	local debug = self:GetModule("Debug")
	if debug and debug:IsEnabled() and module ~= debug then
		local levels = self.db.global.logLevels
		local children = {}
		for _, choice in ipairs({ { "off", "Errors only" }, { "info", "Normal" }, { "debug", "Everything" } }) do
			children[#children + 1] = {
				text = choice[2],
				radio = true,
				checked = function() return (levels[module.name] or "info") == choice[1] end,
				func = function() levels[module.name] = choice[1] end,
			}
		end
		children[#children + 1] = { isDivider = true }
		children[#children + 1] = { text = "Show its log", func = function() debug:ShowLog(module.name) end }
		entries[#entries + 1] = { text = "Debug log", tooltip = "How much this component writes to the Debug log.", children = children }
	end

	local keys = {}
	for _, key in ipairs(module.moverKeys) do
		if self.movers[key] then
			keys[#keys + 1] = key
		end
	end
	for _, key in ipairs(keys) do
		entries[#entries + 1] = { isDivider = true }
		local prefix = #keys > 1 and (self.movers[key].label .. ": ") or ""
		for _, entry in ipairs(MoverEntries(key, prefix)) do
			entries[#entries + 1] = entry
		end
	end
	return entries
end

local function ModulesOf(addon)
	local modules = {}
	for _, name in ipairs(Grimoire.moduleOrder) do
		local module = Grimoire.modules[name]
		if module.addon == addon then
			modules[#modules + 1] = module
		end
	end
	return modules
end

local function ComponentEntry(component)
	local status = StatusText(component)
	if status then
		return {
			text = ("%s |cff808080(%s)|r"):format(component.label, status),
			children = {
				{ text = component.label, isTitle = true },
				{ text = "Enable (needs reload)", func = function() SetAddOnEnabled(component.name, true) end },
			},
		}
	end

	local children = {
		{
			text = "Enabled in AddOns list",
			checked = function() return true end,
			func = function() SetAddOnEnabled(component.name, false) end,
		},
	}
	local modules = ModulesOf(component.name)
	if #modules == 1 then
		children[#children + 1] = { isDivider = true }
		for _, entry in ipairs(Grimoire:GetModuleMenu(modules[1])) do
			children[#children + 1] = entry
		end
	else
		for _, module in ipairs(modules) do
			children[#children + 1] = { text = module.label, children = Grimoire:GetModuleMenu(module) }
		end
	end
	return { text = component.label, children = children }
end

-- Main menu ----------------------------------------------------------------------------

local function ProfileChoice(label, key, values, onChange, tooltip)
	local children = {}
	for _, choice in ipairs(values) do
		local value, text = choice[1], choice[2]
		children[#children + 1] = {
			text = text,
			radio = true,
			checked = function() return Grimoire.db.profile[key] == value end,
			func = function()
				Grimoire.db.profile[key] = value
				onChange()
			end,
		}
	end
	return { text = label, tooltip = tooltip, children = children }
end

function Grimoire:ToggleMoveMode()
	if self.moversUnlocked then
		self:LockMovers()
	else
		self:UnlockMovers()
	end
end

function Grimoire:ResetAllPositions()
	self:ResetMover()
	self:Fire("PositionsReset")
	self:Print("Frame positions reset.")
end

function Grimoire:GetMainMenu()
	local open = {}
	for _, name in ipairs(self.moduleOrder) do
		local module = self.modules[name]
		if module.Toggle and module:IsEnabled() then
			open[#open + 1] = { text = module.label, func = function() module:Toggle() end }
		end
	end

	local components = {}
	for _, component in ipairs(self:GetComponents()) do
		components[#components + 1] = ComponentEntry(component)
	end

	local layout = {
		ProfileChoice("Dim strength", "dimAlpha", { { 0.2, "Faint" }, { 0.4, "Medium" }, { 0.6, "Light" } },
			function() self:UpdateMoverDimming() end, "How faint idle frames become (Dim when idle)."),
		ProfileChoice("Dim after", "idleSeconds", { { 1, "1 second" }, { 1.5, "1.5 seconds" }, { 3, "3 seconds" } },
			function() self:NotifyAllMoverActivity() end, "How long a frame waits, unused, before it dims."),
		ProfileChoice("Button size", "buttonSize", { { 31, "Small" }, { 38, "Medium" }, { 44, "Large" }, { 52, "Huge" } },
			function() self:ApplyRoundButtonSize() end, "The size of every round Grimoire button (Grimoire, Notes, Tempo, Prophecy)."),
		{ text = "Reset all positions", tooltip = "Put every Grimoire frame and window back where it started.", func = function() self:ResetAllPositions() end },
	}
	local selected = self:GetSelectedMovers()
	if #selected >= 2 then
		layout[#layout + 1] = { text = "Group selected frames", func = function() self:GroupMovers(selected) end }
	end
	if #selected >= 1 then
		layout[#layout + 1] = { text = "Clear selection", func = function() self:ClearMoverSelection() end }
	end

	local entries = { { text = "Grimoire", isTitle = true } }
	if #open > 0 then
		entries[#entries + 1] = { text = "Open", children = open }
	end
	entries[#entries + 1] = { text = "Move frames", checked = function() return self.moversUnlocked end, func = function() self:ToggleMoveMode() end }
	entries[#entries + 1] = { text = "Components", children = components }
	entries[#entries + 1] = { text = "Layout", children = layout }
	local debug = self:GetModule("Debug")
	if debug and debug:IsEnabled() then
		entries[#entries + 1] = { text = "Debug", children = debug:GetMenu() }
	end
	entries[#entries + 1] = { isDivider = true }
	entries[#entries + 1] = { text = RELOADUI or "Reload UI", func = ReloadUI }
	return entries
end

Grimoire:RegisterCommand("menu", "menu - open the Grimoire menu", function()
	Grimoire.OpenMenu(nil, Grimoire:GetMainMenu())
end)

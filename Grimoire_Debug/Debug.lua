local ADDON_NAME = ...
local Grimoire = Grimoire

-- Debug (plan Milestone 2): shows core's log (Core/Log.lua: Grimoire's own entries plus
-- every Lua error and blocked action in the game) in a window you can copy from, writes
-- an environment report, and saves both to SavedVariables\Grimoire_Debug.lua on logout
-- and /reload, where they can be read directly. The log of earlier sessions is kept
-- (up to SAVED_ENTRIES), so an error from before a /reload is still there afterwards.
--
-- GrimoireDebugDB = { log = { entry, ... }, report = "text", saved = "date" }

local WIDTH, HEIGHT = 680, 440
local SAVED_ENTRIES = 500
local SCROLLBAR = 28
local BUTTON_ROW = 30

local M = Grimoire:NewModule("Debug", {
	addon = ADDON_NAME,
	label = "Debug",
})

local LEVEL_TAGS = { error = "ERROR", warn = "warn ", info = "info ", debug = "debug" }

local function FormatEntry(entry)
	return ("[%s] %s %s: %s%s"):format(date("%m-%d %H:%M:%S", entry.time), LEVEL_TAGS[entry.level] or entry.level,
		entry.source, entry.message, entry.count > 1 and (" (x" .. entry.count .. ")") or "")
end

-- Log text --------------------------------------------------------------------------------

local function AddEntries(lines, entries, source)
	local added = 0
	for _, entry in ipairs(entries) do
		if not source or entry.source == source then
			lines[#lines + 1] = FormatEntry(entry)
			added = added + 1
		end
	end
	return added
end

function M:LogText()
	local lines = {}
	if #self.previous > 0 then
		lines[#lines + 1] = "--- earlier sessions ---"
		AddEntries(lines, self.previous, self.filter)
		lines[#lines + 1] = "--- this session ---"
	end
	if AddEntries(lines, Grimoire.log, self.filter) == 0 then
		lines[#lines + 1] = self.filter and ("(nothing from " .. self.filter .. " this session)") or "(nothing logged this session)"
	end
	return table.concat(lines, "\n")
end

-- Every source in the log, for the filter menu.
function M:Sources()
	local seen, list = {}, {}
	for _, entries in ipairs({ self.previous, Grimoire.log }) do
		for _, entry in ipairs(entries) do
			if not seen[entry.source] then
				seen[entry.source] = true
				list[#list + 1] = entry.source
			end
		end
	end
	table.sort(list)
	return list
end

-- Environment report ------------------------------------------------------------------------

local function Flat(value)
	if type(value) ~= "table" then return tostring(value) end
	local parts = {}
	for k, v in pairs(value) do
		parts[#parts + 1] = (type(k) == "number" and "" or (tostring(k) .. "=")) .. (type(v) == "table" and "{...}" or tostring(v))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

function M:Report()
	local lines = {}
	local function Add(fmt, ...)
		lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt
	end
	local version, build, _, interface = GetBuildInfo()
	local _, class = UnitClass("player")
	Add("Grimoire %s on client %s.%s (interface %s), locale %s, %s", Grimoire.version, version, build,
		tostring(interface), GetLocale(), date("%Y-%m-%d %H:%M"))
	Add("Character: %s, %s level %d, profile %s", Grimoire.db.charKey, class or "?", UnitLevel("player"), Grimoire.db.profileName)

	Add("")
	Add("Add-ons (Grimoire and error catchers):")
	for i = 1, C_AddOns.GetNumAddOns() do
		local name, _, _, _, reason = C_AddOns.GetAddOnInfo(i)
		if name:match("^Grimoire") or name:match("^!?Bug") then
			Add("  %s: %s%s", name, C_AddOns.IsAddOnLoaded(name) and "loaded" or "not loaded",
				reason and (" (" .. tostring(reason) .. ")") or "")
		end
	end

	Add("")
	Add("Modules:")
	for _, name in ipairs(Grimoire.moduleOrder) do
		local module = Grimoire.modules[name]
		local _, reason = module:IsAvailable()
		Add("  %s (%s): %s%s", name, module.addon or "?", module.state, reason and (" (" .. reason .. ")") or "")
	end

	Add("")
	Add("Frames (saved positions):")
	local keys = {}
	for key in pairs(Grimoire.db.profile.movers) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		Add("  %s: %s", key, Flat(Grimoire.db.profile.movers[key]))
	end
	Add("Groups: %s", Flat(Grimoire.db.profile.moverGroups))
	Add("Log levels: %s", Flat(Grimoire.db.global.logLevels))
	return table.concat(lines, "\n")
end

-- Window -------------------------------------------------------------------------------------

function M:Build()
	local frame = Grimoire:CreateWindow("Debug", "Grimoire debug", self)
	frame:SetContentSize(WIDTH, HEIGHT)
	frame:HookScript("OnShow", function() self:UpdateWindow() end)
	self.window = frame
	local content = frame.content

	frame.subtitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.subtitle:SetPoint("TOPLEFT")
	frame.subtitle:SetPoint("TOPRIGHT")
	frame.subtitle:SetJustifyH("LEFT")

	local textBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(textBg)
	textBg:SetPoint("TOPLEFT", 0, -18)
	textBg:SetPoint("BOTTOMRIGHT", 0, BUTTON_ROW)
	local box = CreateFrame("EditBox", nil, textBg)
	local scroll = Grimoire.CreateScrollArea(textBg, "GrimoireDebugScroll", box)
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 8)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetFontObject(ChatFontNormal)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	-- Read-only: typing puts the text back (selecting and copying still work).
	box:SetScript("OnTextChanged", function(b, userInput)
		if userInput then b:SetText(self.shownText or "") end
		ScrollingEdit_OnTextChanged(b, scroll)
	end)
	box:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
	box:SetScript("OnUpdate", function(b, elapsed) ScrollingEdit_OnUpdate(b, elapsed, scroll) end)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
	self.box, self.scroll = box, scroll

	local function Button(text, width, onClick)
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetSize(width, 22)
		button:SetText(text)
		button:SetScript("OnClick", onClick)
		return button
	end
	self.modeButton = Button("Report", 90, function()
		self.mode = self.mode == "report" and "log" or "report"
		self:UpdateWindow()
	end)
	self.modeButton:SetPoint("BOTTOMLEFT")
	self.filterButton = Button("Filter", 90, function(b) self:OpenFilterMenu(b) end)
	self.filterButton:SetPoint("LEFT", self.modeButton, "RIGHT", 6, 0)
	local selectAll = Button("Select all", 90, function()
		box:SetFocus()
		box:HighlightText()
	end)
	selectAll:SetPoint("LEFT", self.filterButton, "RIGHT", 6, 0)
	local clear = Button("Clear", 90, function() self:Clear() end)
	clear:SetPoint("BOTTOMRIGHT")
end

function M:OpenFilterMenu(anchor)
	local entries = {
		{ text = "Show", isTitle = true },
		{ text = "Everything", radio = true, checked = function() return self.filter == nil end,
			func = function() self.filter = nil; self:UpdateWindow() end },
	}
	for _, source in ipairs(self:Sources()) do
		entries[#entries + 1] = { text = source, radio = true, checked = function() return self.filter == source end,
			func = function() self.filter = source; self:UpdateWindow() end }
	end
	Grimoire.OpenMenu(anchor, entries)
end

function M:UpdateWindow()
	if not self.window or not self.window:IsShown() then return end
	local report = self.mode == "report"
	self.shownText = report and self:Report() or self:LogText()
	self.box:SetText(self.shownText)
	self.modeButton:SetText(report and "Log" or "Report")
	self.filterButton:SetShown(not report)
	self.window.subtitle:SetText(report
		and "Environment report. Select all, Ctrl+C, and paste it where it's needed."
		or ("Log%s. Saved to Grimoire_Debug.lua on /reload. Select all, Ctrl+C to copy."):format(
			self.filter and (" for " .. self.filter) or ""))
	-- Newest at the bottom: start scrolled there.
	C_Timer.After(0, function()
		self.scroll:SetVerticalScroll(self.scroll:GetVerticalScrollRange())
	end)
end

-- New entries refresh an open log, at most a few times a second.
function M:OnLog()
	local last = Grimoire.log[#Grimoire.log]
	if last and last.level == "error" and last.count == 1 and not self.toldAboutErrors then
		self.toldAboutErrors = true
		self:Print("A Lua error was logged. /grim debug shows it (and it's saved on /reload).")
	end
	if self.window and self.window:IsShown() and self.mode ~= "report" and not self.refreshQueued then
		self.refreshQueued = true
		C_Timer.After(0.3, function()
			self.refreshQueued = false
			self:UpdateWindow()
		end)
	end
end

-- Public: core's menus and commands ------------------------------------------------------------

function M:ShowLog(source)
	if not self.window then self:Build() end
	self.mode, self.filter = "log", source
	self.window:Show()
	self:UpdateWindow()
end

function M:ShowReport()
	if not self.window then self:Build() end
	self.mode = "report"
	self.window:Show()
	self:UpdateWindow()
end

function M:Clear()
	wipe(Grimoire.log)
	wipe(self.previous)
	GrimoireDebugDB.log = {}
	self:UpdateWindow()
end

function M:Toggle()
	if self.window and self.window:IsShown() then
		self.window:Hide()
	else
		self:ShowLog()
	end
end

-- The top-level Debug ▸ menu.
function M:GetMenu()
	local levels = Grimoire.db.global.logLevels
	return {
		{ text = "Show log", func = function() self:ShowLog() end },
		{ text = "Environment report", func = function() self:ShowReport() end },
		{
			text = "Log everything",
			checked = function() return levels["*"] == "debug" end,
			func = function() levels["*"] = levels["*"] ~= "debug" and "debug" or nil end,
		},
		{ text = "Clear log", func = function() self:Clear() end },
	}
end

-- Saving ----------------------------------------------------------------------------------------

function M:Save()
	local saved = {}
	for _, entries in ipairs({ self.previous, Grimoire.log }) do
		for _, entry in ipairs(entries) do
			saved[#saved + 1] = entry
		end
	end
	while #saved > SAVED_ENTRIES do
		table.remove(saved, 1)
	end
	GrimoireDebugDB.log = saved
	GrimoireDebugDB.saved = date("%Y-%m-%d %H:%M:%S")
	local ok, report = pcall(self.Report, self)
	GrimoireDebugDB.report = ok and report or ("report failed: " .. tostring(report))
end

-- Lifecycle -------------------------------------------------------------------------------------

function M:OnInitialize()
	GrimoireDebugDB = GrimoireDebugDB or {}
	self.previous = GrimoireDebugDB.log or {}
	Grimoire:RegisterCommand("debug", "debug [report] - the log of errors and events, or the environment report", function(arg)
		if not self:IsEnabled() then
			Grimoire:Print("Debug is turned off (Grimoire menu: Components, Debug).")
		elseif (arg or ""):lower() == "report" then
			self:ShowReport()
		else
			self:Toggle()
		end
	end)
end

function M:OnEnable()
	Grimoire.onLog = function() self:OnLog() end
	self:RegisterEvent("PLAYER_LOGOUT", "Save")
end

function M:OnDisable()
	Grimoire.onLog = nil
	if self.window then self.window:Hide() end
end

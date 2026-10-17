local Grimoire = Grimoire

-- The log (plan Milestone 2). Core keeps the last MAX_ENTRIES entries in memory; the
-- Debug component (Grimoire_Debug) shows them, adds an environment report and saves them
-- to disk on logout and /reload.
--
--   Grimoire:Log(source, level, fmt, ...)   Module:Log(level, fmt, ...)
--   levels: error, warn, info, debug
--
-- Which levels are kept is set per source in GrimoireDB.global.logLevels ("off", "info"
-- or "debug"; default "info"). Errors are always kept.
--
-- Every Lua error in the game, from any add-on, is logged too: this file installs an
-- error handler from the moment core loads, which records the error and then passes it
-- on to the handler that was there before (Blizzard's, or BugGrabber's). Blocked-action
-- pop-ups (ADDON_ACTION_BLOCKED / _FORBIDDEN) are logged as errors. So nothing is lost
-- even without BugSack (seen 2026-10-16: BugGrabber was off and errors went missing).

local MAX_ENTRIES = 500
local MAX_STACK = 1500 -- characters of stack kept per error

local LEVELS = { error = 1, warn = 2, info = 3, debug = 4 }
local KEEP = { off = 1, info = 3, debug = 4 }
Grimoire.LOG_LEVELS = LEVELS

-- Entries: { time, level, source, message, count } (count > 1 for repeats).
Grimoire.log = {}

local function Kept(source, level)
	if level == "error" then return true end
	local levels = Grimoire.db and Grimoire.db.global.logLevels
	local wanted = levels and (levels[source] or levels["*"]) or "info"
	return LEVELS[level] <= (KEEP[wanted] or KEEP.info)
end

local function Text(fmt, ...)
	if select("#", ...) == 0 then return tostring(fmt) end
	local args = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		args[i] = (Grimoire.IsSecret and Grimoire.IsSecret(value)) and "<secret>" or value
	end
	local ok, text = pcall(string.format, tostring(fmt), unpack(args, 1, select("#", ...)))
	if ok then return text end
	-- A format that doesn't fit its values (e.g. %d given "<secret>"): show them plainly.
	for i = 1, select("#", ...) do args[i] = tostring(args[i]) end
	return tostring(fmt) .. " [" .. table.concat(args, ", ") .. "]"
end

function Grimoire:Log(source, level, fmt, ...)
	if not LEVELS[level] or not Kept(source, level) then return end
	local message = Text(fmt, ...)
	local log = self.log
	local last = log[#log]
	-- An error repeating every frame becomes one entry with a count.
	if last and last.source == source and last.message == message then
		last.count = last.count + 1
		last.time = time()
	else
		log[#log + 1] = { time = time(), level = level, source = source, message = message, count = 1 }
		if #log > MAX_ENTRIES then
			table.remove(log, 1)
		end
	end
	if self.onLog then
		pcall(self.onLog) -- the Debug window refreshes; never let that break logging
	end
end

-- Lua errors ---------------------------------------------------------------------------

-- The add-on an error came from: the first AddOns\<name> in its message or stack.
local function SourceOf(message, stack)
	return (message:match("AddOns[/\\]([^/\\%]]+)") or (stack or ""):match("AddOns[/\\]([^/\\%]]+)") or "Lua")
end

local logging = false -- an error while logging an error must not loop
local previousHandler = geterrorhandler()
seterrorhandler(function(message, ...)
	if not logging then
		logging = true
		pcall(function()
			local text = (Grimoire.IsSecret and Grimoire.IsSecret(message)) and "<secret error>" or tostring(message)
			local stack = debugstack and debugstack(3) or ""
			if #stack > MAX_STACK then stack = stack:sub(1, MAX_STACK) .. "..." end
			Grimoire:Log(SourceOf(text, stack), "error", "%s\n%s", text, stack)
		end)
		logging = false
	end
	if previousHandler then
		return previousHandler(message, ...)
	end
end)

-- Blocked actions ("... has been blocked from an action only available to the Blizzard UI").
local blocked = CreateFrame("Frame")
blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blocked:SetScript("OnEvent", function(_, event, addon, action)
	Grimoire:Log(tostring(addon), "error", "%s: tried to call %s", event, tostring(action))
end)

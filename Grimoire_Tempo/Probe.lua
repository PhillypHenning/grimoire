local _, ns = ...
local Grimoire = Grimoire
local M = ns.M

-- The probe (plan milestone T1): lists the APIs this client has, then records the next
-- fight from every source that might give damage data. The recorder already uses the
-- best source it finds; the probe shows what each one actually gave, to tune the order.
-- The combat log isn't probed: registering it is blocked on Forever (see Recorder.lua).
-- Results go to SavedVariables\Grimoire_Tempo.lua on /reload, where they can be read
-- directly. It has its own event frame, so it never takes events from the recorder.

local MAX_SAMPLES = 40   -- per source, so one long fight can't bloat saved data

-- Values are stored as plain text: secrets can't be compared, printed or saved.
local function Describe(value)
	if Grimoire.IsSecret(value) then return "<secret>" end
	local kind = type(value)
	if kind == "string" or kind == "number" or kind == "boolean" or kind == "nil" then
		return tostring(value)
	end
	return "<" .. kind .. ">"
end

local function DescribeAll(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = Describe((select(i, ...)))
	end
	return table.concat(parts, ", ")
end

local function SortedKeys(t)
	local keys = {}
	if type(t) == "table" then
		for key in pairs(t) do keys[#keys + 1] = tostring(key) end
	end
	table.sort(keys)
	return keys
end

local function SpellName(spellID)
	if Grimoire.IsSecret(spellID) or not spellID then return nil end
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
	return GetSpellInfo and (GetSpellInfo(spellID))
end

-- API inventory ------------------------------------------------------------------------

local GLOBALS = {
	"CombatLogGetCurrentEventInfo", "issecretvalue", "UnitHealthPercent", "UnitCastingDuration",
	"C_DamageMeter", "C_CombatLog", "C_DurationUtil", "C_CurveUtil", "C_ActionBar",
}

local function Inventory()
	local found = {}
	for _, name in ipairs(GLOBALS) do
		found[name] = _G[name] ~= nil
	end
	return {
		globals = found,
		damageMeter = SortedKeys(C_DamageMeter),
		combatLog = SortedKeys(C_CombatLog),
	}
end

-- A nested table as text lines, a few levels deep and a few list items wide.
local function Dump(value, depth, lines, indent)
	lines, indent = lines or {}, indent or ""
	if type(value) ~= "table" or Grimoire.IsSecret(value) then
		lines[#lines + 1] = indent .. Describe(value)
		return lines
	end
	local shown = 0
	for _, key in ipairs(SortedKeys(value)) do
		local child = value[key] ~= nil and value[key] or value[tonumber(key)]
		shown = shown + 1
		if shown > 8 then
			lines[#lines + 1] = indent .. "..."
			break
		end
		if type(child) == "table" and depth > 1 then
			lines[#lines + 1] = indent .. key .. ":"
			Dump(child, depth - 1, lines, indent .. "  ")
		else
			lines[#lines + 1] = indent .. key .. " = " .. Describe(child)
		end
	end
	return lines
end

local function Try(fn, ...)
	if type(fn) ~= "function" then return { "missing" } end
	local packed = { pcall(fn, ...) }
	if not table.remove(packed, 1) then
		return { "error: " .. Describe(packed[1]) }
	end
	return Dump(packed[1], 4)
end

-- Blizzard's damage meter (the first probe, 2026-10-16, found C_DamageMeter but called it
-- without arguments). Every session type is asked for every meter type, whole and for
-- the player alone: the player-only damage would leave out other players and the pet.
local function SampleDamageMeter()
	local api = C_DamageMeter
	if type(api) ~= "table" then return nil end
	local sessionTypes = Enum and Enum.DamageMeterSessionType or {}
	local meterTypes = Enum and Enum.DamageMeterType or {}
	local results = {
		available = Try(api.IsDamageMeterAvailable),
		combatLogRestricted = C_CombatLog and Try(C_CombatLog.IsCombatLogRestricted),
		sessionTypes = Dump(sessionTypes, 1),
		meterTypes = Dump(meterTypes, 1),
		sessions = Try(api.GetAvailableCombatSessions),
		byType = {},
	}
	local guid = UnitGUID("player")
	for sessionName, sessionType in pairs(sessionTypes) do
		results.byType[sessionName .. " duration"] = Try(api.GetSessionDurationSeconds, sessionType)
		for meterName, meterType in pairs(meterTypes) do
			local key = sessionName .. " " .. meterName
			results.byType[key] = Try(api.GetCombatSessionFromType, sessionType, meterType)
			results.byType[key .. " (you)"] = Try(api.GetCombatSessionSourceFromType, sessionType, meterType, guid)
		end
	end
	return results
end

-- Recording ----------------------------------------------------------------------------

local probe = {}

local function Add(source, line)
	local fight = probe.fight
	if not fight then return end
	local list = fight.samples[source]
	if not list then
		list = {}
		fight.samples[source] = list
	end
	fight.counts[source] = (fight.counts[source] or 0) + 1
	if #list < MAX_SAMPLES then
		list[#list + 1] = ("%.2f %s"):format(GetTime() - fight.start, line)
	end
end

local function TargetHealth(label)
	local percent = UnitHealthPercent and select(2, pcall(UnitHealthPercent, "target"))
	Add(label, ("health %s / %s, percent %s"):format(
		Describe(UnitHealth("target")), Describe(UnitHealthMax("target")), Describe(percent)))
end

local HANDLERS = {
	UNIT_SPELLCAST_SENT = function(event, unit, _, _, spellID)
		Add(event, DescribeAll(unit, spellID) .. (SpellName(spellID) and (" " .. SpellName(spellID)) or ""))
	end,
	UNIT_SPELLCAST_SUCCEEDED = function(event, unit, _, spellID)
		Add(event, DescribeAll(unit, spellID) .. (SpellName(spellID) and (" " .. SpellName(spellID)) or ""))
	end,
	UNIT_COMBAT = function(event, unit, action, descriptor, amount, school)
		Add(event, DescribeAll(unit, action, descriptor, amount, school))
	end,
	PET_ATTACK_START = function(event)
		Add(event, "pet sent in")
	end,
	UNIT_HEALTH = function(event)
		TargetHealth(event)
	end,
}

function M:ProbeStart()
	if not probe.armed or probe.fight then return end
	probe.fight = {
		start = GetTime(),
		target = UnitExists("target") and Describe(UnitName("target")) or "none",
		samples = {},
		counts = {},
	}
	local frame = probe.frame
	if not frame then
		frame = CreateFrame("Frame")
		frame:SetScript("OnEvent", function(_, event, ...) HANDLERS[event](event, ...) end)
		probe.frame = frame
	end
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
	pcall(frame.RegisterEvent, frame, "PET_ATTACK_START") -- in case this client lacks it
	frame:RegisterUnitEvent("UNIT_COMBAT", "target")
	frame:RegisterUnitEvent("UNIT_HEALTH", "target")
	TargetHealth("UNIT_HEALTH (start)")
	self:Print("Probe: recording this fight.")
end

function M:ProbeStop()
	local fight = probe.fight
	if not fight then return end
	probe.frame:UnregisterAllEvents()
	TargetHealth("UNIT_HEALTH (end)")
	fight.duration = GetTime() - fight.start
	fight.start = nil
	fight.damageMeter = SampleDamageMeter()
	-- The meter may settle after combat: read it again a moment later.
	C_Timer.After(3, function()
		if self.store.probe and self.store.probe.fight == fight then
			fight.damageMeterLater = SampleDamageMeter()
		end
	end)
	fight.recorder = {
		usedSource = self:GetCharacter().fights[1] and self:GetCharacter().fights[1].source or "none",
	}
	probe.fight, probe.armed = nil, false

	local version, build = GetBuildInfo()
	self.store.probe = {
		time = date("%Y-%m-%d %H:%M"),
		build = version .. "." .. build,
		inventory = Inventory(),
		fight = fight,
	}
	self:Print(("Probe: fight recorded (%.0f s). Casts seen: %d, damage events (UNIT_COMBAT): %d.")
		:format(fight.duration, fight.counts.UNIT_SPELLCAST_SUCCEEDED or 0, fight.counts.UNIT_COMBAT or 0))
	self:Print("/reload to write it to SavedVariables\\Grimoire_Tempo.lua.")
end

function M:ArmProbe()
	probe.armed = true
	self:Print("Probe ready: target a mob and fight it. Results save when combat ends.")
	if InCombatLockdown() then
		self:ProbeStart()
	end
end

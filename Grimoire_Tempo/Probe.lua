local _, ns = ...
local Grimoire = Grimoire
local M = ns.M

-- The probe (plan milestone T1): lists the APIs this client has, then records the next
-- fight from every source that might give damage data. The recorder already uses the
-- best source it finds; the probe shows what each one actually gave, to tune the order.
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

-- Damage-meter API: unknown shape, so every Get* function is tried with no arguments.
local function SampleDamageMeter()
	if type(C_DamageMeter) ~= "table" then return nil end
	local results = {}
	for _, name in ipairs(SortedKeys(C_DamageMeter)) do
		local fn = C_DamageMeter[name]
		if type(fn) == "function" and name:find("^Get") then
			local packed = { pcall(fn) }
			local ok = table.remove(packed, 1)
			local line = ok and DescribeAll(unpack(packed)) or ("error: " .. Describe(packed[1]))
			if ok and type(packed[1]) == "table" then
				line = line .. " keys: " .. table.concat(SortedKeys(packed[1]), " ")
			end
			results[name] = line
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
	UNIT_HEALTH = function(event)
		TargetHealth(event)
	end,
	COMBAT_LOG_EVENT_UNFILTERED = function(event)
		local ok, _, subevent, _, sourceGUID, _, _, _, _, _, _, _, spellID, spellName, _, amount =
			pcall(CombatLogGetCurrentEventInfo)
		if not ok then
			Add(event, "error reading event")
		elseif Grimoire.IsSecret(sourceGUID) or sourceGUID ~= UnitGUID("player") then
			probe.fight.counts.otherCombatLog = (probe.fight.counts.otherCombatLog or 0) + 1
		else
			Add(event, DescribeAll(subevent, spellID, spellName, amount))
		end
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
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	frame:RegisterUnitEvent("UNIT_COMBAT", "target")
	frame:RegisterUnitEvent("UNIT_HEALTH", "target")
	-- Retail Midnight forbids add-ons this event; a refusal is itself a probe result.
	local ok, err = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
	probe.fight.combatLog = ok and "registered" or ("refused: " .. Describe(err))
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
	fight.recorder = {
		combatLogAllowed = self.combatLogAllowed,
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
	self:Print(("Probe: fight recorded (%.0f s). Combat log: %s. Casts seen: %d, damage events (UNIT_COMBAT): %d.")
		:format(fight.duration, fight.combatLog, fight.counts.UNIT_SPELLCAST_SUCCEEDED or 0, fight.counts.UNIT_COMBAT or 0))
	self:Print("/reload to write it to SavedVariables\\Grimoire_Tempo.lua.")
end

function M:ArmProbe()
	probe.armed = true
	self:Print("Probe ready: target a mob and fight it. Results save when combat ends.")
	if InCombatLockdown() then
		self:ProbeStart()
	end
end

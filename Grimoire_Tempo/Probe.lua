local ADDON_NAME = ...
local Grimoire = Grimoire

-- Tempo, milestone T1: the probe. Before scoring rotations we need to know what fight data
-- Forever gives an add-on: the combat log may be blocked (as in retail Midnight), and
-- damage or health values may be secret. /grim tempo probe lists the APIs this client has,
-- then records the next fight from every source that might work. Results go to
-- SavedVariables\Grimoire_Tempo.lua on /reload, where they can be read directly.

local MAX_SAMPLES = 40   -- per source, so one long fight can't bloat saved data

local M = Grimoire:NewModule("Tempo", {
	addon = ADDON_NAME,
	label = "Tempo",
})

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

function M:Add(source, line)
	local fight = self.fight
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

function M:OnSpellcast(event, unit, castGUID, spellID)
	local name = SpellName(spellID)
	self:Add(event, DescribeAll(unit, spellID) .. (name and (" " .. name) or ""))
end

function M:OnUnitCombat(event, unit, action, descriptor, amount, school)
	self:Add(event, DescribeAll(unit, action, descriptor, amount, school))
end

function M:OnTargetHealth(event, unit)
	local percent = UnitHealthPercent and select(2, pcall(UnitHealthPercent, unit))
	self:Add(event, ("health %s / %s, percent %s"):format(
		Describe(UnitHealth(unit)), Describe(UnitHealthMax(unit)), Describe(percent)))
end

function M:OnCombatLog()
	local ok, timestamp, subevent, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID, spellName, _, amount =
		pcall(CombatLogGetCurrentEventInfo)
	if not ok then
		self:Add("COMBAT_LOG_EVENT_UNFILTERED", "error reading event")
		return
	end
	if Grimoire.IsSecret(sourceGUID) or sourceGUID ~= UnitGUID("player") then
		-- Only count other units' events; keep samples for the player's own.
		self.fight.counts.otherCombatLog = (self.fight.counts.otherCombatLog or 0) + 1
		return
	end
	self:Add("COMBAT_LOG_EVENT_UNFILTERED", DescribeAll(subevent, spellID, spellName, amount))
end

function M:StartFight()
	if not self.armed or self.fight then return end
	self.fight = {
		start = GetTime(),
		target = UnitExists("target") and Describe(UnitName("target")) or "none",
		samples = {},
		counts = {},
	}
	for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do
		self:RegisterUnitEvent(event, "player", "OnSpellcast")
	end
	self:RegisterUnitEvent("UNIT_COMBAT", "target", "OnUnitCombat")
	self:RegisterUnitEvent("UNIT_HEALTH", "target", "OnTargetHealth")
	-- Retail Midnight forbids add-ons this event; a refusal is itself a probe result.
	local frame = self:GetEventFrame()
	frame.handlers.COMBAT_LOG_EVENT_UNFILTERED = "OnCombatLog"
	local ok, err = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
	self.fight.combatLog = ok and "registered" or ("refused: " .. Describe(err))
	self:OnTargetHealth("UNIT_HEALTH (start)", "target")
	self:Print("Recording this fight.")
end

function M:StopFight()
	local fight = self.fight
	if not fight then return end
	for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_COMBAT",
		"UNIT_HEALTH", "COMBAT_LOG_EVENT_UNFILTERED" }) do
		self:UnregisterEvent(event)
	end
	self:OnTargetHealth("UNIT_HEALTH (end)", "target")
	fight.duration = GetTime() - fight.start
	fight.start = nil
	fight.damageMeter = SampleDamageMeter()
	self.fight, self.armed = nil, false

	local version, build = GetBuildInfo()
	GrimoireTempoDB = GrimoireTempoDB or {}
	GrimoireTempoDB.probe = {
		time = date("%Y-%m-%d %H:%M"),
		build = version .. "." .. build,
		inventory = Inventory(),
		fight = fight,
	}
	self:Print(("Fight recorded (%.0f s). Combat log: %s. Casts seen: %d, damage events (UNIT_COMBAT): %d.")
		:format(fight.duration, fight.combatLog, fight.counts.UNIT_SPELLCAST_SUCCEEDED or 0, fight.counts.UNIT_COMBAT or 0))
	self:Print("/reload to write it to SavedVariables\\Grimoire_Tempo.lua.")
end

function M:Arm()
	if not self:IsEnabled() then
		Grimoire:Print("Tempo is turned off.")
		return
	end
	self.armed = true
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "StartFight")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "StopFight")
	self:Print("Probe ready: target a mob and fight it. Results save when combat ends.")
	if InCombatLockdown() then
		self:StartFight()
	end
end

function M:OnInitialize()
	Grimoire:RegisterCommand("tempo", "tempo probe - record the next fight to see what data this client gives", function(arg)
		if (arg or ""):lower() == "probe" then
			self:Arm()
		else
			Grimoire:Print("Usage: /grim tempo probe")
		end
	end)
end

function M:OnDisable()
	self:StopFight()
	self.armed = false
end

local _, ns = ...
local Grimoire = Grimoire
local M = ns.M
local Cycles = ns.Cycles

-- The recorder (plan milestone T2). Casts come from UNIT_SPELLCAST_SUCCEEDED, so keybinds,
-- clicks and macros all count. Damage comes from whichever source this client allows,
-- all listened to at once and the best one kept per fight:
--   combatLog   your own damage, exact (if add-ons may read the combat log)
--   unitCombat  damage your target takes (anyone's), from UNIT_COMBAT
--   health      percent of your target's health lost; the last resort
-- Secret values are skipped, never compared: a source that only gives secrets ends up
-- empty and the next one is used.
--
-- fight = { time, target, level, duration, unit, source, total, dps,
--           casts = { { t, spell, name } }, damage = { { t, amount } } }   -- t: seconds

local PREPULL = 3          -- casts this long before combat count: the pull lands first
local MIN_FIGHT = 6        -- seconds; shorter fights aren't kept
local MIN_CASTS = 2
local BUCKET = 0.5         -- damage is summed into half-second buckets to keep saved data small
local MAX_CASTS = 400
local COLLAPSE = { [75] = true, [5019] = true } -- Auto Shot, Shoot (wand): one note per run

local SOURCES = { "combatLog", "unitCombat", "health" }
local SOURCE_UNIT = { combatLog = "damage", unitCombat = "damage", health = "health" }
M.SOURCE_LABELS = { combatLog = "combat log", unitCombat = "damage taken", health = "target health" }

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spellID) end
	return GetSpellInfo and (GetSpellInfo(spellID))
end

-- Casts ------------------------------------------------------------------------------------

function M:OnPlayerCast(_, unit, _, spellID)
	if not spellID or Grimoire.IsSecret(spellID) then return end
	local name = SpellName(spellID)
	if not name or Grimoire.IsSecret(name) then return end
	local now = GetTime()
	local rec = self.recording
	local list = rec and rec.casts or self.recentCasts
	local last = list[#list]
	if COLLAPSE[spellID] and last and last.spell == spellID then return end
	if rec then
		if #list < MAX_CASTS then
			list[#list + 1] = { time = now, spell = spellID, name = name }
		end
	else
		-- Out of combat only the last few seconds are kept, for the pull.
		while list[1] and now - list[1].time > PREPULL do
			table.remove(list, 1)
		end
		list[#list + 1] = { time = now, spell = spellID, name = name }
	end
	self:JudgeCast(name, now)
end

-- Damage -----------------------------------------------------------------------------------

local function AddDamage(rec, source, amount)
	local list = rec.sources[source]
	local t = GetTime()
	local last = list[#list]
	if last and t - last.time < BUCKET then
		last.amount = last.amount + amount
	else
		list[#list + 1] = { time = t, amount = amount }
	end
end

function M:OnCombatLog()
	local rec = self.recording
	if not rec then return end
	local _, subevent, _, sourceGUID, _, _, _, _, _, _, _, arg12, _, _, arg15 = CombatLogGetCurrentEventInfo()
	if Grimoire.AnySecret(subevent, sourceGUID) or sourceGUID ~= self.playerGUID or not subevent then return end
	local amount
	if subevent == "SWING_DAMAGE" then
		amount = arg12
	elseif subevent:find("_DAMAGE$") then -- SPELL_, SPELL_PERIODIC_, RANGE_
		amount = arg15
	end
	if type(amount) == "number" and not Grimoire.IsSecret(amount) and amount > 0 then
		AddDamage(rec, "combatLog", amount)
	end
end

function M:OnTargetCombat(_, unit, action, _, amount)
	local rec = self.recording
	if not rec or unit ~= "target" or Grimoire.AnySecret(action, amount) then return end
	if action == "WOUND" and type(amount) == "number" and amount > 0 then
		AddDamage(rec, "unitCombat", amount)
	end
end

-- Percent of the target's health, if any form of it is readable.
local function HealthPercent(unit)
	local health, max = UnitHealth(unit), UnitHealthMax(unit)
	if not Grimoire.AnySecret(health, max) and max and max > 0 then
		return health / max * 100
	end
	if UnitHealthPercent then
		local ok, percent = pcall(UnitHealthPercent, unit)
		if ok and type(percent) == "number" and not Grimoire.IsSecret(percent) then
			return percent <= 1 and percent * 100 or percent
		end
	end
end

-- Health lost is tracked per mob, so switching targets doesn't count as damage.
function M:OnTargetHealth(_, unit)
	local rec = self.recording
	if not rec or (unit and unit ~= "target") or not UnitExists("target") then return end
	local guid = UnitGUID("target")
	local percent = HealthPercent("target")
	if not guid or Grimoire.IsSecret(guid) or not percent then return end
	local last = rec.health[guid]
	if last and percent < last then
		AddDamage(rec, "health", last - percent)
	end
	rec.health[guid] = percent
end

-- Recording --------------------------------------------------------------------------------

function M:EnableRecorder()
	self.recentCasts = {}
	self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "OnPlayerCast")
	self:RegisterUnitEvent("UNIT_COMBAT", "target", "OnTargetCombat")
	self:RegisterUnitEvent("UNIT_HEALTH", "target", "OnTargetHealth")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetHealth")
	-- Retail Midnight forbids add-ons the combat log. After one refusal it isn't asked again
	-- this session (no repeated errors); otherwise it's registered on every enable.
	if self.combatLogAllowed ~= false then
		local frame = self:GetEventFrame()
		frame.handlers.COMBAT_LOG_EVENT_UNFILTERED = "OnCombatLog"
		self.combatLogAllowed = pcall(frame.RegisterEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED") and true or false
	end
end

local function TargetName()
	local name = UnitExists("target") and UnitName("target")
	if not name or Grimoire.IsSecret(name) then return "unknown" end
	return name
end

function M:StartRecording()
	if self.recording then return end
	local now = GetTime()
	local casts = {}
	for _, cast in ipairs(self.recentCasts or {}) do
		if now - cast.time <= PREPULL then casts[#casts + 1] = cast end
	end
	self.recentCasts = {}
	self.recording = {
		start = now,
		target = TargetName(),
		casts = casts,
		health = {},
		sources = { combatLog = {}, unitCombat = {}, health = {} },
	}
	self:OnTargetHealth()
end

-- Ends the recording; returns the saved fight (nil if too short) and what became a new best.
function M:StopRecording()
	local rec = self.recording
	if not rec then return nil end
	self:OnTargetHealth()
	self.recording = nil
	local now = GetTime()
	local start = rec.start
	if rec.casts[1] and rec.casts[1].time < start then start = rec.casts[1].time end

	local fight = { time = time(), target = rec.target, level = UnitLevel("player"), duration = now - start, casts = {}, damage = {} }
	for _, cast in ipairs(rec.casts) do
		fight.casts[#fight.casts + 1] = { t = cast.time - start, spell = cast.spell, name = cast.name }
	end
	for _, source in ipairs(SOURCES) do
		if #rec.sources[source] > 0 then
			fight.source, fight.unit = source, SOURCE_UNIT[source]
			local total = 0
			for _, entry in ipairs(rec.sources[source]) do
				fight.damage[#fight.damage + 1] = { t = entry.time - start, amount = entry.amount }
				total = total + entry.amount
			end
			fight.total, fight.dps = total, total / math.max(fight.duration, 1)
			break
		end
	end

	if fight.duration < MIN_FIGHT or #fight.casts < MIN_CASTS then
		return nil
	end
	local char = self:GetCharacter()
	table.insert(char.fights, 1, fight)
	while #char.fights > (self.db.keepFights or 20) do
		table.remove(char.fights)
	end
	return fight, self:UpdateBest(fight, Cycles.Split(fight, self:GetClass()))
end

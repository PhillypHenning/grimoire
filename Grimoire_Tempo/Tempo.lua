local ADDON_NAME, ns = ...
local Grimoire = Grimoire
local Cycles = ns.Cycles

-- Tempo: learns your best rotation from your fights and plays it back as a guide
-- (docs/plans/tempo.md). Recorder.lua records each fight, Cycles.lua splits and scores
-- it, Lane.lua is the music-staff playback, Window.lua the history, Share.lua the text
-- format for teaching, Probe.lua the data probe.
--
-- GrimoireTempoDB = {
--     characters = { ["Name - Realm"] = {
--         fights = { fight, ... },          -- newest first; see Recorder.lua
--         best = { opener = rotation, cycle = rotation },
--         pinned = rotation,                -- what "Pinned" mode plays
--     } },
--     rotations = { rotation, ... },        -- imported or saved, account-wide
--     probe = { ... },                      -- last /grim tempo probe
-- }
-- A rotation is a Cycles segment plus name, class, notes, time and target.

local M = Grimoire:NewModule("Tempo", {
	addon = ADDON_NAME,
	label = "Tempo",
	defaults = {
		mode = "follow",
		showLane = true,
		keepFights = 20,
	},
	options = {
		{ type = "choice", key = "mode", label = "Playback", values = {
			{ "follow", "Follow my best" }, { "pinned", "Pinned rotation" }, { "experiment", "Experiment (record only)" },
		} },
		{ type = "toggle", key = "showLane", label = "Show the playback lane" },
		{ type = "choice", key = "keepFights", label = "Fights kept", values = {
			{ 10, "10" }, { 20, "20" }, { 50, "50" },
		} },
	},
})
ns.M = M

-- Data ------------------------------------------------------------------------------------

function M:GetCharacter()
	local chars = self.store.characters
	local key = Grimoire.db.charKey
	chars[key] = Grimoire.CopyDefaults({ fights = {}, best = {} }, chars[key] or {})
	return chars[key]
end

function M:GetClass()
	return select(2, UnitClass("player"))
end

local KIND_LABELS = { opener = "Opener", cycle = "Cycle" }

function M.KindLabel(kind)
	return KIND_LABELS[kind] or kind
end

-- A segment becomes a saved rotation: a copy, so later edits can't change the fight.
function M:MakeRotation(segment, fight)
	return {
		name = ("%s, %s"):format(M.KindLabel(segment.kind), fight and fight.target or "imported"),
		class = self:GetClass(),
		kind = segment.kind,
		steps = CopyTable(segment.steps),
		length = segment.length,
		damage = segment.damage,
		dps = segment.dps,
		unit = segment.unit,
		scored = segment.scored,
		notes = segment.notes and CopyTable(segment.notes) or {},
		time = fight and fight.time or time(),
		target = fight and fight.target,
	}
end

-- Keeps a fight's best opener and cycle if they beat the saved ones. Returns what improved.
function M:UpdateBest(fight, segments)
	local best, improved = self:GetCharacter().best, {}
	for kind, segment in pairs(Cycles.BestOf(segments)) do
		if Cycles.IsBetter(segment, best[kind]) then
			best[kind] = self:MakeRotation(segment, fight)
			improved[#improved + 1] = kind
		end
	end
	return improved
end

function M:ForgetBest()
	wipe(self:GetCharacter().best)
	self:Refresh()
end

-- Pinned: an opener plays once, then your best cycle; a cycle loops.
function M:Pin(rotation)
	self:GetCharacter().pinned = CopyTable(rotation)
	Grimoire:SetModuleSetting(self, "mode", "pinned")
	self:Print(("Pinned \"%s\". Your next fight plays it."):format(rotation.name))
	self:Refresh()
end

function M:Unpin()
	self:GetCharacter().pinned = nil
	Grimoire:SetModuleSetting(self, "mode", "follow")
	self:Refresh()
end

-- What the lane plays: opener (once), then cycle (looped). Either may be nil.
function M:GetPlayback()
	local char = self:GetCharacter()
	if self.db.mode == "experiment" then return nil, nil end
	local pinned = self.db.mode == "pinned" and char.pinned
	if pinned then
		if pinned.kind == "opener" then return pinned, char.best.cycle end
		return nil, pinned
	end
	return char.best.opener, char.best.cycle
end

function M:SaveRotation(rotation)
	table.insert(self.store.rotations, 1, rotation)
	self:Refresh()
end

function M:DeleteRotation(index)
	table.remove(self.store.rotations, index)
	self:Refresh()
end

-- Combat -----------------------------------------------------------------------------------

function M:OnCombatStart()
	self:StartRecording()
	self:StartPlayback()
	self:ProbeStart()
end

function M:OnCombatEnd()
	local fight, improved = self:StopRecording()
	self:StopPlayback(fight, improved)
	self:ProbeStop()
	self:Refresh()
end

-- Lifecycle --------------------------------------------------------------------------------

function M:Refresh()
	if not self:IsEnabled() then return end
	if self.window and self.window:IsShown() then self:UpdateWindow() end
	self:UpdateLane()
end

function M:Toggle()
	self:ToggleWindow()
end

function M:ApplySettings()
	self:Refresh()
end

function M:OnInitialize()
	GrimoireTempoDB = GrimoireTempoDB or {}
	self.store = Grimoire.CopyDefaults({ characters = {}, rotations = {} }, GrimoireTempoDB)
	Grimoire:RegisterCommand("tempo", "tempo [probe|import] - your rotations; probe records what fight data this client gives", function(arg)
		arg = (arg or ""):lower()
		if not self:IsEnabled() then
			Grimoire:Print("Tempo is turned off (Grimoire menu: Components, Tempo).")
		elseif arg == "probe" then
			self:ArmProbe()
		elseif arg == "import" then
			self:ShowShare()
		else
			self:ToggleWindow()
		end
	end)
end

function M:OnEnable()
	self.playerGUID = UnitGUID("player")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	self:EnableRecorder()
	self:RegisterCallback("MoversUnlocked", "UpdateLane")
	self:RegisterCallback("MoversLocked", "UpdateLane")
	self:UpdateLane()
end

function M:OnDisable()
	self:StopRecording()
	self:StopPlayback()
	self:ProbeStop()
	if self.lane then self.lane:Hide() end
	if self.window then self.window:Hide() end
	if self.shareWindow then self.shareWindow:Hide() end
end

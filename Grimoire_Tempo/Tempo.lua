local ADDON_NAME, ns = ...
local Grimoire = Grimoire
local Cycles = ns.Cycles

-- Tempo: learns your best rotation from your fights (docs/plans/tempo.md). Recorder.lua
-- records each fight, Cycles.lua splits and scores it, Window.lua shows your best and your
-- fights, Share.lua is the text format for teaching, Probe.lua the data probe.
-- (A music-staff playback lane was built and then dropped at Phil's request, 2026-10-16:
-- rotations are studied in the window instead.)
--
-- GrimoireTempoDB = {
--     characters = { ["Name - Realm"] = {
--         fights = { fight, ... },          -- newest first; see Recorder.lua
--         best = { opener = rotation, cycle = rotation },
--     } },
--     rotations = { rotation, ... },        -- imported or saved, account-wide
--     probe = { ... },                      -- last /grim tempo probe
-- }
-- A rotation is a Cycles segment plus name, class, notes, time and target.

local M = Grimoire:NewModule("Tempo", {
	addon = ADDON_NAME,
	label = "Tempo",
	defaults = {
		showButton = true,
		keepFights = 20,
	},
	options = {
		{ type = "toggle", key = "showButton", label = "Show the Tempo button", tooltip = "A round button that opens your rotations. Drag it in move mode." },
		{ type = "choice", key = "keepFights", label = "Fights kept", tooltip = "How many recent fights Tempo keeps for each character.", values = {
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
	chars[key].pinned = nil -- from the playback lane, which is gone
	return chars[key]
end

function M:GetClass()
	return select(2, UnitClass("player"))
end

function M.SpellIcon(spell)
	if not spell then return nil end
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) end
	return GetSpellTexture and GetSpellTexture(spell)
end

-- A step's icon: its spell's, the pet-attack icon for sending the pet, or a question mark.
function M.StepIcon(step)
	if step.name == Cycles.PET_ATTACK and not step.spell then
		return Grimoire.media.petAttack
	end
	return M.SpellIcon(step.spell) or M.SpellIcon(step.name) or Grimoire.media.unknownIcon
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

function M:SaveRotation(rotation)
	table.insert(self.store.rotations, 1, CopyTable(rotation))
	self:Refresh()
end

function M:DeleteRotation(index)
	table.remove(self.store.rotations, index)
	self:Refresh()
end

-- Combat -----------------------------------------------------------------------------------

function M:OnCombatStart()
	self:StartRecording()
	self:ProbeStart()
end

function M:OnCombatEnd()
	local fight, improved = self:StopRecording()
	for _, kind in ipairs(improved or {}) do
		local best = self:GetCharacter().best[kind]
		self:Print(("New best %s: %s (%s). /grim tempo to see it."):format(
			M.KindLabel(kind):lower(), Cycles.FormatScore(best), best.target or "?"))
	end
	self:ProbeStop()
	self:Refresh()
end

-- Lifecycle --------------------------------------------------------------------------------

function M:Refresh()
	if not self:IsEnabled() then return end
	if self.window and self.window:IsShown() then self:UpdateWindow() end
end

function M:Toggle()
	self:ToggleWindow()
end

function M:ApplySettings()
	if self.db.showButton and not self.button then
		self.button = Grimoire.CreateModuleButton(self, {
			name = "GrimoireTempoButton",
			icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
			title = "Tempo",
			hint = "Click: your rotations",
			onClick = function() self:ToggleWindow() end,
			default = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -150, 120 },
		})
	end
	if self.button then
		self.button:SetShown(self.db.showButton)
	end
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
	self:ApplySettings()
end

function M:OnDisable()
	self:StopRecording()
	self:ProbeStop()
	if self.button then self.button:Hide() end
	if self.window then self.window:Hide() end
	if self.shareWindow then self.shareWindow:Hide() end
end

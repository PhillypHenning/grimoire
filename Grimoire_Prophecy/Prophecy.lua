local ADDON_NAME, ns = ...
local Grimoire = Grimoire
local Parser = ns.Parser

-- Prophecy: plans written outside the game (docs/prophecy/FORMAT.md), pasted in,
-- checked and saved (ADR 0006). This file keeps the plans and each character's
-- progress and works out what's next; Import.lua, Viewer.lua and Tracker.lua are the
-- windows. Quests.lua ticks steps whose quest conditions are met; other conditions
-- (level, skill, items, ...) are still ticked by hand.
--
-- GrimoireProphecyDB = {
--     plans = { [title] = { text, imported, source = "pasted" | "bundled" } },
--     dismissedBundles = { [title] = text hash },   -- bundled plans you deleted
--     characters = { ["Name - Realm"] = {
--         active = title,
--         progress = { [title] = { steps = { [stepId] = "done" | "skipped" },
--                                  checks = { [checkKey] = true },
--                                  gates = { [chapterId] = "dismissed" },
--                                  manual = { [stepId] = true } } },  -- un-ticked by hand
--         quests = { ... },                          -- see Quests.lua
--     } },
--     questIDs = { ... },                            -- see Quests.lua
-- }

ns.bundledPlans = {} -- plan texts from Plans\*.lua, loaded after this file

local M = Grimoire:NewModule("Prophecy", {
	addon = ADDON_NAME,
	label = "Prophecy",
	defaults = {
		showTracker = true,
		trackerSteps = 4,
		showButton = true,
		waypoints = true,
		trackerScale = 1,
		windowScale = 1,
	},
	options = {
		{ type = "toggle", key = "showButton", label = "Show the Prophecy button", tooltip = "A round button that opens your levelling plan. Drag it in move mode." },
		{ type = "toggle", key = "waypoints", label = "Waypoint arrow (TomTom)", tooltip = "When TomTom is installed, its arrow points to the next step that has a map position." },
		{ type = "toggle", key = "showTracker", label = "Show step panel", tooltip = "A small panel listing your next steps while you play." },
		{ type = "choice", key = "trackerSteps", label = "Steps in the panel", tooltip = "How many upcoming steps the panel lists.", values = {
			{ 2, "2" }, { 3, "3" }, { 4, "4" }, { 6, "6" },
		} },
		{ type = "choice", key = "trackerScale", label = "Step panel size", tooltip = "How large the step panel is.", values = {
			{ 0.8, "Small" }, { 1, "Normal" }, { 1.2, "Large" }, { 1.4, "Huge" },
		} },
		{ type = "choice", key = "windowScale", label = "Plan window size", tooltip = "How large the Prophecy plan window is.", values = {
			{ 0.8, "Small" }, { 1, "Normal" }, { 1.2, "Large" }, { 1.4, "Huge" },
		} },
	},
})
ns.M = M

-- Display ------------------------------------------------------------------------------

M.KIND_TAGS = {
	p = "|cff40c0b0Profession|r",
	o = "|cff9d9d9dOptional|r",
}

local STYLE = {
	quest = function(name) return "|cffffd200" .. name .. "|r" end,
	name = function(name) return "|cff71d5ff" .. name .. "|r" end,
	coord = function(x, y, zone)
		return ("|cff9d9d9d(%s%s, %s)|r"):format(zone and (zone .. " ") or "", x, y)
	end,
}

-- Plan text with its markup coloured; a literal | is escaped so it can't start a UI code.
function M.FormatText(text)
	return Parser.FormatText((text:gsub("|", "||")), STYLE)
end

-- "Class" in the player's class colour, "Profession" in teal, ...; nil for plain steps.
function M.KindTag(step)
	if step.kind == "c" then
		return Grimoire.ClassColorText("Class", Grimoire:GetPlayerClass())
	end
	return M.KIND_TAGS[step.kind]
end

local function QuestList(quests)
	local names = {}
	for _, quest in ipairs(quests) do
		names[#names + 1] = STYLE.quest(quest.name)
	end
	return table.concat(names, ", ")
end

-- A gate target or `done` condition in words, e.g. "Tailoring 40 (soft target)".
function ns.DescribeRequirement(req)
	local t = req.type
	if t == "skill" then
		local text = req.name .. " " .. req.value
		if req.min then
			return text .. (" (soft target, at least %d)"):format(req.min)
		end
		return req.soft and (text .. " (soft target)") or text
	elseif t == "level" then
		return "Level " .. req.value
	elseif t == "item" then
		return ("%d x %s"):format(req.value, STYLE.name(req.name))
	elseif t == "learn" then
		return "Learn " .. STYLE.name(req.name)
	elseif t == "accept" then
		return "Accept " .. QuestList(req.quests)
	elseif t == "complete" then
		return "Complete " .. QuestList(req.quests)
	elseif t == "turnin" then
		return "Turn in " .. QuestList(req.quests)
	elseif t == "reach" then
		return "Reach " .. STYLE.coord(req.coord.x, req.coord.y, req.coord.zone)
	elseif t == "zone" then
		return "Be in " .. req.name
	end
	return M.FormatText(req.text or t)
end

-- "Accept [A], [B]; Turn in [C]" for a step that ticks itself, else nil.
function M.DescribeDone(step)
	if not M.CanAutoComplete(step) then return nil end
	local parts = {}
	for _, condition in ipairs(step.done) do
		parts[#parts + 1] = ns.DescribeRequirement(condition)
	end
	return table.concat(parts, "; ")
end

-- Tooltip lines for a step: details, reward and verify notes.
function M:AddStepTooltip(step)
	GameTooltip:AddLine(M.FormatText(step.text), 1, 1, 1, true)
	for _, detail in ipairs(step.details) do
		GameTooltip:AddLine(M.FormatText(detail), 0.8, 0.8, 0.8, true)
	end
	for _, reward in ipairs(step.rewards) do
		GameTooltip:AddLine("Reward: " .. M.FormatText(reward), 0.4, 1, 0.4, true)
	end
	for _, verify in ipairs(step.verify) do
		GameTooltip:AddLine("Verify: " .. M.FormatText(verify), 1, 0.5, 0, true)
	end
	if step.minlevel then
		GameTooltip:AddLine("From level " .. step.minlevel, 0.6, 0.6, 0.6)
	end
	local done = M.DescribeDone(step)
	if done then
		GameTooltip:AddLine("Ticks itself: " .. done, 0.6, 0.6, 0.6, true)
	end
end

-- Plans ---------------------------------------------------------------------------------

-- The parsed plan, cached until it's re-imported or deleted.
function M:GetPlan(title)
	if not (title and self.store.plans[title]) then return nil end
	self.parsed = self.parsed or {}
	if not self.parsed[title] then
		self.parsed[title] = Parser.Parse(self.store.plans[title].text)
	end
	return self.parsed[title]
end

function M:GetPlanTitles()
	local titles = {}
	for title in pairs(self.store.plans) do
		titles[#titles + 1] = title
	end
	table.sort(titles)
	return titles
end

-- Warnings the parser can't give: the plan's class, race and faction against this
-- character's (FORMAT.md, Validation).
local function CharacterWarnings(plan, warnings)
	local _, class = UnitClass("player")
	if plan.class and plan.class:upper() ~= class then
		warnings[#warnings + 1] = { line = 0, message = ("plan is for %s; this character is %s"):format(plan.class, class) }
	end
	local race = UnitRace("player")
	if plan.race and race and plan.race ~= race then
		warnings[#warnings + 1] = { line = 0, message = ("plan is for a %s; this character is a %s"):format(plan.race, race) }
	end
	local faction = UnitFactionGroup("player")
	if plan.faction and faction and plan.faction ~= faction then
		warnings[#warnings + 1] = { line = 0, message = ("plan is for %s; this character is %s"):format(plan.faction, faction) }
	end
end

-- Checks a pasted plan. Returns plan (nil on errors), errors, warnings.
function M:CheckPlan(text)
	text = text:gsub("^\239\187\191", ""):gsub("\r\n", "\n")
	local plan, errors, warnings = Parser.Parse(text)
	if plan then
		CharacterWarnings(plan, warnings)
	end
	return plan, errors, warnings, text
end

-- Checks and saves a plan; one with the same title is replaced, and progress on every
-- step whose identity didn't change carries over. The plan becomes this character's
-- active one. Returns plan (nil on errors), errors, warnings, steps with kept progress.
function M:ImportPlan(text)
	local plan, errors, warnings, clean = self:CheckPlan(text)
	if not plan then return nil, errors, warnings end
	self.store.plans[plan.title] = { text = clean, imported = time(), source = "pasted" }
	self.parsed[plan.title] = plan
	local kept = 0
	local steps = self:GetProgress(plan.title).steps
	for _, step in self:EachStep(plan) do
		if steps[step.id] then kept = kept + 1 end
	end
	self:SetActivePlan(plan.title)
	return plan, errors, warnings, kept
end

function M:DeletePlan(title)
	local saved = self.store.plans[title]
	if not saved then return end
	if saved.source == "bundled" then
		self.store.dismissedBundles[title] = Parser.Hash(saved.text)
	end
	self.store.plans[title] = nil
	self.parsed[title] = nil
	for _, char in pairs(self.store.characters) do
		if char.active == title then char.active = nil end
		char.progress[title] = nil
	end
	self:Refresh()
end

-- Plans shipped in Plans\*.lua are added on login, and replaced when the add-on ships a
-- new version of them, unless you pasted your own plan with that title or deleted it.
function M:LoadBundledPlans()
	for _, text in ipairs(ns.bundledPlans) do
		local plan = Parser.Parse(text)
		if plan then
			local saved = self.store.plans[plan.title]
			local hash = Parser.Hash(text)
			local dismissed = self.store.dismissedBundles[plan.title]
			if dismissed ~= hash and (not saved or (saved.source == "bundled" and saved.text ~= text)) then
				self.store.dismissedBundles[plan.title] = nil
				self.store.plans[plan.title] = { text = text, imported = time(), source = "bundled" }
				self.parsed[plan.title] = plan
			end
		end
	end
end

-- Progress (this character) -------------------------------------------------------------

function M:GetCharacter()
	local key = Grimoire.db.charKey
	local chars = self.store.characters
	chars[key] = chars[key] or { progress = {} }
	return chars[key]
end

function M:GetProgress(title)
	local progress = self:GetCharacter().progress
	progress[title] = progress[title] or {}
	return Grimoire.CopyDefaults({ steps = {}, checks = {}, gates = {}, manual = {} }, progress[title])
end

function M:GetActivePlan()
	local title = self:GetCharacter().active
	local plan = self:GetPlan(title)
	return plan, plan and title
end

function M:SetActivePlan(title)
	self:GetCharacter().active = title
	self:Refresh()
	if self:IsEnabled() then self:QueueAutoComplete() end -- tick what's already done
end

-- With no active plan, a plan written for this class is picked.
function M:ChooseDefaultPlan()
	if self:GetActivePlan() then return end
	local class = Grimoire:GetPlayerClass()
	for _, title in ipairs(self:GetPlanTitles()) do
		local plan = self:GetPlan(title)
		if plan and plan.class and plan.class:upper() == class then
			self:GetCharacter().active = title
			return
		end
	end
end

function M:ResetProgress(title)
	self:GetCharacter().progress[title] = nil
	self:Refresh()
end

-- Every step in plan order: for _, step, chapter in M:EachStep(plan)
function M:EachStep(plan)
	return coroutine.wrap(function()
		for _, chapter in ipairs(plan.chapters) do
			for _, step in ipairs(chapter.steps) do
				coroutine.yield(step.id, step, chapter)
			end
		end
	end)
end

function M:GetStepState(step)
	local _, title = self:GetActivePlan()
	return title and self:GetProgress(title).steps[step.id]
end

-- state: "done", "skipped" or nil (not done).
function M:SetStepState(step, state)
	local _, title = self:GetActivePlan()
	if not title then return end
	local progress = self:GetProgress(title)
	progress.steps[step.id] = state
	-- Un-ticking by hand sticks: the step no longer ticks itself (Quests.lua).
	progress.manual[step.id] = state == nil or nil
	self:Refresh()
end

function M:IsChecked(requirement)
	local _, title = self:GetActivePlan()
	return title and self:GetProgress(title).checks[requirement.key] or false
end

function M:SetChecked(requirement, checked)
	local _, title = self:GetActivePlan()
	if not title then return end
	self:GetProgress(title).checks[requirement.key] = checked or nil
	self:Refresh()
end

function M:DismissGate(chapter)
	local _, title = self:GetActivePlan()
	if not title then return end
	self:GetProgress(title).gates[chapter.id] = "dismissed"
	self:Refresh()
end

-- A step you tick: every kind but notes, in route chapters.
local function IsTask(step, chapter)
	return step.kind ~= "n" and chapter.type == "route"
end
M.IsTask = IsTask

-- Done and total ticks for a chapter, or the whole plan when chapter is nil.
function M:CountProgress(plan, chapter)
	local handled, total = 0, 0
	for _, ch in ipairs(chapter and { chapter } or plan.chapters) do
		for _, step in ipairs(ch.steps) do
			if IsTask(step, ch) then
				total = total + 1
				if self:GetStepState(step) then handled = handled + 1 end
			end
		end
	end
	return handled, total
end

-- Open when every check is ticked and every target that isn't soft is met. Targets the
-- game can't be asked about yet (skill, level, ...: see Quests.lua) count as not met,
-- so such a gate stays until you move on or dismiss it.
function M:IsGateOpen(chapter)
	for _, req in ipairs(chapter.gate.requirements) do
		if req.type == "check" then
			if not self:IsChecked(req) then return false end
		elseif req.type ~= "note" and not req.soft and self:Evaluate(req) ~= true then
			return false
		end
	end
	return true
end

-- What the step panel shows: up to `limit` entries, { step = , chapter = } or
-- { gate = , chapter = }, in plan order.
--   * Notes and reference chapters are skipped.
--   * An optional step you've moved past (a later step in its chapter is ticked) drops
--     out: optional steps never hold the panel.
--   * A step with a minlevel above yours waits; the panel goes on without it.
--   * A chapter's gate appears once its steps are handled, until it opens, you dismiss
--     it, or you tick something in a later chapter. Gates never block.
function M:GetUpcoming(limit)
	local plan = self:GetActivePlan()
	if not plan then return {} end
	local level = UnitLevel("player")
	local progress = self:GetProgress(self:GetCharacter().active)

	local lastTouchedChapter = 0
	for index, chapter in ipairs(plan.chapters) do
		for _, step in ipairs(chapter.steps) do
			if IsTask(step, chapter) and progress.steps[step.id] then
				lastTouchedChapter = index
			end
		end
	end

	local entries = {}
	for index, chapter in ipairs(plan.chapters) do
		if chapter.type == "route" then
			local lastHandled = 0
			for i, step in ipairs(chapter.steps) do
				if progress.steps[step.id] then lastHandled = i end
			end
			local open = false
			for i, step in ipairs(chapter.steps) do
				if IsTask(step, chapter) and not progress.steps[step.id] and not (step.kind == "o" and i < lastHandled) then
					if step.kind ~= "o" then open = true end
					if not (step.minlevel and level < step.minlevel) then
						entries[#entries + 1] = { step = step, chapter = chapter }
						if #entries >= limit then return entries end
					end
				end
			end
			if not open and chapter.gate and index >= lastTouchedChapter
				and not progress.gates[chapter.id] and not self:IsGateOpen(chapter) then
				entries[#entries + 1] = { gate = chapter.gate, chapter = chapter }
				if #entries >= limit then return entries end
			end
		end
	end
	return entries
end

-- "Make this the current step": everything before it that isn't handled is skipped,
-- earlier gates are dismissed, and the step itself is un-ticked.
function M:MakeCurrent(target)
	local plan, title = self:GetActivePlan()
	if not plan then return end
	local progress = self:GetProgress(title)
	for _, chapter in ipairs(plan.chapters) do
		if chapter.type == "route" then
			for _, step in ipairs(chapter.steps) do
				if step == target then
					progress.steps[step.id] = nil
					progress.manual[step.id] = true
					self:Refresh()
					return
				end
				if IsTask(step, chapter) and not progress.steps[step.id] then
					progress.steps[step.id] = "skipped"
				end
			end
			if chapter.gate then -- the target is in a later chapter
				progress.gates[chapter.id] = progress.gates[chapter.id] or "dismissed"
			end
		end
	end
	self:Refresh()
end

-- Windows ----------------------------------------------------------------------------------

function M:Refresh()
	if not self:IsEnabled() then return end
	self:UpdateWaypoint()
	if self.tracker then self:UpdateTracker() end
	if self.viewer and self.viewer:IsShown() then self:UpdateViewer() end
end

function M:Toggle()
	self:ToggleViewer()
end

function M:ApplySettings()
	if self.db.showButton and not self.button then
		self.button = Grimoire.CreateModuleButton(self, {
			name = "GrimoireProphecyButton",
			icon = "Interface\\Icons\\INV_Scroll_03",
			title = "Prophecy",
			hint = "Click: your levelling plan",
			onClick = function() self:ToggleViewer() end,
			default = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -205, 120 },
		})
	end
	if self.button then
		self.button:SetShown(self.db.showButton)
	end
	if self.tracker then
		Grimoire:SetMoverScale("ProphecyTracker", self.db.trackerScale)
	end
	if self.viewer then
		Grimoire:SetMoverScale("ProphecyWindow", self.db.windowScale)
	end
	self:UpdateTracker()
	self:UpdateWaypoint()
end

-- Lifecycle --------------------------------------------------------------------------------

function M:OnInitialize()
	GrimoireProphecyDB = GrimoireProphecyDB or {}
	self.store = Grimoire.CopyDefaults({ plans = {}, dismissedBundles = {}, questIDs = {}, characters = {} }, GrimoireProphecyDB)
	self.parsed = {}
	self:LoadBundledPlans()
	self:ChooseDefaultPlan()

	local function Command(arg)
		if not self:IsEnabled() then
			Grimoire:Print("Prophecy is turned off (Grimoire menu: Components, Prophecy).")
		elseif arg == "import" then
			self:ShowImport()
		else
			self:ToggleViewer()
		end
	end
	Grimoire:RegisterCommand("prophecy", "prophecy [import] - open your plans, or the import window", Command)
	SLASH_PROPHECY1 = "/prophecy"
	SlashCmdList.PROPHECY = function(msg)
		Command(msg:match("^%s*(.-)%s*$"):lower())
	end
end

function M:OnEnable()
	self:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(1, function() self:Refresh() end) end)
	self:RegisterCallback("MoversUnlocked", "UpdateTracker")
	self:RegisterCallback("MoversLocked", "UpdateTracker")
	self:EnableQuests()
	self:ApplySettings()
end

function M:OnDisable()
	self:ClearWaypoint()
	if self.tracker then self.tracker:Hide() end
	if self.button then self.button:Hide() end
	if self.viewer then self.viewer:Hide() end
	if self.importWindow then self.importWindow:Hide() end
end

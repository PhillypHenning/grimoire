local _, ns = ...
local Grimoire = Grimoire
local M = ns.M

-- Steps that tick themselves: `done accept / complete / turnin [Quest]` (FORMAT.md).
--
-- Plans name quests by title; the game knows turned-in quests only by ID. So Prophecy:
--   * learns each title's IDs when the quest is in your log (account-wide),
--   * records every turn-in as it happens (QUEST_TURNED_IN, per character),
--   * at login, looks up the titles of quests finished before it was installed
--     (asking the game to load quest data it hasn't cached).
-- Titles are matched without regard to case. A [Quest#123] in a plan is checked by ID.
--
-- Other conditions (level, skill, item, learn, reach, zone) aren't read yet: a step
-- that uses one stays manual, and a gate target counts as not met.
--
-- GrimoireProphecyDB.questIDs = { [lower-case title] = { [questID] = true } }
-- characters[charKey].quests = { turnedIn = { [lower-case title] = true },
--                                completedIDs = { [questID] = true } }  -- titles resolved

local UPDATE_DELAY = 0.3

-- Case and punctuation are ignored: the game's "From The Wreckage...." matches a plan's
-- [From The Wreckage...].
local function Key(name)
	return (name:lower():gsub("[^%w%s]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Re-keys a { [key] = value } table saved before Key changed.
local function Rekey(map)
	local fixed = {}
	for key, value in pairs(map) do
		local new = Key(key)
		if type(value) == "table" and type(fixed[new]) == "table" then
			for k, v in pairs(value) do fixed[new][k] = v end
		else
			fixed[new] = value
		end
	end
	return fixed
end

local function IsFlaggedCompleted(id)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return C_QuestLog.IsQuestFlaggedCompleted(id)
	end
	return IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(id) or false
end

-- The quest's title if the client has it cached, else nil.
local function QuestTitle(id)
	if C_QuestLog then
		local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
		if not title and C_QuestLog.GetQuestInfo then
			title = C_QuestLog.GetQuestInfo(id)
		end
		if type(title) == "string" and title ~= "" then return title end
	end
end

-- Every quest in the log: { title, id, complete }. Forever has the retail
-- C_QuestLog; the classic GetQuestLogTitle is the fallback.
local function ReadQuestLog()
	local quests = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, (C_QuestLog.GetNumQuestLogEntries()) do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.title and info.questID then
				local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
				quests[#quests + 1] = { title = info.title, id = info.questID, complete = complete and true or false }
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, (GetNumQuestLogEntries()) do
			local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
			if title and not isHeader then
				quests[#quests + 1] = { title = title, id = id, complete = isComplete == 1 or isComplete == true }
			end
		end
	end
	return quests
end

function M:GetQuestStore()
	local char = self:GetCharacter()
	char.quests = Grimoire.CopyDefaults({ turnedIn = {}, completedIDs = {} }, char.quests or {})
	if not self.questsRekeyed then
		self.questsRekeyed = true
		char.quests.turnedIn = Rekey(char.quests.turnedIn)
		self.store.questIDs = Rekey(self.store.questIDs)
	end
	return char.quests
end

function M:RecordTurnIn(title)
	if title then
		self:GetQuestStore().turnedIn[Key(title)] = true
	end
end

function M:UpdateQuestLog()
	local byKey, byID = {}, {}
	for _, quest in ipairs(ReadQuestLog()) do
		local key = Key(quest.title)
		byKey[key] = quest
		if quest.id then
			byID[quest.id] = quest
			self.store.questIDs[key] = self.store.questIDs[key] or {}
			self.store.questIDs[key][quest.id] = true
		end
	end
	self.questLog = { byKey = byKey, byID = byID }
end

-- Quests finished before Prophecy was watching. Titles the client hasn't cached are
-- requested; QUEST_DATA_LOAD_RESULT brings them in.
function M:ScanCompletedQuests()
	local ids = {}
	if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
		ids = C_QuestLog.GetAllCompletedQuestIDs() or {}
	elseif GetQuestsCompleted then
		for id in pairs(GetQuestsCompleted() or {}) do ids[#ids + 1] = id end
	end
	local store = self:GetQuestStore()
	self.pendingTitles = {}
	for _, id in ipairs(ids) do
		if not store.completedIDs[id] then
			local title = QuestTitle(id)
			if title then
				self:RecordTurnIn(title)
				store.completedIDs[id] = true
			elseif C_QuestLog and C_QuestLog.RequestLoadQuestByID then
				self.pendingTitles[id] = true
				C_QuestLog.RequestLoadQuestByID(id)
			end
		end
	end
end

function M:QUEST_DATA_LOAD_RESULT(_, id, success)
	if not (self.pendingTitles and self.pendingTitles[id]) then return end
	self.pendingTitles[id] = nil
	local title = success and QuestTitle(id)
	if title then
		self:RecordTurnIn(title)
		self:GetQuestStore().completedIDs[id] = true
		self:QueueAutoComplete()
	end
end

function M:QUEST_TURNED_IN(_, id)
	local quest = self.questLog and self.questLog.byID[id] -- the log as it was before
	self:RecordTurnIn(quest and quest.title or QuestTitle(id))
	if id then self:GetQuestStore().completedIDs[id] = true end
	self:QueueAutoComplete()
end

-- Conditions ------------------------------------------------------------------------------

function M:IsTurnedIn(quest)
	if quest.id and IsFlaggedCompleted(quest.id) then return true end
	local key = Key(quest.name)
	if self:GetQuestStore().turnedIn[key] then return true end
	if not quest.id then
		for id in pairs(self.store.questIDs[key] or {}) do
			if IsFlaggedCompleted(id) then return true end
		end
	end
	return false
end

function M:FindInLog(quest)
	local log = self.questLog
	if not log then return nil end
	if quest.id then return log.byID[quest.id] end
	return log.byKey[Key(quest.name)]
end

local QUEST_TESTS = {
	accept = function(self, quest) return self:FindInLog(quest) ~= nil or self:IsTurnedIn(quest) end,
	complete = function(self, quest)
		local entry = self:FindInLog(quest)
		return (entry and entry.complete) or self:IsTurnedIn(quest)
	end,
	turnin = function(self, quest) return self:IsTurnedIn(quest) end,
}

-- true / false, or nil when Prophecy can't read this kind of condition yet.
function M:Evaluate(condition)
	local test = QUEST_TESTS[condition.type]
	if not test then return nil end
	for _, quest in ipairs(condition.quests) do
		if not test(self, quest) then return false end
	end
	return true
end

-- Whether every one of a step's `done` conditions is a kind Prophecy can read.
function M.CanAutoComplete(step)
	if #step.done == 0 then return false end
	for _, condition in ipairs(step.done) do
		if not QUEST_TESTS[condition.type] then return false end
	end
	return true
end

-- Ticks every step whose conditions are all met, except ones you un-ticked by hand.
function M:AutoComplete()
	local plan, title = self:GetActivePlan()
	if not plan then return end
	local progress = self:GetProgress(title)
	local changed = false
	for _, chapter in ipairs(plan.chapters) do
		for _, step in ipairs(chapter.steps) do
			if M.IsTask(step, chapter) and not progress.steps[step.id] and not progress.manual[step.id]
				and M.CanAutoComplete(step) then
				local met = true
				for _, condition in ipairs(step.done) do
					if self:Evaluate(condition) ~= true then
						met = false
						break
					end
				end
				if met then
					progress.steps[step.id] = "done"
					changed = true
				end
			end
		end
	end
	if changed then self:Refresh() end
end

-- Quest events come in bursts; read the log once they settle.
function M:QueueAutoComplete()
	if self.autoQueued then return end
	self.autoQueued = true
	C_Timer.After(UPDATE_DELAY, function()
		self.autoQueued = nil
		if not self:IsEnabled() then return end
		self:UpdateQuestLog()
		self:AutoComplete()
	end)
end

function M:EnableQuests()
	local function Queue() self:QueueAutoComplete() end
	self:RegisterEvent("QUEST_LOG_UPDATE", Queue)
	self:RegisterEvent("QUEST_ACCEPTED", Queue)
	self:RegisterEvent("QUEST_REMOVED", Queue)
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("QUEST_DATA_LOAD_RESULT")
	self:UpdateQuestLog()
	self:ScanCompletedQuests()
	self:QueueAutoComplete()
end

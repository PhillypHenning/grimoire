local _, ns = ...
local Grimoire = Grimoire
local M = ns.M
local Cycles = ns.Cycles

-- The playback lane (plan milestone T4): a music staff where the rotation's spells scroll
-- from the right toward the "now" line, at the pace they were cast. Each cast you make is
-- matched to the next note with that spell:
--   on time (within HIT s)   green
--   early or late (CLOSE s)  yellow
--   not cast                 red, once it's CLOSE s past the line
--   a cast with no note      shown in red at the line ("off script")
-- A matched note re-syncs the music to you, so being a little slow doesn't push every
-- later note out of reach. The opener plays once, then the cycle repeats.
-- Pet notes (abilities you had your pet use) sit on a smaller, lower row: they light up when
-- they happen but never count as missed or off script, since the pet's timing isn't all
-- yours. Sending the pet in ("Pet Attack") is your own action and is judged like a spell.

local WIDTH, HEIGHT = 380, 64
local STAFF_Y = -5         -- the staff's middle, below the status line
local PET_Y, PET_ICON = -20, 16
local NOW_X = 40
local ICON = 24
local VIEW = 8            -- seconds of music on screen
local HIT, CLOSE = 0.6, 2.0
local SUMMARY_SECONDS = 10
local PX = (WIDTH - NOW_X - 12) / VIEW
local MIN_LOOP = 1        -- seconds; guards against a zero-length cycle

local STATE_COLORS = {
	pending = { 0.8, 0.8, 0.8 },
	hit = { 0.2, 1, 0.2 },
	close = { 1, 0.82, 0 },
	missed = { 1, 0.15, 0.15 },
	passed = { 0.4, 0.4, 0.4 },   -- a pet note nobody played
}

-- Frame ------------------------------------------------------------------------------------

function M:BuildLane()
	local lane = CreateFrame("Frame", "GrimoireTempoLane", UIParent, "BackdropTemplate")
	lane:SetSize(WIDTH, HEIGHT)
	Grimoire.ApplyClassicBackdrop(lane)
	lane:SetClipsChildren(true)
	self.lane = lane

	-- Five staff lines and the "now" line.
	for i = 1, 5 do
		local line = lane:CreateTexture(nil, "BACKGROUND", nil, 1)
		line:SetColorTexture(0.75, 0.62, 0.35, 0.35)
		line:SetHeight(1)
		line:SetPoint("LEFT", 6, 0)
		line:SetPoint("RIGHT", -6, 0)
		line:SetPoint("TOP", 0, -18 - (i - 1) * 9)
	end
	local now = lane:CreateTexture(nil, "ARTWORK", nil, 2)
	now:SetColorTexture(1, 0.82, 0, 0.9)
	now:SetWidth(2)
	now:SetPoint("TOP", lane, "TOPLEFT", NOW_X, -14)
	now:SetPoint("BOTTOM", lane, "BOTTOMLEFT", NOW_X, 5)

	lane.status = lane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	lane.status:SetPoint("TOPLEFT", 8, -4)
	lane.summary = lane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lane.summary:SetPoint("LEFT", 12, STAFF_Y)
	lane.summary:SetPoint("RIGHT", -12, STAFF_Y)
	lane.summary:SetJustifyH("LEFT")

	-- The spell you cast that wasn't in the music, flashed at the line.
	lane.wrong = lane:CreateTexture(nil, "OVERLAY", nil, 3)
	lane.wrong:SetSize(ICON, ICON)
	lane.wrong:SetPoint("CENTER", lane, "LEFT", NOW_X, STAFF_Y)
	lane.wrong:SetVertexColor(1, 0.3, 0.3)
	lane.wrong:Hide()

	lane.notes = {}
	lane:SetScript("OnUpdate", function(_, elapsed) self:OnLaneUpdate(elapsed) end)
	self:RegisterMover(lane, "Tempo lane", { "CENTER", "UIParent", "CENTER", 0, -230 }, { dim = false, suffix = "Lane" })
end

local function NoteFrame(lane, i)
	local note = lane.notes[i]
	if note then return note end
	note = CreateFrame("Frame", nil, lane)
	note:SetSize(ICON, ICON)
	note.icon = note:CreateTexture(nil, "ARTWORK")
	note.icon:SetPoint("TOPLEFT", 2, -2)
	note.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	note.border = note:CreateTexture(nil, "BACKGROUND")
	note.border:SetAllPoints()
	note.border:SetColorTexture(1, 1, 1, 1)
	lane.notes[i] = note
	return note
end

-- Playback ---------------------------------------------------------------------------------

local function AddSteps(play, rotation, from)
	for _, step in ipairs(rotation.steps) do
		play.notes[#play.notes + 1] = { at = from + step.at, spell = step.spell, name = step.name, pet = step.pet,
			key = Cycles.Key(step.name), state = "pending" }
	end
	return from + math.max(rotation.length or 0, MIN_LOOP)
end

-- Adds cycles until the music reaches past the screen's right edge.
local function Extend(play, songTime)
	while play.cycle and play.songEnd < songTime + VIEW + 1 do
		play.songEnd = AddSteps(play, play.cycle, play.songEnd)
	end
end

function M:StartPlayback()
	local opener, cycle = self:GetPlayback()
	-- The pull is cast before combat starts: the music starts at that cast, which is judged now.
	local pulls = self.recording and self.recording.casts or {}
	self.summaryUntil = nil
	self.play = { start = pulls[1] and pulls[1].time or GetTime(), offset = 0, notes = {}, songEnd = 0, cycle = cycle,
		hits = 0, close = 0, missed = 0, wrong = 0, playing = (opener or cycle) ~= nil }
	if opener then
		self.play.songEnd = AddSteps(self.play, opener, 0)
	end
	Extend(self.play, 0)
	for _, cast in ipairs(pulls) do
		self:JudgeCast(cast.name, cast.time, cast.pet)
	end
	self:UpdateLane()
end

function M:SongTime(now)
	local play = self.play
	return (now or GetTime()) - play.start - play.offset
end

function M:JudgeCast(name, now, pet)
	local play = self.play
	if not play or not play.playing then return end
	local songTime, key = self:SongTime(now), Cycles.Key(name)
	for _, note in ipairs(play.notes) do
		if note.state == "pending" and note.key == key and (note.pet or false) == (pet or false) and math.abs(note.at - songTime) <= CLOSE then
			local delta = songTime - note.at
			local onTime = math.abs(delta) <= HIT
			note.state = onTime and "hit" or "close"
			if not note.pet then
				-- Pet notes light up but don't count toward your accuracy or set the pace.
				if onTime then play.hits = play.hits + 1 else play.close = play.close + 1 end
				play.offset = play.offset + delta -- follow the player's pace
			end
			return
		end
	end
	if pet then return end -- the pet doing something unscripted isn't your mistake
	play.wrong = play.wrong + 1
	if self.lane then
		self.lane.wrong:SetTexture(M.StepIcon({ name = name }))
		self.lane.wrong:Show()
		self.wrongUntil = GetTime() + 0.6
	end
end

function M:OnLaneUpdate()
	local lane, play = self.lane, self.play
	if self.wrongUntil and GetTime() > self.wrongUntil then
		lane.wrong:Hide()
		self.wrongUntil = nil
	end
	if self.summaryUntil and GetTime() > self.summaryUntil then
		self.summaryUntil = nil
		self:UpdateLane()
		return
	end
	if not play or not play.playing then return end
	local songTime = self:SongTime()
	Extend(play, songTime)

	-- Drop notes that have scrolled off; judge the ones that went by unplayed.
	while play.notes[1] and play.notes[1].at < songTime - (NOW_X + ICON) / PX do
		table.remove(play.notes, 1)
	end
	local shown = 0
	for _, note in ipairs(play.notes) do
		if note.state == "pending" and songTime - note.at > CLOSE then
			if note.pet then
				note.state = "passed"
			else
				note.state = "missed"
				play.missed = play.missed + 1
			end
		end
		local x = NOW_X + (note.at - songTime) * PX
		if x > WIDTH + ICON then break end
		shown = shown + 1
		local frame = NoteFrame(lane, shown)
		frame:ClearAllPoints()
		local size = note.pet and PET_ICON or ICON
		frame:SetSize(size, size)
		frame:SetPoint("CENTER", lane, "LEFT", x, note.pet and PET_Y or STAFF_Y + 4)
		frame.icon:SetTexture(M.StepIcon(note))
		frame.icon:SetDesaturated(note.state == "missed" or note.state == "passed")
		local color = STATE_COLORS[note.state]
		frame.border:SetVertexColor(color[1], color[2], color[3])
		frame:Show()
	end
	for i = shown + 1, #lane.notes do
		lane.notes[i]:Hide()
	end
end

-- After the fight: how it went, then the lane hides.
function M:StopPlayback(fight, improved)
	local play = self.play
	self.play = nil
	if not play or not self.lane then return end
	local parts = {}
	if fight then
		parts[#parts + 1] = fight.unit and Cycles.FormatScore(fight) or "no damage data"
	end
	if play.playing then
		local total = play.hits + play.close + play.missed
		parts[#parts + 1] = ("on time %d/%d, early/late %d, missed %d, off script %d"):format(
			play.hits, total, play.close, play.missed, play.wrong)
	end
	for _, kind in ipairs(improved or {}) do
		parts[#parts + 1] = "|cff66ff66new best " .. M.KindLabel(kind):lower() .. "!|r"
	end
	if #parts == 0 then
		self:UpdateLane()
		return
	end
	self.lane.summary:SetText(table.concat(parts, "  ·  "))
	self.summaryUntil = GetTime() + SUMMARY_SECONDS
	self:UpdateLane()
end

-- Shown while a fight plays (or records), for the summary after it, and in move mode.
function M:UpdateLane()
	if not self:IsEnabled() then return end
	if not self.lane then self:BuildLane() end
	local lane, play = self.lane, self.play
	local fighting = play ~= nil
	local summary = self.summaryUntil ~= nil and not fighting
	local show = Grimoire.moversUnlocked or (self.db.showLane and (fighting or summary))
	lane:SetShown(show and true or false)
	if not show then return end

	local mode = self.db.mode
	if fighting and not play.playing then
		lane.status:SetText(mode == "experiment" and "Tempo: experimenting (recording only)"
			or "Tempo: recording; no best rotation yet")
	elseif fighting then
		lane.status:SetText(mode == "pinned" and "Tempo: pinned rotation" or "Tempo: following your best")
	else
		lane.status:SetText("Tempo")
	end
	lane.summary:SetShown(summary)
	if not fighting then
		for _, note in ipairs(lane.notes) do note:Hide() end
		if not summary then
			lane.summary:SetText("")
		end
	end
end

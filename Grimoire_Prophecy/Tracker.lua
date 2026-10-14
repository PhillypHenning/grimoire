local _, ns = ...
local Grimoire = Grimoire
local M = ns.M

-- The step panel: the current step and the next few, each with a checkbox.
--   Tick          done (the step leaves the panel)
--   Right-click   skip it (for a gate: move on without it)
--   Left-click    open the plan at that chapter
-- At a gate, the gate's targets show until it opens; it never blocks the steps after it.

local WIDTH = 290
local PADDING = 8
local CHECK_SIZE = 20
local ROW_GAP = 4
local HEADER_HEIGHT = 18

local function Row_OnEnter(row)
	if not row.entry then return end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	if row.entry.step then
		M:AddStepTooltip(row.entry.step)
		GameTooltip:AddLine("Right-click: skip", 0.6, 0.6, 0.6)
	elseif row.entry.gate then
		GameTooltip:AddLine(M.FormatText(row.entry.gate.title), 1, 0.82, 0, true)
		GameTooltip:AddLine("Gates are advice: the plan goes on either way.", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("Right-click: move on", 0.6, 0.6, 0.6)
	else
		GameTooltip:AddLine(row.entry.chapter.title, 1, 0.82, 0, true)
		GameTooltip:AddLine("Click: open the plan here", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function Row_OnClick(row, button)
	local entry = row.entry
	if not entry then return end
	if button == "RightButton" then
		if entry.step then
			M:SetStepState(entry.step, "skipped")
		elseif entry.gate then
			M:DismissGate(entry.chapter)
		end
	else
		M:ShowViewer(entry.chapter)
	end
end

local function Check_OnClick(check)
	local row = check:GetParent()
	if row.entry.step then
		M:SetStepState(row.entry.step, check:GetChecked() and "done" or nil)
	elseif row.requirement then
		M:SetChecked(row.requirement, check:GetChecked())
	end
end

function M:CreateTrackerRow()
	local row = CreateFrame("Button", nil, self.tracker)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetWidth(WIDTH - PADDING * 2)
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", Row_OnClick)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(CHECK_SIZE, CHECK_SIZE)
	row.check:SetPoint("TOPLEFT", -3, 2)
	row.check:SetScript("OnClick", Check_OnClick)

	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(true)
	self.trackerRows[#self.trackerRows + 1] = row
	return row
end

-- One line of the panel: optional checkbox, then wrapped text. Returns its height.
function M:LayoutTrackerRow(index, y, text, opts)
	local row = self.trackerRows[index] or self:CreateTrackerRow()
	row.entry, row.requirement = opts.entry, opts.requirement
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", PADDING, -y)
	row.check:SetShown(opts.checkable or false)
	row.check:SetChecked(opts.checked or false)
	local indent = (opts.checkable and CHECK_SIZE or 0) + (opts.indent or 0)
	row.text:ClearAllPoints()
	row.text:SetPoint("TOPLEFT", indent, 0)
	row.text:SetWidth(WIDTH - PADDING * 2 - indent)
	row.text:SetText(text)
	if opts.dim then
		row.text:SetTextColor(0.6, 0.6, 0.6)
	else
		row.text:SetTextColor(1, 1, 1)
	end
	local height = math.max(opts.checkable and CHECK_SIZE - 4 or 0, row.text:GetStringHeight())
	row:SetHeight(height)
	row:Show()
	return height
end

function M:BuildTracker()
	local frame = CreateFrame("Frame", "GrimoireProphecyTracker", UIParent, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(frame)
	frame:SetWidth(WIDTH)
	frame:SetFrameStrata("LOW")
	self.tracker = frame
	self.trackerRows = {}

	local header = CreateFrame("Button", nil, frame)
	header:SetPoint("TOPLEFT", PADDING, -PADDING)
	header:SetPoint("TOPRIGHT", -PADDING, -PADDING)
	header:SetHeight(HEADER_HEIGHT)
	header:SetScript("OnClick", function() self:ToggleViewer() end)
	header:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_LEFT")
		GameTooltip:AddLine("Prophecy")
		GameTooltip:AddLine("Click: open the plan", 1, 1, 1)
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	header.text:SetAllPoints()
	header.text:SetJustifyH("LEFT")
	header.text:SetWordWrap(false)
	frame.header = header

	self:RegisterMover(frame, "Prophecy steps", { "TOPRIGHT", "UIParent", "TOPRIGHT", -330, -220 }, { suffix = "Tracker" })
end

local function ChapterTitle(chapter)
	return chapter.badge .. "  " .. chapter.title
end

-- Gate box: its title, then one line per requirement. Checks can be ticked; targets
-- are listed until 5b reads them from the game.
function M:LayoutGate(entry, index, y)
	local height = self:LayoutTrackerRow(index, y, "|cffffd200Gate:|r " .. M.FormatText(entry.gate.title), { entry = entry })
	y = y + height + ROW_GAP
	index = index + 1
	for _, req in ipairs(entry.gate.requirements) do
		local text, opts = nil, { indent = 8, entry = entry }
		if req.type == "check" then
			text = M.FormatText(req.text)
			opts.checkable, opts.checked, opts.requirement = true, self:IsChecked(req), req
		elseif req.type == "note" then
			text, opts.dim = M.FormatText(req.text), true
		else
			text = "- " .. ns.DescribeRequirement(req)
		end
		height = self:LayoutTrackerRow(index, y, text, opts)
		y = y + height + ROW_GAP
		index = index + 1
	end
	return index, y
end

function M:UpdateTracker()
	if not self:IsEnabled() then return end
	local plan = self:GetActivePlan()
	local show = self.db.showTracker and (plan or Grimoire.moversUnlocked)
	if not show then
		if self.tracker then self.tracker:Hide() end
		return
	end
	if not self.tracker then self:BuildTracker() end

	local entries = plan and self:GetUpcoming(self.db.trackerSteps) or {}
	local header = self.tracker.header.text
	local y, index = PADDING + HEADER_HEIGHT + ROW_GAP, 1
	if not plan then
		header:SetText("Prophecy")
		y = y + self:LayoutTrackerRow(index, y, "No plan. Type /prophecy to import one.", { dim = true })
		index = index + 1
	elseif #entries == 0 then
		header:SetText(plan.title)
		y = y + self:LayoutTrackerRow(index, y, "Plan complete.", { dim = true })
		index = index + 1
	else
		header:SetText(ChapterTitle(entries[1].chapter))
		local chapter = entries[1].chapter
		for _, entry in ipairs(entries) do
			if entry.chapter ~= chapter then
				-- A new chapter starts within the panel: name it.
				chapter = entry.chapter
				y = y + 2
				y = y + self:LayoutTrackerRow(index, y, "|cffffd200" .. ChapterTitle(chapter) .. "|r", { entry = { chapter = chapter } }) + ROW_GAP
				index = index + 1
			end
			if entry.gate then
				index, y = self:LayoutGate(entry, index, y)
			else
				local step = entry.step
				local tag = M.KindTag(step)
				local text = (tag and (tag .. " ") or "") .. M.FormatText(step.text)
				if #step.verify > 0 then text = text .. " |cffff8000?|r" end
				y = y + self:LayoutTrackerRow(index, y, text, { entry = entry, checkable = true, checked = false }) + ROW_GAP
				index = index + 1
			end
		end
	end
	for i = index, #self.trackerRows do
		self.trackerRows[i]:Hide()
		self.trackerRows[i].entry = nil
	end
	self.tracker:SetHeight(y - ROW_GAP + PADDING)
	self.tracker:Show()
	Grimoire:NotifyMoverActivity(self.name .. "Tracker")
end

local _, ns = ...
local Grimoire = Grimoire
local M = ns.M

-- The plan viewer: chapters on the left, the chosen chapter's steps on the right, laid
-- out like the web guide. The top bar picks the active plan and imports, resets or
-- deletes plans. Progress shown is this character's (ADR 0003: it's named).

local VIEW_WIDTH, VIEW_HEIGHT = 780, 470
local TOP_BAR = 30
local LIST_WIDTH = 230
local LIST_ROW = 20
local GAP = 8
local SCROLLBAR = 28
local PANE_INSET = 8
local TEXT_WIDTH = VIEW_WIDTH - LIST_WIDTH - GAP - PANE_INSET - SCROLLBAR
local CHECK = 20
local CONFIRM_SECONDS = 3

local OVERVIEW = "overview"

-- Small pools so a re-render reuses its widgets.
local function NewPool(create)
	return { free = {}, used = {}, create = create }
end

local function Acquire(pool)
	local object = table.remove(pool.free) or pool.create()
	pool.used[#pool.used + 1] = object
	object:ClearAllPoints()
	object:Show()
	return object
end

local function ReleaseAll(pool)
	for _, object in ipairs(pool.used) do
		object:Hide()
		pool.free[#pool.free + 1] = object
	end
	wipe(pool.used)
end

-- A button that asks for a second click within a few seconds (no StaticPopup: taint).
local function ConfirmButton(parent, label, width, action)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(label)
	local token = 0
	button:SetScript("OnClick", function()
		token = token + 1
		if button.confirming then
			button.confirming = nil
			button:SetText(label)
			action()
			return
		end
		button.confirming = true
		button:SetText("Confirm?")
		local mine = token
		C_Timer.After(CONFIRM_SECONDS, function()
			if token == mine then
				button.confirming = nil
				button:SetText(label)
			end
		end)
	end)
	return button
end

-- Step rows --------------------------------------------------------------------------

local function StepRow_OnClick(row, button)
	if button ~= "RightButton" or not row.step or not row.tickable then return end
	local step = row.step
	local state = M:GetStepState(step)
	Grimoire.OpenMenu(row, {
		{ text = "Step", isTitle = true },
		{ text = "Done", radio = true, checked = function() return state == "done" end, func = function() M:SetStepState(step, "done") end },
		{ text = "Skipped", radio = true, checked = function() return state == "skipped" end, func = function() M:SetStepState(step, "skipped") end },
		{ text = "Not done", radio = true, checked = function() return state == nil end, func = function() M:SetStepState(step, nil) end },
		{ isDivider = true },
		{ text = "Make this the current step", func = function() M:MakeCurrent(step) end },
	})
end

local function StepRow_OnEnter(row)
	if row.tickable then
		GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
		GameTooltip:AddLine("Right-click: done, skip, or make it the current step", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end
end

local function Check_OnClick(check)
	local row = check:GetParent()
	if row.step then
		M:SetStepState(row.step, check:GetChecked() and "done" or nil)
	elseif row.requirement then
		M:SetChecked(row.requirement, check:GetChecked())
	end
end

function M:CreateStepRow()
	local row = CreateFrame("Button", nil, self.paneChild)
	row:RegisterForClicks("RightButtonUp")
	row:SetWidth(TEXT_WIDTH)
	row:SetScript("OnClick", StepRow_OnClick)
	row:SetScript("OnEnter", StepRow_OnEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(CHECK, CHECK)
	row.check:SetPoint("TOPLEFT", -2, 3)
	row.check:SetScript("OnClick", Check_OnClick)

	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetPoint("TOPLEFT", CHECK + 2, 0)
	row.text:SetWidth(TEXT_WIDTH - CHECK - 2)
	row.text:SetJustifyH("LEFT")

	row.extra = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.extra:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
	row.extra:SetWidth(TEXT_WIDTH - CHECK - 2)
	row.extra:SetJustifyH("LEFT")
	row.extra:SetTextColor(0.75, 0.75, 0.75)
	return row
end

-- Layout -----------------------------------------------------------------------------

-- Adds a wrapped line of text at the cursor and moves it down.
function M:PaneText(text, font, color, indent, gap)
	local fs = Acquire(self.textPool)
	fs:SetFontObject(font or "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", indent or 0, -self.cursor)
	fs:SetWidth(TEXT_WIDTH - (indent or 0))
	fs:SetText(text)
	fs:SetTextColor(unpack(color or { 1, 1, 1 }))
	self.cursor = self.cursor + fs:GetStringHeight() + (gap or 6)
	return fs
end

-- opts: step, requirement, checked, tickable (checkbox), text, extra, dim
function M:PaneRow(opts)
	local row = Acquire(self.rowPool)
	row.step, row.requirement, row.tickable = opts.step, opts.requirement, opts.tickable
	row:SetPoint("TOPLEFT", opts.indent or 0, -self.cursor)
	row:SetWidth(TEXT_WIDTH - (opts.indent or 0))
	row.check:SetShown(opts.tickable or false)
	row.check:SetChecked(opts.checked or false)
	row.text:SetText(opts.text)
	local shade = opts.dim and 0.6 or 1
	row.text:SetTextColor(shade, shade, shade)
	row.extra:SetText(opts.extra or "")
	local height = row.text:GetStringHeight()
	if opts.extra and opts.extra ~= "" then
		height = height + 3 + row.extra:GetStringHeight()
	end
	height = math.max(height, opts.tickable and CHECK - 4 or 0)
	row:SetHeight(height)
	self.cursor = self.cursor + height + 8
	return row
end

local function Paragraphs(list)
	local out = {}
	for _, paragraph in ipairs(list) do
		if paragraph ~= "" then out[#out + 1] = paragraph end
	end
	return out
end

local function StepExtra(step)
	local lines = {}
	for _, detail in ipairs(step.details) do
		lines[#lines + 1] = M.FormatText(detail)
	end
	for _, reward in ipairs(step.rewards) do
		lines[#lines + 1] = "|cff66ff66Reward:|r " .. M.FormatText(reward)
	end
	for _, verify in ipairs(step.verify) do
		lines[#lines + 1] = "|cffff8000Verify:|r " .. M.FormatText(verify)
	end
	return table.concat(lines, "\n")
end

function M:RenderOverview(plan, title)
	local saved = self.store.plans[title]
	self:PaneText(M.FormatText(plan.title), "GameFontNormalLarge", { 1, 0.82, 0 }, 0, 4)
	if plan.subtitle then self:PaneText(M.FormatText(plan.subtitle), "GameFontHighlight") end
	local about = {}
	if plan.author then about[#about + 1] = "By " .. plan.author end
	local who = table.concat({ plan.race or "", plan.class and Grimoire.ClassColorText(plan.class:sub(1, 1) .. plan.class:sub(2):lower(), plan.class:upper()) or "", plan.faction and ("(" .. plan.faction .. ")") or "" }, " ")
	if who:match("%S") then about[#about + 1] = "For " .. who:gsub("^%s+", "") end
	if saved then
		about[#about + 1] = ("%s %s"):format(saved.source == "bundled" and "Shipped with Grimoire," or "Imported", date("%Y-%m-%d", saved.imported))
	end
	self:PaneText(table.concat(about, "  |  "), "GameFontDisableSmall", nil, 0, 10)
	if #plan.skills > 0 then
		self:PaneText("|cffffd200Professions:|r " .. table.concat(plan.skills, ", "), "GameFontHighlightSmall", nil, 0, 10)
	end
	for _, paragraph in ipairs(Paragraphs(plan.intro)) do
		self:PaneText(M.FormatText(paragraph), "GameFontHighlight", { 0.9, 0.9, 0.9 }, 0, 8)
	end
	for _, note in ipairs(plan.notes) do
		self:PaneText("|cffffd200Note:|r " .. M.FormatText(note), "GameFontHighlightSmall", nil, 8, 8)
	end
	if #plan.sources > 0 then
		self:PaneText("Sources", "GameFontNormal", { 1, 0.82, 0 }, 0, 4)
		for _, source in ipairs(plan.sources) do
			self:PaneText(source.label .. "\n|cff808080" .. source.url .. "|r", "GameFontHighlightSmall", nil, 8, 6)
		end
	end
end

function M:RenderChapter(chapter)
	local level = UnitLevel("player")
	self:PaneText(chapter.badge .. "  " .. M.FormatText(chapter.title), "GameFontNormalLarge", { 1, 0.82, 0 }, 0, 2)
	local levels = chapter.levels
	if chapter.type == "reference" then levels = levels .. "  |cff808080(reference: not part of the route)|r" end
	self:PaneText(levels, "GameFontDisableSmall", nil, 0, 10)
	for _, paragraph in ipairs(Paragraphs(chapter.why)) do
		self:PaneText(M.FormatText(paragraph), "GameFontHighlight", { 0.85, 0.85, 0.85 }, 0, 8)
	end
	self.cursor = self.cursor + 4

	for _, step in ipairs(chapter.steps) do
		local tickable = M.IsTask(step, chapter)
		local state = tickable and self:GetStepState(step)
		local tag = M.KindTag(step)
		local text = (tag and (tag .. "  ") or "") .. M.FormatText(step.text)
		if #step.verify > 0 then text = text .. " |cffff8000?|r" end
		if step.minlevel then
			local color = level < step.minlevel and "ff4040" or "808080"
			text = text .. (" |cff%s(level %d)|r"):format(color, step.minlevel)
		end
		if state == "skipped" then text = "|cff808080Skipped:|r " .. text end
		self:PaneRow({
			step = step, tickable = tickable, checked = state == "done", text = text,
			extra = StepExtra(step), dim = state ~= nil or step.kind == "n",
			indent = tickable and 0 or CHECK + 2,
		})
	end

	if chapter.gate then
		self:RenderGate(chapter)
	end
end

function M:RenderGate(chapter)
	local gate = chapter.gate
	self.cursor = self.cursor + 6
	local top = self.cursor
	self.cursor = self.cursor + 10
	local title = "|cffffd200Gate:|r " .. M.FormatText(gate.title)
	if self:GetActivePlan() and self:GetProgress(self:GetCharacter().active).gates[chapter.id] then
		title = title .. "  |cff808080(moved on)|r"
	elseif self:IsGateOpen(chapter) then
		title = title .. "  |cff66ff66(open)|r"
	end
	self:PaneText(title, "GameFontHighlight", nil, 10, 8)
	for _, req in ipairs(gate.requirements) do
		if req.type == "check" then
			self:PaneRow({ requirement = req, tickable = true, checked = self:IsChecked(req), text = M.FormatText(req.text), indent = 10 })
		elseif req.type == "note" then
			self:PaneText(M.FormatText(req.text), "GameFontHighlightSmall", { 0.75, 0.75, 0.75 }, 10 + CHECK + 2, 6)
		else
			self:PaneText(ns.DescribeRequirement(req), "GameFontHighlight", nil, 10 + CHECK + 2, 8)
		end
	end
	self.cursor = self.cursor + 4
	local box = self.gateBox
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", -4, -top)
	box:SetSize(TEXT_WIDTH + 4, self.cursor - top)
	box:Show()
	self.cursor = self.cursor + 8
end

-- Chapter list ------------------------------------------------------------------------

function M:CreateListRow(index)
	local row = CreateFrame("Button", nil, self.listChild)
	row:SetHeight(LIST_ROW)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * LIST_ROW)
	row:SetPoint("RIGHT")
	row:SetHighlightTexture(Grimoire.media.rowHighlight, "ADD")
	row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.count:SetPoint("RIGHT", -4, 0)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 6, 0)
	row.text:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row:SetScript("OnClick", function(b)
		self.selected = b.chapterId
		self:UpdateViewer(true)
	end)
	self.listRows[index] = row
	return row
end

function M:UpdateChapterList(plan)
	local items = {}
	if plan then
		items[1] = { id = OVERVIEW, text = "Overview" }
		for _, chapter in ipairs(plan.chapters) do
			local handled, total = self:CountProgress(plan, chapter)
			local text = chapter.badge .. "  " .. chapter.title
			if chapter.type == "reference" then text = "|cffa0a0a0" .. text .. "|r" end
			items[#items + 1] = {
				id = chapter.id, text = text,
				count = total > 0 and (handled == total and "|cff66ff66done|r" or (handled .. "/" .. total)) or "",
			}
		end
	end
	for i, item in ipairs(items) do
		local row = self.listRows[i] or self:CreateListRow(i)
		row.chapterId = item.id
		row.text:SetText(item.text)
		row.count:SetText(item.count or "")
		if item.id == self.selected then row:LockHighlight() else row:UnlockHighlight() end
		row:Show()
	end
	for i = #items + 1, #self.listRows do
		self.listRows[i]:Hide()
	end
	self.listChild:SetHeight(math.max(1, #items * LIST_ROW))
end

-- Window -------------------------------------------------------------------------------

function M:OpenPlanMenu(anchor)
	local _, active = self:GetActivePlan()
	local entries = { { text = "Plans", isTitle = true } }
	for _, title in ipairs(self:GetPlanTitles()) do
		entries[#entries + 1] = {
			text = title, radio = true,
			checked = function() return title == active end,
			func = function()
				self.selected = nil
				self:SetActivePlan(title)
			end,
		}
	end
	entries[#entries + 1] = { isDivider = true }
	entries[#entries + 1] = { text = "Import a plan...", func = function() self:ShowImport() end }
	Grimoire.OpenMenu(anchor, entries)
end

function M:BuildViewer()
	local frame = Grimoire:CreateWindow("Prophecy", "Prophecy", self)
	frame:SetContentSize(VIEW_WIDTH, VIEW_HEIGHT)
	frame:SetScript("OnShow", function() self:UpdateViewer() end)
	self.viewer = frame
	local content = frame.content

	-- Top bar
	local planButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	planButton:SetSize(LIST_WIDTH, 22)
	planButton:SetPoint("TOPLEFT")
	planButton:SetScript("OnClick", function(b) self:OpenPlanMenu(b) end)
	self.planButton = planButton

	local import = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	import:SetSize(80, 22)
	import:SetPoint("LEFT", planButton, "RIGHT", GAP, 0)
	import:SetText("Import")
	import:SetScript("OnClick", function() self:ShowImport() end)

	self.resetButton = ConfirmButton(content, "Reset progress", 120, function()
		local _, title = self:GetActivePlan()
		if title then self:ResetProgress(title) end
	end)
	self.resetButton:SetPoint("LEFT", import, "RIGHT", 4, 0)

	self.deleteButton = ConfirmButton(content, "Delete plan", 100, function()
		local _, title = self:GetActivePlan()
		if title then
			self.selected = nil
			self:DeletePlan(title)
		end
	end)
	self.deleteButton:SetPoint("LEFT", self.resetButton, "RIGHT", 4, 0)

	self.progressText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.progressText:SetPoint("TOPRIGHT", -4, -5)
	self.progressText:SetJustifyH("RIGHT")

	-- Chapter list
	local listBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(listBg)
	listBg:SetPoint("TOPLEFT", 0, -TOP_BAR)
	listBg:SetPoint("BOTTOMLEFT")
	listBg:SetWidth(LIST_WIDTH)
	local listScroll, listChild = Grimoire.CreateScrollArea(listBg, "GrimoireProphecyChapterScroll")
	listScroll:SetPoint("TOPLEFT", 6, -6)
	listScroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 6)
	self.listChild = listChild
	self.listRows = {}

	-- Chapter pane
	local paneBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(paneBg)
	paneBg:SetPoint("TOPLEFT", listBg, "TOPRIGHT", GAP, 0)
	paneBg:SetPoint("BOTTOMRIGHT")
	local paneScroll, paneChild = Grimoire.CreateScrollArea(paneBg, "GrimoireProphecyPaneScroll")
	paneScroll:SetPoint("TOPLEFT", PANE_INSET, -PANE_INSET)
	paneScroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, PANE_INSET)
	self.paneScroll, self.paneChild = paneScroll, paneChild

	-- Layers, bottom to top: gate box, step rows, text (so the box never covers text).
	local textLayer = CreateFrame("Frame", nil, paneChild)
	textLayer:SetAllPoints()
	textLayer:SetFrameLevel(paneChild:GetFrameLevel() + 2)
	self.textPool = NewPool(function()
		local fs = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		return fs
	end)
	self.rowPool = NewPool(function() return self:CreateStepRow() end)

	local box = CreateFrame("Frame", nil, paneChild, "BackdropTemplate")
	box:SetBackdrop(Grimoire.media.classicBackdrop)
	box:SetBackdropColor(0.25, 0.2, 0.05, 0.5)
	box:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
	box:SetFrameLevel(paneChild:GetFrameLevel())
	self.gateBox = box
end

-- newChapter: scroll to the top (a different chapter was picked); otherwise keep the place.
function M:UpdateViewer(newChapter)
	local plan, title = self:GetActivePlan()
	self.planButton:SetText(title or "No plan")
	self.resetButton:SetEnabled(plan ~= nil)
	self.deleteButton:SetEnabled(plan ~= nil)

	local valid = self.selected == OVERVIEW
	for _, chapter in ipairs(plan and plan.chapters or {}) do
		if chapter.id == self.selected then valid = true end
	end
	if not valid then self.selected = OVERVIEW end

	if plan then
		local handled, total = self:CountProgress(plan)
		self.progressText:SetText(("%s: %d / %d steps"):format(Grimoire:FormatCharacterName(), handled, total))
	else
		self.progressText:SetText(Grimoire:FormatCharacterName())
	end
	self:UpdateChapterList(plan)

	local scroll = self.paneScroll:GetVerticalScroll()
	ReleaseAll(self.textPool)
	ReleaseAll(self.rowPool)
	self.gateBox:Hide()
	self.cursor = 0
	if not plan then
		self:PaneText("No plan yet.", "GameFontNormalLarge", { 1, 0.82, 0 }, 0, 8)
		self:PaneText("Click Import and paste a plan written in the Prophecy format (docs/prophecy/FORMAT.md in the Grimoire repo).", "GameFontHighlight")
	elseif self.selected == OVERVIEW then
		self:RenderOverview(plan, title)
	else
		for _, chapter in ipairs(plan.chapters) do
			if chapter.id == self.selected then self:RenderChapter(chapter) end
		end
	end
	self.paneChild:SetHeight(math.max(1, self.cursor))
	self.paneScroll:UpdateScrollChildRect()
	self.paneScroll:SetVerticalScroll(newChapter and 0 or math.min(scroll, self.paneScroll:GetVerticalScrollRange()))
end

-- Opens the viewer at a chapter; with none, at the current step's chapter.
function M:ShowViewer(chapter)
	if not self.viewer then self:BuildViewer() end
	if not chapter then
		local upcoming = self:GetUpcoming(1)[1]
		chapter = upcoming and upcoming.chapter
	end
	self.selected = chapter and chapter.id or self.selected
	if self.viewer:IsShown() then
		self:UpdateViewer(true)
	else
		self.viewer:Show()
		self.paneScroll:SetVerticalScroll(0)
	end
end

function M:ToggleViewer()
	if self.viewer and self.viewer:IsShown() then
		self.viewer:Hide()
	else
		self:ShowViewer()
	end
end

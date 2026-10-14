local _, ns = ...
local Grimoire = Grimoire
local M = ns.M

-- The import window: paste a plan, check it (errors and warnings with line numbers),
-- save it. A plan with errors isn't saved; one with the same title as a saved plan
-- replaces it and keeps the progress of unchanged steps (FORMAT.md).

local WIDTH, HEIGHT = 640, 440
local RESULTS_HEIGHT = 96
local BUTTON_ROW = 30
local SCROLLBAR = 28
local MAX_LISTED = 30

local function ProblemLines(list, color, label)
	local lines = {}
	for i, problem in ipairs(list) do
		if i > MAX_LISTED then
			lines[#lines + 1] = ("%s... and %d more|r"):format(color, #list - MAX_LISTED)
			break
		end
		local where = problem.line > 0 and ("line " .. problem.line) or "character"
		lines[#lines + 1] = ("%s%s, %s:|r %s"):format(color, label, where, (problem.message:gsub("|", "||")))
	end
	return lines
end

function M:ShowImportResult(plan, errors, warnings, kept)
	local lines
	if plan then
		local steps = 0
		for _ in self:EachStep(plan) do steps = steps + 1 end
		lines = { ("|cff66ff66%s:|r %d chapters, %d steps."):format((plan.title:gsub("|", "||")), #plan.chapters, steps) }
		if kept then
			lines[1] = lines[1] .. (" Saved and made active%s."):format(kept > 0 and ("; kept progress on " .. kept .. " steps") or "")
		else
			lines[1] = lines[1] .. " No errors: click Save."
		end
	else
		lines = { ("|cffff4040%d error(s): not saved.|r"):format(#errors) }
	end
	for _, line in ipairs(ProblemLines(errors, "|cffff4040", "Error")) do lines[#lines + 1] = line end
	for _, line in ipairs(ProblemLines(warnings, "|cffffd200", "Warning")) do lines[#lines + 1] = line end
	self.importResults:SetText(table.concat(lines, "\n"))
	self.importResultsChild:SetHeight(math.max(1, self.importResults:GetStringHeight()))
end

function M:BuildImport()
	local frame = Grimoire:CreateWindow("ProphecyImport", "Import a Prophecy plan", self)
	frame:SetContentSize(WIDTH, HEIGHT)
	self.importWindow = frame
	local content = frame.content

	local help = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT")
	help:SetPoint("TOPRIGHT")
	help:SetJustifyH("LEFT")
	help:SetText("Paste a plan below (Ctrl+V), then Check or Save. The format is docs/prophecy/FORMAT.md in the Grimoire repo. A plan with the same title replaces the saved one and keeps your progress.")

	-- Text box
	local textBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(textBg)
	textBg:SetPoint("TOPLEFT", 0, -34)
	textBg:SetPoint("BOTTOMRIGHT", 0, RESULTS_HEIGHT + BUTTON_ROW + 8)

	local box = CreateFrame("EditBox", nil, textBg)
	local boxScroll = Grimoire.CreateScrollArea(textBg, "GrimoireProphecyImportScroll", box)
	boxScroll:SetPoint("TOPLEFT", 8, -8)
	boxScroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 8)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetFontObject(ChatFontNormal)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnTextChanged", function(b) ScrollingEdit_OnTextChanged(b, boxScroll) end)
	box:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
	box:SetScript("OnUpdate", function(b, elapsed) ScrollingEdit_OnUpdate(b, elapsed, boxScroll) end)
	boxScroll:EnableMouse(true)
	boxScroll:SetScript("OnMouseDown", function() box:SetFocus() end)
	self.importBox = box

	-- Results
	local resultsBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(resultsBg)
	resultsBg:SetPoint("BOTTOMLEFT", 0, BUTTON_ROW)
	resultsBg:SetPoint("BOTTOMRIGHT", 0, BUTTON_ROW)
	resultsBg:SetHeight(RESULTS_HEIGHT)
	local resultsScroll, resultsChild = Grimoire.CreateScrollArea(resultsBg, "GrimoireProphecyImportResults")
	resultsScroll:SetPoint("TOPLEFT", 8, -6)
	resultsScroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 6)
	self.importResults = resultsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.importResults:SetPoint("TOPLEFT")
	self.importResults:SetWidth(WIDTH - 8 - SCROLLBAR - 8)
	self.importResults:SetJustifyH("LEFT")
	self.importResultsChild = resultsChild

	-- Buttons
	local check = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	check:SetSize(90, 22)
	check:SetPoint("BOTTOMLEFT")
	check:SetText("Check")
	check:SetScript("OnClick", function()
		local plan, errors, warnings = self:CheckPlan(box:GetText())
		self:ShowImportResult(plan, errors, warnings)
	end)

	local save = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	save:SetSize(90, 22)
	save:SetPoint("LEFT", check, "RIGHT", 6, 0)
	save:SetText(SAVE or "Save")
	save:SetScript("OnClick", function()
		local plan, errors, warnings, kept = self:ImportPlan(box:GetText())
		self:ShowImportResult(plan, errors, warnings, plan and kept)
		if plan and self.viewer and self.viewer:IsShown() then
			self.selected = nil
			self:UpdateViewer(true)
		end
	end)

	local clear = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	clear:SetSize(90, 22)
	clear:SetPoint("LEFT", save, "RIGHT", 6, 0)
	clear:SetText("Clear")
	clear:SetScript("OnClick", function()
		box:SetText("")
		self.importResults:SetText("")
		box:SetFocus()
	end)

	local open = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	open:SetSize(110, 22)
	open:SetPoint("BOTTOMRIGHT")
	open:SetText("Open plans")
	open:SetScript("OnClick", function() self:ShowViewer() end)
end

function M:ShowImport()
	if not self.importWindow then self:BuildImport() end
	self.importWindow:Show()
	self.importBox:SetFocus()
end

local _, ns = ...
local Grimoire = Grimoire
local M = ns.M
local Cycles = ns.Cycles
local Share = ns.Share

-- The Tempo window (plan milestones T3 and T5): this character's best opener and cycle,
-- saved (and imported) rotations, and recent fights. Click a fight to see its opener and
-- cycles. Every rotation row shows its spells in order and can be saved (kept in Saved
-- rotations, account-wide) or exported as text for someone else.
-- Pet steps (abilities you had your pet use) are drawn smaller.

local WIDTH, HEIGHT = 560, 440
local ROW_HEIGHT = 24
local ICON = 18
local MAX_ICONS = 14
local LABEL_WIDTH = 110
local SCROLLBAR = 28
local BUTTON_WIDTH = 52

local function Icon_OnEnter(icon)
	GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
	if icon.spell and GameTooltip.SetSpellByID then
		GameTooltip:SetSpellByID(icon.spell)
	else
		GameTooltip:SetText(icon.name or "")
	end
	if icon.pet then
		GameTooltip:AddLine("Your pet", 0.4, 0.8, 1)
	end
	GameTooltip:AddLine(("%.1f s into the rotation"):format(icon.at or 0), 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

-- Rows -------------------------------------------------------------------------------------
-- One row type serves every line: a label, optional spell icons, a score, up to three
-- buttons. Rows are pooled and filled in order on every update.

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(1, 1, 1, 0.08)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", 4, 0)
	row.label:SetJustifyH("LEFT")
	row.label:SetWordWrap(false)
	row.icons = {}
	for i = 1, MAX_ICONS do
		local icon = CreateFrame("Frame", nil, row)
		icon:SetSize(ICON, ICON)
		icon:SetPoint("LEFT", LABEL_WIDTH + (i - 1) * (ICON + 1), 0)
		icon.texture = icon:CreateTexture(nil, "ARTWORK")
		icon.texture:SetAllPoints()
		icon:SetScript("OnEnter", Icon_OnEnter)
		icon:SetScript("OnLeave", GameTooltip_Hide)
		row.icons[i] = icon
	end
	row.more = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.score = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.buttons = {}
	for i = 1, 3 do
		local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		button:SetSize(BUTTON_WIDTH, 18)
		button:SetPoint("RIGHT", -(i - 1) * (BUTTON_WIDTH + 2), 0)
		row.buttons[i] = button
	end
	return row
end

function M:NextRow()
	self.rowCount = self.rowCount + 1
	local row = self.rows[self.rowCount]
	if not row then
		row = CreateRow(self.listChild)
		self.rows[self.rowCount] = row
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", 0, -(self.rowCount - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT")
	row:SetScript("OnClick", nil)
	row:EnableMouse(false)
	row.label:SetFontObject("GameFontHighlightSmall")
	row.label:SetWidth(0)
	row.label:ClearAllPoints()
	row.label:SetPoint("LEFT", 4, 0)
	for _, icon in ipairs(row.icons) do icon:Hide() end
	row.more:SetText("")
	row.score:SetText("")
	for _, button in ipairs(row.buttons) do button:Hide() end
	row:Show()
	return row
end

function M:AddHeader(text)
	local row = self:NextRow()
	row.label:SetFontObject("GameFontNormal")
	row.label:SetText(text)
end

function M:AddText(text)
	local row = self:NextRow()
	row.label:SetPoint("RIGHT", -4, 0)
	row.label:SetText("|cff9d9d9d" .. text .. "|r")
end

-- buttons: { { text, onClick }, ... } from right to left.
function M:AddRotation(label, rotation, buttons)
	local row = self:NextRow()
	row.label:SetWidth(LABEL_WIDTH - 8)
	row.label:SetText(label)
	local steps = rotation.steps or {}
	for i = 1, math.min(#steps, MAX_ICONS) do
		local icon, step = row.icons[i], steps[i]
		icon.spell, icon.name, icon.at, icon.pet = step.spell, step.name, step.at, step.pet
		icon.texture:SetTexture(M.StepIcon(step))
		-- Pet steps are drawn smaller.
		local inset = step.pet and 3 or 0
		icon.texture:SetPoint("TOPLEFT", inset, -inset)
		icon.texture:SetPoint("BOTTOMRIGHT", -inset, inset)
		icon:Show()
	end
	local shownIcons = math.min(#steps, MAX_ICONS)
	row.more:ClearAllPoints()
	row.more:SetPoint("LEFT", LABEL_WIDTH + shownIcons * (ICON + 1) + 2, 0)
	row.more:SetText(#steps > MAX_ICONS and ("+" .. (#steps - MAX_ICONS)) or "")
	local buttonCount = #(buttons or {})
	row.score:ClearAllPoints()
	row.score:SetPoint("RIGHT", -(buttonCount * (BUTTON_WIDTH + 2)) - 4, 0)
	row.score:SetText(("%s, %.0f s"):format(Cycles.FormatScore(rotation), rotation.length or 0))
	for i, spec in ipairs(buttons or {}) do
		local button = row.buttons[i]
		button:SetText(spec[1])
		button:SetScript("OnClick", spec[2])
		button:Show()
	end
	return row
end

-- Contents ---------------------------------------------------------------------------------

-- Buttons, right to left: Export, then Save (or Delete for one already saved).
function M:RotationButtons(rotation, savedIndex)
	local buttons = { { "Export", function() self:ShowShare(rotation) end } }
	if savedIndex then
		buttons[2] = { "Delete", function() self:DeleteRotation(savedIndex) end }
	else
		buttons[2] = { "Save", function()
			self:SaveRotation(rotation)
			self:Print(("Saved \"%s\" to Saved rotations."):format(rotation.name or "rotation"))
		end }
	end
	return buttons
end

function M:FillFight(fight, index)
	local row = self:NextRow()
	row:EnableMouse(true)
	local open = self.openFight == index
	row.label:SetPoint("RIGHT", -4, 0)
	row.label:SetText(("%s %s  |cffffd200%s|r  %.0f s  %s%s"):format(
		open and "-" or "+", Grimoire.FormatAgo(fight.time), fight.target or "?", fight.duration or 0,
		fight.unit and Cycles.FormatScore(fight) or "no damage data",
		fight.source and ("  |cff9d9d9d(" .. (M.SOURCE_LABELS[fight.source] or fight.source) .. ")|r") or ""))
	row:SetScript("OnClick", function()
		self.openFight = (self.openFight ~= index) and index or nil
		self:UpdateWindow()
	end)
	if not open then return end
	local cycleNumber = 0
	for _, segment in ipairs(Cycles.Split(fight, self:GetClass())) do
		local label = M.KindLabel(segment.kind)
		if segment.kind == "cycle" then
			cycleNumber = cycleNumber + 1
			label = label .. " " .. cycleNumber
		end
		if not segment.scored then label = "|cff9d9d9d" .. label .. "|r" end
		self:AddRotation("    " .. label, segment, self:RotationButtons(self:MakeRotation(segment, fight)))
	end
end

function M:UpdateWindow()
	self.rowCount = 0
	local char = self:GetCharacter()
	self.window.subtitle:SetText(Grimoire:FormatCharacterName())

	self:AddHeader("Your best")
	if char.best.opener or char.best.cycle then
		for _, kind in ipairs({ "opener", "cycle" }) do
			local rotation = char.best[kind]
			if rotation then
				self:AddRotation(M.KindLabel(kind), rotation, self:RotationButtons(rotation))
			end
		end
	else
		self:AddText("Nothing yet. Fight something and Tempo learns your rotation.")
	end

	if #self.store.rotations > 0 then
		self:AddHeader("Saved rotations")
		for index, rotation in ipairs(self.store.rotations) do
			self:AddRotation(rotation.name or "Rotation", rotation, self:RotationButtons(rotation, index))
		end
	end

	self:AddHeader("Recent fights")
	if #char.fights == 0 then
		self:AddText("No fights recorded yet.")
	end
	for index, fight in ipairs(char.fights) do
		self:FillFight(fight, index)
	end

	for i = self.rowCount + 1, #self.rows do
		self.rows[i]:Hide()
	end
	self.listChild:SetHeight(math.max(1, self.rowCount * ROW_HEIGHT))
end

function M:BuildWindow()
	local frame = Grimoire:CreateWindow("Tempo", "Tempo", self)
	frame:SetContentSize(WIDTH, HEIGHT)
	frame:HookScript("OnShow", function() self:UpdateWindow() end)
	self.window = frame
	local content = frame.content

	frame.subtitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.subtitle:SetPoint("TOPLEFT", 2, 0)

	local listBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(listBg)
	listBg:SetPoint("TOPLEFT", 0, -20)
	listBg:SetPoint("BOTTOMRIGHT", 0, 30)
	local scroll, child = Grimoire.CreateScrollArea(listBg, "GrimoireTempoList")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 6)
	self.listChild = child
	self.rows = {}

	local function Button(text, width, onClick)
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetSize(width, 22)
		button:SetText(text)
		button:SetScript("OnClick", onClick)
		return button
	end
	local import = Button("Import", 90, function() self:ShowShare() end)
	import:SetPoint("BOTTOMLEFT")
	local forget = Button("Forget best", 100, function() self:ForgetBest() end)
	forget:SetPoint("LEFT", import, "RIGHT", 6, 0)
	local clear = Button("Clear fights", 100, function()
		wipe(self:GetCharacter().fights)
		self.openFight = nil
		self:Refresh()
	end)
	clear:SetPoint("LEFT", forget, "RIGHT", 6, 0)
end

function M:ToggleWindow()
	if not self.window then self:BuildWindow() end
	self.window:SetShown(not self.window:IsShown())
end

-- Share window ---------------------------------------------------------------------------------
-- Export: the rotation as text, selected, ready for Ctrl+C. Import: paste, then Import.

function M:BuildShare()
	local frame = Grimoire:CreateWindow("TempoShare", "Share a rotation", self)
	frame:SetContentSize(460, 300)
	self.shareWindow = frame
	local content = frame.content

	frame.help = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.help:SetPoint("TOPLEFT")
	frame.help:SetPoint("TOPRIGHT")
	frame.help:SetJustifyH("LEFT")

	local textBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Grimoire.ApplyClassicBackdrop(textBg)
	textBg:SetPoint("TOPLEFT", 0, -30)
	textBg:SetPoint("BOTTOMRIGHT", 0, 30)
	local box = CreateFrame("EditBox", nil, textBg)
	local scroll = Grimoire.CreateScrollArea(textBg, "GrimoireTempoShareScroll", box)
	scroll:SetPoint("TOPLEFT", 8, -8)
	scroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR, 8)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetFontObject(ChatFontNormal)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnTextChanged", function(b) ScrollingEdit_OnTextChanged(b, scroll) end)
	box:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
	box:SetScript("OnUpdate", function(b, elapsed) ScrollingEdit_OnUpdate(b, elapsed, scroll) end)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
	frame.box = box

	frame.result = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.result:SetPoint("BOTTOMLEFT", 100, 6)
	frame.result:SetPoint("RIGHT")
	frame.result:SetJustifyH("LEFT")

	frame.import = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	frame.import:SetSize(90, 22)
	frame.import:SetPoint("BOTTOMLEFT")
	frame.import:SetText("Import")
	frame.import:SetScript("OnClick", function()
		local rotation, err = Share.Import(box:GetText())
		if not rotation then
			frame.result:SetText("|cffff4040" .. err .. "|r")
			return
		end
		rotation.scored = rotation.unit ~= nil
		rotation.time = time()
		self:SaveRotation(rotation)
		frame.result:SetText(("|cff66ff66Saved \"%s\" (%d steps).|r It's in Saved rotations in the Tempo window."):format(rotation.name, #rotation.steps))
	end)
end

-- With a rotation: export it. Without: an empty box to paste one into.
function M:ShowShare(rotation)
	if not self.shareWindow then self:BuildShare() end
	local frame = self.shareWindow
	frame.result:SetText("")
	if rotation then
		frame.help:SetText("Press Ctrl+C to copy, then send it to whoever you're teaching. They paste it in /grim tempo import.")
		frame.box:SetText(Share.Export(rotation))
		frame.import:Hide()
		frame:Show()
		frame.box:SetFocus()
		frame.box:HighlightText()
	else
		frame.help:SetText("Paste a rotation (Ctrl+V), then Import. Notes can be added as \"note: ...\" lines.")
		frame.box:SetText("")
		frame.import:Show()
		frame:Show()
		frame.box:SetFocus()
	end
end

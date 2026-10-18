local ADDON_NAME = ...
local Homunculus = Homunculus

local LIST_WIDTH = 170
local ROW_HEIGHT = 20
local VIEW_WIDTH = 600
local VIEW_HEIGHT = 400
local BUTTON_ROW_HEIGHT = 30
local SCROLLBAR_WIDTH = 24
local DELETE_CONFIRM_SECONDS = 3

local NOTE_ICON = "Interface\\Icons\\INV_Misc_Note_01"

local M = Homunculus:NewModule("Notes", {
	addon = ADDON_NAME,
	label = "Notes",
	defaults = {
		showButton = true,
	},
	options = {
		{ type = "toggle", key = "showButton", label = "Show Notes button", tooltip = "A round button that opens your notes. Drag it in move mode." },
	},
})

-- Notes are account-wide: HomunculusDB.global.notes = { nextID, list = { {id, title, body, created, updated, author, class} } }
-- author/class record which character wrote the note, so it can be class-colored (ADR 0003).

function M:GetNote(id)
	for index, note in ipairs(self.store.list) do
		if note.id == id then
			return note, index
		end
	end
end

function M:NewNote()
	local id = self.store.nextID
	self.store.nextID = id + 1
	local now = time()
	table.insert(self.store.list, 1, {
		id = id,
		title = "",
		body = "",
		created = now,
		updated = now,
		author = Homunculus.db.charKey,
		class = Homunculus:GetPlayerClass(),
	})
	self:SelectNote(id)
	self.title:SetFocus()
end

function M:DeleteSelected()
	local _, index = self:GetNote(self.selectedID)
	if not index then return end
	table.remove(self.store.list, index)
	local next = self.store.list[index] or self.store.list[index - 1]
	self:SelectNote(next and next.id)
end

function M:Save(field, text)
	local note = self:GetNote(self.selectedID)
	if not note then return end
	note[field] = text
	note.updated = time()
	self:UpdateFooter(note)
	if field == "title" then
		self:RefreshList()
	end
end

-- Delete asks for a second click instead of a StaticPopup, which can spread taint.
function M:OnDeleteClicked()
	if not self.selectedID then return end
	if self.confirmingDelete then
		self:ResetDeleteConfirm()
		self:DeleteSelected()
		return
	end
	self.confirmingDelete = true
	self.deleteButton:SetText("Confirm?")
	self.confirmToken = (self.confirmToken or 0) + 1
	local token = self.confirmToken
	C_Timer.After(DELETE_CONFIRM_SECONDS, function()
		if self.confirmToken == token then
			self:ResetDeleteConfirm()
		end
	end)
end

function M:ResetDeleteConfirm()
	self.confirmingDelete = false
	self.confirmToken = (self.confirmToken or 0) + 1
	self.deleteButton:SetText(DELETE or "Delete")
end

-- Window -----------------------------------------------------------------------

function M:CreateRow(index)
	local row = CreateFrame("Button", nil, self.listChild)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT")
	row:SetHighlightTexture(Homunculus.media.rowHighlight, "ADD")
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 6, 0)
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row:SetScript("OnClick", function(button)
		self:SelectNote(button.noteID)
	end)
	self.rows[index] = row
	return row
end

function M:Build()
	local frame = Homunculus:CreateWindow("Notes", "Notes", self)
	frame:SetContentSize(VIEW_WIDTH, VIEW_HEIGHT)
	self.frame = frame
	local content = frame.content

	-- Note list
	local listBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Homunculus.ApplyClassicBackdrop(listBg)
	listBg:SetPoint("TOPLEFT")
	listBg:SetPoint("BOTTOMLEFT", 0, BUTTON_ROW_HEIGHT)
	listBg:SetWidth(LIST_WIDTH)
	local listScroll, listChild = Homunculus.CreateScrollArea(listBg, "HomunculusNotesListScroll")
	listScroll:SetPoint("TOPLEFT", 6, -6)
	listScroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH - 4, 6)
	self.listChild = listChild
	self.rows = {}

	local newButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	newButton:SetSize(80, 22)
	newButton:SetPoint("BOTTOMLEFT")
	newButton:SetText(NEW or "New")
	newButton:SetScript("OnClick", function() self:NewNote() end)

	self.deleteButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	self.deleteButton:SetSize(80, 22)
	self.deleteButton:SetPoint("LEFT", newButton, "RIGHT", 6, 0)
	self.deleteButton:SetScript("OnClick", function() self:OnDeleteClicked() end)

	-- Editor
	local title = CreateFrame("EditBox", "HomunculusNotesTitle", content, "InputBoxTemplate")
	title:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 16, -2)
	title:SetPoint("RIGHT", content, "RIGHT", -4, 0)
	title:SetHeight(22)
	title:SetAutoFocus(false)
	title:HookScript("OnTextChanged", function(box, userInput)
		if userInput then self:Save("title", box:GetText()) end
	end)
	title:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
		self.body:SetFocus()
	end)
	self.title = title

	local bodyBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Homunculus.ApplyClassicBackdrop(bodyBg)
	bodyBg:SetPoint("TOPLEFT", listBg, "TOPRIGHT", 8, -30)
	bodyBg:SetPoint("BOTTOMRIGHT", 0, BUTTON_ROW_HEIGHT)

	local body = CreateFrame("EditBox", nil, bodyBg)
	local bodyScroll = Homunculus.CreateScrollArea(bodyBg, "HomunculusNotesBodyScroll", body)
	bodyScroll:SetPoint("TOPLEFT", 8, -8)
	bodyScroll:SetPoint("BOTTOMRIGHT", -SCROLLBAR_WIDTH - 4, 8)
	body:SetMultiLine(true)
	body:SetAutoFocus(false)
	body:SetMaxLetters(0)
	body:SetFontObject(ChatFontNormal)
	body:SetScript("OnEscapePressed", body.ClearFocus)
	body:SetScript("OnTextChanged", function(box, userInput)
		if userInput then self:Save("body", box:GetText()) end
		ScrollingEdit_OnTextChanged(box, bodyScroll)
	end)
	body:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
	body:SetScript("OnUpdate", function(box, elapsed)
		ScrollingEdit_OnUpdate(box, elapsed, bodyScroll)
	end)
	-- Clicking anywhere in the editor area focuses the text.
	bodyScroll:EnableMouse(true)
	bodyScroll:SetScript("OnMouseDown", function() body:SetFocus() end)
	self.body = body

	self.edited = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.edited:SetPoint("BOTTOMRIGHT", -4, 6)

	self:ResetDeleteConfirm()
end

function M:RefreshList()
	local list = self.store.list
	for i, note in ipairs(list) do
		local row = self.rows[i] or self:CreateRow(i)
		row.noteID = note.id
		row.text:SetText(Homunculus.ClassColorText(note.title ~= "" and note.title or "Untitled", note.class))
		if note.id == self.selectedID then
			row:LockHighlight()
		else
			row:UnlockHighlight()
		end
		row:Show()
	end
	for i = #list + 1, #self.rows do
		self.rows[i]:Hide()
	end
	self.listChild:SetHeight(math.max(1, #list * ROW_HEIGHT))
end

-- "Edited 5m ago by <class-colored name>"; older notes without an author omit the name.
function M:UpdateFooter(note)
	if not note then
		self.edited:SetText("")
		return
	end
	local text = "Edited " .. Homunculus.FormatAgo(note.updated)
	if note.author then
		text = text .. " by " .. Homunculus:FormatCharacterName(note.author)
	end
	self.edited:SetText(text)
end

function M:SelectNote(id)
	local note = id and self:GetNote(id)
	self.selectedID = note and note.id
	self.title:SetText(note and note.title or "")
	self.body:SetText(note and note.body or "")
	self.title:SetEnabled(note ~= nil)
	self.body:SetEnabled(note ~= nil)
	self:UpdateFooter(note)
	local color = Homunculus.GetClassColor(note and note.class)
	if color then
		self.title:SetTextColor(color.r, color.g, color.b)
	else
		self.title:SetTextColor(1, 1, 1)
	end
	self:ResetDeleteConfirm()
	self:RefreshList()
end

function M:Toggle()
	if not self.frame then
		self:Build()
		local first = self.store.list[1]
		self:SelectNote(first and first.id)
	end
	self.frame:SetShown(not self.frame:IsShown())
end

-- Floating button ----------------------------------------------------------------
-- An optional round button that opens Notes. It's a normal mover: drag it in move
-- mode, and the menu offers its reset and dimming options.

function M:BuildButton()
	self.button = Homunculus.CreateModuleButton(self, {
		name = "HomunculusNotesButton",
		icon = NOTE_ICON,
		title = "Notes",
		hint = "Click: open your notes",
		onClick = function() self:Toggle() end,
		default = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -95, 120 },
	})
end

function M:ApplySettings()
	if self.db.showButton and not self.button then
		self:BuildButton()
	end
	if self.button then
		self.button:SetShown(self.db.showButton)
	end
end

-- Lifecycle --------------------------------------------------------------------

function M:OnEnable()
	self:ApplySettings()
end

function M:OnInitialize()
	local global = Homunculus.db.global
	global.notes = global.notes or { nextID = 1, list = {} }
	self.store = global.notes
	Homunculus:RegisterCommand("notes", "notes - open your notes", function()
		if self:IsEnabled() then self:Toggle() end
	end)
end

function M:OnDisable()
	if self.frame then
		self.frame:Hide()
	end
	if self.button then
		self.button:Hide()
	end
end

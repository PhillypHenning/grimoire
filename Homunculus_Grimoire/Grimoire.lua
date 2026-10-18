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

-- The Grimoire: an account-wide notebook (called Notes before ADR 0010). Notes can hold
-- your current location and links: shift-click an item, spell or quest while writing,
-- or use the Location and Quest buttons.

local M = Homunculus:NewModule("Grimoire", {
	addon = ADDON_NAME,
	label = "Grimoire",
	defaults = {
		showButton = true,
	},
	options = {
		{ type = "toggle", key = "showButton", label = "Show Grimoire button", tooltip = "A round button that opens your Grimoire. Drag it in move mode." },
	},
})

-- Notes are account-wide: HomunculusDB.global.notes = { nextID, list = { {id, title, body, created, updated, author, class} } }
-- (the storage key kept its old name). Links are stored in the body as the game's own
-- |H...|h link text, which the editor shows in colour.
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

-- Inserting ----------------------------------------------------------------------

-- Puts text at the cursor in the open note and saves it.
function M:InsertText(text)
	if not (self.selectedID and self.body and type(text) == "string" and text ~= "") then return end
	self.body:SetFocus()
	self.body:Insert(text)
	self:Save("body", self.body:GetText())
end

-- "Razor Hill, Durotar (52.4, 43.1)": subzone, zone and map coordinates. Where the map
-- has no position for you (instances) or it's secret, the place name alone.
function M:LocationText()
	local mapID = C_Map and C_Map.GetBestMapForUnit("player")
	local info = mapID and C_Map.GetMapInfo(mapID)
	local zone = info and info.name or (GetRealZoneText and GetRealZoneText()) or ""
	local sub = GetSubZoneText and GetSubZoneText() or ""
	local place = (sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		local x, y = pos:GetXY()
		if not Homunculus.AnySecret(x, y) and x and y then
			return ("%s (%.1f, %.1f)"):format(place, x * 100, y * 100)
		end
	end
	return place
end

-- The quests in your log: the modern API first, then the classic one.
local function QuestLogEntries()
	local quests = {}
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.title then
				quests[#quests + 1] = { title = info.title, questID = info.questID, index = i }
			end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, GetNumQuestLogEntries() do
			local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
			if title and not isHeader then
				quests[#quests + 1] = { title = title, questID = questID, index = i }
			end
		end
	end
	return quests
end

-- The game's quest link (by quest ID on modern clients, by log index on old ones), or
-- the title in brackets when it won't make one.
local function QuestLinkText(quest)
	if GetQuestLink then
		for _, key in ipairs({ quest.questID, quest.index }) do
			local ok, link = pcall(GetQuestLink, key)
			if ok and type(link) == "string" and link ~= "" then
				return link
			end
		end
	end
	return "[" .. quest.title .. "]"
end

function M:OpenQuestMenu(anchor)
	local entries = { { text = QUEST_LOG or "Quest Log", isTitle = true } }
	for _, quest in ipairs(QuestLogEntries()) do
		entries[#entries + 1] = { text = quest.title, func = function() self:InsertText(QuestLinkText(quest)) end }
	end
	if #entries == 1 then
		entries[2] = { text = "Your quest log is empty", disabled = true }
	end
	Homunculus.OpenMenu(anchor, entries)
end

-- Shift-click: the game hands item, spell and quest links to the chat box. While a
-- note has the cursor they go into the note instead. These hooks run after the game's
-- own handling, so nothing of Blizzard's is replaced or tainted.
function M:OnLinkClicked(link)
	if not (self.body and self.body:HasFocus() and type(link) == "string") then return end
	local now = GetTime()
	if self.lastLink == link and self.lastLinkTime == now then return end -- one click, two hooks
	self.lastLink, self.lastLinkTime = link, now
	self:InsertText(link)
end

function M:HookLinks()
	local function onLink(link) self:OnLinkClicked(link) end
	if ChatEdit_InsertLink then
		hooksecurefunc("ChatEdit_InsertLink", onLink)
	end
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", onLink)
	end
	-- The modern quest log only offers quest links to an open chat box.
	if ChatEdit_TryInsertQuestLinkForQuestID and GetQuestLink then
		hooksecurefunc("ChatEdit_TryInsertQuestLinkForQuestID", function(questID)
			local ok, link = pcall(GetQuestLink, questID)
			if ok then onLink(link) end
		end)
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
	local frame = Homunculus:CreateWindow("Grimoire", "Grimoire", self)
	frame:SetContentSize(VIEW_WIDTH, VIEW_HEIGHT)
	self.frame = frame
	local content = frame.content

	-- Note list
	local listBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	Homunculus.ApplyClassicBackdrop(listBg)
	listBg:SetPoint("TOPLEFT")
	listBg:SetPoint("BOTTOMLEFT", 0, BUTTON_ROW_HEIGHT)
	listBg:SetWidth(LIST_WIDTH)
	local listScroll, listChild = Homunculus.CreateScrollArea(listBg, "HomunculusGrimoireListScroll")
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

	-- Insert into the open note, at the cursor.
	local function InsertButton(text, tooltip, onClick)
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetSize(80, 22)
		button:SetText(text)
		button:SetScript("OnClick", onClick)
		button:SetScript("OnEnter", function(b)
			GameTooltip:SetOwner(b, "ANCHOR_TOP")
			GameTooltip:SetText(text)
			GameTooltip:AddLine(tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		return button
	end
	local locationButton = InsertButton("Location", "Add where you are: zone and map coordinates.",
		function() self:InsertText(self:LocationText()) end)
	locationButton:SetPoint("LEFT", self.deleteButton, "RIGHT", 16, 0)
	local questButton
	questButton = InsertButton("Quest", "Add a link to a quest in your log. Shift-click an item, spell or quest while writing to add its link too.",
		function() self:OpenQuestMenu(questButton) end)
	questButton:SetPoint("LEFT", locationButton, "RIGHT", 6, 0)
	self.insertButtons = { locationButton, questButton }

	-- Editor
	local title = CreateFrame("EditBox", "HomunculusGrimoireTitle", content, "InputBoxTemplate")
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
	local bodyScroll = Homunculus.CreateScrollArea(bodyBg, "HomunculusGrimoireBodyScroll", body)
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
	for _, button in ipairs(self.insertButtons) do
		button:SetEnabled(note ~= nil)
	end
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
-- An optional round button that opens the Grimoire. It's a normal mover: drag it in move
-- mode, and the menu offers its reset and dimming options.

function M:BuildButton()
	self.button = Homunculus.CreateModuleButton(self, {
		name = "HomunculusGrimoireButton",
		icon = NOTE_ICON,
		title = "Grimoire",
		hint = "Click: open your Grimoire",
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
	self:MigrateFromNotes()
	local function open()
		if self:IsEnabled() then self:Toggle() end
	end
	Homunculus:RegisterCommand("grimoire", "grimoire - open your Grimoire (notes)", open)
	Homunculus:RegisterCommand("notes", "notes - open your Grimoire (notes)", open)
	self:HookLinks()
end

-- Settings and positions saved while this module was called Notes (ADR 0010): copied
-- once, before the module is enabled and its window and button are placed.
function M:MigrateFromNotes()
	local profile = Homunculus.db.profile
	local old = profile.modules.Notes
	if not old then return end
	self.db.enabled, self.db.showButton = old.enabled, old.showButton
	for _, store in ipairs({ profile.movers, profile.moverDim, profile.moverGroups }) do
		for _, suffix in ipairs({ "Window", "Button" }) do
			if store and store["Notes" .. suffix] ~= nil then
				store["Grimoire" .. suffix] = store["Notes" .. suffix]
				store["Notes" .. suffix] = nil
			end
		end
	end
	profile.modules.Notes = nil
end

function M:OnDisable()
	if self.frame then
		self.frame:Hide()
	end
	if self.button then
		self.button:Hide()
	end
end

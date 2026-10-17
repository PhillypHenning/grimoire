local Grimoire = Grimoire

-- Layout sharing (learned from Shadowed Unit Frames / ElvUI, 2026-10-16): the current
-- profile's layout as text to copy, and a box to paste one into. The text is read by
-- Grimoire.Serialize, never run. Importing replaces this profile's layout; /reload applies it.
--
-- Shared: frame positions, groups, which frames dim, dim strength and delay, button size,
-- and every component's settings (including whether it's on).

local HEADER = "# Grimoire layout v1"
local WIDTH, HEIGHT = 520, 320
local SCROLLBAR = 28

-- Profile keys a layout carries, and the type each must have.
local FIELDS = {
	movers = "table", moverGroups = "table", moverDim = "table", modules = "table",
	dimAlpha = "number", idleSeconds = "number", buttonSize = "number",
}

function Grimoire:ExportLayout()
	local layout = {}
	for key in pairs(FIELDS) do
		layout[key] = self.db.profile[key]
	end
	return HEADER .. "\n" .. self.Serialize.Write(layout)
end

-- Returns true, or nil and why not.
function Grimoire:ImportLayout(text)
	local body = text and text:match("^%s*" .. HEADER:gsub("%p", "%%%0") .. "%s*(.-)%s*$")
	if not body then
		return nil, "the text must start with \"" .. HEADER .. "\""
	end
	local layout, err = self.Serialize.Read(body)
	if not layout then return nil, err end
	if type(layout) ~= "table" then return nil, "not a layout" end
	for key, value in pairs(layout) do
		if not FIELDS[key] then return nil, "unknown setting: " .. tostring(key) end
		if type(value) ~= FIELDS[key] then return nil, ("%s should be a %s"):format(key, FIELDS[key]) end
	end
	for key in pairs(FIELDS) do
		if layout[key] ~= nil then
			self.db.profile[key] = layout[key]
		end
	end
	self:Log("Grimoire", "info", "layout imported into profile %s", self.db.profileName)
	return true
end

-- Window ---------------------------------------------------------------------------------------

function Grimoire:BuildLayoutWindow()
	local frame = self:CreateWindow("Layout", "Share your layout")
	frame:SetContentSize(WIDTH, HEIGHT)
	self.layoutWindow = frame
	local content = frame.content

	frame.help = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.help:SetPoint("TOPLEFT")
	frame.help:SetPoint("TOPRIGHT")
	frame.help:SetJustifyH("LEFT")

	local textBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
	self.ApplyClassicBackdrop(textBg)
	textBg:SetPoint("TOPLEFT", 0, -30)
	textBg:SetPoint("BOTTOMRIGHT", 0, 30)
	local box = CreateFrame("EditBox", nil, textBg)
	local scroll = self.CreateScrollArea(textBg, "GrimoireLayoutScroll", box)
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
	frame.result:SetPoint("BOTTOMLEFT", 196, 6)
	frame.result:SetPoint("RIGHT")
	frame.result:SetJustifyH("LEFT")

	frame.import = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	frame.import:SetSize(90, 22)
	frame.import:SetPoint("BOTTOMLEFT")
	frame.import:SetText("Import")
	frame.import:SetScript("OnClick", function()
		local ok, err = self:ImportLayout(box:GetText())
		if ok then
			frame.result:SetText("|cff66ff66Imported.|r Reload to apply it.")
			frame.reload:Show()
		else
			frame.result:SetText("|cffff4040" .. err .. "|r")
		end
	end)
	frame.reload = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	frame.reload:SetSize(96, 22)
	frame.reload:SetPoint("LEFT", frame.import, "RIGHT", 6, 0)
	frame.reload:SetText(RELOADUI or "Reload UI")
	frame.reload:SetScript("OnClick", ReloadUI)
end

function Grimoire:ShowLayoutExport()
	if not self.layoutWindow then self:BuildLayoutWindow() end
	local frame = self.layoutWindow
	frame.help:SetText(("Your layout (profile %s). Ctrl+C to copy; paste it into Import layout on another character or for someone else."):format(self.db.profileName))
	frame.box:SetText(self:ExportLayout())
	frame.import:Hide()
	frame.reload:Hide()
	frame.result:SetText("")
	frame:Show()
	frame.box:SetFocus()
	frame.box:HighlightText()
end

function Grimoire:ShowLayoutImport()
	if not self.layoutWindow then self:BuildLayoutWindow() end
	local frame = self.layoutWindow
	frame.help:SetText(("Paste a layout (Ctrl+V), then Import. It replaces the layout of profile %s."):format(self.db.profileName))
	frame.box:SetText("")
	frame.import:Show()
	frame.reload:Hide()
	frame.result:SetText("")
	frame:Show()
	frame.box:SetFocus()
end

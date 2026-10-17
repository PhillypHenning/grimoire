local Grimoire = Grimoire

-- Reusable classic-style building blocks (ADR 0001).

local CONTENT_TOP, CONTENT_SIDE, CONTENT_BOTTOM = 32, 16, 16

-- A movable dialog-style window with a header title and close button.
-- Closes on Escape. It's a mover (key "<key>Window"), so it can be dragged by its
-- body any time (taking its group along), shows an overlay in move mode, and its
-- position is reset with the other frames.
-- Lay out children inside frame.content; size with frame:SetContentSize(w, h).
-- owner (optional): the module the window belongs to; its menu then offers the
-- window's position options.
function Grimoire:CreateWindow(key, title, owner)
	local frame = CreateFrame("Frame", "Grimoire" .. key .. "Window", UIParent, "BackdropTemplate")
	local moverKey = key .. "Window"
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetBackdrop(self.media.dialogBackdrop)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function() Grimoire:BeginMoverDrag(moverKey) end)
	frame:SetScript("OnDragStop", function() Grimoire:EndMoverDrag() end)

	local header = frame:CreateTexture(nil, "ARTWORK")
	header:SetTexture(self.media.dialogHeader)
	header:SetSize(300, 64)
	header:SetPoint("TOP", 0, 12)
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", header, "TOP", 0, -14)
	frame.title:SetText(title)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)

	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", CONTENT_SIDE, -CONTENT_TOP)
	frame.content:SetPoint("BOTTOMRIGHT", -CONTENT_SIDE, CONTENT_BOTTOM)

	function frame:SetContentSize(width, height)
		self:SetSize(width + CONTENT_SIDE * 2, height + CONTENT_TOP + CONTENT_BOTTOM)
	end

	self:RegisterMover(frame, moverKey, title, { "CENTER", "UIParent", "CENTER", 0, 0 })
	if owner then
		owner.moverKeys[#owner.moverKeys + 1] = moverKey
	end

	tinsert(UISpecialFrames, frame:GetName())
	frame:Hide()
	return frame
end

-- A scroll frame with a scrollbar. Pass `child` to scroll an existing frame
-- (e.g. a multi-line EditBox); otherwise a plain content frame is created.
-- The caller anchors the returned scroll frame; leave ~24px on the right for the bar.
function Grimoire.CreateScrollArea(parent, name, child)
	local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	child = child or CreateFrame("Frame", nil, scroll)
	child:SetParent(scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnSizeChanged", function(_, width)
		child:SetWidth(width)
	end)
	return scroll, child
end

-- A round button in the minimap-button style (ADR 0001): border, background and
-- highlight from the game's own art. Set the picture with button.icon:SetTexture.
-- Every round button has the same size, the profile's buttonSize (Layout ▸ Button size);
-- the art is resized rather than the button scaled, so saved positions don't move.
-- Pass `size` for a button that keeps its own (e.g. the emote wheel's slices).

local BASE_SIZE = 31 -- the art's own size, in Blizzard's minimap-button proportions
Grimoire.roundButtons = {}

local function LayoutRoundButton(button, size)
	local s = size / BASE_SIZE
	button:SetSize(size, size)
	button.background:SetSize(20 * s, 20 * s)
	button.background:SetPoint("TOPLEFT", 7 * s, -5 * s)
	button.icon:SetSize(17 * s, 17 * s)
	button.icon:SetPoint("TOPLEFT", 7 * s, -6 * s)
	button.border:SetSize(53 * s, 53 * s)
end

function Grimoire.CreateRoundButton(name, parent, size)
	local media = Grimoire.media
	local button = CreateFrame("Button", name, parent or UIParent)
	button:SetFrameStrata("MEDIUM")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetHighlightTexture(media.roundButtonHighlight, "ADD")

	button.background = button:CreateTexture(nil, "BACKGROUND")
	button.background:SetTexture(media.roundButtonBackground)

	button.icon = button:CreateTexture(nil, "ARTWORK")

	button.border = button:CreateTexture(nil, "OVERLAY")
	button.border:SetTexture(media.roundButtonBorder)
	button.border:SetPoint("TOPLEFT")

	if size then
		LayoutRoundButton(button, size)
	else
		Grimoire.roundButtons[#Grimoire.roundButtons + 1] = button
		LayoutRoundButton(button, Grimoire.db.profile.buttonSize or 44)
	end
	return button
end

function Grimoire:ApplyRoundButtonSize()
	for _, button in ipairs(self.roundButtons) do
		LayoutRoundButton(button, self.db.profile.buttonSize)
	end
end

-- A component's floating button: a round button that's a mover of its module (drag it in
-- move mode; the menu offers its reset), shown while db[optionKey] is on.
--   opts = { name, icon, title, hint, onClick, default (mover position) }
function Grimoire.CreateModuleButton(module, opts)
	local button = Grimoire.CreateRoundButton(opts.name)
	button.icon:SetTexture(opts.icon)
	button:SetScript("OnClick", opts.onClick)
	button:SetScript("OnEnter", function(b)
		GameTooltip:SetOwner(b, "ANCHOR_LEFT")
		GameTooltip:AddLine(opts.title)
		GameTooltip:AddLine(opts.hint, 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	module:RegisterMover(button, opts.title .. " button", opts.default, { suffix = "Button" })
	return button
end

local function DisplaySlot_OnEnter(slot)
	if slot.link then
		GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(slot.link)
		GameTooltip:Show()
	end
end

local function DisplaySlot_OnClick(slot)
	if slot.link then
		HandleModifiedItemClick(slot.link)
	end
end

-- A read-only item slot for cached data (bank, auctions). Shows the tooltip on
-- hover and supports shift-click linking, but can't use or move the item.
function Grimoire.CreateDisplaySlot(parent)
	local slot = CreateFrame("ItemButton", nil, parent)
	local bg = slot:CreateTexture(nil, "BACKGROUND", nil, -1)
	bg:SetTexture(Grimoire.media.emptySlot)
	bg:SetAllPoints()
	slot:SetScript("OnEnter", DisplaySlot_OnEnter)
	slot:SetScript("OnLeave", GameTooltip_Hide)
	slot:SetScript("OnClick", DisplaySlot_OnClick)
	return slot
end

-- item: a record from Grimoire.ReadContainer, or false/nil for empty.
function Grimoire.SetDisplaySlotItem(slot, item)
	slot.link = item and item.link or nil
	SetItemButtonTexture(slot, item and item.icon or nil)
	SetItemButtonCount(slot, item and item.count or 0)
	SetItemButtonQuality(slot, item and item.quality or nil, slot.link)
end

-- Menus ------------------------------------------------------------------------
-- entries: array of
--   { text = "Title", isTitle = true }
--   { isDivider = true }
--   { text = "Do it", func = fn }
--   { text = "Option", func = fn, checked = fn() -> bool, radio = true? }
--   { text = "More", children = { ...entries } }       -- submenu
-- Any entry may set disabled = true, and tooltip = "text" (shown on hover).
-- anchor nil opens at the cursor. Uses Blizzard's Menu API when the client has it,
-- otherwise UIDropDownMenu. Returns false if neither exists.

local function AddMenuEntries(root, entries)
	for _, e in ipairs(entries) do
		local element
		if e.isTitle then
			root:CreateTitle(e.text)
		elseif e.isDivider then
			root:CreateDivider()
		elseif e.children then
			element = root:CreateButton(e.text)
			AddMenuEntries(element, e.children)
		elseif e.checked and e.radio then
			element = root:CreateRadio(e.text, e.checked, e.func)
		elseif e.checked then
			element = root:CreateCheckbox(e.text, e.checked, e.func)
		else
			element = root:CreateButton(e.text, e.func)
		end
		if element and e.disabled and element.SetEnabled then
			element:SetEnabled(false)
		end
		if element and e.tooltip and element.SetTooltip then
			element:SetTooltip(function(tooltip)
				GameTooltip_SetTitle(tooltip, e.text)
				GameTooltip_AddNormalLine(tooltip, e.tooltip)
			end)
		end
	end
end

local dropdown

local function AddDropDownEntries(entries, level)
	for _, e in ipairs(entries) do
		if e.isDivider then
			if UIDropDownMenu_AddSeparator then
				UIDropDownMenu_AddSeparator(level)
			end
		else
			local info = UIDropDownMenu_CreateInfo()
			info.text = e.text
			info.disabled = e.disabled
			if e.tooltip then
				info.tooltipTitle, info.tooltipText, info.tooltipOnButton = e.text, e.tooltip, true
			end
			if e.isTitle then
				info.isTitle = true
				info.notCheckable = true
			elseif e.children then
				info.hasArrow = true
				info.menuList = e.children
				info.notCheckable = true
				info.keepShownOnClick = true
			else
				info.func = function() e.func() end
				if e.checked then
					info.checked = e.checked()
					info.isNotRadio = not e.radio
				else
					info.notCheckable = true
				end
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end
end

function Grimoire.OpenMenu(anchor, entries)
	if MenuUtil and MenuUtil.CreateContextMenu then
		MenuUtil.CreateContextMenu(anchor or UIParent, function(_, root)
			AddMenuEntries(root, entries)
		end)
		return true
	end

	if not (UIDropDownMenu_Initialize and ToggleDropDownMenu) then
		return false
	end
	dropdown = dropdown or CreateFrame("Frame", "GrimoireDropDownMenu", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(dropdown, function(_, level, menuList)
		AddDropDownEntries((level or 1) > 1 and menuList or entries, level)
	end, "MENU")
	ToggleDropDownMenu(1, nil, dropdown, anchor or "cursor", 0, 0)
	return true
end

-- A button showing the selected character's class-colored name (ADR 0003).
-- Clicking lists every character that has stored `field` data; picking one calls
-- onChange(charKey). Cycles through characters if the client has no menu API.
function Grimoire.CreateCharacterPicker(parent, field, onChange)
	local picker = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	picker:SetSize(170, 22)

	function picker:SetCharacter(charKey)
		self.selected = charKey
		self:SetText(Grimoire:FormatCharacterName(charKey))
		onChange(charKey)
	end

	picker:SetScript("OnClick", function(self)
		local keys = Grimoire:GetCharactersWith(field)
		local entries = {}
		for _, charKey in ipairs(keys) do
			entries[#entries + 1] = {
				text = Grimoire:FormatCharacterName(charKey),
				radio = true,
				checked = function() return self.selected == charKey end,
				func = function() self:SetCharacter(charKey) end,
			}
		end
		if Grimoire.OpenMenu(self, entries) then return end

		local nextIndex = 1
		for i, charKey in ipairs(keys) do
			if charKey == self.selected then
				nextIndex = i % #keys + 1
			end
		end
		self:SetCharacter(keys[nextIndex])
	end)

	return picker
end

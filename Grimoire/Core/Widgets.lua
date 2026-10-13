local Grimoire = Grimoire

-- Reusable classic-style building blocks (ADR 0001).

local CONTENT_TOP, CONTENT_SIDE, CONTENT_BOTTOM = 32, 16, 16

local function SaveWindowPosition(frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	Grimoire.db.profile.windows[frame.windowKey] = { point, relativePoint, x, y }
end

-- A movable dialog-style window with a header title and close button.
-- Closes on Escape and remembers its position per profile.
-- Lay out children inside frame.content; size with frame:SetContentSize(w, h).
function Grimoire:CreateWindow(key, title)
	local frame = CreateFrame("Frame", "Grimoire" .. key .. "Window", UIParent, "BackdropTemplate")
	frame.windowKey = key
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetBackdrop(self.media.dialogBackdrop)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		SaveWindowPosition(f)
	end)

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

	local pos = self.db.profile.windows[key]
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		frame:SetPoint("CENTER")
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

-- A button showing the selected character's class-colored name (ADR 0003).
-- Clicking lists every character that has stored `field` data; picking one calls
-- onChange(charKey). Uses Blizzard's Menu API when present, otherwise cycles.
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
		if MenuUtil and MenuUtil.CreateContextMenu then
			MenuUtil.CreateContextMenu(self, function(_, root)
				for _, charKey in ipairs(keys) do
					root:CreateRadio(Grimoire:FormatCharacterName(charKey),
						function() return self.selected == charKey end,
						function() self:SetCharacter(charKey) end)
				end
			end)
		else
			local nextIndex = 1
			for i, charKey in ipairs(keys) do
				if charKey == self.selected then
					nextIndex = i % #keys + 1
				end
			end
			self:SetCharacter(keys[nextIndex])
		end
	end)

	return picker
end

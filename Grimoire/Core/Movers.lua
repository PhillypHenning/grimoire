local Grimoire = Grimoire

-- Any frame can opt into drag-to-move with RegisterMover. Positions are stored per
-- profile under db.profile.movers[key]. Movers lock automatically when combat
-- starts because protected frames can't be repositioned in combat.
--
-- Groups: movers that share a name in db.profile.moverGroups[key] move together and
-- keep their offsets. In move mode, shift-click overlays to select frames, then
-- right-click one and pick "Group with selected" (or use the Launcher menu).
--
-- Idle dimming: a mover (or a whole group) with "Dim when idle" fades once nothing
-- has changed for profile.idleSeconds. Modules call Grimoire:NotifyMoverActivity(key)
-- whenever their display changes; hovering also counts. Core owns the alpha of
-- every mover frame, so modules must not set it themselves.

Grimoire.movers = {}
Grimoire.moversUnlocked = false
Grimoire.moverSelection = {}

local CLICK_AFTER_DRAG_SECONDS = 0.2
local DIM_CHECK_SECONDS = 0.2
local COLOR_NORMAL = { 0.2, 0.6, 1 }
local COLOR_GROUPED = { 0.2, 0.85, 0.3 }
local COLOR_SELECTED = { 1, 0.82, 0 }

local function Groups()
	return Grimoire.db.profile.moverGroups
end

-- Dragging -----------------------------------------------------------------------
-- The dragged frame moves with StartMoving; other group members follow it every
-- frame by the same offset. Every member's position is saved when the drag ends.

local drag
local dragDriver = CreateFrame("Frame")
dragDriver:Hide()
dragDriver:SetScript("OnUpdate", function()
	local dx = drag.frame:GetLeft() - drag.left
	local dy = drag.frame:GetTop() - drag.top
	for _, other in ipairs(drag.others) do
		other.frame:ClearAllPoints()
		other.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", other.left + dx, other.top + dy)
	end
end)

function Grimoire:BeginMoverDrag(key)
	local mover = self.movers[key]
	if drag or not mover or not mover.frame:GetLeft() then return end

	local others = {}
	for _, k in ipairs(self:GetMoverGroupMembers(key)) do
		local frame = self.movers[k].frame
		if k ~= key and frame:GetLeft() then
			others[#others + 1] = { key = k, frame = frame, left = frame:GetLeft(), top = frame:GetTop() }
		end
	end
	-- Windows can be dragged in combat, but not if that would move a protected frame.
	if InCombatLockdown() then
		if mover.frame:IsProtected() then return end
		for _, other in ipairs(others) do
			if other.frame:IsProtected() then return end
		end
	end

	drag = { key = key, frame = mover.frame, left = mover.frame:GetLeft(), top = mover.frame:GetTop(), others = others }
	mover.frame:StartMoving()
	dragDriver:SetShown(#others > 0)
end

function Grimoire:EndMoverDrag()
	if not drag then return end
	dragDriver:Hide()
	drag.frame:StopMovingOrSizing()
	self:SaveMoverPosition(drag.key)
	for _, other in ipairs(drag.others) do
		self:SaveMoverPosition(other.key)
	end
	drag = nil
	self.lastMoverDrag = GetTime()
end

-- Registration --------------------------------------------------------------------

local function Handle_OnMouseUp(handle, button)
	local key = handle.moverKey
	if Grimoire.lastMoverDrag and GetTime() - Grimoire.lastMoverDrag < CLICK_AFTER_DRAG_SECONDS then return end
	if button == "RightButton" then
		Grimoire.OpenMenu(handle, Grimoire:GetMoverMenu(key))
	elseif IsShiftKeyDown() then
		Grimoire:ToggleMoverSelection(key)
	end
end

local function Handle_OnEnter(handle)
	local key = handle.moverKey
	local group = Groups()[key]
	GameTooltip:SetOwner(handle, "ANCHOR_TOP")
	GameTooltip:AddLine(Grimoire.movers[key].label)
	GameTooltip:AddLine(group and ("Drag: move " .. group) or "Drag: move", 1, 1, 1)
	GameTooltip:AddLine("Shift-click: select for grouping", 1, 1, 1)
	GameTooltip:AddLine("Right-click: options", 1, 1, 1)
	GameTooltip:Show()
end

---@param frame Frame
---@param key string unique, stable id used as the saved-variable key
---@param label string shown on the drag handle
---@param default table { point, relativeTo, relativePoint, x, y }
---@param opts? { dim?: boolean, isBusy?: fun(): boolean } dim: "Dim when idle" starts on;
---  isBusy: while it returns true the frame (and its group) never dims
function Grimoire:RegisterMover(frame, key, label, default, opts)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	local handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	handle.moverKey = key
	handle:SetAllPoints()
	handle:SetFrameLevel(frame:GetFrameLevel() + 20)
	handle:SetBackdrop({ bgFile = self.media.flat, edgeFile = self.media.flat, edgeSize = 1 })
	handle.text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	handle.text:SetPoint("CENTER")
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function() Grimoire:BeginMoverDrag(key) end)
	handle:SetScript("OnDragStop", function() Grimoire:EndMoverDrag() end)
	handle:SetScript("OnMouseUp", Handle_OnMouseUp)
	handle:SetScript("OnEnter", Handle_OnEnter)
	handle:SetScript("OnLeave", GameTooltip_Hide)
	handle:SetShown(self.moversUnlocked)

	self.movers[key] = {
		frame = frame, handle = handle, label = label, default = default,
		isBusy = opts and opts.isBusy, lastActivity = GetTime(),
	}
	local dim = self.db.profile.moverDim
	if dim[key] == nil then
		dim[key] = opts and opts.dim or false
	end
	self:UpdateMoverHandle(key)
	self:ApplyMoverPosition(key)
	self:UpdateMoverDimming()
end

function Grimoire:SaveMoverPosition(key)
	local mover = self.movers[key]
	local point, _, relativePoint, x, y = mover.frame:GetPoint(1)
	self.db.profile.movers[key] = { point, "UIParent", relativePoint, x, y }
end

function Grimoire:ApplyMoverPosition(key)
	local mover = self.movers[key]
	local pos = self.db.profile.movers[key] or mover.default
	self:RunOutOfCombat(function()
		mover.frame:ClearAllPoints()
		mover.frame:SetPoint(pos[1], _G[pos[2]] or UIParent, pos[3], pos[4], pos[5])
	end)
end

-- Changes a mover's scale without moving it on screen. Positions are saved in the frame's
-- own units, so the saved offsets are rescaled with it.
function Grimoire:SetMoverScale(key, scale)
	local mover = self.movers[key]
	if not mover then return end
	local old = mover.frame:GetScale()
	if math.abs(old - scale) < 0.001 then return end
	local pos = self.db.profile.movers[key] or mover.default
	self.db.profile.movers[key] = { pos[1], pos[2], pos[3], pos[4] * old / scale, pos[5] * old / scale }
	mover.frame:SetScale(scale)
	self:ApplyMoverPosition(key)
end

function Grimoire:ResetMover(key)
	if key then
		if not self.movers[key] then return false end
		self.db.profile.movers[key] = nil
		self:ApplyMoverPosition(key)
	else
		for k in pairs(self.movers) do
			self.db.profile.movers[k] = nil
			self:ApplyMoverPosition(k)
		end
	end
	return true
end

function Grimoire:UnlockMovers()
	if InCombatLockdown() then
		self:Print("Can't unlock frames in combat.")
		return
	end
	self.moversUnlocked = true
	for _, mover in pairs(self.movers) do
		mover.handle:Show()
	end
	self:UpdateMoverDimming()
	self:Fire("MoversUnlocked")
end

function Grimoire:LockMovers()
	self.moversUnlocked = false
	wipe(self.moverSelection)
	for key, mover in pairs(self.movers) do
		mover.handle:Hide()
		self:UpdateMoverHandle(key)
	end
	self:NotifyAllMoverActivity()
	self:Fire("MoversLocked")
end

Grimoire:RegisterCallback("CombatStart", Grimoire, function()
	if Grimoire.moversUnlocked then
		Grimoire:LockMovers()
		Grimoire:Print("Frames locked for combat.")
	end
end)

-- Selection and groups -------------------------------------------------------------

function Grimoire:UpdateMoverHandle(key)
	local mover = self.movers[key]
	local group = Groups()[key]
	local color = self.moverSelection[key] and COLOR_SELECTED or group and COLOR_GROUPED or COLOR_NORMAL
	mover.handle:SetBackdropColor(color[1], color[2], color[3], 0.35)
	mover.handle:SetBackdropBorderColor(color[1], color[2], color[3], 0.9)
	mover.handle.text:SetText(group and (mover.label .. " |cffd0d0d0(" .. group .. ")|r") or mover.label)
end

function Grimoire:RefreshMoverHandles()
	for key in pairs(self.movers) do
		self:UpdateMoverHandle(key)
	end
	self:Fire("MoverGroupsChanged")
end

function Grimoire:ToggleMoverSelection(key)
	self.moverSelection[key] = not self.moverSelection[key] or nil
	self:UpdateMoverHandle(key)
end

function Grimoire:ClearMoverSelection()
	wipe(self.moverSelection)
	self:RefreshMoverHandles()
end

function Grimoire:GetSelectedMovers()
	local keys = {}
	for key in pairs(self.moverSelection) do
		keys[#keys + 1] = key
	end
	return keys
end

function Grimoire:GetMoverGroup(key)
	return Groups()[key]
end

-- Registered movers in the same group as key (just key when it isn't grouped).
function Grimoire:GetMoverGroupMembers(key)
	local group = Groups()[key]
	if not group then return { key } end
	local members = {}
	for k in pairs(self.movers) do
		if Groups()[k] == group then
			members[#members + 1] = k
		end
	end
	return members
end

-- A group with one member left isn't a group.
local function DissolveSingletons()
	local groups = Groups()
	local counts = {}
	for _, group in pairs(groups) do
		counts[group] = (counts[group] or 0) + 1
	end
	for key, group in pairs(groups) do
		if counts[group] < 2 then
			groups[key] = nil
		end
	end
end

-- Puts keys, and everything already grouped with any of them, into one new group.
function Grimoire:GroupMovers(keys)
	local groups = Groups()
	local members = {}
	for _, key in ipairs(keys) do
		members[key] = true
		local group = groups[key]
		if group then
			for other, otherGroup in pairs(groups) do
				if otherGroup == group then
					members[other] = true
				end
			end
		end
	end

	local used = {}
	for _, group in pairs(groups) do
		used[group] = true
	end
	local n = 1
	while used["Group " .. n] do
		n = n + 1
	end

	-- The group dims as one: if any member dimmed, they all do.
	local dimAny = false
	for key in pairs(members) do
		dimAny = dimAny or self.db.profile.moverDim[key]
	end
	for key in pairs(members) do
		groups[key] = "Group " .. n
		self.db.profile.moverDim[key] = dimAny
	end
	DissolveSingletons()
	self:ClearMoverSelection()
end

function Grimoire:UngroupMover(key)
	Groups()[key] = nil
	DissolveSingletons()
	self:RefreshMoverHandles()
end

function Grimoire:GetMoverMenu(key)
	local group = Groups()[key]
	local entries = {
		{ text = self.movers[key].label, isTitle = true },
		{
			text = "Selected",
			checked = function() return self.moverSelection[key] ~= nil end,
			func = function() self:ToggleMoverSelection(key) end,
		},
	}
	local selected = self:GetSelectedMovers()
	local othersSelected = #selected - (self.moverSelection[key] and 1 or 0)
	if othersSelected > 0 then
		entries[#entries + 1] = {
			text = "Group with selected",
			func = function()
				selected[#selected + 1] = key
				self:GroupMovers(selected)
			end,
		}
	end
	if group then
		entries[#entries + 1] = { text = "Remove from " .. group, func = function() self:UngroupMover(key) end }
	end
	entries[#entries + 1] = {
		text = group and "Dim group when idle" or "Dim when idle",
		checked = function() return self.db.profile.moverDim[key] end,
		func = function() self:SetMoverDim(key, not self.db.profile.moverDim[key]) end,
	}
	entries[#entries + 1] = { text = "Reset position", func = function() self:ResetMover(key) end }
	return entries
end

-- Idle dimming --------------------------------------------------------------------

function Grimoire:NotifyMoverActivity(key)
	local mover = self.movers[key]
	if not mover then return end
	mover.lastActivity = GetTime()
	if self.db.profile.moverDim[key] then
		self:UpdateMoverDimming()
	end
end

function Grimoire:NotifyAllMoverActivity()
	local now = GetTime()
	for _, mover in pairs(self.movers) do
		mover.lastActivity = now
	end
	self:UpdateMoverDimming()
end

-- Applies to key's whole group.
function Grimoire:SetMoverDim(key, enabled)
	for _, k in ipairs(self:GetMoverGroupMembers(key)) do
		self.db.profile.moverDim[k] = enabled
	end
	self:NotifyAllMoverActivity()
end

-- A group is idle only when every member is: newest activity, any hover, or any
-- member reporting itself busy counts.
local function GroupLastActivity(members)
	local last = 0
	for _, k in ipairs(members) do
		local mover = Grimoire.movers[k]
		if mover.frame:IsVisible() and (mover.frame:IsMouseOver() or (mover.isBusy and mover.isBusy())) then
			return GetTime()
		end
		last = math.max(last, mover.lastActivity)
	end
	return last
end

function Grimoire:UpdateMoverDimming()
	local now = GetTime()
	local dimAlpha = self.db.profile.dimAlpha
	for key, mover in pairs(self.movers) do
		local dimmed = false
		if self.db.profile.moverDim[key] and not self.moversUnlocked then
			dimmed = now - GroupLastActivity(self:GetMoverGroupMembers(key)) > self.db.profile.idleSeconds
		end
		mover.frame:SetAlpha(dimmed and dimAlpha or 1)
	end
end

C_Timer.NewTicker(DIM_CHECK_SECONDS, function()
	if Grimoire.db then
		Grimoire:UpdateMoverDimming()
	end
end)

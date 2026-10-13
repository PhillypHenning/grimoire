local Grimoire = Grimoire

-- Any frame can opt into drag-to-move with RegisterMover. Positions are stored per
-- profile under db.profile.movers[key]. Movers lock automatically when combat
-- starts because protected frames can't be repositioned in combat.

Grimoire.movers = {}
Grimoire.moversUnlocked = false

---@param frame Frame
---@param key string unique, stable id used as the saved-variable key
---@param label string shown on the drag handle
---@param default table { point, relativeTo, relativePoint, x, y }
function Grimoire:RegisterMover(frame, key, label, default)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)

	local handle = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	handle:SetAllPoints()
	handle:SetFrameLevel(frame:GetFrameLevel() + 20)
	handle:SetBackdrop({ bgFile = self.media.flat, edgeFile = self.media.flat, edgeSize = 1 })
	handle:SetBackdropColor(0.2, 0.6, 1, 0.35)
	handle:SetBackdropBorderColor(0.2, 0.6, 1, 0.9)
	handle.text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	handle.text:SetPoint("CENTER")
	handle.text:SetText(label)
	handle:EnableMouse(true)
	handle:RegisterForDrag("LeftButton")
	handle:SetScript("OnDragStart", function()
		if not InCombatLockdown() then
			frame:StartMoving()
		end
	end)
	handle:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		Grimoire:SaveMoverPosition(key)
	end)
	handle:SetShown(self.moversUnlocked)

	self.movers[key] = { frame = frame, handle = handle, label = label, default = default }
	self:ApplyMoverPosition(key)
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
	self:Fire("MoversUnlocked")
end

function Grimoire:LockMovers()
	self.moversUnlocked = false
	for _, mover in pairs(self.movers) do
		mover.handle:Hide()
	end
	self:Fire("MoversLocked")
end

Grimoire:RegisterCallback("CombatStart", Grimoire, function()
	if Grimoire.moversUnlocked then
		Grimoire:LockMovers()
		Grimoire:Print("Frames locked for combat.")
	end
end)

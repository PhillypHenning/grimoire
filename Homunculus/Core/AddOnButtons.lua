local Homunculus = Homunculus

-- Other add-ons' minimap buttons, as menu entries: open each add-on, open its options,
-- or take its button off the minimap. Found at runtime with no dependency:
--   * LibDBIcon-1.0 / LibDataBroker-1.1 launchers (most add-ons: Questie, AtlasLoot,
--     Leatrix, DBM, Details, Spy, ...), via LibStub if any add-on loaded them;
--   * other buttons parented to the minimap, by scanning its children.
-- Which buttons are hidden is saved per profile in profile.addonButtons.

local LibStub = _G.LibStub

local function Libs()
	if not LibStub then return nil, nil end
	return LibStub("LibDBIcon-1.0", true), LibStub("LibDataBroker-1.1", true)
end

local function Settings()
	return Homunculus.db.profile.addonButtons
end

-- Blizzard's own minimap furniture, never listed.
local BLIZZARD_PREFIXES = { "Minimap", "MiniMap", "GameTimeFrame", "TimeManager", "LibDBIcon10_", "QueueStatus", "GarrisonLandingPage" }

local function IsBlizzardName(name)
	for _, prefix in ipairs(BLIZZARD_PREFIXES) do
		if name:sub(1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- Buttons on the minimap that don't come from LibDBIcon.
local function LooseButtons()
	local buttons = {}
	for _, parent in ipairs({ Minimap, MinimapBackdrop }) do
		if parent then
			for _, child in ipairs({ parent:GetChildren() }) do
				local name = child:GetName()
				if name and child:IsObjectType("Button") and not IsBlizzardName(name) and child:GetScript("OnClick") then
					buttons[#buttons + 1] = child
				end
			end
		end
	end
	return buttons
end

-- One record per add-on button: { key, label, icon, frame, click(mouseButton) }.
function Homunculus:GetAddOnButtons()
	local list = {}
	local icon, ldb = Libs()
	if icon and icon.GetButtonList then
		for _, name in ipairs(icon:GetButtonList()) do
			local object = ldb and ldb:GetDataObjectByName(name)
			local frame = icon.GetMinimapButton and icon:GetMinimapButton(name)
			if object and object.OnClick then
				list[#list + 1] = {
					key = "ldb:" .. name,
					label = object.label or name,
					icon = object.icon,
					frame = frame,
					click = function(mouseButton) object.OnClick(frame or UIParent, mouseButton) end,
				}
			end
		end
	end
	for _, button in ipairs(LooseButtons()) do
		local name = button:GetName()
		list[#list + 1] = {
			key = "frame:" .. name,
			label = (name:gsub("MinimapButton$", ""):gsub("Minimap$", ""):gsub("_", " ")),
			frame = button,
			click = function(mouseButton) button:Click(mouseButton) end,
		}
	end
	table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
	return list
end

-- Showing and hiding on the minimap -------------------------------------------------------

local function IsHidden(key)
	local settings = Settings()
	return settings.hideAll or settings.hidden[key] == true
end

local hooked = {}

local function ApplyOne(entry)
	local hide = IsHidden(entry.key)
	local icon = Libs()
	local name = entry.key:match("^ldb:(.+)")
	if name and icon then
		if hide then icon:Hide(name) else icon:Show(name) end
	elseif entry.frame then
		-- Other add-ons may show their own button again; keep it hidden.
		if not hooked[entry.frame] then
			hooked[entry.frame] = true
			hooksecurefunc(entry.frame, "Show", function(f)
				if IsHidden(entry.key) then f:Hide() end
			end)
		end
		entry.frame:SetShown(not hide)
	end
end

function Homunculus:ApplyAddOnButtons()
	for _, entry in ipairs(self:GetAddOnButtons()) do
		ApplyOne(entry)
	end
end

function Homunculus:SetAddOnButtonShown(key, shown)
	Settings().hidden[key] = not shown or nil
	self:ApplyAddOnButtons()
end

function Homunculus:SetAllAddOnButtonsHidden(hidden)
	Settings().hideAll = hidden
	self:ApplyAddOnButtons()
end

-- Menu ------------------------------------------------------------------------------------

-- Entries for an "Add-ons" submenu. Each add-on gets Open, Options and Show on minimap.
function Homunculus:GetAddOnButtonMenu()
	local entries = {}
	for _, entry in ipairs(self:GetAddOnButtons()) do
		local text = entry.icon and ("|T%s:16|t %s"):format(entry.icon, entry.label) or entry.label
		entries[#entries + 1] = {
			text = text,
			children = {
				{ text = entry.label, isTitle = true },
				{ text = "Open", func = function() entry.click("LeftButton") end },
				{ text = "Options", func = function() entry.click("RightButton") end },
				{
					text = "Show on minimap",
					checked = function() return not IsHidden(entry.key) end,
					func = function() self:SetAddOnButtonShown(entry.key, IsHidden(entry.key)) end,
					disabled = Settings().hideAll,
				},
			},
		}
	end
	if #entries == 0 then
		entries[1] = { text = "No add-on buttons found", isTitle = true }
	end
	entries[#entries + 1] = { isDivider = true }
	entries[#entries + 1] = {
		text = "Hide all minimap buttons",
		checked = function() return Settings().hideAll end,
		func = function() self:SetAllAddOnButtonsHidden(not Settings().hideAll) end,
	}
	return entries
end

-- Re-apply once add-ons have created their buttons, and whenever LibDBIcon makes one.
local owner = {}
Homunculus:RegisterCallback("Ready", owner, function()
	C_Timer.After(2, function() Homunculus:ApplyAddOnButtons() end)
	local icon = Libs()
	if icon and icon.RegisterCallback then
		icon.RegisterCallback(owner, "LibDBIcon_IconCreated", function()
			Homunculus:ApplyAddOnButtons()
		end)
	end
end)

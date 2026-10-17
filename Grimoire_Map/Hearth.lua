local ADDON_NAME, ns = ...
local Grimoire = Grimoire

-- Your hearthstone on the world map (Phil, 2026-10-16). The game gives add-ons the name
-- of the place your hearthstone is set to (GetBindLocation), but not where it is, so the
-- spot is saved when you set it: HEARTHSTONE_BOUND fires while you stand at the innkeeper.
-- An inn icon marks it on every map that shows that spot; hovering it names the place
-- and the character (ADR 0003). Until you next set your hearthstone the spot is unknown,
-- and the map shows the place's name in its corner instead.
--
-- Pins come from a pool registered on the map in Lua (no XML template), the way the
-- HereBeDragons library does it for Questie and TomTom on this client.

local PIN = "GrimoireHearthPin"
local PIN_SIZE = 20

local M = Grimoire:NewModule("Hearth", {
	addon = ADDON_NAME,
	label = "Hearthstone on the map",
})

function M:IsAvailable()
	if not (WorldMapFrame and WorldMapFrame.AddDataProvider and WorldMapFrame.pinPools
		and MapCanvasDataProviderMixin and MapCanvasPinMixin and C_Map and C_Map.GetMapPosFromWorldPos) then
		return false, "this client's world map can't take pins"
	end
	return true
end

-- Saving the spot ----------------------------------------------------------------------------

function M:SaveHearth()
	local name = GetBindLocation()
	local hearth = { name = name, time = time() }
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
	if pos then
		local x, y = pos:GetXY()
		if not Grimoire.AnySecret(x, y) and x and y then
			hearth.mapID, hearth.x, hearth.y = mapID, x, y
			local continent, world = C_Map.GetWorldPosFromMapPos(mapID, pos)
			if continent and world then
				hearth.continent, hearth.wx, hearth.wy = continent, world:GetXY()
			end
		end
	end
	ns.Character().hearth = hearth
	self:Refresh()
end

-- The saved hearth, if it's still where the hearthstone is set.
function M:GetHearth()
	local hearth = ns.Character().hearth
	local name = GetBindLocation()
	if hearth and hearth.name == name then return hearth end
	return name and { name = name } or nil -- set before this add-on knew: no spot yet
end

-- Pin ------------------------------------------------------------------------------------------

local PinMixin = {}

function PinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetSize(PIN_SIZE, PIN_SIZE)
	self.icon = self:CreateTexture(nil, "ARTWORK")
	self.icon:SetAllPoints()
	self.icon:SetTexture(Grimoire.media.innIcon)
	self:EnableMouse(true)
	self:SetScript("OnEnter", function(pin)
		GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
		GameTooltip:AddLine(HEARTHSTONE or "Hearthstone")
		GameTooltip:AddLine(pin.hearth.name or "", 1, 1, 1)
		GameTooltip:AddLine(Grimoire:FormatCharacterName())
		GameTooltip:Show()
	end)
	self:SetScript("OnLeave", GameTooltip_Hide)
end

function PinMixin:OnAcquired(x, y, hearth)
	self.hearth = hearth
	self:SetPosition(x, y)
	self:Show()
end

-- From HereBeDragons: avoids an in-combat error when the map passes mouse buttons through.
PinMixin.SetPassThroughButtons = function() end

local function CreatePinPool()
	local mixin = CreateFromMixins(MapCanvasPinMixin, PinMixin)
	local canvas = WorldMapFrame:GetCanvas()
	local pool = CreateUnsecuredRegionPoolInstance and CreateUnsecuredRegionPoolInstance(PIN) or CreateFramePool("FRAME")
	pool.parent = canvas
	pool.createFunc = function()
		local pin = Mixin(CreateFrame("Frame", nil, canvas), mixin)
		pin:OnLoad()
		return pin
	end
	pool.resetFunc = function(_, pin)
		pin:Hide()
		pin:ClearAllPoints()
		pin.pinTemplate, pin.owningMap = nil, nil
	end
	pool.creationFunc, pool.resetterFunc = pool.createFunc, pool.resetFunc -- older clients' names
	WorldMapFrame.pinPools[PIN] = pool
end

-- Where the saved spot is on the open map, or nil if that map doesn't show it.
local function PositionOn(hearth, mapID)
	if not (hearth.continent and hearth.wx and mapID) then return nil end
	local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, hearth.continent, CreateVector2D(hearth.wx, hearth.wy), mapID)
	if not ok or not pos then return nil end
	local x, y = pos:GetXY()
	if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

-- Map ------------------------------------------------------------------------------------------

function M:BuildMap()
	CreatePinPool()
	local provider = CreateFromMixins(MapCanvasDataProviderMixin)
	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(PIN)
	end
	function provider.RefreshAllData(p)
		p:RemoveAllData()
		if M:IsEnabled() then M:AddPin(p:GetMap()) end
	end
	self.provider = provider

	-- Shown when the spot isn't known yet (or isn't on this map's page).
	local label = CreateFrame("Frame", nil, WorldMapFrame)
	label:SetAllPoints(WorldMapFrame.ScrollContainer or WorldMapFrame)
	label:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 20)
	label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label.text:SetPoint("BOTTOMLEFT", 10, 10)
	self.label = label
end

function M:AddPin(map)
	local hearth = self:GetHearth()
	if not hearth then
		self.label:Hide()
		return
	end
	local x, y = PositionOn(hearth, map:GetMapID())
	if x then
		map:AcquirePin(PIN, x, y, hearth)
	end
	local where = hearth.continent and "" or " (set it again at an innkeeper to pin it on the map)"
	self.label.text:SetText(("%s: %s%s"):format(HEARTHSTONE or "Hearthstone", hearth.name, where))
	self.label:Show()
end

function M:Refresh()
	if self.provider and WorldMapFrame:IsShown() then
		self.provider:RefreshAllData()
	end
end

-- Lifecycle ---------------------------------------------------------------------------------------

function M:OnEnable()
	if not self.provider then self:BuildMap() end
	WorldMapFrame:AddDataProvider(self.provider)
	-- Read a moment later, so the new name is in place (you're still by the innkeeper).
	self:RegisterEvent("HEARTHSTONE_BOUND", function()
		C_Timer.After(0.5, function() self:SaveHearth() end)
	end)
	self:Refresh()
end

function M:OnDisable()
	if self.provider then
		WorldMapFrame:RemoveDataProvider(self.provider)
		self.label:Hide()
	end
end

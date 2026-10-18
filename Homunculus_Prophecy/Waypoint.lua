local _, ns = ...
local Homunculus = Homunculus
local M = ns.M

-- The current step as a TomTom waypoint (learned from RestedXP / Guidelime, 2026-10-16):
-- when the next step in your plan has an @coordinate, TomTom's arrow points there, and the
-- waypoint moves on as steps are ticked. TomTom is found at runtime (ADR 0002): without it,
-- or with the "Waypoint arrow (TomTom)" setting off, nothing happens.

-- Zone names to map IDs, built once from the game's own map list (so Forever's new zones
-- are included).
local mapIDs

local function MapID(zone)
	if not mapIDs then
		mapIDs = {}
		local world = 947 -- Azeroth, the classic world map; its zones include every continent's
		local ok, children = pcall(C_Map.GetMapChildrenInfo, world, Enum and Enum.UIMapType and Enum.UIMapType.Zone, true)
		for _, info in ipairs(ok and children or {}) do
			if not mapIDs[info.name] then mapIDs[info.name] = info.mapID end
		end
	end
	return mapIDs[zone]
end

-- The step's text without plan markup, for the arrow's title.
local function PlainText(text)
	return (text:gsub("@[^%s]+", ""):gsub("[%[%]{}]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

function M:ClearWaypoint()
	if self.waypoint and TomTom and TomTom.RemoveWaypoint then
		pcall(TomTom.RemoveWaypoint, TomTom, self.waypoint.uid)
	end
	self.waypoint = nil
end

function M:UpdateWaypoint()
	local tomtom = TomTom and TomTom.AddWaypoint and TomTom
	if not (self:IsEnabled() and self.db.waypoints and tomtom and C_Map and C_Map.GetMapChildrenInfo) then
		self:ClearWaypoint()
		return
	end
	local entry = self:GetUpcoming(1)[1]
	local step = entry and entry.step
	local coord = step and step.coords and step.coords[1]
	local mapID = coord and MapID(coord.zone)
	if not mapID then
		if coord then self:Log("info", "no map found for zone %s; no waypoint", coord.zone) end
		self:ClearWaypoint()
		return
	end
	local key = ("%s:%s:%s"):format(step.id, coord.x, coord.y)
	if self.waypoint and self.waypoint.key == key then return end
	self:ClearWaypoint()
	local ok, uid = pcall(tomtom.AddWaypoint, tomtom, mapID, coord.x / 100, coord.y / 100, {
		title = PlainText(step.text),
		from = "Homunculus Prophecy",
		persistent = false,
		crazy = true, -- point the arrow at it
	})
	if ok and uid then
		self.waypoint = { uid = uid, key = key }
	else
		self:Log("warn", "TomTom refused the waypoint: %s", tostring(uid))
	end
end

local ADDON_NAME, ns = ...
local Homunculus = Homunculus

-- Flight times on the flight map (Phil, 2026-10-16). The game doesn't give flight
-- durations, so they're learned: each flight you take is timed from take-off to landing
-- and saved for that route, account-wide. Hovering a destination on the flight map then
-- shows its time, or "not flown yet". Forever's own new routes are learned the same way.
--
-- Supports the classic flight map (TaxiFrame: TaxiNodeOnButtonEnter, which Leatrix Plus
-- also hooks on this client) and, if this client shows it, the modern one
-- (Blizzard_FlightMap's FlightMap_FlightPointPinMixin).

local POLL_SECONDS = 0.5
local BOARD_TIMEOUT = 20   -- seconds to wait for take-off after choosing a flight
local MIN_FLIGHT = 5       -- shorter "flights" aren't saved
local CUT_SHORT = 0.8      -- a flight under 80% of the known time was cut short: not saved

local M = Homunculus:NewModule("FlightTimes", {
	addon = ADDON_NAME,
	label = "Flight times",
})

-- "Orgrimmar, Durotar" -> "Orgrimmar"
local function NodeName(index)
	local name = TaxiNodeName(index)
	return name and name:match("^[^,]+") or name
end

local function RouteKey(from, to)
	return from .. " > " .. to
end

-- The flight point you're standing at, while the flight map is open.
local function Origin()
	for i = 1, NumTaxiNodes() do
		if TaxiNodeGetType(i) == "CURRENT" then
			return NodeName(i)
		end
	end
end

-- Tooltips -------------------------------------------------------------------------------------

function M:AddTimeToTooltip(index)
	if not self:IsEnabled() or not index or TaxiNodeGetType(index) ~= "REACHABLE" then return end
	local from, to = Origin(), NodeName(index)
	if not from or not to then return end
	local seconds = ns.Store().flights[RouteKey(from, to)]
	if seconds then
		GameTooltip:AddLine(("Flight time: %s"):format(ns.FormatTime(seconds)), 1, 1, 1)
	else
		GameTooltip:AddLine("Flight time: not flown yet", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

function M:HookFlightMaps()
	if self.hooked then return end
	self.hooked = true
	if TaxiNodeOnButtonEnter then
		hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
			self:AddTimeToTooltip(button:GetID())
		end)
	end
	local function HookModern()
		local mixin = FlightMap_FlightPointPinMixin
		if mixin and mixin.OnMouseEnter and not self.hookedModern then
			self.hookedModern = true
			hooksecurefunc(mixin, "OnMouseEnter", function(pin)
				self:AddTimeToTooltip(pin.taxiNodeData and pin.taxiNodeData.slotIndex)
			end)
		end
	end
	HookModern()
	if not self.hookedModern then
		-- Blizzard_FlightMap loads when the flight map is first opened.
		self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_FlightMap" then HookModern() end
		end)
	end

	-- Choosing a flight: remember the route, then wait for take-off.
	hooksecurefunc("TakeTaxiNode", function(index)
		if not self:IsEnabled() then return end
		local from, to = Origin(), NodeName(index)
		if from and to then
			self:StartTiming(from, to)
		end
	end)
	-- Landing early (the "Request early landing" button) would save a wrong time.
	if TaxiRequestEarlyLanding then
		hooksecurefunc("TaxiRequestEarlyLanding", function() self:StopTiming() end)
	end
end

-- Timing ---------------------------------------------------------------------------------------

function M:StartTiming(from, to)
	self:StopTiming()
	local flight = { route = RouteKey(from, to), chosen = GetTime() }
	self.flight = flight
	self.ticker = C_Timer.NewTicker(POLL_SECONDS, function()
		local now = GetTime()
		if not flight.start then
			if UnitOnTaxi("player") then
				flight.start = now
			elseif now - flight.chosen > BOARD_TIMEOUT then
				self:StopTiming()
			end
		elseif not UnitOnTaxi("player") then
			self:StopTiming()
			self:SaveTime(flight.route, now - flight.start)
		end
	end)
end

function M:StopTiming()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	self.flight = nil
end

function M:SaveTime(route, seconds)
	if seconds < MIN_FLIGHT then return end
	local flights = ns.Store().flights
	local known = flights[route]
	if known and seconds < known * CUT_SHORT then
		self:Log("info", "flight %s took %.0f s, under the known %.0f s: not saved", route, seconds, known)
		return
	end
	flights[route] = seconds
	self:Log("info", "flight %s: %.0f s", route, seconds)
end

-- Lifecycle -------------------------------------------------------------------------------------

function M:IsAvailable()
	if not (TakeTaxiNode and TaxiNodeName and UnitOnTaxi) then
		return false, "this client has no flight map functions"
	end
	return true
end

function M:OnEnable()
	self:HookFlightMaps() -- hooks can't be removed; they check IsEnabled()
end

function M:OnDisable()
	self:StopTiming()
end

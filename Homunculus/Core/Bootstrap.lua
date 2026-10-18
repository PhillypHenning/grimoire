local ADDON_NAME = ...
local Homunculus = Homunculus

-- Loaded last: wires the core lifecycle once every core file has defined itself.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, addon)
	if event == "ADDON_LOADED" then
		if addon == ADDON_NAME then
			Homunculus:InitializeDatabase()
		elseif Homunculus.loggedIn then
			-- A plugin loaded after login (on demand or by another add-on).
			Homunculus:InitializeModules()
		end
	elseif event == "PLAYER_LOGIN" then
		Homunculus.loggedIn = true
		Homunculus:RecordCharacter()
		Homunculus:LoadClassAddOns()
		Homunculus:InitializeModules()
		Homunculus:Fire("Ready")
	end
end)

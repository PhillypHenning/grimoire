local ADDON_NAME = ...
local Grimoire = Grimoire

-- Loaded last: wires the core lifecycle once every core file has defined itself.
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, addon)
	if event == "ADDON_LOADED" then
		if addon == ADDON_NAME then
			Grimoire:InitializeDatabase()
		elseif Grimoire.loggedIn then
			-- A plugin loaded after login (on demand or by another add-on).
			Grimoire:InitializeModules()
		end
	elseif event == "PLAYER_LOGIN" then
		Grimoire.loggedIn = true
		Grimoire:RecordCharacter()
		Grimoire:LoadClassAddOns()
		Grimoire:InitializeModules()
		Grimoire:Fire("Ready")
	end
end)

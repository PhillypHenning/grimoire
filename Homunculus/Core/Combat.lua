local Homunculus = Homunculus

-- InCombatLockdown() still returns false inside the PLAYER_REGEN_DISABLED handler,
-- so track combat state ourselves for visibility logic.
Homunculus.inCombat = InCombatLockdown()

local queue = {}

-- Runs fn now, or as soon as combat ends if protected frames are locked.
function Homunculus:RunOutOfCombat(fn)
	if InCombatLockdown() then
		queue[#queue + 1] = fn
	else
		fn()
	end
end

function Homunculus:InCombat()
	return self.inCombat
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		Homunculus.inCombat = true
		Homunculus:Fire("CombatStart")
	else
		Homunculus.inCombat = false
		local pending = queue
		queue = {}
		for _, fn in ipairs(pending) do
			Homunculus.SafeCall(fn)
		end
		Homunculus:Fire("CombatEnd")
	end
end)

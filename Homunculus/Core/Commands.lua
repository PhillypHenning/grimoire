local Homunculus = Homunculus

-- /homunculus <command> [args]. Modules can add their own subcommands with RegisterCommand.

Homunculus.commands = {}
Homunculus.commandOrder = {}

function Homunculus:RegisterCommand(name, usage, fn)
	name = name:lower()
	if not self.commands[name] then
		self.commandOrder[#self.commandOrder + 1] = name
	end
	self.commands[name] = { usage = usage, fn = fn }
end

Homunculus:RegisterCommand("help", "help - list commands", function()
	Homunculus:Print("v" .. Homunculus.version .. " commands:")
	for _, name in ipairs(Homunculus.commandOrder) do
		print("  /homunculus " .. Homunculus.commands[name].usage)
	end
end)

Homunculus:RegisterCommand("unlock", "unlock - show drag handles", function()
	Homunculus:UnlockMovers()
end)

Homunculus:RegisterCommand("lock", "lock - hide drag handles", function()
	Homunculus:LockMovers()
end)

Homunculus:RegisterCommand("reset", "reset [frame] - reset one or all frame positions", function(arg)
	if not Homunculus:ResetMover(arg ~= "" and arg or nil) then
		Homunculus:Print("Unknown frame: " .. arg)
	end
end)

Homunculus:RegisterCommand("modules", "modules - list modules and their state", function()
	for _, name in ipairs(Homunculus.moduleOrder) do
		local module = Homunculus.modules[name]
		local _, reason = module:IsAvailable()
		print(("  %s: %s%s"):format(name, module.state, reason and (" (" .. reason .. ")") or ""))
	end
end)

Homunculus:RegisterCommand("enable", "enable <module>", function(arg)
	local ok, reason = Homunculus:EnableModule(arg)
	Homunculus:Print(ok and ("Enabled " .. arg) or ("Could not enable " .. arg .. ": " .. tostring(reason)))
end)

Homunculus:RegisterCommand("disable", "disable <module>", function(arg)
	local ok, reason = Homunculus:DisableModule(arg)
	Homunculus:Print(ok and ("Disabled " .. arg) or ("Could not disable " .. arg .. ": " .. tostring(reason)))
end)

Homunculus:RegisterCommand("profile", "profile [name] - show or switch profile", function(arg)
	if arg == "" then
		Homunculus:Print("Current profile: " .. Homunculus.db.profileName)
	else
		Homunculus:SetProfile(arg)
	end
end)

SLASH_HOMUNCULUS1 = "/homunculus"
SLASH_HOMUNCULUS2 = "/hom"
SLASH_HOMUNCULUS3 = "/grim" -- the old name (ADR 0010)
SlashCmdList.HOMUNCULUS = function(msg)
	local name, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
	local command = Homunculus.commands[name:lower()] or Homunculus.commands.help
	command.fn(arg)
end

local Grimoire = Grimoire

-- /grimoire <command> [args]. Modules can add their own subcommands with RegisterCommand.

Grimoire.commands = {}
Grimoire.commandOrder = {}

function Grimoire:RegisterCommand(name, usage, fn)
	name = name:lower()
	if not self.commands[name] then
		self.commandOrder[#self.commandOrder + 1] = name
	end
	self.commands[name] = { usage = usage, fn = fn }
end

Grimoire:RegisterCommand("help", "help - list commands", function()
	Grimoire:Print("v" .. Grimoire.version .. " commands:")
	for _, name in ipairs(Grimoire.commandOrder) do
		print("  /grimoire " .. Grimoire.commands[name].usage)
	end
end)

Grimoire:RegisterCommand("unlock", "unlock - show drag handles", function()
	Grimoire:UnlockMovers()
end)

Grimoire:RegisterCommand("lock", "lock - hide drag handles", function()
	Grimoire:LockMovers()
end)

Grimoire:RegisterCommand("reset", "reset [frame] - reset one or all frame positions", function(arg)
	if not Grimoire:ResetMover(arg ~= "" and arg or nil) then
		Grimoire:Print("Unknown frame: " .. arg)
	end
end)

Grimoire:RegisterCommand("modules", "modules - list modules and their state", function()
	for _, name in ipairs(Grimoire.moduleOrder) do
		local module = Grimoire.modules[name]
		local _, reason = module:IsAvailable()
		print(("  %s: %s%s"):format(name, module.state, reason and (" (" .. reason .. ")") or ""))
	end
end)

Grimoire:RegisterCommand("enable", "enable <module>", function(arg)
	local ok, reason = Grimoire:EnableModule(arg)
	Grimoire:Print(ok and ("Enabled " .. arg) or ("Could not enable " .. arg .. ": " .. tostring(reason)))
end)

Grimoire:RegisterCommand("disable", "disable <module>", function(arg)
	local ok, reason = Grimoire:DisableModule(arg)
	Grimoire:Print(ok and ("Disabled " .. arg) or ("Could not disable " .. arg .. ": " .. tostring(reason)))
end)

Grimoire:RegisterCommand("profile", "profile [name] - show or switch profile", function(arg)
	if arg == "" then
		Grimoire:Print("Current profile: " .. Grimoire.db.profileName)
	else
		Grimoire:SetProfile(arg)
	end
end)

SLASH_GRIMOIRE1 = "/grimoire"
SLASH_GRIMOIRE2 = "/grim"
SlashCmdList.GRIMOIRE = function(msg)
	local name, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
	local command = Grimoire.commands[name:lower()] or Grimoire.commands.help
	command.fn(arg)
end

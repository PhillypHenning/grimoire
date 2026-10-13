-- Checks a Prophecy plan file against the format (docs/prophecy/FORMAT.md).
--   lua scripts/prophecy/check.lua <plan file>
-- Prints errors and warnings with line numbers and a summary; exits 1 on errors.

local here = arg[0]:match("^(.*)[/\\]") or "."
local Parser = dofile(here .. "/parser.lua")

local path = arg[1]
if not path then
	io.stderr:write("usage: lua check.lua <plan file>\n")
	os.exit(2)
end
local file = assert(io.open(path, "rb"))
local text = file:read("*a")
file:close()
text = text:gsub("^\239\187\191", "") -- UTF-8 byte order mark

local plan, errors, warnings = Parser.Parse(text)
for _, e in ipairs(errors) do
	print(("%s:%d: error: %s"):format(path, e.line, e.message))
end
for _, w in ipairs(warnings) do
	print(("%s:%d: warning: %s"):format(path, w.line, w.message))
end
if not plan then
	print(("%d error(s), %d warning(s)"):format(#errors, #warnings))
	os.exit(1)
end

local steps, done, quests, coords, gates, manual = 0, 0, 0, 0, 0, 0
for _, chapter in ipairs(plan.chapters) do
	for _, step in ipairs(chapter.steps) do
		steps = steps + 1
		quests = quests + #step.quests
		coords = coords + #step.coords
		if #step.done > 0 then done = done + 1 elseif step.kind ~= "n" then manual = manual + 1 end
	end
	if chapter.gate then gates = gates + 1 end
end
print(("OK: \"%s\": %d chapters, %d steps (%d self-completing, %d manual), %d quest refs, %d coordinates, %d gates; %d warning(s)")
	:format(plan.title, #plan.chapters, steps, done, manual, quests, coords, gates, #warnings))

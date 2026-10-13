# ADR 0006: Prophecy plans are pasted text, stored in saved variables

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

Prophecy turns a plan written outside the game (a levelling route, profession targets, a to-do list) into in-game guidance: the current step, quests on the native tracker, map pins and a pointer. The plans are long (the first one, a Troll Warlock 1–30 guide, is 16 chapters), written by Phil or by agents, and revised often.

Add-ons can't read files or the network at runtime. The ways in are:
- a Lua file shipped inside the add-on folder (needs `/reload`, and a restart for new files);
- the saved-variables file, edited while the game is closed (the game overwrites it on logout);
- text pasted into an edit box in game.

## Decision

1. **Plans are plain text in a documented, line-based format** ([`docs/prophecy/FORMAT.md`](../prophecy/FORMAT.md)), versioned on its first line (`prophecy 1`).
2. **They're pasted into a Prophecy window in game**, validated (errors and warnings with line numbers), and stored in Prophecy's saved variables. They persist across sessions and characters without touching the add-on's files.
3. **Data only.** A plan is never executed as Lua, so pasting one can't run code.
4. **Fallback:** a plan file placed in the add-on's `Plans/` folder (listed in its `.toc`) loads the same text, for plans too large to paste or for development.
5. **Progress is stored separately from the plan**, per character, keyed by chapter id and a hash of each step's main line, so re-importing an edited plan keeps progress on unchanged steps.

## Consequences

- Plans can be written, reviewed and diffed as text, and agents can produce them against a fixed spec.
- The parser has to be strict and helpful: anything outside the format is an error with a line number, not a guess.
- Large plans live in saved variables; tens of kilobytes is fine.
- Quest names are matched by title, so plans work on Forever without verified quest IDs; ambiguous titles take an optional `#id`.

## Alternatives considered

- **Lua tables pasted and run with `loadstring`:** no parser to write, but pasting would run arbitrary code, and Lua syntax is harder to write by hand.
- **JSON:** well specified, but verbose to write by hand and needs a JSON parser in Lua anyway.
- **Only plan files in the add-on folder:** simplest, but every new plan needs a restart and access to the add-on folder.

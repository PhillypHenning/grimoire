# Grimoire: notes for Claude

Phil's personal WoW Forever UI suite. It's just for him, not a public release. He plays a **Warlock**. The goal is to replace as many third-party add-ons as possible with one consistent codebase.

## The game client
- WoW Forever is a **Classic-family client** (it shows as "Classic WoW"). Build 1.60.1 → `## Interface: 16001` in every `.toc`. The client version is in `.build.info` in the World of Warcraft folder; interface = major×10000 + minor×100 + patch. A wrong number shows add-ons as "Incompatible", which can't be overridden.
- Classic-era rules: soul shards are bag items (item 6265), not a power type.
- Forever lacks some Blizzard templates: **no `SecureAuraHeaderTemplate`** (seen 2026-10-13). Check for a template before inheriting from it (`C_XMLUtil.GetTemplateInfo`), and have the module's `IsAvailable` report a missing one.
- CVar names are case-insensitive but must be exact (`groundEffectDist`, not `groundeffectdistance`). `/grim cvars` (Grimoire_Tweaks) dumps every CVar to `SavedVariables\Grimoire_Tweaks.lua`, which you can read directly on this PC.
- Secret values (retail Midnight) probably don't exist here, but guard with `Grimoire.IsSecret` / `AnySecret` anyway.
- Beta ends 2026-10-22; launch is 2026-11-04.

## Dev loop (Windows PC)
- The repo folders are linked into `<game>\Interface\AddOns` with junctions: `scripts\link-addons.ps1 -GameDir <game>`. Re-run it when a new `Grimoire_*` folder appears.
- Lua edits: `/reload`. `.toc` changes, new add-ons or new files: **restart the game**.
- BugGrabber + BugSack catch errors. Saved data: `<game>\WTF\Account\<ACCOUNT>\SavedVariables\Grimoire.lua`.
- Before pushing, run `scripts\check-lua.ps1` (`luac -p` on every file plus a `.toc` file-list check). Lua 5.4 is installed with `winget install DEVCOM.Lua` (luac is in `%LOCALAPPDATA%\Programs\Lua\bin`). This PC has no Python.
- Game folder on this PC: `C:\Program Files (x86)\World of Warcraft\_classic_beta_`; the character is the Warlock "Manflesh" on Classic Beta PvE. Baganator is installed there, and while it's loaded Grimoire Bags turns itself off (declared conflict).

## Architecture rules (see docs/adr)
- **ADR 0001:** classic Blizzard look. All asset paths go through `Grimoire.media`; use Blizzard fonts, colors and icons; no bundled textures.
- **ADR 0002:** every component is its own add-on `Grimoire_<Name>` that depends only on core (`## RequiredDeps: Grimoire`). Components find each other at runtime with `Grimoire:GetModule(name)` + `IsEnabled()`. Shared code goes in core. New add-ons go in `.pkgmeta`.
- **ADR 0003:** any view of per-character data names the character, using class colors (`Grimoire.ClassColorText`, `Grimoire:FormatCharacterName`).
- Modules: `Grimoire:NewModule(name, { addon = ADDON_NAME, label, defaults, options, class, conflicts })`, where `local ADDON_NAME = ...` is at the top of each file. `options` are the settings the in-game menu shows (`toggle` / `choice`); a module applies a change live in `ApplySettings(key)`.
- Movers: `Module:RegisterMover(frame, label, default, { dim, isBusy, suffix })`.
  - **Core owns mover alpha.** Modules report changes with `Grimoire:NotifyMoverActivity(key)` and never call `SetAlpha` on their own frame.
  - Groups move and dim together.
- Protected frames (secure headers, unit buttons) are only created, moved or resized out of combat: use `Grimoire:RunOutOfCombat`.
- Replacing Blizzard UI: `Grimoire:HideBlizzardFrame(frame)` (`/reload` restores it).

## Docs are part of every change
- Every feature has `docs/features/<name>/README.md` (copy `docs/features/TEMPLATE.md`): summary, Mermaid diagrams, code highlights, design decisions, settings, and a `screenshots/` folder.
- Keep `docs/README.md` (index) and `README.md` (layout, commands) current.
- New architectural decisions get a new numbered ADR. Never edit an accepted ADR's decision.

## Current work
See `docs/plans/manager-menu-debug-player-frame.md`. Milestones 1 (manager menu) and 3 (player frame) are done on branch `wip/manager-menu`, waiting for in-game testing. Milestone 4 (pet done; party and target frames to do) and Milestone 2 (Debug) are open; raid frames are in the backlog. Long-term goal: replace Blizzard's UI entirely (ADR 0004).

## Working with Phil
- He tests in game and reports back. Ask for BugSack text, `/grim modules` output, or screenshots rather than guessing.
- He likes the faded classic mana blue `{0, 0, 1}`.
- He wants bars to stay bright in combat or while not full, and dim only when idle.
- Commit and push when a piece of work is ready for him to test.

## Other add-on
`SkillScape` (separate repo, github.com/PhillypHenning/skillscape) plays RuneScape level-up jingles on profession skill-ups. Also interface 16001.

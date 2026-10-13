# Grimoire

My personal, modular UI suite for WoW Forever. The goal is to replace as many third-party add-ons as possible with one consistent codebase that I own and enjoy maintaining.

## Layout

```
Grimoire/              Core: modules, saved variables, windows, movers, combat queue, slash commands
Grimoire_Warlock/      Warlock resource bar (LoadOnDemand, Warlocks only)
Grimoire_Bags/         Combined bag window with search and sort
Grimoire_Bank/         Bank snapshot + viewer
Grimoire_Auctions/     Auction snapshot + viewer
Grimoire_Notes/        Account-wide notes
scripts/               Dev tooling (Windows junction linker)
docs/                  Component docs (summary, diagrams, screenshots) and ADRs
```

Each top-level `Grimoire*` folder is a separate WoW add-on that can be switched on or off in the in-game AddOns list ([ADR 0002](docs/adr/0002-every-component-is-a-toggleable-addon.md)). Every feature gets a doc in `docs/features/` (see [docs/README.md](docs/README.md)). UI follows [ADR 0001: prefer classic-style UI](docs/adr/0001-prefer-classic-style-ui.md).

## Architecture

**Core vs. feature add-ons.** `Grimoire` holds only shared infrastructure. Features live in their own add-on folders so they can be toggled in the in-game AddOns list, and they don't take memory when they aren't needed.

**Class packages load on demand.** Any add-on with `## LoadOnDemand: 1` and `## X-Grimoire-Class: WARLOCK` (a comma-separated list works too) is loaded at login only for those classes.

**Modules.** Every feature is a module:

```lua
local M = Grimoire:NewModule("MyFeature", {
    defaults  = { width = 200 },   -- merged into M.db (per profile)
    class     = "WARLOCK",         -- optional class gate
    conflicts = { "ElvUI" },       -- optional: auto-skip when these add-ons are loaded
})

function M:OnInitialize() end      -- M.db is ready
function M:OnEnable()
    self:RegisterUnitEvent("UNIT_HEALTH", "player", "Update")
    self:RegisterCallback("CombatStart", "Update")
end
function M:OnDisable() end         -- events + callbacks are released automatically
```

**Callback bus.** `Grimoire:Fire(name, ...)` / `Grimoire:RegisterCallback(name, owner, fn)`. Built-in events: `Ready`, `CombatStart`, `CombatEnd`, `MoversUnlocked`, `MoversLocked`, `ModuleEnabled`, `ModuleDisabled`. External add-ons can listen to these through the global `Grimoire`.

**Movers.** `Grimoire:RegisterMover(frame, key, label, defaultPoint)` makes any frame draggable via `/grimoire unlock`. Positions are saved per profile.

**Combat safety.** `Grimoire:RunOutOfCombat(fn)` defers protected-frame changes until combat ends.

**Secret values.** In combat, many values (health, auras, cooldowns…) are opaque "secrets". You can pass them to widgets (`StatusBar:SetValue`, `FontString:SetText`), but you can't compare them or do maths on them. Guard with `Grimoire.IsSecret(v)` / `Grimoire.AnySecret(...)` and fall back to widget-only display. See `Grimoire_Warlock/ResourceBar.lua` for the pattern.

**Saved variables.** `GrimoireDB` holds per-character profiles plus account-wide `global` settings. `/grimoire profile <name>` switches profile (applies after `/reload`).

## Slash commands

`/grimoire` (or `/grim`) lists all commands. Core: `unlock`, `lock`, `reset [frame]`, `modules`, `enable <module>`, `disable <module>`, `profile [name]`. Components add their own: `bags`, `bank`, `auctions`, `notes`.

## Dev setup (Windows)

1. Clone this repo anywhere, e.g. `C:\dev\grimoire`.
2. Link it into the game (no admin needed):
   ```powershell
   .\scripts\link-addons.ps1 -GameDir "C:\Program Files (x86)\World of Warcraft\_forever_"
   ```
   Adjust `-GameDir` to the actual Forever client folder.
3. In game, confirm the interface number with `/dump select(4, GetBuildInfo())` and update `## Interface:` in every `.toc` if it differs from `16001` (Forever 1.60.1). The client version is also in `.build.info` in the World of Warcraft folder: interface = major × 10000 + minor × 100 + patch.
4. Edit, then `/reload` in game to see changes.
5. Recommended: VS Code with the **WoW API** (Ketho) and **Lua** (LuaLS) extensions (prompted via `.vscode/extensions.json`). In game, install **BugGrabber + BugSack** to catch Lua errors.

## Releasing

`.pkgmeta` is set up for the [BigWigs packager](https://github.com/BigWigsMods/packager). It produces one zip containing all add-on folders, ready for CurseForge or Wago via GitHub Actions.

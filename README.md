# Grimoire

My personal, modular UI suite for WoW Forever. The goal is to replace as many third-party add-ons as possible with one consistent codebase that I own and enjoy maintaining.

## Layout

```
Grimoire/              Core: modules, saved variables, windows, movers, manager menu, combat queue, slash commands
Grimoire_Player/       Health and power bars, each movable
Grimoire_Warlock/      Warlock resources: soul shard count (LoadOnDemand, Warlocks only)
Grimoire_Auras/        Buffs and debuffs as separate frames (replaces the default buff frame)
Grimoire_Bags/         Combined bag window with search and sort
Grimoire_Bank/         Bank snapshot + viewer
Grimoire_Auctions/     Auction snapshot + viewer
Grimoire_Notes/        Account-wide notes
Grimoire_Launcher/     Movable Grimoire button: left-click menu, right-click move mode
scripts/               Dev tooling: link-addons.ps1 (junctions), check-lua.ps1 (syntax + .toc check)
docs/                  Component docs (summary, diagrams, screenshots) and ADRs
```

Each top-level `Grimoire*` folder is a separate WoW add-on that can be switched on or off in the in-game AddOns list ([ADR 0002](docs/adr/0002-every-component-is-a-toggleable-addon.md)). Every feature gets a doc in `docs/features/` (see [docs/README.md](docs/README.md)). UI follows [ADR 0001: prefer classic-style UI](docs/adr/0001-prefer-classic-style-ui.md).

## Architecture

**Core vs. feature add-ons.** `Grimoire` holds only shared infrastructure. Features live in their own add-on folders so they can be toggled in the in-game AddOns list, and they don't take memory when they aren't needed.

**Class packages load on demand.** Any add-on with `## LoadOnDemand: 1` and `## X-Grimoire-Class: WARLOCK` (a comma-separated list works too) is loaded at login only for those classes.

**Modules.** Every feature is a module:

```lua
local ADDON_NAME = ...
local M = Grimoire:NewModule("MyFeature", {
    addon     = ADDON_NAME,        -- groups the module under its add-on in the menu
    label     = "My feature",      -- display name
    defaults  = { width = 200 },   -- merged into M.db (per profile)
    options   = {                  -- settings the in-game menu shows (ADR 0005)
        { type = "choice", key = "width", label = "Width", values = { { 200, "200" }, { 260, "260" } } },
    },
    class     = "WARLOCK",         -- optional class gate
    conflicts = { "ElvUI" },       -- optional: auto-skip when these add-ons are loaded
})

function M:OnInitialize() end      -- M.db is ready
function M:OnEnable()
    self:RegisterUnitEvent("UNIT_HEALTH", "player", "Update")
    self:RegisterCallback("CombatStart", "Update")
end
function M:ApplySettings(key) end  -- a menu setting changed; apply it live
function M:OnDisable() end         -- events + callbacks are released automatically
```

**In-game menu.** Left-click the Grimoire button (or `/grim menu`) to open windows, toggle move mode, turn components and modules on or off, change their settings, and reload. It's built from what's installed and what each module declares; see [docs/features/menu](docs/features/menu/README.md).

**Callback bus.** `Grimoire:Fire(name, ...)` / `Grimoire:RegisterCallback(name, owner, fn)`. Built-in events: `Ready`, `CombatStart`, `CombatEnd`, `MoversUnlocked`, `MoversLocked`, `ModuleEnabled`, `ModuleDisabled`, `PositionsReset`. External add-ons can listen to these through the global `Grimoire`.

**Movers.** `Grimoire:RegisterMover(frame, key, label, defaultPoint)` makes any frame draggable in move mode (right-click the Grimoire button, or `/grimoire unlock`). Windows from `Grimoire:CreateWindow` are movers automatically. In move mode, shift-click frames and right-click → *Group with selected* to move them together; *Dim when idle* fades a frame or group after `idleSeconds` (1.5s by default; Layout menu) without changes, unless a member reports itself busy. Positions, groups and dimming are saved per profile.

**Combat safety.** `Grimoire:RunOutOfCombat(fn)` defers protected-frame changes until combat ends.

**Secret values.** In combat, many values (health, auras, cooldowns…) are opaque "secrets". You can pass them to widgets (`StatusBar:SetValue`, `FontString:SetText`), but you can't compare them or do maths on them. Guard with `Grimoire.IsSecret(v)` / `Grimoire.AnySecret(...)` and fall back to widget-only display. See `Grimoire_Warlock/ResourceBar.lua` for the pattern.

**Saved variables.** `GrimoireDB` holds per-character profiles plus account-wide `global` settings. `/grimoire profile <name>` switches profile (applies after `/reload`).

## Slash commands

`/grimoire` (or `/grim`) lists all commands. Core: `menu`, `unlock`, `lock`, `reset [frame]`, `modules`, `enable <module>`, `disable <module>`, `profile [name]`. Components add their own: `bags`, `bank`, `auctions`, `notes`, `icon`.

## Dev setup (Windows)

1. Clone this repo anywhere, e.g. `C:\dev\grimoire`.
2. Link it into the game (no admin needed):
   ```powershell
   .\scripts\link-addons.ps1 -GameDir "C:\Program Files (x86)\World of Warcraft\_forever_"
   ```
   Adjust `-GameDir` to the actual Forever client folder.
3. In game, confirm the interface number with `/dump select(4, GetBuildInfo())` and update `## Interface:` in every `.toc` if it differs from `16001` (Forever 1.60.1). The client version is also in `.build.info` in the World of Warcraft folder: interface = major × 10000 + minor × 100 + patch.
4. Edit, then `/reload` in game to see changes.
5. Before pushing, check syntax and `.toc` file lists (needs Lua once: `winget install DEVCOM.Lua`):
   ```powershell
   .\scripts\check-lua.ps1
   ```
6. Recommended: VS Code with the **WoW API** (Ketho) and **Lua** (LuaLS) extensions (prompted via `.vscode/extensions.json`). In game, install **BugGrabber + BugSack** to catch Lua errors.

## Releasing

`.pkgmeta` is set up for the [BigWigs packager](https://github.com/BigWigsMods/packager). It produces one zip containing all add-on folders, ready for CurseForge or Wago via GitHub Actions.

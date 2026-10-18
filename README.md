# Homunculus

My personal, modular UI suite for WoW Forever. The goal is to replace as many third-party add-ons as possible with one consistent codebase that I own and enjoy maintaining.

## Layout

```
Homunculus/                Core: modules, saved variables, windows, movers, manager menu, combat queue, slash commands
Homunculus_Player/         Player frame (animated portrait, replaces Blizzard's) and health/power bars, each movable
Homunculus_Pet/            Pet frame and pet health/power bars, shown while you have a pet
Homunculus_Party/          Classic party frames in one movable frame, with target keybind badges
Homunculus_Target/         Classic target frame with auras and target of target, in one movable frame
Homunculus_Warlock/        Warlock resources: soul shard count (LoadOnDemand, Warlocks only)
Homunculus_Auras/          Makes the default buff frame movable, groupable and sizable
Homunculus_Bags/           Combined bag window with search and sort
Homunculus_Bank/           Bank snapshot + viewer
Homunculus_Auctions/       Auction snapshot + viewer
Homunculus_Grimoire/       Grimoire: account-wide notes with locations, item and quest links; optional floating button
Homunculus_Launcher/       Movable Homunculus button: left-click menu, right-click move mode
Homunculus_Tweaks/         Game settings Blizzard's menu lacks (graphics CVars); /hom cvars dump
Homunculus_Prophecy/       Levelling plans pasted in from outside the game: plan viewer, step panel; /prophecy
Homunculus_Tempo/          Learns your best rotation (opener and cycle) from your fights; save and share them; /hom tempo
Homunculus_Emotes/         Emote wheel: hold a key, point at an emote, let go; /hom emotes
Homunculus_Debug/          Log window (every Lua error, Homunculus events), environment report, saved on /reload; /hom debug
Homunculus_Map/            Your hearthstone on the world map; flight times on the flight map
scripts/                   Dev tooling: link-addons.ps1 (junctions), migrate-to-homunculus.ps1 (one-time rename of saved data, ADR 0010), check-lua.ps1 (syntax + .toc check), prophecy/ (plan checker and bundler; the parser is Homunculus_Prophecy/Parser.lua), tempo/test.lua (Tempo analysis tests), core/test.lua (serializer tests), bags/test.lua (bag search tests)
docs/                      Component docs (summary, diagrams, screenshots) and ADRs
```

Each top-level `Homunculus*` folder is a separate WoW add-on that can be switched on or off in the in-game AddOns list ([ADR 0002](docs/adr/0002-every-component-is-a-toggleable-addon.md)). Every feature gets a doc in `docs/features/` (see [docs/README.md](docs/README.md)). UI follows [ADR 0001: prefer classic-style UI](docs/adr/0001-prefer-classic-style-ui.md).

## Architecture

**Core vs. feature add-ons.** `Homunculus` holds only shared infrastructure. Features live in their own add-on folders so they can be toggled in the in-game AddOns list, and they don't take memory when they aren't needed.

**Class packages load on demand.** Any add-on with `## LoadOnDemand: 1` and `## X-Homunculus-Class: WARLOCK` (a comma-separated list works too) is loaded at login only for those classes.

**Modules.** Every feature is a module:

```lua
local ADDON_NAME = ...
local M = Homunculus:NewModule("MyFeature", {
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

**In-game menu.** Left-click the Homunculus button (or `/hom menu`) to open windows, toggle move mode, turn components and modules on or off, change their settings, and reload. It's built from what's installed and what each module declares; see [docs/features/menu](docs/features/menu/README.md).

**Callback bus.** `Homunculus:Fire(name, ...)` / `Homunculus:RegisterCallback(name, owner, fn)`. Built-in events: `Ready`, `CombatStart`, `CombatEnd`, `MoversUnlocked`, `MoversLocked`, `ModuleEnabled`, `ModuleDisabled`, `PositionsReset`. External add-ons can listen to these through the global `Homunculus`.

**Movers.** `Homunculus:RegisterMover(frame, key, label, defaultPoint)` makes any frame draggable in move mode (right-click the Homunculus button, or `/homunculus unlock`). Windows from `Homunculus:CreateWindow` are movers automatically. In move mode, shift-click frames and right-click → *Group with selected* to move them together; *Dim when idle* fades a frame or group after `idleSeconds` (1.5s by default; Layout menu) without changes, unless a member reports itself busy. Positions, groups and dimming are saved per profile.

**Combat safety.** `Homunculus:RunOutOfCombat(fn)` defers protected-frame changes until combat ends.

**Secret values.** In combat, many values (health, auras, cooldowns…) are opaque "secrets". You can pass them to widgets (`StatusBar:SetValue`, `FontString:SetText`), but you can't compare them or do maths on them. Guard with `Homunculus.IsSecret(v)` / `Homunculus.AnySecret(...)` and fall back to widget-only display. See `Homunculus_Warlock/ResourceBar.lua` for the pattern.

**Saved variables.** `HomunculusDB` holds per-character profiles plus account-wide `global` settings. `/homunculus profile <name>` switches profile (applies after `/reload`).

## Slash commands

`/homunculus` (or `/hom`; the old `/grim` still works) lists all commands. Core: `menu`, `unlock`, `lock`, `reset [frame]`, `modules`, `enable <module>`, `disable <module>`, `profile [name]`. Components add their own: `bags`, `bank`, `auctions [shopping]`, `grimoire` (or `notes`), `icon`, `cvars`, `tempo [probe|import]`, `emotes`, `debug [report]`, `prophecy [import]` (also `/prophecy`).

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

**Coming from the Grimoire name** ([ADR 0010](docs/adr/0010-rename-to-homunculus.md)): close the game and run `.\scripts\migrate-to-homunculus.ps1 -GameDir <game>` once. It renames your saved data, the AddOns.txt entries and the emote wheel key binding, swaps the old add-on links for new ones, and keeps the old files as `*.grimoire-backup`.
6. Recommended: VS Code with the **WoW API** (Ketho) and **Lua** (LuaLS) extensions (prompted via `.vscode/extensions.json`). In game, install **BugGrabber + BugSack** to catch Lua errors.

## Releasing

`.pkgmeta` is set up for the [BigWigs packager](https://github.com/BigWigsMods/packager). It produces one zip containing all add-on folders, ready for CurseForge or Wago via GitHub Actions.

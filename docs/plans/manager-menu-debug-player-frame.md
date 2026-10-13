# Grimoire: manager menu, Debug component, player, pet, party and target frames

> **Progress (2026-10-13, on the PC):**
> - **Milestone 1:** code and docs done on branch `wip/manager-menu`; every `.lua` passes `scripts/check-lua.ps1`. Waiting on the in-game checks below, then merge.
>   - **Found in game:** Forever has no `SecureAuraHeaderTemplate`, so Grimoire Auras failed on login. Buffs and Debuffs now report themselves unavailable and Blizzard's buff frame stays. Phil chose to move Blizzard's own buff frame: Grimoire Auras now reparents `BuffFrame` / `TemporaryEnchantFrame` (and `DebuffFrame` where it exists) to Grimoire movers, with a Size setting.
>   - **Added (Phil's request):** `Grimoire_Tweaks` with a `Graphics` module (his `/console` graphics settings as menu choices, reapplied at login, undoable) and `/grim cvars` to dump every CVar for finding more.
>   - Fixed while finishing: the launcher kept its on-screen spot when its size changes (offsets are converted for the new scale); settings changed while a module is off apply when it's turned back on; unknown option types are skipped.
> - **Extra, done:** Health/Power never dim in combat or while not full (`isBusy` option on `RegisterMover`).
> - **Milestone 3:** code and docs done (2026-10-13), done before Milestone 2 at Phil's request. Changes from the plan below: left-click opens a micro-menu (Character Info … Game Menu + Grimoire) instead of targeting; the portrait is an animated 3D model by default (Classic 2D as a setting) and plays emotes (cheer on level-up, laugh or cry on death, wave when someone joins the party or the pet appears); the pet frame is kept when Blizzard's player frame is hidden; the default "Player" group was dropped after Phil tried it. ADR 0004 written. Waiting on in-game testing.
> - **Milestone 2:** not started.
> - **Milestone 4** (pet, party, target frames): code and docs done (2026-10-13). `Grimoire_Pet`, `Grimoire_Party`, `Grimoire_Target`, shared helpers in `Core/UnitFrames.lua`. Changed from the plan: Blizzard's classic party and target art is used directly; the existing unit-frame modules were kept and small shared helpers added beside them (no widget/module split needed); the target frame got auras (Phil hadn't answered; the recommended option) and Grimoire's own target of target (Blizzard's stops updating once its target frame is hidden). Waiting on in-game testing; target layout numbers to tune from a screenshot.
> - **Milestone 4b** (add-on buttons in the portrait menu): code and docs done (2026-10-13), `Core/AddOnButtons.lua`. Waiting on in-game testing.
> - **Order agreed 2026-10-13:** Milestone 4 (party, target), then 4b (add-on buttons in the portrait menu), then 5 (Prophecy). Prophecy format v1 is on `main`.
> - **Backlog:** action bars, map and quests, raid frames.

## Context
You're testing Grimoire on the PC and have hit these:
- Nothing makes Notes discoverable.
- The Grimoire button is too small.
- You want to manage every component from inside the game, not with slash commands.
- You can't see the Health/Mana bars or a Notes button.
- You'd like debugging to be easier.
- You answered "yes": Grimoire should hide Blizzard's player frame, and Grimoire should build the parts of it that are still missing (portrait, name, level, click menu).

Your choices:
- **Manager:** a nested pop-up menu. Settings are on/off toggles or a pick from preset values.
- **Grimoire button:** left-click opens the menu, right-click toggles move mode.
- ~~**Default group:** the new player frame, Health, Mana and Warlock Resources start in one "Player" group.~~ Dropped after testing: no automatic grouping.

I can't run the game, so the work ships in three milestones. Each is pushed separately and you test it before I start the next.

## Step 0: find out why the bars and Notes are missing (you, now)
Health/Mana live in the new `Grimoire_Player` add-on. They only appear if you ran `link-addons.ps1` again and fully restarted the game. Notes are reachable today only through `/grim notes` or the Grimoire button's right-click menu. Please send me:
1. Whether **Grimoire Player** and **Grimoire Auras** appear (and are ticked) in the AddOns list.
2. The output of `/grim modules`.
3. Anything BugSack caught.

Milestone 1 also answers this inside the game: the menu shows every component's status (loaded, not installed, turned off, Warlock-only) and lets you turn it on.

---

## Milestone 1: manager menu, bigger button, settings for every component

### Core: submenus in `Grimoire.OpenMenu` (`Grimoire/Core/Widgets.lua`)
- An entry can have `children = { ... }`, which opens a submenu.
  - With Blizzard's Menu API (MenuUtil): `local sub = root:CreateButton(text)`, then fill `sub` from `children`, recursively.
  - With the older UIDropDownMenu: `info.hasArrow = true` and `info.menuList = children`. The init function reads `menuList` for levels deeper than 1.
- `{ isTitle }`, `{ isDivider }`, checkbox and radio entries work at every level.
- The character picker keeps working unchanged.

### Core: what modules tell core about themselves (`Grimoire/Core/Modules.lua`)
- `NewModule(name, opts)` gains these options:
  - `addon`: the add-on folder the module came from. Each component file passes `local ADDON_NAME = ...`.
  - `label`: the display name.
  - `options`: the list of settings the menu shows (format below).
- New `Module:RegisterMover(frame, label, default, opts)`. It wraps `Grimoire:RegisterMover` and records the mover key in `module.moverKeys`. The key is `module.name`, or `module.name .. suffix` when a module has more than one frame.
  - Existing callers move to the wrapper: the Bars, Resources and Auras modules.
  - `CreateWindow` tags its windows with their owning module.
- Setting format:
  - `{ type = "toggle", key, label }`
  - `{ type = "choice", key, label, values = { {value, label}, ... } }`
  - Either one can add `reload = true`, meaning the change only takes effect after a `/reload`.
- New `Grimoire:SetModuleSetting(module, key, value)`:
  1. Writes the value to `module.db`.
  2. Calls `module:ApplySettings(key)` if the module has it.
  3. Prints "Type /reload to apply" for `reload = true` settings.
  4. Logs the change (the log comes in Milestone 2; until then the call does nothing).

### Core: the menu builder (new `Grimoire/Core/Menu.lua`, added to `Grimoire.toc`)
`Grimoire:GetMainMenu()` returns the menu below. The Grimoire button uses it, and `/grim menu` opens it at the cursor.
- **Open ▸**: every enabled module that has a `Toggle` method (Bags, Notes, Bank, Auctions).
- **✓ Move frames**
- **Components ▸** lists each `Grimoire_*` add-on found through `C_AddOns`, using its `.toc` title.
  - **Loaded add-on ▸**
    - "✓ Enabled in AddOns list" (uses `C_AddOns.DisableAddOn`, then says a reload is needed)
    - Then one submenu per module (or the module's entries directly, if the add-on has only one module):
      - ✓ Enabled (`EnableModule` / `DisableModule`; shows the reason if the module isn't available)
      - The module's own `options`
      - For each of the module's movers: ✓ Dim when idle, Reset position, and Remove from group (if grouped)
      - **Debug ▸** (only when the Debug component is loaded; Milestone 2)
  - **Add-on that isn't loaded**: the label shows the status ("turned off", "Warlock only", "missing", or the load error). It gets an "Enable (needs reload)" entry.
- **Layout ▸**:
  - Dim strength (0.2 / 0.4 / 0.6)
  - Idle time (1 / 1.5 / 3 s)
  - Reset all positions
  - Group selected / Clear selection (only while frames are selected)
- **Reload UI**: calls `ReloadUI()`. It works because it runs from a click.
- Dim strength and idle time become profile settings. `IDLE_SECONDS` in `Core/Movers.lua` turns into `profile.idleSeconds`.

### Grimoire button (`Grimoire_Launcher/Launcher.lua`)
- **Left-click** opens `Grimoire:GetMainMenu()`. **Right-click** toggles move mode. Dragging still moves the button.
- The tooltip is updated to match.
- New `scale` setting, default 1.4 (choices 1.0 / 1.25 / 1.4 / 1.75). It's applied with `button:SetScale`. `ResetPositions` stays as it is.
- The old move/reset/group items move out of this file into the core menu.

### Notes discoverability
- ~~Notes button in the Bags toolbar~~ (changed 2026-10-13, your call): Notes is separate from Bags. It has its own **floating round button** (shared `Grimoire.CreateRoundButton`, a normal mover), shown by default and turned off with *Components ▸ Notes ▸ Show Notes button*.
- **Open ▸ Notes** in the main menu.

### Settings and live updates per component
Each component gets an `options` list and `ApplySettings`:

| Module | Settings | How it applies |
| --- | --- | --- |
| Health / Power (`Grimoire_Player/Bars.lua`) | Show %; width 180/220/260/300; height 10/12/16/20 | Resize the frame, then `Update()` |
| WarlockResources | Icon size 20/26/32 | Resize the icon and frame |
| Buffs / Debuffs | Per row 8/12/16/20; rows 1/2/3 | Change the header attributes and holder size, deferred with `RunOutOfCombat` |
| Bags | Columns 8/10/12/14 | Clear `layoutSignature`, then `Layout()` |
| Launcher | Scale | `SetScale` |
| Notes | Show Notes button | Build or hide the button |
| Bank, Auctions | Only Enabled for now | — |

---

## Milestone 2: Debug component

### Core logging (new `Grimoire/Core/Log.lua`, loaded right after `Init.lua`)
- `Grimoire:Log(source, level, fmt, ...)` and `Module:Log(level, fmt, ...)`.
  - Levels: error, warn, info, debug.
  - Entries go into a memory buffer of the last 500, each with time, source and message.
  - The level to keep is set per component in `GrimoireDB.global.logLevels`. The default is `info`.
- Core writes log entries for:
  - Errors caught by `SafeCall`, `Fire` and `Module:Call`, tagged with the module name.
  - Module state changes, and why a module wasn't available.
  - Events `RegisterEvent` skipped because this client doesn't have them.
  - Blizzard frames hidden by `HideBlizzardFrame`.
  - Grouping and ungrouping.
  - Setting changes.
  - Old-API fallbacks: auctions (legacy owner list), bank layout, menu API.
- Logging costs almost nothing when entries are below the level being kept.

### `Grimoire_Debug` add-on (new; `## SavedVariables: GrimoireDebugDB`)
- **Log window**, built on `CreateWindow`:
  - A read-only multi-line text box. Click it, then Ctrl+A and Ctrl+C to copy it and paste it to me.
  - A filter for which component to show, using `OpenMenu`.
  - Clear button.
- **Environment report**, a copyable block with:
  - Client build and interface number, locale, class and level.
  - Grimoire version.
  - Every `Grimoire_*` add-on's state, and every module's state and the reason for it.
  - Frame positions and groups.
  - Which old-API fallbacks are active.
- **Saved to disk**: the log is copied into `GrimoireDebugDB` on `PLAYER_LOGOUT`, which also happens on `/reload`. That puts it in `WTF\Account\<ACCOUNT>\SavedVariables\Grimoire_Debug.lua`, so you can send me the file.
- **Menus**:
  - Top-level **Debug ▸**: Show log, Environment report, Log everything (debug level), Clear log.
  - In each component's submenu, **Debug ▸**: Log level (off / info / debug) and Show log for this component.
  - Core adds these entries only when the Debug module is enabled, looked up with `GetModule` (ADR 0002).
- `/grim debug` opens the log.

---

## Milestone 3: player frame, hiding Blizzard's, default "Player" group

### `PlayerFrame` module (new `Grimoire_Player/Unit.lua`, added to `Grimoire_Player.toc`)
- **A secure unit button** (`SecureUnitButtonTemplate`, unit `player`), created out of combat:
  - **Left-click** ~~targets you~~ opens a menu of the micro-menu panels plus Grimoire (changed at Phil's request).
  - **Right-click** opens Blizzard's player menu. It uses `type2 = "togglemenu"` if the client supports it. Otherwise it uses the menu function to open `PlayerFrameDropDown`. Which one works is checked in game, and the choice is written to the log.
- **What it shows:**
  - Round portrait (`SetPortraitTexture`; refreshes on `UNIT_PORTRAIT_UPDATE`).
  - Name in your class colour (`Grimoire.ClassColorText`, ADR 0003).
  - Level (refreshes on `PLAYER_LEVEL_UP`).
  - Status icons:
    - Resting (`PLAYER_UPDATE_RESTING`)
    - In combat (core `CombatStart` / `CombatEnd`)
    - Group leader (`GROUP_ROSTER_UPDATE` / `PARTY_LEADER_CHANGED`)
    - PvP flag (`UNIT_FACTION`)
  - Classic look: classic backdrop, Blizzard fonts, Blizzard's status icon textures, all through `Grimoire.media`.
- **Settings:**
  - Hide Blizzard player frame (default on). Uses `Grimoire:HideBlizzardFrame(PlayerFrame)`. Turning it off asks for a `/reload`.
  - Show portrait.
- Its own mover. Because it's protected, it can't be dragged in combat; `BeginMoverDrag` already blocks that.

### ~~Default group~~ (dropped 2026-10-13)
Phil didn't want frames grouped automatically. The code was removed, and `Core/Database.lua` ungroups the "Player" group once for profiles that already got it. The original plan, for reference:
- `RegisterMover` gains a `defaultGroup` option.
  - The first time a frame registers in a profile, it joins that group. This is tracked in `profile.moverDefaultsApplied[key]`, so it happens once.
  - It's skipped if you've already grouped that frame yourself.
- PlayerFrame, Health, Power and WarlockResources each pass `defaultGroup = "Player"`. No component depends on another (ADR 0002).
- Default positions stack neatly: player frame on top, then health, then mana, then shards. Positions you've already saved stay where they are.

---

## Milestone 4: pet, party and target frames

Everything here follows ADR 0004: Blizzard's frame is hidden by default, with a "Hide Blizzard …" toggle that needs a `/reload` to turn off.

**"Locked together" (Phil's request):** a party or target frame is **one mover**. Its portraits and bars are children laid out inside it, not separate movers, so move mode shows a single overlay and nothing can be split off. This isn't a mover group (those are user-made and can be broken up); it's one frame.

### 1. Pet frame: done (`Grimoire_Pet`, 2026-10-13)
- `PetFrame` (animated portrait, 48 px; left-click targets, right-click pet menu), `PetHealth`, `PetPower`.
- Shown only while you have a pet, and always in move mode. Hides Blizzard's `PetFrame`.
- Built on core's unit frames (`Core/UnitFrames.lua`). See `docs/features/pet/`.

### Core: unit frame building blocks (`Grimoire/Core/UnitFrames.lua`)
Today `NewUnitBar` / `NewUnitPortrait` make whole modules, one mover each. Party and target frames need the same pieces *inside* one frame. So, split them:
- `Grimoire.CreateUnitPortrait(parent, unit, opts)` and `Grimoire.CreateUnitBar(parent, unit, kind, opts)` build the widgets, with their update methods and events.
- `NewUnitBar` / `NewUnitPortrait` become thin module wrappers around them. Player and Pet behave exactly as now.
- New widget pieces:
  - Classic round 2D portrait (gold ring, like Blizzard's party and target frames), alongside the existing square 3D/2D box.
  - Level coloured by difficulty (`GetQuestDifficultyColor` / `GetDifficultyColor`).
  - Keybinding badge (below).
  - Out-of-range dimming per child frame (`UnitInRange`), which is separate from mover dimming. Core still owns the mover's alpha; this sets the child's.

### 2. Party frames (new add-on `Grimoire_Party`, module `Party`)
- **One mover, "Party":** up to four member frames stacked inside it, top to bottom in party order (`party1`–`party4`).
  - Each member: classic round portrait, name (class colour, ADR 0003), level, health and power bars, a leader icon, and a dead/ghost/offline state.
  - Can't be split: the members aren't movers.
- **Secure:** each member is a `SecureUnitButtonTemplate` button (`unit = partyN`, left-click target, right-click unit menu) shown with `RegisterUnitWatch`.
  - This uses no `SecureGroupHeaderTemplate`, because Forever may be missing it (it ships in the same file as the `SecureAuraHeaderTemplate` it doesn't have).
  - Party units fill in order, so slots 1..n are always the shown ones.
- **Keybinding badge (Phil's request):** each portrait shows the key bound to its target command, in small text over the portrait.
  - Bindings: `TARGETPARTYMEMBER1`–`4` via `GetBindingKey`, shortened with `GetBindingText(key, "KEY_ABBR_")` or similar (e.g. "F2", "S-2").
  - Refreshes on `UPDATE_BINDINGS`. Nothing is shown when the command isn't bound.
- **Move mode:** shows four placeholder members so the frame can be placed when you're not in a party.
- **Hides** Blizzard's `PartyMemberFrame1`–`4` (Classic) or `PartyFrame` (newer clients); setting "Hide Blizzard party frames".
- **Settings:** Size (portrait 32/40/48), Show bars' % (toggle), Spacing (compact/normal), Show in raid (toggle, default off; until raid frames exist), Hide Blizzard party frames.

### 3. Target frame (new add-on `Grimoire_Target`, module `Target`)
- **One mover, "Target":** classic round portrait, name, level (difficulty colour; "??" for skull), and health and power bars, all locked together inside it.
  - Elite/rare dragon border (Blizzard's `UI-TargetingFrame-Elite` / `-Rare` art, ADR 0001), and the PvP icon.
- **Secure:** `SecureUnitButtonTemplate`, `unit = target`, shown with `RegisterUnitWatch`.
  - Left-click: target (no-op on itself; kept for consistency). Right-click: unit menu.
- **Updates** on `PLAYER_TARGET_CHANGED`, plus `UNIT_*` events for `target`.
  - Health % for mobs, which is what Classic gives. Values are only shown where the client provides them.
- **Move mode:** a placeholder target so it can be placed with nothing targeted.
- **Hides** Blizzard's `TargetFrame`. Its children are moved out first (ADR 0004 rule 4): `ComboFrame` on Classic, and the target-of-target frame if present.
- **Settings:** Size (portrait 48/64/80), Show %, Hide Blizzard target frame.
- **Open question for Phil:** Blizzard's target frame shows the target's debuffs (your DoTs). Hiding it loses them. Either:
  - (a) add target auras to Grimoire's target frame (display only; your own debuffs larger, Classic-style), or
  - (b) keep Blizzard's target auras visible some other way.

  Recommended: (a). Needed before this ships for a Warlock.

### Docs
- New feature docs `docs/features/party/` and `docs/features/target/` (TEMPLATE.md, diagrams, screenshots folder).
- Core doc (unit-frame building blocks), docs index, README layout, ADR 0002 diagram, `.pkgmeta` (`Grimoire_Party`, `Grimoire_Target`).

### Files
- **Core:** `Grimoire/Core/UnitFrames.lua` (split into widgets + module wrappers), `Grimoire/Core/Util.lua` (ring and elite/rare art in `Grimoire.media`)
- **New add-ons:** `Grimoire_Party/` (`.toc`, `Party.lua`), `Grimoire_Target/` (`.toc`, `Target.lua`)
- **Re-run** `scripts/link-addons.ps1` for both new folders.

---

## Milestone 4b: add-on buttons in the portrait menu
After Milestone 4, before Prophecy (Phil, 2026-10-13).
- The player portrait's left-click menu gets **Add-ons ▸**: one entry per add-on with a minimap button.
- Each entry has a submenu:
  - **Open:** the add-on's left-click action.
  - **Options:** its right-click action, if it has one.
  - **✓ Show on minimap:** turn that minimap button off.
- **Found at runtime, no dependency:**
  - LibDBIcon-1.0 / LibDataBroker launchers via `LibStub(name, true)`; most add-ons register this way (Questie, AtlasLoot, Leatrix, DBM, Details, Spy).
  - Other buttons: scan the minimap's child buttons and call their click handlers.
- **Settings:** which buttons are hidden from the minimap (saved per profile); "Hide all minimap buttons" toggle.

## Milestone 5: Prophecy
A plan written outside the game, pasted into WoW, drives the native quest tracker, map and pointer.
- **Format:** [`docs/prophecy/FORMAT.md`](../prophecy/FORMAT.md) (version 1, on `main`). Decision: [ADR 0006](../adr/0006-prophecy-plans-are-pasted-text.md).
- **First plan:** the Troll Warlock 1–30 guide (claude.ai artifact), converted by sub-agents against the format spec.
- **Phases:**
  - **5a: import and view.**
    - `Grimoire_Prophecy` add-on with an import window: paste, validate (errors and warnings with line numbers), save to `GrimoireProphecyDB`.
    - Plan list and plan viewer; current-step panel with manual ticking.
    - Fallback: plan files in `Grimoire_Prophecy/Plans/`.
  - **5b: completion.**
    - `done` conditions and gates evaluate from game events: quest log changes and turn-ins, level, skills, bags, spells, position, zone.
    - Soft and hard profession targets read live.
  - **5c: tracker, map, pointer.**
    - The current step's quests go on the native watch list, with a "Next:" line attached to the tracker.
    - Map and minimap pins.
    - Pointer: the native waypoint if Forever has one, else TomTom (late-bound), else our own arrow.
    - Phil's `/dump` checks decide the map and pointer routes.
  - **5d: feedback loop.**
    - Progress and recorded spots (`/prophecy here`) saved where Claude can read them on this PC, to plan the next session.

---

## Backlog
Not scheduled. Pull an item into a milestone when it's wanted.
- **Action bars** (Phil, 2026-10-13: little value over Blizzard's for now). Feasible: secure action buttons on Blizzard's templates, state-driver paging, hover-to-bind; replacing the main bar also means XP/rep bar, bag buttons and pet bar.
- **Map and quests** (Phil, 2026-10-13: left to Questie, Leatrix Maps and TomTom). Only their minimap buttons get Grimoire control (Milestone 4b).
- **Raid frames** (Phil, 2026-10-13): a compact grid for up to 40, built on the same unit-frame building blocks as party frames.
  - Locked together like the party frame.
  - Hides Blizzard's raid frames (`CompactRaidFrameManager` / `CompactRaidFrameContainer`).
  - Decide with Phil: health-only tiles vs. portraits, sort by group or role, debuff highlighting for dispels.

---

## Docs (updated in each milestone)
- **ADR 0004**: components replace the Blizzard UI they duplicate. Hidden by default, a per-component toggle, and `/reload` to restore.
- **ADR 0005**: modules describe their settings; core turns those descriptions into the menu.
- **New feature docs**: `docs/features/menu/`, `debug/`, `player-frame/`. Each follows TEMPLATE.md, with diagrams and a screenshots folder.
- **Updated**: core (Menu.lua, Log.lua, `SetModuleSetting`, submenus, default groups), launcher (click changes, scale), player-bars, auras, notes (floating button), README layout and commands, `docs/README.md` index, ADR 0002 diagram, `.pkgmeta` (`Grimoire_Debug`), `.luarc.json` globals.

## Files
- **Core:**
  - New: `Grimoire/Core/Menu.lua`, `Grimoire/Core/Log.lua`
  - Edited: `Grimoire/Grimoire.toc`, `Grimoire/Core/Widgets.lua`, `Grimoire/Core/Modules.lua`, `Grimoire/Core/Movers.lua`, `Grimoire/Core/Init.lua` (defaults), `Grimoire/Core/Util.lua` (status-icon media)
- **Components:**
  - `Grimoire_Launcher/Launcher.lua`
  - `Grimoire_Player/Bars.lua`, `Grimoire_Player/Unit.lua` (new), `Grimoire_Player/Grimoire_Player.toc`
  - `Grimoire_Warlock/Resources.lua`
  - `Grimoire_Auras/Auras.lua`
  - `Grimoire_Bags/Bags.lua`
  - Notes, Bank, Auctions: only the `addon` and `label` options
- **New add-on:** `Grimoire_Debug/` (`.toc`, `Debug.lua`)
- **Reused, not rewritten:** `Grimoire.OpenMenu`, `CreateWindow`, `RegisterMover` and `BeginMoverDrag`'s combat check, `HideBlizzardFrame`, `RunOutOfCombat`, `ClassColorText`, `GetModule`, and `IsEnabled` for late-bound links between components.

## Verification
- **Before each push:** run `scripts/check-lua.ps1` (every `.lua` through `luac -p`, and each `.toc` file list against the disk). Lua is installed on the PC (`winget install DEVCOM.Lua`).
- **In game, Milestone 1:**
  - The button is bigger.
  - Left-click shows the menu; right-click toggles move mode.
  - Open ▸ Notes works.
  - Components ▸ lists all 13 add-ons (Tweaks, Pet, Party and Target are new), with the right status for any that aren't loaded.
  - Toggling Show % or Width changes the bar right away.
  - Disabling and re-enabling Health hides and shows it.
  - The floating Notes button appears, opens Notes, can be dragged in move mode, and hides with *Show Notes button* off.
  - Reload UI works.
- **In game, Milestone 2:**
  - Debug ▸ Show log lists module start-up entries.
  - Turning an add-on off shows up in the log.
  - The environment report can be copied.
  - After `/reload`, `Grimoire_Debug.lua` exists in SavedVariables.
- **In game, Milestone 3:**
  - Blizzard's player frame is gone; Grimoire's shows portrait, name and level.
  - Left-click opens the panel menu (Character Info … Game Menu all open); right-click opens the player menu.
  - The 3D portrait animates; it cheers on level-up, laughs or cries on death, waves when a party member or pet appears.
  - The pet frame is still there after Blizzard's player frame is hidden.
  - Resting and combat icons work.
  - Each frame drags on its own (no automatic grouping); a group you make yourself drags as one.
  - Dragging is blocked in combat.
  - Turning off "Hide Blizzard player frame" plus `/reload` brings Blizzard's frame back.
- **In game, Milestone 4:**
  - **Pet:** summon and dismiss: the pet frame and bars appear and disappear, in combat too. Right-click opens the pet menu.
  - **Party:**
    - In a party, members fill the slots in order; leaving shrinks the list.
    - Move mode shows one "Party" overlay, and members can't be dragged apart.
    - Each portrait shows its binding (F2–F5 by default), and it updates after rebinding.
    - Out-of-range members dim.
    - Blizzard's party frames are gone.
  - **Target:**
    - Targeting shows the frame; clearing the target hides it.
    - Elite and rare borders appear.
    - Portrait and bars move as one.
    - Combo points (other classes) and target-of-target aren't lost.
    - Blizzard's target frame is gone.
    - Target debuffs, as decided.
- Each milestone is its own commit and push; you `git pull`, re-link if there's a new add-on, and restart.

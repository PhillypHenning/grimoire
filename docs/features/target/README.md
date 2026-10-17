# Target frame

- **Add-on:** `Grimoire_Target` ([`Target.lua`](../../../Grimoire_Target/Target.lua))
- **Module:** `Target`
- **Status:** Scaffolded, untested in game (redesigned 2026-10-13 to match the player frame)
- **Replaces:** Blizzard's target frame and target-of-target frame; unit-frame add-ons' target frame

## Summary

Your target in Grimoire's own style, matching the player frame:
- The name above the bars, in the target's reaction colour (class colour for players), with "(Elite)", "(Rare)" or "(Boss)" after it.
- Bordered health and power bars.
- A square portrait box, animated 3D by default or classic 2D, with the level in its corner coloured by difficulty ("??" for skull level), plus the raid marker and PvP badge.

It's mirrored (bars left, portrait right), so it faces your player frame. Below it are the target's buffs and debuffs, your own debuffs (your DoTs) larger and with timers; beside it, a compact target of target. It all sits in one movable "Target" frame, so the parts move together and can't be split up. Left-click targets, right-click opens the target's menu.

## What it solves

```mermaid
flowchart LR
    B[Blizzard target frame:<br/>a different style from the rest of Grimoire] ==> G[One movable Target frame<br/>in the player frame's style, with DoTs and target of target]
```

## How it works

```mermaid
flowchart TD
    subgraph Mover["GrimoireTargetFrame (one mover)"]
        T["target: SecureUnitButton<br/>name · health/power boxes · portrait box (model or 2D) · level"]
        B[Buffs above the name, 20 px]
        D[Debuffs under the bars, 24 px<br/>your own 30 px]
        ToT[targettarget: SecureUnitButton<br/>name + health box]
    end
    PTC[PLAYER_TARGET_CHANGED] --> RA[RefreshAll]
    UE[UNIT_HEALTH / POWER … target] --> Bars[UpdateBars]
    UA[UNIT_AURA target] --> Auras[UpdateAuras]
    TK[Ticker, 0.2 s, while shown] --> ToTU[UpdateTargetOfTarget]
    UW[RegisterUnitWatch] --> T & ToT
```

## Code highlights

**Events before Blizzard** ([`Target.lua`](../../../Grimoire_Target/Target.lua)). `OnEnable` registers every event first and hides Blizzard's frame last. On Forever, hiding Blizzard's frame once hit a forbidden call, and because it ran first, the frame never registered its events and stayed on its "Target" placeholder.

**Same pieces as the player frame**: bars in classic bordered boxes, the portrait in a `PlayerModel` (or `SetPortraitTexture`), and the shared helpers `UpdateUnitBar`, `UnitLevelText`, `SetUnitRightClickMenu` from [`Core/UnitFrames.lua`](../../../Grimoire/Core/UnitFrames.lua).

**Auras are display only.** Plain buttons with icon, stack count, debuff-type border and a cooldown swipe; hovering shows the aura's tooltip. Buffs sit above the name in 20 px rows that grow upward; debuffs sit under the bars in 24 px rows that grow downward, and debuffs you or your pet cast are 30 px (Phil, 2026-10-17: enemy debuffs were hard to see). Rows are as wide as the bars.

**Reading auras without tripping secrets.** Forever refuses `GetAuraDataByIndex` on the target while its auras are secret ("Auras cannot be accessed when secret", seen 2026-10-13); the error stopped the whole aura row, so no debuffs showed. `GetAuras` now tries `C_UnitAuras.GetUnitAuras`, then `GetAuraSlots` + `GetAuraDataBySlot`, then by index, then the old `UnitAura`, each call in `pcall`; an empty answer moves on to the next method too (Phil saw no auras at all once, with nothing in the error log), and the module logs which method answered whenever that changes. Fields that may be secret only go to widgets; your own debuffs are found with the `HARMFUL|PLAYER` filter instead of comparing the (secret) caster.

**Target of target is polled.** No event fires when the target's target changes, so it refreshes every 0.2 s while it's shown.

## Design decisions

- **Grimoire style, not Blizzard's classic art** (Phil, 2026-10-13): the first version used Blizzard's classic target texture, which looked too much like the stock frame. It now shares the player frame's look.
- **Mirrored layout**: portrait on the right, facing the player frame. Default position: right of the screen centre, level with the player frame's.
- **Target auras included** (needed for a Warlock): hiding Blizzard's target frame would otherwise lose your DoTs.
- **Grimoire's own target of target**: Blizzard's is inside its target frame and goes with it.
- **Tagged mobs** (tapped by someone else) get a grey health bar.
- **Hidden in place** ([ADR 0007](../../adr/0007-hide-blizzard-frames-in-place.md)): Blizzard's frame isn't reparented, so Edit Mode stays untainted.

## Combat & secret-value constraints

- The target and target-of-target buttons are protected: built and laid out out of combat; they show and hide with their units in combat through unit watches.
- Forever hides real health values (secret values), so the bars show the value the client gives instead of a percentage; secret aura durations use `C_UnitAuras.GetAuraDuration` + `SetCooldownFromDurationObject` where the client has them (no swipe otherwise), secret stack counts use `GetAuraApplicationDisplayCount`, and a secret debuff type gets the default border; a secret level is shown as given.

## Settings

Stored in `GrimoireDB.profiles[<profile>].modules.Target`. In the menu: **Components ▸ Target**.

| Key | Default | Menu choices | Description |
| --- | --- | --- | --- |
| `style` | `animated` | Animated (3D) / Classic (2D) | Portrait type |
| `size` | 64 | Small 48 / Medium 64 / Large 80 | Portrait size |
| `showText` | true | toggle | Values on the bars |
| `showAuras` | true | toggle | Buffs above the frame, debuffs under it |
| `showTargetOfTarget` | true | toggle | The target-of-target frame |
| `hideBlizzard` | true | toggle (needs `/reload` to turn off) | Hide Blizzard's target frame |

## Screenshots

_TODO: add to `screenshots/`. Suggested: an elite with your DoTs, target of target, move mode._

## Open questions / roadmap

- Show health as a percentage when the client hides the real value (retail's percentage API, if Forever has it).
- Cast bar on the target frame.
- Restyle the party frames the same way?

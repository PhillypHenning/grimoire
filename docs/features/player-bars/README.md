# Player and pet bars

- **Add-on:** `Grimoire_Player`
- **Modules:** `Health`, `Power`, `PetHealth`, `PetPower`
- **Status:** Scaffolded, untested in game
- **Replaces:** Player and pet health/mana bar add-ons

## Summary

A health bar and a power bar (mana, or rage/energy for other classes), each its own movable frame, plus a smaller pair for your pet. Pet bars show only while you have a pet (and always in move mode). Put them under your character, group them so they move together, and let them dim when nothing's changing.

## What it solves

```mermaid
flowchart LR
    D[Health + mana: player frame,<br/>top-left corner] ==> G[Two bars wherever you look,<br/>bright while changing, dim at rest]
```

## How it works

```mermaid
flowchart LR
    H[UNIT_HEALTH / UNIT_MAXHEALTH] --> HU[Health:Update]
    P[UNIT_POWER_FREQUENT / UNIT_MAXPOWER] --> PU[Power:Update]
    DP[UNIT_DISPLAYPOWER<br/>druid forms] --> PC[recolor] --> PU
    HU & PU --> SV[SetValues: StatusBar + %]
    SV -- value changed --> N[Grimoire:NotifyMoverActivity] --> Dim[core idle dimming]
```

## Code highlights

**One bar, four modules** ([`Bars.lua`](../../../Grimoire_Player/Bars.lua)). The bar code is shared; a `Health` or `Power` kind and a unit (`player` or `pet`) make each module. They are separate modules, so each can be toggled (`/grim disable PetPower`) and moved on its own.

**Activity only on real changes.** A bar that's regenerating reports activity every tick and stays bright; a full bar stops reporting and dims after the idle time (1.5s by default):

```lua
elseif current ~= self.lastCurrent or max ~= self.lastMax then
    self.lastCurrent, self.lastMax = current, max
    Grimoire:NotifyMoverActivity(self.name)
end
```

**Never dim in combat or while not full.** The bars pass an `isBusy` check to their mover. While it returns true, core treats the bar (and its whole group) as active:

```lua
function Bar:IsBusy()
    if Grimoire:InCombat() or not self.lastCurrent then
        return true -- in combat, or the value is secret
    end
    return self.lastCurrent < self.lastMax
end
```

**Live settings.** Changing width, height or *Show %* in the menu calls `ApplySettings`, which resizes the frame and redraws the text straight away.

## Design decisions

- **Classic colors** ([ADR 0001](../../adr/0001-prefer-classic-style-ui.md)): pure green health, `{0, 0, 1}` mana blue (kept as a setting, `manaColor`). Other power types use Blizzard's `PowerBarColor`.
- **Health 16px, power 12px**, in the classic player frame's order.
- **Dim when idle is on by default** for both, but a bar only dims when it's full, out of combat and unchanged for the idle time. You want them bright whenever they matter.
- **Blizzard's player frame is replaced** by the [player frame](../player-frame/README.md) (portrait, name, level, menus), which hides it. The bars are its health and mana.

## Combat & secret-value constraints

If combat makes values opaque, the bar still fills, the raw value shows instead of a percentage, and every update counts as activity. Neither frame is protected.

## Settings

Stored in `GrimoireDB.profiles[<profile>].modules.Health` / `.Power`. In the menu: **Components ▸ Player ▸ Health / Power (mana)**. Position, group and dimming are mover settings (see [Core](../core/README.md)).

| Key | Default | Menu choices | Description |
| --- | --- | --- | --- |
| `showText` | true | toggle | Show % on the bar |
| `width` | 220 | 180 / 220 / 260 / 300 | Bar width |
| `height` | 16 (Health), 12 (Power) | Health 12 / 16 / 20 / 24; Power 8 / 10 / 12 / 16 | Bar height |
| `manaColor` | `{0, 0, 1}` | — | Power only: mana color |

Pet bars: `.modules.PetHealth` / `.PetPower`. In the menu: **Components ▸ Player ▸ Pet health / Pet power**. They default to under the player bars, beside the pet frame.

| Key | Default | Menu choices | Description |
| --- | --- | --- | --- |
| `showText` | true (Pet health), false (Pet power) | toggle | Show % on the bar |
| `width` | 150 | 120 / 150 / 180 / 220 | Bar width |
| `height` | 12 (Pet health), 8 (Pet power) | Pet health 8 / 10 / 12 / 16; Pet power 6 / 8 / 10 / 12 | Bar height |
| `manaColor` | `{0, 0, 1}` | — | Pet power only: mana color (other pets use Blizzard's power colours) |

## Screenshots

_TODO: add to `screenshots/`. Suggested: changing (bright), idle (dim), grouped in move mode._

## Open questions / roadmap

- Target and pet bars on the same code.

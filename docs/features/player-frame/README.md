# Player frame

- **Add-on:** `Grimoire_Player` ([`Portrait.lua`](../../../Grimoire_Player/Portrait.lua))
- **Module:** `PlayerFrame`
- **Status:** Scaffolded, untested in game
- **Replaces:** Blizzard's player frame (portrait, name, level, health and mana bars); unit-frame add-ons' player frame

## Summary

A movable portrait of your character, animated in 3D by default, with your name in class colour, your level, and status icons (resting, in combat, group leader, PvP). It cheers when you level up, laughs or cries when you die, and waves when someone joins your party or your pet appears. Left-click it for a menu of every game panel (Character Info through Game Menu) plus the Grimoire menu; right-click for Blizzard's player menu. Blizzard's player frame is hidden ([ADR 0004](../../adr/0004-components-replace-blizzard-ui.md)); health and mana are the separate [Health/Power bars](../player-bars/README.md).

## What it solves

```mermaid
flowchart LR
    B[Blizzard player frame:<br/>fixed top-left] ==> G[Grimoire: a movable portrait<br/>beside the movable bars]
    M[Micro menu buttons<br/>bottom-right] ==> C[Same panels from<br/>a left-click on your portrait]
```

## How it works

```mermaid
flowchart TD
    subgraph Frame[GrimoirePlayerFrame: SecureUnitButton, unit = player]
        Model[PlayerModel, 3D] -.or.- Tex[SetPortraitTexture, 2D]
        Overlay[name · level · rest/combat · leader · PvP]
    end
    L[Left-click] --> Hook[OnClick hook] --> Menu["OpenMenu: micro-menu panels + Grimoire ▸"]
    R[Right-click] --> Secure["type2 = togglemenu<br/>(or menu → PlayerFrameDropDown)"]
    LU[PLAYER_LEVEL_UP] --> Cheer[cheer]
    PD[PLAYER_DEAD] --> LC[laugh or cry]
    GR[GROUP_ROSTER_UPDATE: more members] --> Wave[wave]
    UP[UNIT_PET: pet appeared] --> Wave
    Cheer & LC & Wave --> Stand[back to standing:<br/>OnAnimFinished or 3 s]
```

## Code highlights

**A secure button with an insecure left-click** ([`Portrait.lua`](../../../Grimoire_Player/Portrait.lua)). Right-click goes through Blizzard's secure unit menu, so it works in combat. Left-click has no secure action; a hook opens Grimoire's menu:

```lua
frame:SetAttribute("type2", "togglemenu")
frame:HookScript("OnClick", function(b, mouseButton)
    if mouseButton == "LeftButton" then
        Grimoire.OpenMenu(b, self:GetClickMenu())
    end
end)
```

**The click menu follows the micro menu.** Each entry appears only if that micro button exists and is shown (so Talents appears at level 10, Guild only on clients that have it). It calls the panel's toggle function, falling back to clicking the micro button. It checks `IsShown`, not `IsVisible`, so the menu keeps working after the micro menu itself is hidden.

**Emotes are model animations.** `PlayerModel:SetAnimation` with the emote animation IDs: wave 67, cheer 68, laugh 70, cry 77. The model returns to standing on `OnAnimFinished`, or after 3 seconds on clients without it.

**The pet frame survives.** On Classic, `PetFrame` is a child of `PlayerFrame`, so hiding one would hide both. It's moved to `UIParent` at the same spot first.

## Design decisions

- **Left-click is a menu, not "target yourself"** (your call). F1 still targets you. Right-click stays Blizzard's player menu.
- **Animated by default** (your call). A 3D model can't be clipped to a circle, so the frame is a square with the classic tooltip border, matching the bars. *Classic (2D)* shows the flat portrait in the same box.
- **Emotes only on the 3D portrait,** and they can be turned off.
- **Blizzard's player frame is hidden by default** ([ADR 0004](../../adr/0004-components-replace-blizzard-ui.md)). Turning *Hide Blizzard player frame* off needs a `/reload`.
- **Classic look** ([ADR 0001](../../adr/0001-prefer-classic-style-ui.md)): Blizzard's status icons (`UI-StateIcon`, leader crown, PvP badges), fonts and border.

## Combat & secret-value constraints

- The frame is protected: it's created, resized and moved only out of combat (`RunOutOfCombat`); a group containing it can't be dragged in combat.
- Right-click works in combat (secure). Left-click menu entries open Blizzard panels from add-on code, which some clients block in combat for some panels.
- The frame never dims in combat (`isBusy`).

## Settings

Stored in `GrimoireDB.profiles[<profile>].modules.PlayerFrame`. In the menu: **Components ▸ Player ▸ Player frame**.

| Key | Default | Menu choices | Description |
| --- | --- | --- | --- |
| `style` | `animated` | Animated (3D) / Classic (2D) | Portrait type |
| `size` | 64 | Small 48 / Medium 64 / Large 80 | Portrait size |
| `showName` | true | toggle | Name above the portrait, in class colour |
| `emotes` | true | toggle | Cheer, laugh/cry, wave |
| `hideBlizzard` | true | toggle (needs `/reload` to turn off) | Hide Blizzard's player frame |

## Screenshots

_TODO: add to `screenshots/`. Suggested: the frame next to the bars, the click menu, an emote mid-animation._

## Open questions / roadmap

- Verify in game: `togglemenu` vs. the dropdown player menu on Forever; `OnAnimFinished` on `PlayerModel`; the emote animation IDs; the pet frame's position after hiding.
- A Grimoire pet frame (then the Blizzard one can go too).
- More emotes? (e.g. flex on a killing blow, dance when resting.)

# ADR 0007: Hide Blizzard frames in place, without reparenting

- **Status:** Accepted
- **Date:** 2026-10-13
- **Supersedes:** the "reparent to a hidden frame" method in [ADR 0004](0004-components-replace-blizzard-ui.md) decision 1. The rest of ADR 0004 (hidden by default, a toggle per component, `/reload` restores) stands.

## Context

ADR 0004 hid replaced Blizzard frames by unregistering their events and parenting them to a hidden Grimoire frame. Testing on Forever (2026-10-13) showed that Forever runs Blizzard's retail UI code on classic data: Edit Mode, compact party frames, secret values. With the player frame reparented:

- Edit Mode's `RefreshTargetAndFocus` was blocked calling `TargetUnit()` (`ADDON_ACTION_FORBIDDEN`, "tainted by Grimoire_Player").
- Blizzard's own status bars and compact party frames failed comparing secret values "while execution tainted by Grimoire_Player".

Edit Mode reads its frames' parents and anchors. Finding an add-on frame there makes its code insecure, and secure actions and secret-value comparisons then fail.

## Decision

`Grimoire:HideBlizzardFrame(frame)`, run out of combat:

1. Unregisters the events of the frame **and every frame inside it**: a frame's bars register their own events and would keep updating hidden.
2. Stops Blizzard's unit watch on it (`UnregisterUnitWatch`), so Blizzard doesn't show it for a unit.
3. Hides it with a secure state driver (`RegisterStateDriver(frame, "visibility", "hide")`), which keeps it hidden, in combat too.
4. **Never changes its parent or anchors.**

Components also stop moving Blizzard frames out of a frame they hide (the old pet-frame rescue). Where Grimoire replaces the frame, its own version takes over (Grimoire Pet for the pet frame).

## Consequences

- Edit Mode keeps reading Blizzard's own parents and anchors, so it stays untainted.
- Anything inside a hidden frame goes with it. On the retail UI that includes class resource bars that live in the player frame; components replacing the player frame must replace those they need. For Phil's Warlock that's soul shards, already provided by Grimoire Warlock.
- Moving Blizzard frames (Grimoire Auras reparents the buff frame) has the same risk and is reviewed separately. On Forever, Edit Mode can move the buff frame natively.

## Alternatives considered

- **Keep reparenting and fix taint case by case:** each Edit Mode refresh path would need its own workaround, and secret values make tainted Blizzard code fail outright rather than misbehave quietly.
- **Only `SetAlpha(0)` and disable the mouse:** the frame keeps running its code and events, which wastes work and keeps Blizzard's code paths live.

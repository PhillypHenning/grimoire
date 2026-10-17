# ADR 0008: Borrow Blizzard's target aura icons

- **Status:** Accepted
- **Date:** 2026-10-17
- **Amends:** [ADR 0007](0007-hide-blizzard-frames-in-place.md) for Blizzard's target frame only. Every other frame is still hidden as ADR 0007 decides.

## Context

Phil saw no buffs or debuffs on Grimoire's target frame. The debug log (2026-10-17) showed why: out of combat the aura APIs answer with empty lists, and in combat Forever refuses every one of them to add-on code:

> `GetUnitAuras(): Auras cannot be accessed when secret while tainted by 'Grimoire_Target'` (the same for `GetAuraSlots` and `GetAuraDataByIndex`)

Only Blizzard's own, untainted code may read an enemy's auras in combat. A Warlock needs to see their DoTs on the target, and ADR 0007's hiding (events unregistered, frame hidden) stops Blizzard's target frame from showing them anywhere.

## Decision

With "Hide Blizzard target frame" on, Grimoire Target:

1. **Leaves Blizzard's target frame running**: its events, unit watch and aura code stay live.
2. Makes it **invisible and click-through**: `SetAlpha(0)` (kept at 0 by a post-hook on `SetAlpha`) and `EnableMouse(false)` on it and its target-of-target, out of combat.
3. **Never changes the target frame's parent or anchors** (ADR 0007 still holds for the frame Edit Mode manages).
4. After each Blizzard aura update (post-hooks on `UpdateAuras` / `UpdateAuraPositions`, or `TargetFrame_UpdateAuras` on older code), **moves Blizzard's aura icons** onto Grimoire's frame: reparented, re-anchored and resized with `SetScale`. Nothing is written into Blizzard's frame tables.

If none of those update functions exists, the frame is hidden as ADR 0007 decides.

## Consequences

- Enemy buffs and debuffs show in combat; icon textures, timers, stack counts and tooltips are Blizzard's own.
- Grimoire can't choose which auras show or how they're ordered; it follows Blizzard's. "Your own" debuffs are recognised by Blizzard drawing them larger.
- Blizzard's target frame keeps doing its work while invisible (the cost ADR 0007 avoided).
- Moving the aura icons is the same kind of risk as Grimoire Auras moving the buff frame. If it taints Blizzard code, the error log will show `tainted by 'Grimoire_Target'` from Blizzard's target frame code.

## Alternatives considered

- **Read auras another way:** every API path was tried and logged; all are refused in combat.
- **Show Blizzard's target frame again:** safe, but two target frames on screen.
- **Show auras only out of combat:** almost never shows debuffs.

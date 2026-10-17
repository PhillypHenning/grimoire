# ADR 0009: Move Blizzard's target aura container, not its icons

- **Status:** Accepted
- **Date:** 2026-10-17
- **Supersedes:** decision 4 of [ADR 0008](0008-borrow-blizzard-target-auras.md) (moving Blizzard's aura icons one by one). Decisions 1 to 3 (Blizzard's target frame keeps running, invisible and click-through, its own parent and anchors untouched) stand.

## Context

ADR 0008 moved Blizzard's target aura icons onto Grimoire's frame. In game it found none. The probe (2026-10-17) showed why: Forever's target frame draws its auras in `TargetFrame:GetAuraContainer()`, and that container builds its icons from `ForbiddenTargetFrameBuffButtonTemplate` and `ForbiddenTargetFrameDebuffButtonTemplate`. Forbidden frames are hidden from add-ons: the container reports no children, and they can't be moved or resized. In combat even the container's size is a secret value, so Blizzard was drawing the auras, inside an invisible frame.

## Decision

Move the **container**, which is an ordinary frame: reparent it under Grimoire's target bars, anchor it there, and `SetScale` it so Blizzard's 17 px icons draw at Grimoire's 24 px debuff size. Post-hooks on the container's `SetPoint` and `SetParent` pin it back whenever Blizzard re-anchors it. Nothing is written into Blizzard's Lua tables, and none of the container's own setters are called.

## Consequences

- Enemy buffs and debuffs show in combat, drawn entirely by Blizzard.
- Buffs and debuffs are one block under the bars, in Blizzard's order; Phil's "buffs above, debuffs below" layout can't be kept. Edit Mode's "Buffs on top" setting for the target frame decides which come first.
- Blizzard's own debuffs are drawn larger; Grimoire can't size buffs and debuffs separately.
- The container is reparented, which ADR 0007 avoids for Edit Mode frames. It isn't one itself, but Edit Mode configures it; if that taints, the error log will show it.

## Alternatives considered

- **Call the container's setters** (`SetSmallAuraSize`, `SetFlowLayout…`, filter strings) to get two containers or separate sizes: they may store Grimoire's values in Blizzard's tables, which taints its code (CLAUDE.md, secret values).
- **Keep Blizzard's target frame visible but fade everything except the container:** many parts to hide, and Blizzard sets alpha on the whole frame (range fading).

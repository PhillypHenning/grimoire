# ADR 0001: Prefer classic-style UI

- **Status:** Accepted
- **Date:** 2026-10-13

## Context

WoW Forever runs classic-era game rules on a Classic-family client (build 1.60.1, interface 16001). Most popular UI replacements, such as ElvUI-style suites, swap Blizzard's look for a flat, modern aesthetic. Grimoire aims to replace many add-ons at once, so without a guiding style each new feature would drift towards whatever its author felt like that day. The suite would end up looking like a patchwork.

Playing Forever is partly about the classic feel. A UI that matches the rest of the game's art (tooltips, character sheet, spellbook, default frames) keeps that feel intact. It also means Grimoire frames sit naturally next to Blizzard frames we haven't replaced yet.

## Decision

Where possible, Grimoire features use classic-era Blizzard visual language:

| Aspect | Use | Avoid |
| --- | --- | --- |
| Borders & backgrounds | `Grimoire.ApplyClassicBackdrop` (tooltip border/background) | Flat 1px pixel borders |
| Bars | `Interface\TargetingFrame\UI-StatusBar` | Custom flat/gradient textures |
| Fonts | Blizzard font objects (`GameFontNormal`, `NumberFontNormal`, `TextStatusBarText`) | Bundled third-party fonts |
| Colors | Blizzard tables (`PowerBarColor`, `RAID_CLASS_COLORS`, item quality colors) | Hand-picked palettes |
| Icons | Real item/spell icons (`C_Item.GetItemIconByID`, `C_Spell`) | Abstract pips/shapes |
| Layout | Classic positions and proportions as the default; movers let the player adjust | Radically new default layouts |

All asset paths go through `Grimoire.media` so the look is defined in one place.

**"Where possible"** means a modern treatment is acceptable when:
- no classic equivalent exists (e.g. drag handles for `/grimoire unlock`, debug overlays), or
- the classic version clearly hurts readability or function, such as information density in bags or raid frames. The exception is recorded in that feature's doc under *Design decisions*.

## Consequences

- New features start from `Grimoire.media` and the helpers in `Core/Util.lua`, not from bespoke textures.
- We don't ship a texture or font pack. That keeps the download small and avoids licensing questions.
- Because the look is centralised, a "modern" skin could be added later as an alternative `Grimoire.media` set without touching feature code.
- Some players will find the default look dated. That's intended, and an optional skin can address it later.

## Alternatives considered

- **Modern flat theme (ElvUI-style):** popular, but it clashes with Forever's classic identity and with Blizzard frames we haven't replaced.
- **No guidance, decided per feature:** fastest at first, but leads to an inconsistent suite.

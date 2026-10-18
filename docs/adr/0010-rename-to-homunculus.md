# ADR 0010: Rename the suite from Grimoire to Homunculus

- **Status:** Accepted
- **Date:** 2026-10-17

## Context

The suite started as "Grimoire", a spellbook. It has since grown into something that does chores for the player: unit frames, bags, bank and auction snapshots, levelling plans, a rotation recorder. Phil wanted a name that says "it serves you", in the same arcane spirit. A homunculus is an alchemist's small artificial servant, which fits a Warlock's UI.

The rename touches every add-on folder, global, saved variable, frame name and slash command. WoW names each add-on's saved-variables file after its folder, so a plain rename would start every component with empty data. Launch is on 2026-11-04, so the rename should land before then while there's little saved data to carry over.

## Decision

- Every `Grimoire*` add-on folder, `.toc`, global (`Grimoire` → `Homunculus`, `GrimoireDB` → `HomunculusDB`, …), frame name and key binding is renamed to `Homunculus*`.
- Slash commands: `/homunculus` and `/hom`. `/grim` stays as an alias for the old habit.
- Layout export strings made before the rename (`# Grimoire layout v1`) still import.
- `scripts/migrate-to-homunculus.ps1` is run once, with the game closed. It renames the saved-variables files and the variables inside them, the per-character `AddOns.txt` entries, and the emote wheel binding in `bindings-cache.wtf`. It also swaps the old add-on junctions for new ones. It never overwrites existing Homunculus files, and it keeps the old files as `*.grimoire-backup`.
- Accepted ADRs 0001–0009 keep the old name as a historical record.
- After the rename, the Notes component takes the freed name "Grimoire" (`Homunculus_Grimoire`).

## Consequences

- One mechanical change across about 110 files; the repo and its folder on disk keep the old `grimoire` name for now (renaming them is cosmetic).
- Saved data carries over only through the migration script. Without it, every component starts fresh.
- The word "grimoire" stays in the game's own item names ("Imp grimoires" in Prophecy plans), which are left alone.

## Alternatives considered

- **Keep "Grimoire":** no work, but the name no longer describes the suite.
- **Other servant names** (Familiar, Famulus, Imp, Minion, Steward): Phil picked Homunculus.
- **Keep the old saved-variable names under the new folders:** avoids a migration, but the files are named after the folders, so it doesn't actually carry the data over, and it leaves two names in the code for good.

# Notes

- **Add-on:** `Grimoire_Notes`
- **Module:** `Notes`
- **Status:** Scaffolded, untested in game
- **Opened with:** `/grimoire notes` (or `/grim notes`)

## Summary

A simple in-game notebook: a list of notes on the left, title and text on the right. Notes are account-wide, so every character sees them, and they save as you type. Each note remembers which character wrote it and shows in that character's class color: a Warlock's notes are purple ([ADR 0003](../../adr/0003-show-character-and-class-color.md)).

## What it solves

```mermaid
flowchart LR
    Q["Remember a quest route, rotation tips,<br/>a todo list for the alt"] --> D["Default: alt-tab to a text file<br/>or abuse chat macros"]
    Q --> G["Grimoire Notes: in game, saved automatically"]
```

## How it works

```mermaid
flowchart LR
    New[New] --> Insert[Insert note at top] --> Select
    Row[Click list row] --> Select[SelectNote]
    Select --> Editor[Title + body editors]
    Editor -- "OnTextChanged (typed)" --> Save[Save field + updated time]
    Save --> DB[(GrimoireDB.global.notes)]
    Del[Delete] --> Confirm{clicked twice<br/>within 3s?}
    Confirm -- yes --> Remove[Remove, select neighbour]
```

## Code highlights

**Autosave only on typing** ([`Notes.lua`](../../../Grimoire_Notes/Notes.lua)). The `userInput` flag tells real typing apart from `SetText` when switching notes:

```lua
body:SetScript("OnTextChanged", function(box, userInput)
    if userInput then self:Save("body", box:GetText()) end
    ScrollingEdit_OnTextChanged(box, bodyScroll)
end)
```

**Two-click delete instead of a popup.** Adding entries to Blizzard's `StaticPopupDialogs` is a known source of taint:

```lua
if self.confirmingDelete then self:DeleteSelected() return end
self.deleteButton:SetText("Confirm?")
```

## Design decisions

- **Account-wide**, not per character, but each note stores its `author` and `class`. The list and title use the author's class color, and the footer reads "Edited 5m ago by <name>".
- **Newest first** by creation order. Editing doesn't reorder the list, so notes don't jump around while you type.
- **Classic look**: dialog window, tooltip-style panels, quest-log highlight on rows.

## Combat & secret-value constraints

None. Works in combat.

## Settings

None yet.

## Screenshots

_TODO: empty state, a few notes, delete confirmation._

## Open questions / roadmap

- Keybind to toggle.
- Search notes.
- Per-character or per-zone notes, e.g. one that pops up when entering a dungeon.

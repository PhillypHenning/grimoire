# Bags

- **Add-on:** `Grimoire_Bags`
- **Module:** `Bags`
- **Status:** Tested in game (2026-10-16: the window opens, the new-item glow clears on hover)
- **Replaces:** Bagnon / Baganator / AdiBags / ArkInventory (declared as conflicts)
- **Related:** [Bank](../bank/README.md), [Auctions](../auctions/README.md) (separate, optional add-ons)

## Summary

All your bags in one classic-style window. Items work exactly as in Blizzard's bags (right-click to use, drag to move, shift-click to link). The window adds search, a Sort button, free-slot count, your gold, and buttons to open the Bank and Auctions viewers.

## What it solves

```mermaid
flowchart LR
    subgraph Default["Default UI"]
        B1[Up to 5 separate bag windows]
        B2[No search]
        B3[No quick way to see<br/>bank or auctions away from town]
    end
    subgraph Grimoire["Grimoire Bags"]
        S1[One combined window]
        S2[Search dims non-matches]
        S3[Sort button]
        S4[Bank / Auctions buttons<br/>open saved snapshots]
    end
    Default ==> Grimoire
```

## How it works

```mermaid
sequenceDiagram
    participant Player
    participant Blizzard as Blizzard bag functions
    participant Bags as Grimoire Bags
    Player->>Blizzard: press B (ToggleAllBags)
    Blizzard->>Blizzard: opens its bag frames
    Blizzard-->>Bags: hooksecurefunc → Request("toggle")
    Bags->>Blizzard: hide player bag frames
    Note over Bags: next frame: resolve all requests once
    Bags->>Player: toggle combined window
```

```mermaid
flowchart LR
    E1[BAG_UPDATE_DELAYED] --> R[Refresh]
    E2[ITEM_LOCK_CHANGED] --> U[Update one slot]
    E3[BAG_UPDATE_COOLDOWN] --> R
    E4[PLAYER_MONEY] --> R
    R --> L{bag sizes changed?}
    L -- yes --> Lay[Layout<br/>deferred if in combat]
    L -- no --> Items[Update icons, counts,<br/>locks, cooldowns, search]
```

## Code highlights

**Usable item buttons without custom secure code** ([`Bags.lua`](../../../Grimoire_Bags/Bags.lua)). Each bag gets a holder frame whose ID is the bag; each button's ID is its slot. Blizzard's `ContainerFrameItemButtonTemplate` reads those IDs, so using and moving items goes through Blizzard's own code:

```lua
holder:SetID(bag)
button = CreateFrame("ItemButton", name, holder, "ContainerFrameItemButtonTemplate")
button:SetID(slot)
```

**Hook, don't replace.** Overwriting `ToggleAllBags` would taint it. Hooks are collected and resolved once on the next frame, because one key press can trigger several bag functions:

```lua
if pending ~= "toggle" then
    pending = action -- a toggle (the key press) wins over open/close
end
```

**New-item glow is cleared like Blizzard's bags.** The client keeps "new" flags (`C_NewItems`) until a bag UI clears them. The first version never did, so every item glowed every time (Phil, 2026-10-16). Now a slot glows while `C_NewItems.IsNewItem` says so, hovering it calls `RemoveNewItem`, and closing the window calls `ClearAll`. The flags live in the client, so "seen" survives reloads.

**Who owns an item** (2026-10-16, learned from Syndicator). Core's shared item data (`Grimoire/Core/Items.lua`) keeps each character's bag counts current (`bagCounts`, rescanned when bags settle) and reads bank counts from the Bank component's snapshot. `Grimoire:GetItemCounts(itemID)` answers for any component; Bags adds the class-coloured owner lines to item tooltips (`TooltipDataProcessor`, or `OnTooltipSetItem` on older clients).

**Bank bags are left alone.** Only frames for player bags are hidden, so the Blizzard bank still works:

```lua
if frame and frame:IsShown() and Grimoire.IsPlayerBag(frame:GetID()) then frame:Hide() end
```

**Optional components ([ADR 0002](../../adr/0002-every-component-is-a-toggleable-addon.md)).** The Bank and Auctions buttons appear only when those add-ons are enabled. The search box stretches to fill whatever room the buttons leave:

```lua
local module = Grimoire:GetModule("Bank")
button:SetShown(module and module:IsEnabled())
```

## Design decisions

- **Sort uses Blizzard's `C_Container.SortBags()`.** It physically rearranges items. The button disables itself if the client lacks the API.
- **Search dims rather than hides.** Slots stay in place, so muscle memory keeps working.
- **Search language** (2026-10-16, learned from Baganator; [`Search.lua`](../../../Grimoire_Bags/Search.lua), tested by `lua scripts/bags/test.lua`): words match names, item types and subtypes; `junk`/`poor`, `common` … `legendary`; `boe`, `bop`; slots (`head`, `chest`, `feet`, `finger`, `trinket`, `ranged`, `bag` …); item level `>20`, `<10`, `10-15`; a space or `&` is and, `|` is or, `!` is not. Hovering the box lists them.
- **Icon corners** (learned from Baganator): equipment shows its item level bottom-left, and items that bind when equipped show BoE top-left (setting `iconInfo`).
- **Classic art ([ADR 0001](../../adr/0001-prefer-classic-style-ui.md)):** dialog border, header, empty-slot texture, quality borders, Blizzard bag sounds.

## Combat & secret-value constraints

- Creating or moving item buttons is blocked in combat. If a bag is swapped in combat, the layout change waits until combat ends. Items and counts still update.
- Item cooldowns may be secret in combat, in which case they go straight to the cooldown widget.

## Settings

Stored in `GrimoireDB.profiles[<profile>].modules.Bags`. In the menu: **Components ▸ Bags**. A new column count is laid out straight away (`ApplySettings` clears the layout signature and refreshes an open window).

| Key | Default | Menu choices | Description |
| --- | --- | --- | --- |
| `columns` | 10 | 8 / 10 / 12 / 14 | Slots per row |
| `ownerTooltips` | true | toggle | Item tooltips list every character that has the item, with bag and bank counts |
| `iconInfo` | true | toggle | Item level and BoE on icons |

While Baganator, Bagnon, AdiBags or ArkInventory is loaded, the module stays off and the menu shows "(conflicts with …)".

## Screenshots

_TODO: closed vs open, search active, after sort, Bank/Auctions buttons visible vs hidden._

## Open questions / roadmap

- Verify in game: the button template still reads the bag from the parent ID; no taint when using items in combat; `C_Container.SortBags` exists on Forever.
- Categories (consumables, reagents, quest, junk) as optional sections.
- Soul Bag / quiver as their own section.
- Junk selling button at vendors.

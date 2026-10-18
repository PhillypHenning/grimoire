# Auctions

- **Add-on:** `Homunculus_Auctions`
- **Module:** `Auctions`
- **Status:** Scaffolded, untested in game
- **Opened from:** the *Auctions* button in [Bags](../bags/README.md), the [Homunculus menu](../menu/README.md) (*Open ▸ Auctions*), or `/hom auctions`

## Summary

See your active auctions, on any of your characters, from anywhere: what's listed, price, time left, and what's sold. Each time you visit an auctioneer, Homunculus saves that character's auction list. A class-colored character picker switches between characters ([ADR 0003](../../adr/0003-show-character-and-class-color.md)).

## What it solves

```mermaid
flowchart LR
    Q["Did my auctions sell? When do they expire?"] --> D["Default: go back to the auction house<br/>or wait for mail"]
    Q --> G["Homunculus: open the Auctions viewer anywhere"]
```

## How it works

```mermaid
sequenceDiagram
    participant AH as Auction house
    participant A as Homunculus Auctions
    participant DB as HomunculusDB.global.characters[you].auctions
    AH->>A: PLAYER_INTERACTION_MANAGER_FRAME_SHOW (Auctioneer)
    A->>AH: QueryOwnedAuctions (modern) / GetOwnerAuctionItems (legacy)
    AH->>A: OWNED_AUCTIONS_UPDATED / AUCTION_OWNED_LIST_UPDATE
    A->>DB: Record() → list + timestamp
    AH->>A: AUCTION_HOUSE_AUCTION_CREATED / AUCTION_CANCELED → query again
```

## Code highlights

**Two auction APIs** ([`Auctions.lua`](../../../Homunculus_Auctions/Auctions.lua)). The Mainline client has `C_AuctionHouse`, and the classic-style owner list may exist instead. Both are supported, and only events this client knows are registered:

```lua
local list = HasModernAPI() and ReadModern(now) or ReadLegacy()
```

**Time left keeps counting while you're away.** The modern API gives seconds remaining, stored as an absolute expiry:

```lua
expiresAt = info.timeLeftSeconds and (now + info.timeLeftSeconds)
-- later: SecondsToTime(auction.expiresAt - time(), true) or "Expired"
```

The legacy API only gives buckets (Short/Medium/Long/Very Long), which are shown as-is.

**Mail tracking is idempotent.** The inbox is re-read on every update, so for each item name the code only tops up to the number of matching mails, and marks are never removed. Mail that arrived before the snapshot is ignored. Arrival is estimated as `now + daysLeft − 30 days`.

```lua
if auction.name == itemName and not auction.mailOutcome and not auction.sold then
    auction.mailOutcome = outcome
```

```mermaid
flowchart LR
    M[MAIL_INBOX_UPDATE] --> R[Read inbox]
    R --> F{arrived after<br/>snapshot?}
    F -- no --> X[ignore]
    F -- yes --> T{invoice or subject}
    T -- seller invoice --> S[mark one matching auction Sold]
    T -- "Auction expired/cancelled: X" --> E[mark one matching auction Expired]
```

## Design decisions

- **Character picker.** It opens on the current character and lists every character with saved auctions. "Live" shows only for the character you're playing.
- **Listed value** totals unsold auctions (buyout, or bid if no buyout).
- **A snapshot, updated from your mail.** Opening the mailbox marks auctions as *Sold* (sale invoices, including pending ones) or *Expired* (expired/cancelled mail) without revisiting the auction house.

## Prices and shopping lists (2026-10-16, learned from Auctionator)

- **Scan prices** (button in the Auctions window, at the auction house; [`Prices.lua`](../../../Homunculus_Auctions/Prices.lua)): reads every auction and saves the lowest buyout per item, per unit, per realm, with the time (`HomunculusAuctionsDB.prices`). Modern client: `C_AuctionHouse.ReplicateItems`; legacy: `QueryAuctionItems(..., getAll)`. Results are read 500 per frame so a big scan doesn't freeze the game; the Debug log records which API ran. A full scan is allowed every 15 minutes, so it's a button, not automatic.
- **Price tooltips** (setting `priceTooltips`, on): item tooltips show "Auction  <price> (<age>)".
- **Shopping lists** (*Shopping lists* button or `/hom auctions shopping`; [`Shopping.lua`](../../../Homunculus_Auctions/Shopping.lua)): named lists of item names (type a name or shift-click an item into the box). At the auction house, *Search* looks each up in turn (`SendBrowseQuery`, or `QueryAuctionItems` with an exact name) and shows the cheapest price per unit, how many are listed, and when. Prices found are saved for tooltips too.

## Combat & secret-value constraints

None expected.

## Screenshots

_TODO: never visited, mixed active/sold, expired._

## Open questions / roadmap

- Verify which API Forever exposes and that `Enum.PlayerInteractionType.Auctioneer` fires.
- Verify the mail matching on Forever: invoice types, subject strings, and the 30-day mail lifetime.

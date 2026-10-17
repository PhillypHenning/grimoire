# Learnings from popular add-ons

> **Progress (2026-10-16, on the PC):** plan written; work in order L1 → L7, each pushed for testing as it lands. L1–L5 done.

## Context
Phil asked what the most popular related add-ons do that Grimoire should learn from, then picked (2026-10-16): layout sharing, a better bag search, Prophecy waypoints, an error count, setting tooltips, a shared item-data layer, and, last, an Auctionator-style expansion of Auctions. Only these; nothing else from the review.

## L1: error count on the Grimoire button (from BugSack)
- While errors have been logged this session and the Debug log hasn't been opened since, the Grimoire button shows a small red count.
- Opening the Debug log clears it. Needs Debug enabled (found with `GetModule`).

## L2: tooltips on settings (from Leatrix Plus)
- Options get an optional `tooltip` text; the menu shows it on hover (Menu API `SetTooltip`, or the old dropdown's `tooltipTitle`/`tooltipText`). Options that need a reload say so.
- Every existing option gets a one-line explanation.

## L3: layout sharing (from Shadowed Unit Frames / ElvUI)
- *Layout ▸ Export layout* shows the current profile as text: frame positions, groups, dimming, dim strength and delay, button size, and every component's settings.
- *Layout ▸ Import layout* takes that text, checks it, and replaces the current profile's layout; then `/reload`.
- Text only, never run (like ADR 0006): a small serializer/reader in core for strings, numbers, booleans and tables, tested by `scripts/core/test.lua`.

## L4: Prophecy waypoints (from RestedXP / Guidelime)
- If TomTom is loaded, the current step's coordinates become a TomTom waypoint (its arrow points there), updated as steps tick. Found at runtime (ADR 0002); a Prophecy setting turns it off.

## L5: shared item-data layer (from Syndicator)
- Core records each character's bag contents (counts by item) on bag changes; the bank snapshot the Bank component already saves is read too.
- `Grimoire:GetItemCounts(itemID)` → per character: bags, bank.
- Item tooltips show which characters own it ("Manflesh: 3 (bags 2, bank 1)"), class-coloured (ADR 0003). A Bags setting turns it off.

## L6: bag search and icon info (from Baganator)
- Search terms: words match the name; `junk`/`poor`, `common`, `uncommon`, `rare`, `epic`; item type and slot words (`armor`, `weapon`, `consumable`, `head`, …); `boe`, `bop`; item level `>20`, `<10`, `10-15`. Combine with spaces or `&` (and), `|` (or), `!` (not). The matcher is plain Lua, tested.
- Item level and "BoE" on item icons (a Bags setting).

## L7: auctions expansion (from Auctionator)
- **Prices:** while the auction house is open, Grimoire scans it and saves the lowest buyout per item (per realm, with the time). Supports both the modern (`C_AuctionHouse`) and the legacy (`QueryAuctionItems`) API; Debug logs which one ran.
- **Tooltips:** item tooltips show the auction price and its age.
- **Shopping lists:** named lists of item names; at the auction house, *Search* looks each up and shows the cheapest price.

# Prophecy plan format, version 1

Prophecy plans are plain text: written outside the game (by hand or by an agent), pasted into the Prophecy window in game, checked, and saved in Prophecy's saved variables. In game, Prophecy shows the current step, puts its quests on the native quest tracker, pins its coordinates on the map and points the arrow at them, and ticks steps off by itself when their conditions are met. See [ADR 0006](../adr/0006-prophecy-plans-are-pasted-text.md) for why it's text.

This document is the contract between plan writers and the add-on. A plan that follows it loads; anything it doesn't cover is reported with a line number, not guessed at.

The format was designed from the first real plan, the *Troll Warlock 1–30* guide: chapters with level ranges and a "why", steps of a few kinds, quests and items named in the text, coordinates, reward notes, "verify" flags, and gates with hard and soft profession targets.

## At a glance

```
prophecy 1
title Troll Warlock, 1 to 30
skills Enchanting, Tailoring, Cooking, Fishing

chapter 6 | Crossroads and the eastern camps | 10-12
> Wool and greens start dropping. Grab the Orgrimmar flight path first.
zone The Barrens
q Get the Crossroads flight path
q Accept [Plainstrider Menace], [Disrupt the Attacks], [Raptor Thieves] and [The Forgotten Pools]
  done accept [Plainstrider Menace], [Disrupt the Attacks], [Raptor Thieves], [The Forgotten Pools]
q Take [Meats to Orgrimmar] from {Zargh} @52.6,29.8
  done accept [Meats to Orgrimmar]
  detail It ends with the Orgrimmar flight path learned.
p Hand a {Waylaid Crate} to {Dokimi} @50.0,29.2
  detail Fill one line of what it asks for. Your first crate also gives a Shipping Label quest.
  verify Dokimi's position in Forever

gate Leave the eastern camps with
  skill Tailoring 40 soft
  skill Enchanting 30 soft
  check Crossroads and Orgrimmar flight paths
```

## Lines

A plan is UTF-8 text, one instruction per line.

- **Top-level lines** start at column 0 with a keyword (`title`, `chapter`, `q`, `gate`, …) followed by a space and its value.
- **Attribute lines** are indented (two spaces or a tab) and belong to the step or gate above them: `  done …`, `  detail …`, `  skill …`.
- **Blank lines** are ignored.
- **Comments:** a line whose first non-space characters are `--` is ignored.
- **Keywords are lower case.** Values keep their case.
- **Line length:** no hard limit, but a step's main line is what the tracker shows, so keep it under about 90 characters and put the rest in `detail`.

## Header

The header comes before the first `chapter`.

| Line | Required | Meaning |
| --- | --- | --- |
| `prophecy 1` | yes, first line | Format version. Prophecy refuses versions it doesn't know. |
| `title <text>` | yes | Plan name, shown in the plan list. |
| `subtitle <text>` | no | One-line description. |
| `author <text>` | no | Who wrote it. |
| `class <TOKEN>` | no | `WARLOCK`, `MAGE`, … Prophecy warns when the current character doesn't match. |
| `race <text>` | no | e.g. `Troll`. Informational warning, like `class`. |
| `faction Horde` / `faction Alliance` | no | Informational warning. |
| `skills <Name>, <Name>, …` | no | Professions to show in the plan's skill strip (e.g. `Enchanting, Tailoring, Cooking, Fishing`). Prophecy reads the levels from the game. |
| `> <text>` | no, repeatable | Introduction paragraph lines. Consecutive `>` lines join with a space; an empty `>` starts a new paragraph. |
| `note <text>` | no, repeatable | A caveat shown in a box under the introduction. |
| `source <url> <label>` | no, repeatable | Where the plan's information came from. |

## Chapters

```
chapter <badge> | <title> | <levels>
```

- **badge:** a short marker shown before the title: `1`, `12`, `T`, `D`, `★`. Up to 3 characters.
- **title:** the chapter name.
- **levels:** free text shown under the title: `1-5`, `16-18, about 45 minutes`, `Reference`.

Optional lines directly after the chapter line:

| Line | Meaning |
| --- | --- |
| `id <word>` | Stable identifier for saved progress (letters, digits, `-`, `_`). Defaults to `ch-` plus the badge, e.g. `ch-6`. Give one explicitly when two chapters share a badge. Must be unique. |
| `type route` / `type reference` | `route` (default): part of the sequence Prophecy walks through. `reference`: shown in the plan viewer only, never becomes the current step (the three-day plan and profession tables in the Warlock guide). |
| `> <text>` | The chapter's "why", joined like the header's `>` lines. |

## Zones and coordinates

- `zone <map name>` sets the zone for coordinates in the steps that follow, until the next `zone` line. It carries across chapters. Use the zone name as the game shows it on the world map (`Durotar`, `The Barrens`, `Orgrimmar`, `Thunder Bluff`, `Tirisfal Glades`, `Undercity`, `Stonetalon Mountains`).
- In step text, `@x,y` is a coordinate in the current zone: `@52.6,29.8`. Both numbers are map percentages, 0–100, one decimal place.
- `@Zone Name:x,y` names the zone inline for one coordinate: `@Thunder Bluff:70.6,29.6`.
- The first coordinate in a step is where the map pin and arrow point. Further coordinates get smaller pins.

## Steps

```
<kind> <text>
```

| Kind | Meaning | Shown as |
| --- | --- | --- |
| `q` | Quest or route step: go somewhere, accept, kill, turn in | default |
| `p` | Profession step: train, craft, buy materials | teal "Profession" tag |
| `c` | Class step: class quests, spells, pets | class-coloured "Class" tag |
| `o` | Optional step: worth doing, safe to skip | "Optional" outline tag; never blocks the route |
| `n` | Note: advice, not a task. No checkbox | muted text |

### Inline markup

| Markup | Meaning | Example |
| --- | --- | --- |
| `[Quest Name]` | A quest, by its exact in-game title. Bold in the text; `done` conditions and the tracker use it. | `[Sting of the Scorpid]` |
| `[Quest Name#123]` | A quest with its ID, when the title is ambiguous (two quests share it). | `[Vile Familiars#1499]` |
| `{Name}` | Any other name worth highlighting: NPC, item, recipe, spell, place. Display only. | `{Gornek}`, `{Bolt of Linen Cloth}` |
| `@x,y`, `@Zone:x,y` | A coordinate (above). | `@52.0,47.4` |
| `\[`, `\{`, `\@`, `\\` | A literal `[`, `{`, `@` or backslash. | |

### Step attributes

Indented under a step, in any order:

| Attribute | Meaning |
| --- | --- |
| `detail <text>` | More text, shown on hover and in the plan viewer. Repeatable; lines join with a space. |
| `reward <text>` | Which quest reward to take, and why. Repeatable. |
| `verify <text>` | Not yet confirmed for this client; check it in game. Shows a `?` marker; the text says what to check. |
| `minlevel <n>` | The step can't be done before this level (e.g. a quest that unlocks at 13). Prophecy shows it greyed out and skips past it until you reach the level. |
| `done <condition>` | When the step ticks itself off (below). Repeatable: every `done` must be met. No `done` means you tick it by hand. |

### Completion conditions

Used by `done` under a step, and by gate requirements.

| Condition | Met when | Example |
| --- | --- | --- |
| `accept [Q], [Q], …` | Every listed quest is in your quest log, or already turned in. | `done accept [Cutting Teeth], [Wayward Weapons]` |
| `complete [Q], …` | Every listed quest's objectives are finished (ready to turn in), or it's turned in. | `done complete [Sarkoth]` |
| `turnin [Q], …` | Every listed quest has been turned in. | `done turnin [Vanquish the Betrayers]` |
| `level <n>` | Character level ≥ n. | `done level 10` |
| `skill <Profession> <n>` | Profession skill ≥ n. | `done skill Fishing 20` |
| `item <Item Name> <n>` | At least n of the item in your bags. | `done item Raw Brilliant Smallfish 3` |
| `learn <Spell Name>` | The spell or recipe is known. | `done learn Summon Voidwalker` |
| `reach @x,y` (or `@Zone:x,y`) | You're within about 15 yards of the spot. | `done reach @45.0,23.5` |
| `zone <map name>` | You're in that zone. | `done zone Thunder Bluff` |

Quest names in conditions use the same `[ ]` markup as step text, and must match quest titles exactly. Prophecy remembers quests it has seen you turn in, and also asks the game for completed quests where the client supports it.

## Gates

A gate closes a chapter: the things you should have before moving on.

```
gate <title>
  <requirement>
  ...
```

Requirements, one per indented line:

| Requirement | Meaning |
| --- | --- |
| `skill <Profession> <n>` | A hard target. |
| `skill <Profession> <n> soft` | A soft target: shown as a goal, never blocks. |
| `skill <Profession> <n> soft min <m>` | Soft, but blocks below `m`. |
| `level <n>`, `item …`, `learn …`, `accept …`, `turnin …` | As in completion conditions; hard. |
| `check <text>` | A manual checklist item you tick. |
| `note <text>` | Text shown in the gate box. |

A gate is **open** when every hard requirement is met and every `check` is ticked. Prophecy shows each target's progress (`Tailoring 32 / 40`), and the route doesn't advance past a closed gate's chapter until you open it or skip it.

## Progress and identity

Prophecy saves progress per plan and per character: which steps and checks are ticked, and which steps were skipped.

- A step's identity is its chapter `id` plus a short hash of its main line. Rewording a step's main line makes it a new step (unticked). Editing its attributes doesn't.
- Re-importing a plan with the same `title` replaces the old version and keeps the progress of every step whose identity didn't change.

## Validation

Prophecy checks a pasted plan before saving it.

**Errors** (the plan isn't saved):
- First line isn't `prophecy 1`.
- No `title`.
- An unknown top-level keyword.
- A step or gate before the first `chapter`.
- An attribute line with nothing above it to attach to.
- A malformed `chapter` line (needs two `|`).
- Two chapters with the same `id`.
- A malformed coordinate (`@` not followed by `x,y` or `Zone:x,y`).
- A `done` or gate condition it doesn't know.
- A `skill` or `level` without a number.

**Warnings** (the plan is saved and the line is listed):
- A quest name the client doesn't recognise. Quest titles can't be checked until the quest has been seen, so this only appears for quests Prophecy has met.
- An unknown zone name.
- `class`/`race`/`faction` not matching the current character.
- A step main line over 120 characters.

## Writing plans (for people and agents)

1. **One step per line, as the action.** Start with the verb: "Take…", "Kill…", "Turn in…", "Train…", "Craft…". The main line is what the tracker shows.
2. **Push the prose down.** Explanations, alternatives and costs go in `detail`. Reward advice goes in `reward`. "Verify" flags go in `verify`.
3. **Mark every quest** with `[ ]` using its exact in-game title, and give each quest-driven step a `done` line. Don't invent conditions you aren't sure of; a manual step is fine.
4. **Mark names** of NPCs, items, recipes and places with `{ }`.
5. **Coordinates:** convert any form (`(52.6, 29.8)`, `52.0 47.4`) to `@52.6,29.8`, and set `zone` when the zone changes.
6. **Kinds:** quests and travel are `q`, profession work `p`, class work `c`, optional `o`, and pure advice `n`.
7. **Levels:** a quest marked "(13)" in the source gets `minlevel 13`.
8. **Gates:** profession targets marked "soft target" in the source are `soft`; minimums for soft targets become `soft min <m>`; checklist items become `check`.
9. **Don't drop information.** Anything that doesn't fit a step goes in `detail`, `note` or the chapter's `>` lines.

## Example: chapter 1 of the Warlock guide

```
chapter 1 | Valley of Trials | 1-5
> No profession trainers here, so this chapter is about stockpiling. Everything you
> loot now becomes skill points in the next two hours.
zone Durotar

q Speak to {Kaltunk}, then {Gornek}: [Your Place In The World]
  done turnin [Your Place In The World]
q Take [Cutting Teeth] and [Wayward Weapons]
  done accept [Cutting Teeth], [Wayward Weapons]
q Kill 10 Mottled Boars and pick up 6 abandoned training weapons
  done complete [Cutting Teeth], [Wayward Weapons]
q Head west to Hana'zua: [Sarkoth], kill him on the ledge, turn in
  detail Carry the follow-up back to Gornek.
  reward Sarkoth follow-up: Soft Wool Vest.
  done turnin [Sarkoth]
c Turn in [Cutting Teeth]; take [Tainted Parchment] to {Nartok}
  reward Cutting Teeth: Soft Wool Boots.
  done turnin [Tainted Parchment]
c Keep Imp training to a minimum
  detail Skip the Imp grimoires; the Voidwalker takes over at level 10.
p Loot every {Linen Cloth} from the Burning Blade in the cave
  detail They're humanoids. Don't turn any of it into bandages.

gate Leave the Valley with
  check Imp summoned and on your bar
  check 6-slot bag bought from the traveling gear stall (5s)
  check Every Linen Cloth you've looted
  check Every green still in your bags or on your character
```

## Example: a reference chapter

```
chapter ★ | The three-day plan: level 22, stretch 25 | Launch Wednesday to Friday
id plan
type reference
> Level 22 by Friday night is the target and 25 is a bonus.
n Day 1: Valley of Trials through the level 10 Orgrimmar stop and into the Crossroads
  detail Aim for 11 to 13, with Fishing 20 and the Fish Bowl, Enchanting 20 and the Enchanted Lute.
n Log off in an inn or a city each night for rested XP

gate Flight paths unlocked by level 25
  check Crossroads
  check Orgrimmar (from Meats to Orgrimmar)
```

## Changes to this format

The version on the first line only changes for incompatible changes. New optional keywords can be added to version 1; Prophecy reports keywords it doesn't know as errors, so a plan that uses a newer keyword tells you to update the add-on instead of half-loading.

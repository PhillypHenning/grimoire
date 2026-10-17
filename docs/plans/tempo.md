# Tempo: learn your best rotation and play it back

> **Progress (2026-10-16, on the PC):**
> - **T1 (probe):** code done. `/grim tempo probe`. Waiting for Phil to fight one mob and `/reload`; then Claude reads `SavedVariables\Grimoire_Tempo.lua` and tunes the damage-source order.
> - **T2–T5:** code done the same day (Phil: "go ahead with the plan"), without waiting for the probe: the recorder listens to every damage source at once and keeps the best that gave data. `Cycles.lua` and `Share.lua` are tested with `lua scripts/tempo/test.lua`. Waiting on in-game testing.

## Context
Phil wants a component that watches his fights, works out which sequence of casts did the most damage, and plays that sequence back in later fights like sheet music, so he can repeat it or try variations. He wants it as a teaching aid.

The WoW terms:
- **Rotation:** the repeating cycle of casts. For a Warlock, roughly: DoTs on (Corruption, a curse), filler (Shadow Bolt, Conflagrate) until the DoTs run low, then repeat.
- **Opener:** the first casts of a fight, before the cycle settles.

A "combo" in Tempo is one **cycle**: the casts from putting your DoTs on to the next time you put them back on.

## What the client allows (to confirm with the probe)
- **Keystrokes can't be recorded**, and don't need to be: Tempo records **casts** (`UNIT_SPELLCAST_SUCCEEDED` for the player). That covers keybinds, clicks and macros alike.
- **The combat log is blocked** (confirmed 2026-10-16: registering it raised the "blocked from an action only available to the Blizzard UI" pop-up; DBM also skips it on Forever). Tempo no longer registers it.
- **Damage numbers are the unknown.** Details ships a "no combat log" parser, which suggests Forever blocks `COMBAT_LOG_EVENT_UNFILTERED` for add-ons, as retail Midnight does. Candidate sources, best first:
  1. ~~the combat log~~ (blocked);
  2. `C_DamageMeter` (Blizzard's built-in meter, if present);
  3. `UNIT_COMBAT` on the target (damage taken, not split by source);
  4. the target's health dropping (works even when values are secret if percentages aren't; doesn't tell your damage from others').
- Tempo never casts anything. Playback is a guide only; the game wouldn't allow anything else.

## Milestones

### T1: probe (done, waiting on a test)
`/grim tempo probe` arms a recorder for the next fight. It saves:
- which APIs exist (`CombatLogGetCurrentEventInfo`, `C_DamageMeter` and its functions, `C_CombatLog`, `UnitHealthPercent`, …);
- the player's casts, `UNIT_COMBAT` on the target, and target health, each marked `<secret>` where the value is secret;
- the result of every `C_DamageMeter.Get*` function after the fight.

**Phil:** `/reload`, `/grim tempo probe`, fight one mob to the end with your usual rotation, `/reload`. Then tell Claude. No screenshots needed.

### T2: recorder (done, waiting on a test)
Per character (ADR 0003): each fight saves casts with timestamps, damage over time from the source the probe picked, duration, and the target's name and level. Only the last N fights are kept (setting). Fights shorter than a few seconds are dropped.

### T3: cycles and scoring (done, waiting on a test)
- Split each fight into an opener plus cycles. A cycle ends when a DoT you already applied is applied again. Each class has a short list of "cycle reset" spells, Warlock first.
- Score each cycle by damage per second, so short and long cycles compare fairly.
- Keep the best opener and the best cycle per character. (Built: every fight's segments can be opened in the window to compare; a "top few" list wasn't needed.)
- A window lists past fights and cycles: spell icons in order, DPS, which one is best.

### T4: playback lane (done, waiting on a test)
- A music-staff style lane (classic look, ADR 0001), movable: upcoming spell icons scroll toward a "now" line at the pace they were cast.
- Each cast you make is checked against the next note: on time, early, late or a different spell. Matches light up; misses show in red.
- Modes: **Follow** (best rotation), **Pinned** (a rotation you chose), **Experiment** (no guide, records only, so a new idea can beat the best).
- After the fight: a short summary (accuracy, DPS against the rotation's).

### Probe results (2026-10-16, 18:49, one fight on a Zhevra Runner)
- Combat log: blocked (see above). `C_CombatLog.IsCombatLogRestricted` exists.
- `UNIT_COMBAT` on the target: works, amounts readable; includes the pet (fire school = imp). This is the source Tempo uses.
- Target health and `UnitHealthPercent`: all secret in combat, so the health fallback gives nothing here.
- `C_DamageMeter` exists (`GetCombatSessionFromType(sessionType, type)`, `GetCombatSessionSourceFromType(sessionType, type, sourceGUID)`, …). The probe now queries every session and meter type, also 3 s after combat; if it gives the player's own damage, it becomes the first source.
- Forever calls Curse of Agony "Bane of Agony"; banes added to the Warlock cycle list.

### T4b: pets (done 2026-10-16, Phil asked: "it needs to account for pet attacks as well")
- Sending the pet in is a judged "Pet Attack" step; abilities you have the pet use are pet steps on their own lane row (not judged as missed); autocast abilities are left out; pet damage was already in the score.
- Share format: `0.0 0 Pet Attack`, `2.1 3110 pet: Firebolt`.

### T5: teaching (done, waiting on a test)
- Export and import rotations as text (like Prophecy plans, ADR 0006), so one can be handed to another player.
- A rotation can carry notes ("refresh Corruption when under 3 s").

## Open questions
- Which damage source? Settled by the T1 probe.
- Cycle detection for classes without DoTs: later. The first version is Warlock-first.

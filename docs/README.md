# Grimoire documentation

## Components

Each component is its own add-on and can be switched on or off in the in-game AddOns list ([ADR 0002](adr/0002-every-component-is-a-toggleable-addon.md)).

| Component | Add-on | Status |
| --- | --- | --- |
| [Core framework](features/core/README.md) | `Grimoire` | Scaffolded |
| [Manager menu](features/menu/README.md) | `Grimoire` (core) | Scaffolded, untested in game |
| [Player frame](features/player-frame/README.md) | `Grimoire_Player` | Scaffolded, untested in game |
| [Player bars](features/player-bars/README.md) | `Grimoire_Player` | Scaffolded, untested in game |
| [Pet](features/pet/README.md) | `Grimoire_Pet` | Scaffolded, untested in game |
| [Party frames](features/party/README.md) | `Grimoire_Party` | Scaffolded, untested in game |
| [Target frame](features/target/README.md) | `Grimoire_Target` | Scaffolded, untested in game |
| [Warlock resources](features/warlock-resources/README.md) | `Grimoire_Warlock` | Scaffolded, untested in game |
| [Auras](features/auras/README.md) | `Grimoire_Auras` | Scaffolded, untested in game (moves Blizzard's buff frame) |
| [Bags](features/bags/README.md) | `Grimoire_Bags` | Tested in game (window, new-item glow) |
| [Bank](features/bank/README.md) | `Grimoire_Bank` | Scaffolded, untested in game |
| [Auctions](features/auctions/README.md) | `Grimoire_Auctions` | Scaffolded, untested in game |
| [Notes](features/notes/README.md) | `Grimoire_Notes` | Scaffolded, untested in game |
| [Launcher](features/launcher/README.md) | `Grimoire_Launcher` | Scaffolded, untested in game |
| [Tweaks](features/tweaks/README.md) | `Grimoire_Tweaks` | Scaffolded, untested in game |
| [Prophecy](features/prophecy/README.md) | `Grimoire_Prophecy` | Scaffolded, untested in game (phase 5a: import, viewer, step panel) |
| [Tempo](features/tempo/README.md) | `Grimoire_Tempo` | Tested in game (plan: [plans/tempo.md](plans/tempo.md)) |
| [Emote wheel](features/emote-wheel/README.md) | `Grimoire_Emotes` | Scaffolded, untested in game |

New component? Copy [`features/TEMPLATE.md`](features/TEMPLATE.md) to `features/<component>/README.md` and put screenshots in `features/<component>/screenshots/`.

## Prophecy

[Plan format, version 1](prophecy/FORMAT.md): the text format Prophecy plans are written in, for people and agents writing plans outside the game.

Plans: [Troll Warlock, 1 to 30](prophecy/plans/troll-warlock-1-30.prophecy) (converted from the claude.ai guide; ships with the add-on). Check a plan with `lua scripts/prophecy/check.lua <file>`; bundle one into the add-on with `lua scripts/prophecy/bundle.lua <file> Grimoire_Prophecy/Plans/<name>.lua`.

## Architecture decision records

| ADR | Title | Status |
| --- | --- | --- |
| [0001](adr/0001-prefer-classic-style-ui.md) | Prefer classic-style UI | Accepted |
| [0002](adr/0002-every-component-is-a-toggleable-addon.md) | Every component is a separately toggleable add-on | Accepted |
| [0003](adr/0003-show-character-and-class-color.md) | Show which character owns data, in class colors | Accepted |
| [0004](adr/0004-components-replace-blizzard-ui.md) | Components replace the Blizzard UI they duplicate | Accepted |
| [0005](adr/0005-modules-describe-their-settings.md) | Modules describe their settings; core builds the menu | Accepted |
| [0006](adr/0006-prophecy-plans-are-pasted-text.md) | Prophecy plans are pasted text, stored in saved variables | Accepted |
| [0007](adr/0007-hide-blizzard-frames-in-place.md) | Hide Blizzard frames in place, without reparenting (supersedes part of 0004) | Accepted |

Number new ADRs sequentially and never edit an accepted one's decision. Supersede it with a new ADR instead.

Diagrams use [Mermaid](https://mermaid.js.org/), which renders on GitHub and in VS Code's Markdown preview.

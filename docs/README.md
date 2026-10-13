# Grimoire documentation

## Components

Each component is its own add-on and can be switched on or off in the in-game AddOns list ([ADR 0002](adr/0002-every-component-is-a-toggleable-addon.md)).

| Component | Add-on | Status |
| --- | --- | --- |
| [Core framework](features/core/README.md) | `Grimoire` | Scaffolded |
| [Warlock resource bar](features/warlock-resource-bar/README.md) | `Grimoire_Warlock` | In game testing |
| [Bags](features/bags/README.md) | `Grimoire_Bags` | Scaffolded, untested in game |
| [Bank](features/bank/README.md) | `Grimoire_Bank` | Scaffolded, untested in game |
| [Auctions](features/auctions/README.md) | `Grimoire_Auctions` | Scaffolded, untested in game |
| [Notes](features/notes/README.md) | `Grimoire_Notes` | Scaffolded, untested in game |
| [Launcher](features/launcher/README.md) | `Grimoire_Launcher` | Scaffolded, untested in game |

New component? Copy [`features/TEMPLATE.md`](features/TEMPLATE.md) to `features/<component>/README.md` and put screenshots in `features/<component>/screenshots/`.

## Architecture decision records

| ADR | Title | Status |
| --- | --- | --- |
| [0001](adr/0001-prefer-classic-style-ui.md) | Prefer classic-style UI | Accepted |
| [0002](adr/0002-every-component-is-a-toggleable-addon.md) | Every component is a separately toggleable add-on | Accepted |
| [0003](adr/0003-show-character-and-class-color.md) | Show which character owns data, in class colors | Accepted |

Number new ADRs sequentially and never edit an accepted one's decision. Supersede it with a new ADR instead.

Diagrams use [Mermaid](https://mermaid.js.org/), which renders on GitHub and in VS Code's Markdown preview.

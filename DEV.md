# Developing SilkRoad

How the addon is built, tested and organised. For what SilkRoad does and how to use it, see
the [README](README.md). The conventions every change follows (rules, patterns, workflow) are
in [AGENTS.md](AGENTS.md).

## Contents

- [Running from source](#running-from-source)
- [Project layout](#project-layout)
- [Architecture](#architecture)
- [Testing](#testing)
- [Game data](#game-data)
- [Translations](#translations)
- [Contributing](#contributing)

## Running from source

1. Clone the repository.
2. Link the addon folder into the game, so it always loads your working copy:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/link-addon.ps1
   ```

   Pass `-WowPath "D:\Games\World of Warcraft"` if the game isn't in the default location.
   Without the script, copy only the **`SilkRoad`** folder (the one containing `SilkRoad.toc`)
   into `World of Warcraft\_forever_\Interface\AddOns\`.

3. Start the game, or type `/reload` after each change.

## Project layout

```
SilkRoad/                  the addon (this folder goes into Interface\AddOns)
├─ SilkRoad.toc            interface 16001, saved variables, load order
├─ Bindings.xml            the open/close key binding
├─ Core/                   version-agnostic services
│  ├─ Init.lua             namespace, game-version detection, events, components, slash commands
│  ├─ Database.lua         saved variables, defaults, migrations, settings, data wipes
│  ├─ Prices.lua           price layer with pluggable auction price providers
│  ├─ Recipes.lua          all recipes, known recipes, cost and profit per craft
│  ├─ Planner.lua          levelling planner: cheapest route, steps, shopping list
│  ├─ Gathering.lua        gathering guides: nodes, creature levels and zones per skill
│  ├─ Sources.lua          where recipes come from, which reagents vendors sell (QuestieDB)
│  ├─ AuctionScanner.lua   full auction house scans within the 15-minute limit
│  ├─ AuctionBuyer.lua     searches and buys one item at a time (Buy Lists tab)
│  ├─ BuyLists.lua         buy lists: items, amounts, what's left to buy
│  ├─ Merchants.lua        records merchant prices
│  ├─ Bindings.lua         key binding helpers
│  └─ Util.lua             formatting and item helpers
├─ Game/Forever.lua        SR.Game: Forever's own APIs (professions, merchants, maps, names,
│                          recipe tracking, auction search and purchase)
├─ Data/Forever/           game data: recipes and items (generated), gathering facts (hand-kept)
├─ UI/                     window, sidebar, data table, widgets, tooltips, AH tabs, launchers
├─ Modules/                one file per page: Overview, Recipes, Leveling Guide, Buy Lists, Price Database, Settings, About
├─ Locales/                enUS (base) and translations
└─ Libs/                   LibStub, LibAHTab
tools/
├─ generate_data.py        builds Data/<Version>/ from Blizzard's client tables
└─ locales.py              translation checks and templates
tests/                     smoke test: runs the addon outside the game against a mock client
scripts/                   link-addon.ps1, test.ps1
docs/                      FOREVER_API_NOTES.md, TRANSLATING.md
media/                     artwork (icon); not part of the addon
AGENTS.md                  conventions and workflow for contributors and coding agents
```

## Architecture

- **Version-agnostic core.** Everything that differs between game versions lives in
  `Data/<Version>/` (generated game data) and `Game/<Version>.lua` (the `SR.Game` adapter
  for that version's APIs). Both load only on their own client (`SR.flavor`, from the
  interface number). Supporting another version means adding a flavor entry, an adapter
  and a data folder.
- **Components.** `SR:NewComponent(name)` creates a service with optional `OnInitialize`
  (saved variables ready) and `OnEnable` (player in the world) hooks.
- **Pages.** One `SR.UI:RegisterPage{ id, title, icon, order }` call plus `OnCreate(frame)`
  and `Refresh()`. Built on first open, refreshed when shown or when data changes.
- **Prices.** Everything reads through `SR.Prices`. New auction price sources plug in with
  `SR.Prices:RegisterProvider{ id, label, IsAvailable, GetPrice }`.
- **Messages.** Components talk through `SR:Fire` / `SR:RegisterCallback`:
  `SETTING_CHANGED`, `PRICES_UPDATED`, `RECIPES_UPDATED`, `SKILL_CHANGED`, `SCAN_STATUS`,
  `ITEM_INFO_RECEIVED`, `BUYLISTS_UPDATED`, `AUCTION_BUYER_UPDATED`.
- **Saved data.** `SilkRoadDB` (account: settings, auction data per realm, merchant prices,
  buy lists) and `SilkRoadCharDB` (per character: known recipes). Documented in
  `Core/Database.lua`.

## Testing

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1
```

The smoke test compiles the addon with real **Lua 5.1** (the game's version) and drives it
through `tests/scenario.lua` against a mock game client: every page, the auction scanner,
recipes and their right-click menu, raw-material breakdowns, buy lists and auction house
purchases, tooltips, settings and key binding, plus a second pass as a Spanish client
(about 400 checks). The mock checks every widget method, frame template and game function
the addon uses against the API lists generated from the Forever client, and rejects layout
and global-variable mistakes. The first run sets up `tests/.venv` (with
[lupa](https://pypi.org/project/lupa/)) and downloads the API lists. Visual checks still
need a `/reload` in game.

## Game data

`SilkRoad/Data/Forever/Recipes.lua` is generated from the game's own client tables, published
by [wago.tools](https://wago.tools):

```powershell
python tools/generate_data.py                       # pinned Forever build
python tools/generate_data.py --build 1.60.1.71000  # after a patch
```

It writes every profession recipe (reagents, product, quantity, skill thresholds, recipe item)
and the items they use (name, quality, icon, vendor prices). Where recipe items are sold or
dropped isn't in the client tables; SilkRoad reads that from QuestieDB at runtime.

Research on the Forever client, its APIs and their quirks is collected in
**[docs/FOREVER_API_NOTES.md](docs/FOREVER_API_NOTES.md)**.

## Translations

Every visible string goes through the locale tables in `SilkRoad/Locales/`. To add a
language or improve one, see **[docs/TRANSLATING.md](docs/TRANSLATING.md)**: one command
creates a file to fill in, and `tools/locales.py` checks it.

## Contributing

1. Read [AGENTS.md](AGENTS.md) for the rules (version-agnostic core, translated strings,
   purchases only from clicks) and the code patterns.
2. Work on a branch, add scenario steps for what you change, and run the tests.
3. Open a pull request describing the change and how you tested it in game.

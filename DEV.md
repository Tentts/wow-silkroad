# Developing SilkRoad

How the addon is built, tested, researched and released. For what SilkRoad does and how to
use it, see the [README](README.md). The conventions every change follows (rules, patterns,
pitfalls, workflow) are in [AGENTS.md](AGENTS.md).

## Contents

- [Setting up](#setting-up)
- [Running from source](#running-from-source)
- [Project layout](#project-layout)
- [Architecture](#architecture)
- [Testing](#testing)
- [Debugging in game](#debugging-in-game)
- [Research sources](#research-sources)
- [Game data](#game-data)
- [Translations](#translations)
- [Releasing](#releasing)
- [Contributing](#contributing)

## Setting up

Needed:

- **Git** and **Python 3.11+** on the `PATH` (the tests and tools are Python).
- **PowerShell** for `scripts/*.ps1` (Windows; on other systems run the Python commands
  they wrap, shown below).
- The game, **World of Warcraft: Forever**, for checking changes in game. Default install:
  `C:\Program Files (x86)\World of Warcraft\_forever_\`.

Then:

```powershell
git clone https://github.com/Tentts/wow-silkroad.git
cd wow-silkroad
git checkout dev                                              # development happens on dev
powershell -ExecutionPolicy Bypass -File scripts/test.ps1     # first run sets up the tests
```

The first test run creates `tests/.venv` (Python with [lupa](https://pypi.org/project/lupa/))
and clones the Forever API lists into `tests/.api`. Both are ignored by git. Without
PowerShell:

```bash
python -m venv tests/.venv && tests/.venv/bin/pip install lupa      # Scripts\ on Windows
git clone --depth 1 --branch forever https://github.com/Ketho/BlizzardInterfaceResources.git tests/.api
tests/.venv/bin/python -I tests/smoke_test.py --api tests/.api/Resources
```

## Running from source

1. Link the addon folder into the game, so it always loads your working copy:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/link-addon.ps1
   ```

   Pass `-WowPath "D:\Games\World of Warcraft"` if the game isn't in the default location.
   Without the script, copy only the **`SilkRoad`** folder (the one containing `SilkRoad.toc`)
   into `World of Warcraft\_forever_\Interface\AddOns\`.

2. Start the game, or type `/reload` after each change.

## Project layout

```
SilkRoad/                  the addon (this folder goes into Interface\AddOns)
├─ SilkRoad.toc            interface 16001, version, saved variables, load order
├─ Bindings.xml            the open/close key binding
├─ Core/                   version-agnostic services (components)
│  ├─ Init.lua             namespace, game-version detection, events, components, slash commands
│  ├─ Util.lua             formatting and item helpers
│  ├─ Database.lua         saved variables, defaults, migrations, settings, data wipes, market keys
│  ├─ Prices.lua           price layer with pluggable auction price providers; vendor prices
│  ├─ Sources.lua          where recipes come from, vendors (QuestieDB)
│  ├─ Recipes.lua          all recipes, known recipes, favorites, recipe colours, costs, raw breakdown
│  ├─ Planner.lua          levelling planner: cheapest route, steps, shopping list
│  ├─ Gathering.lua        gathering guides: nodes, creature levels and zones per skill
│  ├─ Merchants.lua        records merchant prices
│  ├─ Bindings.lua         key binding helpers
│  ├─ AuctionScanner.lua   full auction house scans within the 15-minute limit; login data age
│  ├─ AuctionBuyer.lua     searches and buys one item at a time (Buy Lists tab)
│  ├─ BuyLists.lua         buy lists: items, amounts, recipes, what's left to buy
│  ├─ ItemSearch.lua       item name search for suggestion lists
│  └─ BagSpace.lua         full bags while looting: which bag items are worth less
├─ Game/Forever.lua        SR.Game: every Forever-specific API call (see its header)
├─ Data/Forever/           Recipes.lua (generated recipes and items), Gathering.lua (hand-kept facts)
├─ UI/                     shared interface pieces
│  ├─ Widgets.lua          buttons, inputs, dropdowns, dialogs (Confirm, Prompt, Notice)
│  ├─ DataTable.lua        the sortable, virtualised table
│  ├─ MainFrame.lua        the window, sidebar and page system
│  ├─ Launcher.lua         minimap button, addon compartment
│  ├─ OptionsPanel.lua     entry in the game's options
│  ├─ Tooltip.lua          prices and recipes in item tooltips
│  ├─ SourcePopup.lua      the "Obtained at" window with waypoints
│  ├─ RecipeMenu.lua       the recipe right-click menu
│  ├─ ItemSuggestions.lua  suggestion list under item boxes
│  ├─ ProfessionPrices.lua panel in Blizzard's professions window
│  ├─ BagGlow.lua          red glow on bag slots
│  ├─ AuctionHouseTab.lua  SilkRoad tab in the auction house
│  └─ AuctionHouseBuyLists.lua  Buy Lists tab in the auction house
├─ Modules/                one file per page: Overview, Recipes, Guide, BuyLists, PriceDatabase, Settings, About
├─ Locales/                enUS (base) and esES
└─ Libs/                   LibStub, LibAHTab
tools/
├─ generate_data.py        builds Data/<Version>/Recipes.lua from Blizzard's client tables
└─ locales.py              translation checks and templates
tests/
├─ wow_mock.lua            mock game client (widgets, game APIs, events, timers)
├─ scenario.lua            the test run: steps and checks
└─ smoke_test.py           runner: Lua 5.1, API validation, translation audit, Spanish pass
scripts/                   link-addon.ps1, test.ps1
docs/                      FOREVER_API_NOTES.md, TRANSLATING.md
media/                     artwork (icon); not part of the addon
AGENTS.md                  rules, patterns, pitfalls and workflow
CHANGELOG.md               release notes of the version being released
.pkgmeta                   packager settings (the zip holds only SilkRoad/)
.github/workflows/         release.yml: builds and uploads tagged versions
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
- **Blizzard UI.** SilkRoad adds to Blizzard's windows only through post-hooks and its own
  child frames: LibAHTab tabs in the auction house, a panel in the professions window
  (`SR.Game.HookRecipeView`), tooltip post-calls and glows over bag slots.
- **Saved data.** `SilkRoadDB` (account: settings, auction prices per auction house,
  merchant prices, live recipes, buy lists, favorites, recipe colours) and `SilkRoadCharDB`
  (per character: known recipes). The full schema is documented in `Core/Database.lua`.

## Testing

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1
```

The smoke test compiles the addon with real **Lua 5.1** (the game's version) and drives it
through `tests/scenario.lua` against a mock game client: every page, the auction scanner and
buyer, recipes and their right-click menu, raw-material breakdowns, the planner, buy lists,
tooltips, the professions window panel, the full-bags helper, settings and key binding,
plus a second pass as a Spanish client (about 540 checks). The mock checks every widget
method, frame template and game function the addon uses against the API lists generated
from the Forever client, and rejects layout and global-variable mistakes. Mock helpers and
debugging tips are in [AGENTS.md](AGENTS.md#testing). Visual checks still need a `/reload`
in game.

## Debugging in game

- `/silkroad debug` turns on debug messages; `/silkroad help` lists every command.
- Saved data is written on logout or `/reload` to
  `_forever_\WTF\Account\<account>\SavedVariables\SilkRoad.lua` (and `SilkRoad.lua.bak`).
  Reading it shows exactly what SilkRoad stored (auction prices, merchant prices, colours).
- With [BugGrabber](https://www.curseforge.com/wow/addons/bug-grabber) installed, Lua errors
  are saved to `SavedVariables\!BugGrabber.lua` on logout.
- Installed addons in `_forever_\Interface\AddOns` (Auctionator, Questie, Baganator…) are
  good references for how others handle Forever's APIs; read, don't copy.

## Research sources

- **Blizzard's UI source for Forever** (how the client's own frames work, which functions
  exist): <https://github.com/Gethe/wow-ui-source/tree/forever>. A sparse clone keeps it
  small:

  ```bash
  git clone --filter=blob:none --sparse --depth 1 --branch forever https://github.com/Gethe/wow-ui-source.git ui
  cd ui && git sparse-checkout set Interface/AddOns/Blizzard_APIDocumentationGenerated Interface/AddOns/Blizzard_Professions Interface/AddOns/Blizzard_ProfessionsTemplates Interface/AddOns/Blizzard_AuctionHouseUI Interface/AddOns/Blizzard_UIParentPanelManager
  ```

  `Blizzard_APIDocumentationGenerated` documents every API, event and enum.
- **Generated API lists** (what the tests validate against):
  <https://github.com/Ketho/BlizzardInterfaceResources/tree/forever>.
- What SilkRoad learned about the client is in
  **[docs/FOREVER_API_NOTES.md](docs/FOREVER_API_NOTES.md)**.

## Game data

`SilkRoad/Data/Forever/Recipes.lua` is generated from the game's own client tables, published
by [wago.tools](https://wago.tools):

```powershell
python tools/generate_data.py                       # pinned Forever build
python tools/generate_data.py --build 1.60.1.71000  # after a patch
```

It writes every profession recipe (reagents, product, quantity, skill thresholds, recipe item)
and the items they use (name, quality, icon, vendor prices). Where recipe items are sold or
dropped isn't in the client tables; SilkRoad reads that from QuestieDB at runtime. Trainer
recipes have no learn level in the tables (estimated, shown with `~`), and the colours the
professions window shows correct the thresholds at runtime.

## Translations

Every visible string goes through the locale tables in `SilkRoad/Locales/`. To add a
language or improve one, see **[docs/TRANSLATING.md](docs/TRANSLATING.md)**: one command
creates a file to fill in, and `tools/locales.py` checks it.

## Releasing

Releases are cut from `master` by pushing a version tag:

1. On a `chore/release-<version>` branch from `dev`: bump `## Version` in
   `SilkRoad/SilkRoad.toc`, the README badge, the version in AGENTS.md and the version checks
   in `tests/scenario.lua`, and rewrite `CHANGELOG.md` with that version's notes only.
2. Merge into `dev`, then `dev` into `master` (fast-forward), and push both.
3. `git tag -a v<version> -m "SilkRoad <version>"` on `master` and push the tag.

`.github/workflows/release.yml` checks the tag matches the TOC version, then
[BigWigsMods/packager](https://github.com/BigWigsMods/packager) builds the zip (only the
`SilkRoad/` folder, see `.pkgmeta`) and uploads it to CurseForge and GitHub Releases with
`CHANGELOG.md` as the notes. It needs the repository secret `CF_API_KEY` (a CurseForge API
token). Tags with `-beta1` / `-alpha1` make beta / alpha files.

## Contributing

1. Read [AGENTS.md](AGENTS.md) for the rules (version-agnostic core, translated strings,
   purchases only from clicks, no keyboard capture) and the code patterns.
2. Work on a branch from `dev` (`master` only gets releases), add scenario steps for what
   you change, and run the tests.
3. Open a pull request against `dev` describing the change and how you tested it in game.

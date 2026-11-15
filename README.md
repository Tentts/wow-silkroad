<div align="center">

# SilkRoad

**A crafting and trading companion for World of Warcraft: Forever.**

Find out which recipes make gold, where to sell what you craft, where to get the recipes you're missing, the cheapest way to level a profession, and buy everything a craft needs in a few clicks.

![Game](https://img.shields.io/badge/WoW-Forever-c79c6e)
![Interface](https://img.shields.io/badge/interface-16001-blue)
![Version](https://img.shields.io/badge/version-0.7.0-informational)
![Lua](https://img.shields.io/badge/Lua-5.1-2C2D72?logo=lua)
![Languages](https://img.shields.io/badge/languages-English%20%7C%20Espa%C3%B1ol-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

SilkRoad lists **every recipe of every profession** and works out, for each one,
what its materials cost and what the result sells for, on the auction house and to
a vendor, whether you buy the reagents or craft every step yourself. It scans the
auction house on its own, knows which reagents vendors sell and for how much, tells
you where each recipe is obtained, and marks the recipes your character already knows.
Turn any recipe into a **buy list** and buy it item by item from the auction house.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting started](#getting-started)
- [How prices are worked out](#how-prices-are-worked-out)
- [Commands](#commands)
- [Languages](#languages)
- [For developers](#for-developers)
- [Roadmap](#roadmap)
- [Credits](#credits)
- [License](#license)

## Features

### Recipes for every profession

- **All 12 professions**, from Alchemy to Tailoring, including Mining smelts, Cooking,
  First Aid and Forever's new crafts. That's **2,129 recipes**, generated from the
  game's own data.
- Browse professions your character **doesn't have** as well as the ones it does.
- **Known recipes** are read from your spellbook automatically. A **Known only** filter
  hides the rest.
- One sortable, searchable table:

  | Column | Shows |
  |---|---|
  | **Recipe** | The item made. Recipes you haven't learned are greyed out. |
  | **Level** | Skill needed to learn it, coloured like the profession window for your character (red: not yet, orange, yellow, green, grey). |
  | **Obtained at** | Trainer, learned with the profession, or the vendor, drop, quest or container that gives the recipe. **Click** for every source with zone and coordinates. |
  | **Cost** | Materials at the cheapest price per reagent, vendor or auction house. |
  | **Raw cost** | The same craft made from raw materials, crafting every intermediate yourself (a Medium Armor Kit for a Forceful one, Medium Leather from Light Leather). `-` when nothing in the recipe can be crafted. |
  | **AH price** / **Vendor price** | What the result sells for. |
  | **AH profit** / **Vendor profit** | Earnings after the material cost (the AH one after the auction house cut). |
  | **Sell to** | *Auction* or *Vendor*, whichever earns more. Sorting by it sorts by the better profit. |

- Hover a recipe for a **per-reagent cost breakdown** showing where each price comes from,
  and, when reagents can be crafted, the **intermediate crafts and raw materials** behind
  the Raw cost.
- Click a source to set a **waypoint**, through [TomTom](https://www.curseforge.com/wow/addons/tomtom)
  if installed, otherwise the game's own map pin.
- **Right-click** a recipe (here or in a Leveling Guide step) for its menu:
  - **Track in objectives**: the game's objective tracker lists it under your quests and
    counts its reagents as you gather them.
  - **Add to a buy list...**: its reagents, times the crafts you ask for (a guide step
    suggests its own count). Reagents vendors sell are left out.
  - **Add raw materials to a buy list...**: the raw materials for crafting every step
    yourself, shown when something in the recipe can be crafted.
  - **Where to get it**: every source of the recipe.

### Buy lists

Named shopping lists for the auction house, shared by all your characters.

- **Manage them** on the Buy Lists page: create, rename, copy and delete lists, add items
  (item ID, name or a shift-clicked link) and set how many of each you want.
- **Fill them from recipes**: right-click a recipe for its reagents, or its raw materials
  (lists named like *Medium Armor Kit x2 (raw)*).
- Each item shows how many you **have**, how many are **left** to buy, and the cost at the
  latest scan prices. Items you have enough of are marked done, and so are finished lists.
- **Buy them** from the **Buy Lists tab** in the auction house: pick a list, click an item
  to search it, set the quantity (what's left, by default), then **Buy** and **Confirm** at
  the price the auction house quotes. **Next item** moves on to the next thing to buy.
  The game needs a click for every purchase, so nothing is ever bought automatically.
- Stackable reagents are bought by **quantity**; other items one **whole auction** at a time,
  cheapest per item first. Your own auctions are skipped, and changing the quantity after
  **Buy** drops the quote, so you always confirm the amount you see.

### Leveling guide

A **dynamic levelling planner**: the cheapest route from your current skill to a target,
worked out from current prices instead of a fixed guide.

- For every skill point it picks the craft with the **lowest cost per expected skill-up**,
  using each recipe's skill-up chance (orange, yellow, green, grey).
- Costs come from live prices. Intermediates such as bolts of cloth are **crafted when
  that's cheaper than buying them**, and you can count **resale** (to vendors, or wherever
  the result earns most).
- Choose which recipes may be used: **known only**, + trainer, + vendor, + auction house,
  + drops. Recipes to learn are marked; click to see where to get them.
- **Progress tracking**: the current step is highlighted and the plan **re-calculates** when
  your skill goes up, prices change or you learn a recipe.
- A **shopping list** with what you need, what's already in your bags and bank, and the
  cheapest source for the rest.
- **Training reminders**: rows marking when to train Journeyman (at 50), Expert (125) and
  Artisan (200), for ranks you haven't trained yet.
- **Gathering professions** (Mining, Herbalism, Skinning, Fishing) get a simple route: what to
  gather at each skill and where. Mining and Herbalism list the best node for each bracket and
  the zones it's found in, ranked by node count when GatherMate2's node database is enabled;
  Skinning suggests creature levels and zones; Fishing suggests zones where fish don't get away.
  **Click a step** to open the world map on its zone (pick one if there are several); for ore
  and herbs a waypoint marks where those nodes are densest.

### Auction house

- **Automatic scans.** A few seconds after you open the auction house, SilkRoad requests a
  full scan and saves each item's lowest buyout and the quantity listed, per realm.
- **Respects the server's limit** of one full scan every 15 minutes, automatic or manual.
  The limit is tracked across characters and reloads.
- **No stutter.** Listings are processed in small batches across frames.
- **Shares data with other addons.** When Auctionator or another addon runs a full scan,
  SilkRoad records the results too, without a request of its own.
- A small **SilkRoad tab** in the auction house window shows the last scan and a countdown,
  and has a **Scan now** button, the auto-scan toggle and shortcuts into SilkRoad.
- A **Buy Lists tab** buys your [buy lists](#buy-lists) item by item.

### Prices everywhere

- **Item tooltips** get two lines, like Auctionator's: what a vendor pays, and the lowest
  auction price (only for items that can be sold there).
- **Merchant prices are recorded** every time you open a vendor, but you never have to visit
  vendors: common reagent prices come from the game data.
- **Price Database** page: look up any item by ID, name or shift-clicked link to see every
  known price side by side. Your last 20 lookups stay one click away.

### Comfort

- Open the window with **`/silkroad`**, a **key binding**, the **minimap button** or the
  **addon compartment** menu.
- Movable, resizable and scalable window that closes with **Escape**.
- **Settings** in three tabs (General, Prices, Data), including a market data wipe and a
  settings reset.

## Requirements

| | |
|---|---|
| **Game** | World of Warcraft: Forever (interface `16001`) |
| **Recommended** | [Questie](https://www.curseforge.com/wow/addons/questie) with its QuestieDB data addon. It provides where recipes are sold or dropped, and which reagents vendors sell. |
| **Optional** | [Auctionator](https://www.curseforge.com/wow/addons/auctionator): its prices are used as an extra source. [TomTom](https://www.curseforge.com/wow/addons/tomtom): waypoints with an arrow. [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2) with GatherMate2_Data (both enabled): node counts per zone and waypoints to nodes in the gathering guides. |

SilkRoad works on its own; the optional addons only add information.

## Installation

1. Download this repository (**Code > Download ZIP**) or clone it.
2. Copy the **`SilkRoad`** folder (the one containing `SilkRoad.toc`) into:

   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```

3. Start the game, or type `/reload` if it's already running, and check that SilkRoad is
   enabled in the AddOns list on the character screen.

> [!TIP]
> Working on the code? Link the folder instead of copying it, so the game always loads
> your working copy:
>
> ```powershell
> powershell -ExecutionPolicy Bypass -File scripts/link-addon.ps1
> ```
>
> Pass `-WowPath "D:\Games\World of Warcraft"` if the game isn't in the default location.

## Getting started

1. Type **`/silkroad`** (or **`/silk`**), or click the minimap button.
2. Open the **auction house** once. SilkRoad scans it automatically and fills in auction prices.
3. Go to **Recipes**, pick a profession and sort by **Sell to** to see the most profitable
   crafts first.
4. Want to level up? Open **Leveling Guide**, pick the profession and follow the steps.
5. Right-click a recipe and choose **Add to a buy list...**, then buy the list from the
   **Buy Lists** tab of the auction house.
6. Optional: set a key in **Settings > General > Key binding** to open SilkRoad instantly.

## How prices are worked out

All prices are per item, in copper, shown in gold, silver and copper.

| Price | Where it comes from |
|---|---|
| **Auction price** | Lowest buyout from SilkRoad's latest scan of your realm, or Auctionator's price if it has one and SilkRoad doesn't. You can prefer one source in Settings. |
| **Vendor sell price** (what a vendor pays you) | The game's item data. |
| **Vendor buy price** (what a merchant charges) | In order: a price SilkRoad recorded at a merchant, one Auctionator recorded, or the game's item data for items vendors are known to sell (via QuestieDB). |
| **Material cost** | Per reagent, the cheaper of its vendor buy price and auction price. Left empty when a reagent has no price at all. |
| **Raw cost** | Material cost with every craftable reagent crafted instead: by a recipe of the same profession, or of another profession your character knows. A reagent that has a price is bought when its own materials can't be priced (Light Leather rather than Ruined Leather Scraps nobody sells). |
| **AH profit** | Auction price × quantity made, minus the auction house cut (5% by default, adjustable), minus material cost. |
| **Vendor profit** | Vendor sell price × quantity made, minus material cost. |

> [!NOTE]
> The skill needed to learn a recipe is exact for recipes taught by a pattern, plan or
> formula. For trainer recipes the game data doesn't contain the requirement, so SilkRoad
> shows the closest value, marked with `~`.

## Commands

| Command | Does |
|---|---|
| `/silkroad` or `/silk` | Opens or closes the window |
| `/silkroad recipes` · `guide` · `buylists` · `overview` · `prices` · `settings` | Opens a page directly |
| `/silkroad scan` | Scans the auction house (it must be open) |
| `/silkroad minimap` | Shows or hides the minimap button |
| `/silkroad reset` | Resets the window position and size |
| `/silkroad debug` | Toggles debug messages |
| `/silkroad version` | Prints the version |
| `/silkroad help` | Lists all commands |

## Languages

SilkRoad follows the game's language. **English** and **Spanish** (esES/esMX) are
included; anything untranslated falls back to English. Recipe, item, profession and zone
names always come from the game in its own language.

Want to add a language? See **[docs/TRANSLATING.md](docs/TRANSLATING.md)**: one command
creates a file to fill in.

## For developers

### Project layout

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
├─ UI/                     window, sidebar, data table, widgets, tooltips, AH tab, launchers
├─ Modules/                one file per page: Overview, Recipes, Leveling Guide, Buy Lists, Price Database, Settings
├─ Locales/                enUS (base) and translations
└─ Libs/                   LibStub, LibAHTab
tools/
├─ generate_data.py        builds Data/<Version>/ from Blizzard's client tables
└─ locales.py              translation checks and templates
tests/                     smoke test: runs the addon outside the game against a mock client
scripts/                   link-addon.ps1, test.ps1
docs/                      FOREVER_API_NOTES.md, TRANSLATING.md
media/                     artwork (icon); not part of the addon
.pkgmeta                   what goes into the release zip (only SilkRoad/)
.github/workflows/         release.yml: packages and uploads tagged versions
AGENTS.md                  conventions and workflow for contributors and coding agents
```

### Architecture

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

### Testing

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1
```

The smoke test compiles the addon with real **Lua 5.1** (the game's version) and drives it
through `tests/scenario.lua` against a mock game client: every page, the auction scanner,
recipes and their right-click menu, raw-material breakdowns, buy lists and auction house
purchases, tooltips, settings and key binding, plus a second pass as a Spanish client
(about 400 checks). The mock
checks every widget method, frame template and game function the addon uses against the
API lists generated from the Forever client, and rejects layout and global-variable mistakes.
The first run sets up `tests/.venv` (with [lupa](https://pypi.org/project/lupa/)) and downloads
the API lists. Visual checks still need a `/reload` in game.

### Game data

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

### Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
(`.github/workflows/release.yml`) whenever a version tag is pushed. It zips only the
`SilkRoad/` folder (see `.pkgmeta`), writes a changelog from the commits since the previous
tag, and uploads the zip to CurseForge and GitHub Releases. The game version (Forever) comes
from the TOC's `## Interface`.

1. Bump `## Version` in the TOC, the badge above and the version check in
   `tests/scenario.lua`, run the tests and merge into `master`.
2. Tag that commit with the same version and push the tag:

   ```powershell
   git tag v0.7.1
   git push origin v0.7.1
   ```

The tag name sets the CurseForge release type: `v0.7.1` is a release, `v0.8.0-beta1` a beta
and `v0.8.0-alpha1` an alpha. The workflow stops if the tag doesn't match the TOC version.

One-time setup: `## X-Curse-Project-ID` in the TOC holds the CurseForge project ID, and the
repository secret `CF_API_KEY` holds a CurseForge API token (created under *API Tokens* in
the CurseForge author account settings).

## Roadmap

- [x] Recipe list for every profession with costs, profits and where to sell
- [x] Recipe sources with waypoints
- [x] Automatic auction house scanning
- [x] Known recipes from the spellbook
- [x] Tooltip prices, key binding, translations
- [x] Dynamic levelling planner with progress tracking and a shopping list
- [x] Simple levelling guides for gathering professions
- [x] Recipe tracking in the objective tracker
- [x] Buy lists, bought from the auction house
- [x] Raw materials: Raw cost and raw buy lists for crafting every step
- [ ] Crafting queue
- [ ] Price history and trends
- [ ] More languages
- [ ] Other game versions, through the version layer

## Credits

- Recipe and item data: Blizzard's client tables, via [wago.tools](https://wago.tools).
- Recipe sources and vendor lists: [Questie](https://github.com/Questie/Questie)'s QuestieDB, read at runtime.
- Ore and herb node locations: [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2)'s GatherMate2_Data, read at runtime.
- Herbalism requirements, training ranks and Forever's zone notes cross-checked against
  [wow-professions.com](https://www.wow-professions.com/forever/herbalism-leveling-guide)'s Forever guide (facts only).
- Ore, herb and skinning zones cross-checked against [wow.gg](https://wow.gg/professions/forever/mining)'s Forever
  gathering guides (facts only).
- Bundled libraries, unmodified, in `SilkRoad/Libs/`:
  - [LibStub](https://www.wowace.com/projects/libstub): public domain.
  - [LibAHTab](https://github.com/Auctionator/LibAHTab) by plusmouse: MIT (`Libs/LibAHTab/LICENSE`).
    Adds the auction house tab without tainting it.

World of Warcraft is a trademark of Blizzard Entertainment, Inc. SilkRoad is a fan-made addon
and isn't affiliated with or endorsed by Blizzard.

## License

Released under the [MIT License](LICENSE). Bundled libraries keep their own licenses (see [Credits](#credits)).

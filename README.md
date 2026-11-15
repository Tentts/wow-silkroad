<div align="center">

<img src="media/icon.png" alt="SilkRoad" width="128">

# SilkRoad

**A crafting and trading companion for World of Warcraft: Forever.**

Find out which recipes make gold, where to sell what you craft, where to get the recipes you're missing, the cheapest way to level a profession, and buy everything a craft needs in a few clicks.

![Game](https://img.shields.io/badge/WoW-Forever-c79c6e)
![Version](https://img.shields.io/badge/version-0.7.2-informational)
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
- [Roadmap](#roadmap)
- [Feedback](#feedback)
- [Contributing](#contributing)
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
  - **Add to favorites**: starred in the list and in item tooltips (see below). For learned
    recipes these are the same favorites as the star in the game's professions window.
  - **Add to a buy list...**: its reagents, times the crafts you ask for (a guide step
    suggests its own count). Reagents vendors sell are left out.
  - **Add raw materials to a buy list...**: the raw materials for crafting every step
    yourself, shown when something in the recipe can be crafted.
  - **Where to get it**: every source of the recipe.

### Buy lists

Named shopping lists for the auction house, shared by all your characters.

- **Manage them** on the Buy Lists page: create, rename, copy and delete lists, add items
  and set how many of each you want. Type part of a name (`light`) and pick the item from
  the **suggestions** (Light Leather, Light Hide...), or use an item ID or a shift-clicked link.
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
  auction price (only for items that can be sold there). For stacks in your bags, choose in
  Settings whether they show the price of **one item**, the **whole stack**, or **both** (one
  line each), or turn the lines off. Holding **Shift** over a stack swaps between one item
  and the stack.
- **Which recipes use an item**: tooltips list the recipes that need it as a reagent, with
  their profession. Choose in Settings: your **favorites** only, **learned** recipes and
  favorites (the default), **all** recipes, or off. Favorites are starred and listed first.
- **Merchant prices are recorded** every time you open a vendor, but you never have to visit
  vendors: common reagent prices come from the game data.
- **Price Database** page: look up any item by ID, name or shift-clicked link to see every
  known price side by side. Typing part of a name suggests matching items. Your last 20
  lookups stay one click away.

### Comfort

- Open the window with **`/silkroad`**, a **key binding**, the **minimap button** or the
  **addon compartment** menu.
- Movable, resizable and scalable window that closes with **Escape**.
- **Settings** in three tabs (General, Prices, Data), including a market data wipe and a
  settings reset.
- An **About** page with the version, links to SilkRoad on GitHub and CurseForge, and where
  to report problems or suggest ideas (click a link, then Ctrl+C to copy it).

## Requirements

| | |
|---|---|
| **Game** | World of Warcraft: Forever |
| **Recommended** | [Questie](https://www.curseforge.com/wow/addons/questie) with its QuestieDB data addon. It provides where recipes are sold or dropped, and which reagents vendors sell. |
| **Optional** | [Auctionator](https://www.curseforge.com/wow/addons/auctionator): its prices are used as an extra source. [TomTom](https://www.curseforge.com/wow/addons/tomtom): waypoints with an arrow. [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2) with GatherMate2_Data (both enabled): node counts per zone and waypoints to nodes in the gathering guides. |

SilkRoad works on its own; the optional addons only add information.

## Installation

### With the CurseForge app (recommended)

1. In the [CurseForge app](https://www.curseforge.com/download/app), open
   **World of Warcraft** and choose your **Forever** installation.
2. Search for **SilkRoad** and click **Install**. Or open the
   [SilkRoad project page](https://www.curseforge.com/projects/1806315) and click **Install**.
3. Start the game, or type `/reload` if it's already running.

The app keeps SilkRoad up to date; there's nothing to copy by hand.

### Manual download

1. Download the latest zip from the
   [SilkRoad project page](https://www.curseforge.com/projects/1806315) (**Files**) or from
   [GitHub Releases](https://github.com/Tentts/wow-silkroad/releases).
2. Extract it into the AddOns folder, so you end up with `AddOns\SilkRoad\SilkRoad.toc`:

   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```

3. Start the game, or type `/reload` if it's already running, and check that SilkRoad is
   enabled in the AddOns list on the character screen.

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
| `/silkroad recipes` · `guide` · `buylists` · `overview` · `prices` · `settings` · `about` | Opens a page directly |
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

Want SilkRoad in your language? See **[docs/TRANSLATING.md](docs/TRANSLATING.md)**: one
command creates a file to fill in.

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

## Feedback

Suggestions and bug reports are welcome: [open an issue](https://github.com/Tentts/wow-silkroad/issues).

## Contributing

Bug fixes, features and translations are welcome. **[DEV.md](DEV.md)** explains how to run
SilkRoad from source, how the code is organised and how to test a change.

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
    Adds SilkRoad's tabs to the auction house window.

World of Warcraft is a trademark of Blizzard Entertainment, Inc. SilkRoad is a fan-made addon
and isn't affiliated with or endorsed by Blizzard.

## License

Released under the [MIT License](LICENSE). Bundled libraries keep their own licenses (see [Credits](#credits)).

The MIT License covers SilkRoad's own code and artwork. Game data such as recipe and item
names, IDs and icons comes from World of Warcraft and belongs to Blizzard Entertainment; it
isn't covered by this license.

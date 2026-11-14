# SilkRoad

A crafting and trading helper for **World of Warcraft: Forever**. SilkRoad
compares what a recipe's materials cost (from vendors and the auction house)
with what the result sells for, so profitable crafts, auction house flips and
"craft and sell to a vendor" gold become easy to spot.

> **Status: 0.3.0.** Every recipe of every profession (from the game's own data),
> where each is obtained, material costs from vendors and the auction house,
> SilkRoad's own auction scanner, and merchant price recording. Works best with
> Questie installed (for recipe locations and vendor-sold reagents); Auctionator's
> prices are used too when it's installed.

## Install (development)

The addon lives in the `SilkRoad/` folder of this repository. Link it into the
game so WoW loads it straight from here:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/link-addon.ps1
```

That creates a junction at `World of Warcraft\_forever_\Interface\AddOns\SilkRoad`
(pass `-WowPath "D:\...\World of Warcraft"` for a different install). After
editing code, type `/reload` in game.

## Using it

- `/silkroad` or `/silk` opens and closes the window. So does the minimap button
  and the addon compartment menu by the minimap (right-click either for settings).
- `/silkroad help` lists every command: `scan`, `minimap`, `reset`, `debug`,
  `version`, plus page names to jump straight to a page (`/silkroad recipes`).
- The window can be moved, resized from the bottom-right corner, scaled in
  Settings, and closed with Escape.

### Recipes

- Pick any profession, even one this character doesn't have (it says so in red).
- **Level** is the skill needed to learn the recipe, coloured like the profession
  window (red: can't learn yet, orange/yellow/green/grey: skill-up chance). For
  trainer recipes the game data has no exact requirement, so the value is marked `~`.
- **Obtained at**: trainer, learned with the profession, or the recipe item and who
  sells or drops it. Click it for every source with zone and coordinates; click a
  source to set a waypoint (TomTom when installed, otherwise the game's map pin).
- **Cost** uses the cheapest source per reagent: a vendor price (recorded at a
  merchant, seen by Auctionator, or from the game data for items vendors are known
  to sell) or the lowest auction price. **Profit** is the better of the auction
  price after the cut and the vendor price, minus the cost.
- Open each of your profession windows once: SilkRoad then marks which recipes you
  know (and offers a **Known only** filter), and picks up any recipe its data lacks.

### Auction house scanning

- When you open the auction house, SilkRoad requests a full scan (one
  `ReplicateItems` call that returns every listing) a few seconds later and
  saves each item's lowest unit buyout and total quantity for the realm.
- The server allows one full scan every **15 minutes**, so SilkRoad never asks more
  often, automatically or manually. The time is saved account-wide, so `/reload`
  or switching characters doesn't reset it.
- Listings are read in batches across frames, so the game doesn't stall on a big
  auction house. Closing the auction house mid-scan cancels it.
- A full scan started by another addon (Auctionator, for example) is recorded too,
  without an extra request. Auctionator's recent full scans also count toward the
  15-minute wait.
- The **SilkRoad** tab in the auction house window shows the last scan, a
  countdown, a **Scan now** button, the automatic-scan toggle and shortcuts into
  SilkRoad. `/silkroad scan` does the same from chat. Automatic scanning can be
  turned off on the tab or in Settings.

### Pages

| Page | What it shows |
|---|---|
| **Overview** | Counts of indexed recipes and recorded prices, your professions, which price sources are active. |
| **Recipes** | Every recipe of any profession, learned or not: skill level (coloured for your character), where it's obtained (click for vendors, drops and quests with waypoints), material cost, AH price, vendor price and profit. Hover a row for the cost per reagent. |
| **Vendor Flips** | Items a merchant sells for less than they fetch on the auction house. |
| **Price Database** | Look up any item (ID, name, or shift-click a link) to see every known price side by side. Your last 20 lookups stay listed below for quick re-checks. |
| **Settings** | Minimap button, window scale, auction house cut, preferred auction price source, automatic auction scans. |

## How it is built

```
SilkRoad/
  SilkRoad.toc          interface 16001, saved variables, load order
  Libs/                 LibStub, LibAHTab (third-party, see below)
  Locales/enUS.lua      strings (English text doubles as the key)
  Core/
    Init.lua            namespace, game-version detection, events, components, slash commands
    Util.lua            money/percent/time formatting, item helpers
    Database.lua        saved variables, defaults, migrations, settings by path
    Prices.lua          the price layer and pluggable auction price providers
    Sources.lua         where recipes come from and which reagents vendors sell (QuestieDB)
    Recipes.lua         all recipes, known recipes, cost and profit per craft
    Merchants.lua       records merchant prices
    AuctionScanner.lua  full auction house scan with the 15-minute limit
  Game/Forever.lua      SR.Game: Forever's own APIs (profession window, merchants, waypoints)
  Data/Forever/         generated game data (recipes, items) for Forever
  UI/
    Widgets.lua         small factories over Blizzard templates
    DataTable.lua       sortable, filterable, virtualised table (ScrollBox)
    MainFrame.lua       the window, the sidebar and the page registry
    Launcher.lua        minimap button and addon compartment entry
    OptionsPanel.lua    entry in Blizzard's Options > AddOns
    AuctionHouseTab.lua the SilkRoad tab in the auction house window
  Modules/              one file per page
tools/generate_data.py  generates Data/<Version>/ from Blizzard's client tables
tests/                  smoke test that runs the addon outside the game
scripts/                link-addon.ps1, test.ps1
docs/                   FOREVER_API_NOTES.md (research on the Forever client and its API)
```

- **Version-agnostic core.** Everything that differs between game versions lives in
  `Data/<Version>/` (generated game data) and `Game/<Version>.lua` (the `SR.Game`
  adapter for that version's APIs); both load only on their own client
  (`SR.flavor`, set from the interface number in `Core/Init.lua`). The services and
  pages only use `SR.Game` and the data. Supporting another version means adding a
  flavor entry, a `Game/` adapter and a data folder. The auction scanner still calls
  Forever's modern auction API directly and would move behind `SR.Game` then.
- **Components.** `SR:NewComponent(name)` creates a subsystem with optional
  `OnInitialize` (saved variables ready) and `OnEnable` (player in world) hooks.
- **Pages.** A page is one `SR.UI:RegisterPage{ id, title, icon, order }` call plus
  `OnCreate(frame)` and `Refresh()`. Pages are built the first time they're opened
  and refreshed whenever they're shown or the price data changes.
- **Prices.** Pages only talk to `SR.Prices`: vendor sell price (from the client),
  merchant price (recorded), and auction price from *providers*. Built-in
  providers are SilkRoad's own scans and Auctionator; new sources plug in with
  `SR.Prices:RegisterProvider{ id, label, IsAvailable, GetPrice }`.
- **Saved data.** `SilkRoadDB` (account) holds settings, per-realm auction data,
  merchant prices and recipe definitions; `SilkRoadCharDB` holds what the
  character knows. The layout is documented at the top of `Core/Database.lua`.
- **Messages.** Components talk through `SR:Fire` / `SR:RegisterCallback`:
  `SETTING_CHANGED`, `PRICES_UPDATED`, `ITEM_INFO_RECEIVED`, `SCAN_STATUS`,
  `RECIPES_UPDATED`.
- **Auction house tab.** Each auction house helper is a card on the SilkRoad tab
  (`UI/AuctionHouseTab.lua`). The tab is meant to stay small: scan status and
  shortcuts into SilkRoad, not a replacement for the auction house UI.

## Game data

`SilkRoad/Data/Forever/Recipes.lua` is generated, not hand-written:

```powershell
python tools/generate_data.py
```

It downloads the client tables for the pinned Forever build from
[wago.tools](https://wago.tools) (cached in `tools/.cache/`) and writes every
profession recipe (reagents, product, quantity, skill thresholds, recipe item) and
the items they use (name, quality, icon, vendor buy and sell prices). Regenerate after
a game patch with `--build <new build>`. Where recipe items are sold or dropped isn't
in the client tables; SilkRoad reads it at runtime from QuestieDB.

## Testing

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1
```

This runs `tests/smoke_test.py`: the addon is compiled with real Lua 5.1 and
driven through `tests/scenario.lua` against a mock of the game client. The
mock checks every widget method, frame template and game global the addon
touches against the generated API lists for the Forever client, and rejects
over-constrained anchors and stray globals. It can't show what the window looks
like; that still needs a `/reload` in game. The first run creates `tests/.venv`
(with [lupa](https://pypi.org/project/lupa/)) and downloads the API lists into
`tests/.api`.

## Roadmap

1. Shopping lists for missing materials, crafting queue.
2. Price history and trends, tooltip prices.
3. Other game versions, through the version layer described above.

API research for each of these is in [docs/FOREVER_API_NOTES.md](docs/FOREVER_API_NOTES.md).

## Third-party libraries

Bundled in `SilkRoad/Libs/`, unmodified:

- [LibStub](https://www.wowace.com/projects/libstub): public domain.
- [LibAHTab](https://github.com/Auctionator/LibAHTab) v5 by plusmouse: MIT
  (`Libs/LibAHTab/LICENSE`). Adds the auction house tab without tainting the
  auction house.

# SilkRoad

A crafting and trading helper for **World of Warcraft: Forever**. SilkRoad
compares what a recipe's materials cost (from vendors and the auction house)
with what the result sells for, so profitable crafts, auction house flips and
"craft and sell to a vendor" gold become easy to spot.

> **Status: 0.2.0.** The window, the pages, the price layer and SilkRoad's own
> auction house scanner are in place, and Auctionator's prices are used too when
> it's installed. The recipe indexer and vendor price recorder come next; see the
> [roadmap](#roadmap).

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
| **Recipes** | Each recipe's material cost, auction value after the cut, vendor value and profit, sortable and filterable by profession and name. |
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
    Init.lua            namespace, events, internal callbacks, components, slash commands
    Util.lua            money/percent/time formatting, item and profession helpers
    Database.lua        saved variables, defaults, migrations, settings by path
    Prices.lua          the price layer and pluggable auction price providers
    AuctionScanner.lua  full auction house scan with the 15-minute limit
  UI/
    Widgets.lua         small factories over Blizzard templates
    DataTable.lua       sortable, filterable, virtualised table (ScrollBox)
    MainFrame.lua       the window, the sidebar and the page registry
    Launcher.lua        minimap button and addon compartment entry
    OptionsPanel.lua    entry in Blizzard's Options > AddOns
    AuctionHouseTab.lua the SilkRoad tab in the auction house window
  Modules/              one file per page
tests/                  smoke test that runs the addon outside the game
scripts/                link-addon.ps1, test.ps1
docs/                   FOREVER_API_NOTES.md (research on the Forever client and its API)
```

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
  `SETTING_CHANGED`, `PRICES_UPDATED`, `ITEM_INFO_RECEIVED`, `SCAN_STATUS`.
- **Auction house tab.** Each auction house helper is a card on the SilkRoad tab
  (`UI/AuctionHouseTab.lua`). The tab is meant to stay small: scan status and
  shortcuts into SilkRoad, not a replacement for the auction house UI.

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

1. **Recipe indexer**: read recipes and reagents with `C_TradeSkillUI` when a
   profession window opens.
2. **Vendor price recorder**: store merchant prices on `MERCHANT_SHOW`.
3. Price history and trends, shopping lists for missing materials, tooltip prices.

API research for each of these is in [docs/FOREVER_API_NOTES.md](docs/FOREVER_API_NOTES.md).

## Third-party libraries

Bundled in `SilkRoad/Libs/`, unmodified:

- [LibStub](https://www.wowace.com/projects/libstub): public domain.
- [LibAHTab](https://github.com/Auctionator/LibAHTab) v5 by plusmouse: MIT
  (`Libs/LibAHTab/LICENSE`). Adds the auction house tab without tainting the
  auction house.

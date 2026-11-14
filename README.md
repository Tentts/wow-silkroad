# SilkRoad

A crafting and trading helper for **World of Warcraft: Forever**. SilkRoad
compares what a recipe's materials cost (from vendors and the auction house)
with what the result sells for, so profitable crafts, auction house flips and
"craft and sell to a vendor" gold become easy to spot.

> **Status: 0.1.0, the base interface.** The window, the pages, the price layer
> and the saved data layout are in place. Auction prices already come from
> Auctionator if you have it installed. SilkRoad's own data collection (auction
> scanner, recipe indexer, vendor price recorder) comes next; see the
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
- `/silkroad help` lists every command: `minimap`, `reset`, `debug`, `version`,
  plus page names to jump straight to a page (`/silkroad recipes`).
- The window can be moved, resized from the bottom-right corner, scaled in
  Settings, and closed with Escape.

### Pages

| Page | What it shows |
|---|---|
| **Overview** | Counts of indexed recipes and recorded prices, your professions, which price sources are active. |
| **Recipes** | Each recipe's material cost, auction value after the cut, vendor value and profit, sortable and filterable by profession and name. |
| **Vendor Flips** | Items a merchant sells for less than they fetch on the auction house. |
| **Price Database** | Look up any item (ID, name, or shift-click a link) to see every known price side by side, and browse SilkRoad's own auction data. |
| **Settings** | Minimap button, window scale, auction house cut, preferred auction price source. |

## How it is built

```
SilkRoad/
  SilkRoad.toc          interface 16001, saved variables, load order
  Locales/enUS.lua      strings (English text doubles as the key)
  Core/
    Init.lua            namespace, events, internal callbacks, components, slash commands
    Util.lua            money/percent/time formatting, item and profession helpers
    Database.lua        saved variables, defaults, migrations, settings by path
    Prices.lua          the price layer and pluggable auction price providers
  UI/
    Widgets.lua         small factories over Blizzard templates
    DataTable.lua       sortable, filterable, virtualised table (ScrollBox)
    MainFrame.lua       the window, the sidebar and the page registry
    Launcher.lua        minimap button and addon compartment entry
    OptionsPanel.lua    entry in Blizzard's Options > AddOns
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
  `SETTING_CHANGED`, `PRICES_UPDATED`, `ITEM_INFO_RECEIVED`.

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
3. **Auction scanner**: full scans with `C_AuctionHouse.ReplicateItems`, per realm.
4. Price history and trends, shopping lists for missing materials, tooltip prices.

API research for each of these is in [docs/FOREVER_API_NOTES.md](docs/FOREVER_API_NOTES.md).

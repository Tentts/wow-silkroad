# AGENTS.md

Guidance for anyone, human or coding agent, working on SilkRoad. The
[README](README.md) is for players: what the addon does and how to use it.
[DEV.md](DEV.md) is for developers: running from source, layout, architecture,
tests and game data. This file covers the rules the code follows and how to work on it.

## The project

SilkRoad is a crafting and trading addon for **World of Warcraft: Forever**
(game type "camelot", interface `16001`, Midnight 12.x UI APIs with Classic
content). Current version: **0.7.1** (`SilkRoad/SilkRoad.toc`).

Pages in the SilkRoad window, in sidebar order:

| Page | File | What it does |
|---|---|---|
| Overview | `Modules/Overview.lua` | Dashboard |
| Recipes | `Modules/Recipes.lua` | Every recipe of every profession: sources, Cost, Raw cost, prices, profits, Sell to; Known only filter; right-click menu |
| Leveling Guide | `Modules/Guide.lua` | Dynamic crafting planner, gathering guides with map waypoints, training milestones, shopping list |
| Buy Lists | `Modules/BuyLists.lua` | Create, rename, copy and delete buy lists and their items (managing only, no buying) |
| Price Database | `Modules/PriceDatabase.lua` | Item price lookups and recent lookups |
| Settings | `Modules/Settings.lua` | General, Prices and Data tabs (pinned to the bottom) |
| About | `Modules/About.lua` | Version, project links (copyable boxes), how to open an issue; pinned under Settings |

In the auction house window (tabs added with LibAHTab):

- **SilkRoad** tab (`UI/AuctionHouseTab.lua`): scan status, Scan now, auto-scan, shortcuts.
- **Buy Lists** tab (`UI/AuctionHouseBuyLists.lua`): buys a list item by item through
  `Core/AuctionBuyer.lua`.

The recipe right-click menu (`UI/RecipeMenu.lua`), shared by Recipes and Leveling Guide:
Track in objectives / Stop tracking, Add to a buy list..., Add raw materials to a buy
list... (only when something can be crafted), Where to get it.

## Layout

```
SilkRoad/          the addon (copied or linked into Interface\AddOns)
  Core/            version-agnostic services (components)
  Game/Forever.lua SR.Game adapter: every Forever-specific API call
  Data/Forever/    Recipes.lua (generated, don't edit by hand), Gathering.lua (hand-kept facts)
  UI/              window, DataTable, Widgets, tooltips, AH tabs, menus, launchers
  Modules/         one file per page
  Locales/         enUS.lua (base) and esES.lua
  Libs/            LibStub, LibAHTab (unmodified)
tools/             generate_data.py (game data from wago.tools), locales.py (translation audit)
tests/             wow_mock.lua (mock client), scenario.lua (the test run), smoke_test.py (runner)
scripts/           link-addon.ps1, test.ps1
docs/              FOREVER_API_NOTES.md, TRANSLATING.md
media/             artwork and branding (icon.png); not shipped in the addon folder
.pkgmeta           packager config: the release zip holds only SilkRoad/
.github/workflows/ release.yml: packages tagged versions for CurseForge and GitHub
```

Load order is the TOC: Locales, `Core/Init.lua`, the Game and Data layers, Core services,
UI, then Modules. New files must be added to `SilkRoad/SilkRoad.toc`.

## Rules

1. **Version-agnostic core.** `Core/`, `UI/` and `Modules/` must not call
   version-specific game APIs directly. They go through `SR.Game` (`Game/<Flavor>.lua`)
   and read game data from `Data/<Flavor>/`. Both return early unless they match
   `SR.flavor`, which `Core/Init.lua` detects from the interface number. To support
   another game version, add a flavor, an adapter and a data folder. (The auction
   scanner still calls `C_AuctionHouse.ReplicateItems` directly; don't add more of that.)
2. **Every visible string goes through `L`.** Short text uses its English text as the
   key (`L["Buy Lists"]`). Long text uses a symbolic key defined in `Locales/enUS.lua`
   (`L.BUYLISTS_DESC`). Add the **Spanish** translation to `Locales/esES.lua` in the same
   change; the test fails on undefined symbolic keys, unused translations and
   mismatched placeholders. Use `L[...]` with a literal key so `tools/locales.py` can see
   it. Game names (recipes, items, zones) come from the game and are never translated.
3. **Purchases only from clicks.** Buying (`StartCommoditiesPurchase`, `PlaceBid`) is
   restricted to hardware events. Code never buys on its own: Buy asks for a quote,
   Confirm buys exactly the quoted quantity, and any change drops the quote.
4. **Don't taint Blizzard UI.** Add auction house tabs with LibAHTab, not PanelTemplates.
   Prefer our own frames over calling methods on Blizzard frames.
5. **Copyright.** Use facts only from guide sites (wow-professions.com, wow.gg): numbers,
   zones, requirements. Never copy their text or routes. Credit sources in the README.
6. **Keep spellbook recipe detection.** Known recipes come from `C_SpellBook.IsSpellKnown`
   and from profession windows, by recipe ID. Forever's windows don't reliably say which
   profession they show, so don't rely on that.

## Patterns

- **Components:** `SR:NewComponent("Name")` with optional `OnInitialize` (saved
  variables ready) and `OnEnable` (player in the world). Reached as `SR.Name`.
- **Events:** `SR:RegisterEvent(event, function(event, ...) end)`. Event names by purpose
  are in `SR.Game.events` and `SR.Game.auctionEvents`.
- **Messages:** `SR:Fire(name, ...)` / `SR:RegisterCallback(name, fn)`: `SETTING_CHANGED`,
  `PRICES_UPDATED`, `RECIPES_UPDATED`, `SKILL_CHANGED`, `SCAN_STATUS`, `ITEM_INFO_RECEIVED`,
  `BUYLISTS_UPDATED`, `AUCTION_BUYER_UPDATED`. The main window refreshes its page on
  settings, prices, recipes and buy list changes (debounced).
- **Pages:** `SR.UI:RegisterPage{ id, order, title, description, icon }`, then
  `Page:OnCreate(frame)` (built on first open) and `Page:Refresh()`.
- **Tables:** `Widgets.CreateDataTable(parent, config)`. Columns can have `format`,
  `kind` (money, profit, item...), `onClick` and `tooltip`. Config can have `onRowClick(row,
  mouseButton, rowFrame)`, `onRowEnter`, `onRefresh`. `tbl:SetSelected(predicate)` before
  `SetRows` highlights rows. Right-clicking a clickable cell goes to the row's menu.
- **Widgets:** `CreateButton`, `CreateCheckbox`, `CreateDropdown`, `CreateInput`,
  `CreateSearchBox`, `CreateHeader` (set text with `header.Text`), `CreateTabBar`,
  `Confirm(text, onAccept)`, `Prompt(text, default, onAccept, numeric)`.
- **Menus:** `SR.Game.ShowMenu(owner, title, options, onPick)` for flat context menus.
- **Prices:** always through `SR.Prices` (`GetAuctionPrice`, `GetVendorBuyPrice`,
  `GetVendorSellPrice`, `GetAcquireCost`). `Recipes:Evaluate(recipe)` gives cost, rawCost,
  steps, raw materials, sale prices and profits. `Recipes:Breakdown(recipe, crafts, exact)`
  breaks a recipe down to raw materials.
- **Items:** `Util.GetItemDisplay(itemID)` for name, icon and quality (it asks the client
  for uncached items). Only react to `GET_ITEM_INFO_RECEIVED` for items requested through
  `Util.RequestItem`, because the client sends thousands of these.
- **Saved data:** defaults and the documented schema are in `Core/Database.lua`. Account-wide:
  `SilkRoadDB` (settings, markets per realm, merchant prices, live recipes, buy lists).
  Per character: `SilkRoadCharDB` (known recipes, read professions).

## Testing

Run before every commit:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1
```

or, once set up, `tests/.venv/Scripts/python -I tests/smoke_test.py --api tests/.api/Resources`.

The runner loads the addon in real Lua 5.1 (lupa) against `tests/wow_mock.lua` and runs
`tests/scenario.lua` (about 400 checks), first as an English client and then as a Spanish one.
It also:

- checks every global, widget method and template used against Ketho's
  BlizzardInterfaceResources for the Forever branch;
- runs the translation audit (`tools/locales.py`);
- rejects anchor mistakes (for example `TOPLEFT` plus `RIGHT` on one region: use
  `SetWidth` or `TOPRIGHT` instead) and accidental globals.

When you add a feature, extend the mock with any new API it needs (assert the argument
types the real API expects) and add scenario steps for it. Useful mock helpers:
`M.Click(widget, button)`, `M.RunScript`, `M.RunTimers()`, `M.FireEvent`,
`M.AcceptPopup(text)`, `M.PickContextMenu(index or label)`, `M.bags`, `M.ahListings`.
Prefer picking menu entries by label. Visual layout still needs a `/reload` in game.

## Workflow

- **Branches:** `dev` is the development branch; `master` holds released code.
  - One **feature branch** per change (`feature/...`, `fix/...`, `docs/...`), created from `dev`.
  - Feature branches merge into **`dev`**, only when the maintainer asks, as a fast-forward
    (`git merge --ff-only`; rebase the branch on `dev` first if needed).
  - `master` only receives `dev`, from time to time, when the maintainer asks. Never merge a
    feature branch straight into `master`.
  - **Push only when asked.**
- Commit messages: a short summary line and a body explaining the change. No
  co-author or "generated with" lines for coding agents, in commits, tags, pull
  requests or release notes: the changelog on CurseForge is built from commit messages.
- Keep the README (features, commands, roadmap), DEV.md (layout, architecture, testing)
  and this file current when features change. The README is for players: keep code
  details, tooling and release mechanics out of it.
- **Versions:** don't bump on your own initiative. When a bump is asked for, raise only
  the last number (0.7.0 → 0.7.1) unless the maintainer says otherwise. A bump touches
  `## Version` in the TOC, the README badge and the version checks in `tests/scenario.lua`.
- **Releases:** after `dev` is merged into `master`, pushing a tag `v<version>` (matching
  `## Version`) on `master` builds the
  zip and uploads it to CurseForge and GitHub Releases (`.github/workflows/release.yml`).
  `-beta1` / `-alpha1` suffixes make beta / alpha files. Tag and push tags only when the
  maintainer asks. Before tagging, rewrite `CHANGELOG.md` with the notes for that version
  only: the packager uploads the whole file as the release notes. Write it for players
  (what's new, what's fixed), never commit hashes or internal details. New top-level development files or folders must be added to the
  `ignore` list in `.pkgmeta` so they stay out of the zip.
- `tools/generate_data.py` regenerates `Data/Forever/Recipes.lua` after a game patch;
  never edit that file by hand.

## Forever quirks worth knowing

Details are in `docs/FOREVER_API_NOTES.md`.

- `REPLICATE_ITEM_LIST_UPDATE` fires several times per full-scan request. The scanner only
  processes while waiting and notices other addons' scans through a hook on `ReplicateItems`.
- Profession windows don't always report their profession (child profession ID 0), so
  known recipes are recorded by recipe ID.
- Recipe tracking is `C_TradeSkillUI.SetRecipeTracked(recipeID, tracked, isRecraft)`, with
  `TRACKED_RECIPE_UPDATE`. The game may refuse recipes the character can't craft;
  SilkRoad checks one second later and says so.
- Auction house buying: commodities use Start, then `COMMODITY_PRICE_UPDATED`, then Confirm;
  other items use `PlaceBid` at the buyout. `SendSearchQuery` is throttled
  (`IsThrottledMessageSystemReady`, `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`).
- Trainer recipes have no learn level in the client data; it's estimated and shown with `~`.

## State and next steps

Done:

- recipe index with sources and waypoints
- auction scanning
- spellbook-known recipes
- tooltips, key binding and settings
- translations (English, Spanish)
- dynamic levelling planner
- gathering guides
- recipe tracking
- buy lists with auction house buying
- raw-material breakdown

Roadmap (README): crafting queue, price history and trends, more languages, other game
versions through the version layer. Not yet verified in game: the Buy Lists tab's
purchase flow and the Raw cost numbers for multi-step recipes.

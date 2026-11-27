# AGENTS.md

Guidance for anyone, human or coding agent, working on SilkRoad. The
[README](README.md) is for players: what the addon does and how to use it.
[DEV.md](DEV.md) is for developers: setup, layout, architecture, tests, game data and
releases. This file covers the rules the code follows, the patterns to reuse, the
mistakes not to repeat and how to work on the repository.

## Picking the project up

1. Read this file, then [DEV.md](DEV.md) ("Setting up" and "Research sources").
2. Run the tests once (`scripts/test.ps1`): the first run sets up everything they need.
   They must pass before and after every change.
3. Check where things stand: `git log --oneline -15 dev`, `git branch` (unmerged work),
   and [State and next steps](#state-and-next-steps) below.
4. Work on a branch from `dev`, following [Workflow](#workflow).

## The project

SilkRoad is a crafting and trading addon for **World of Warcraft: Forever**
(game type "camelot", interface `16001`, Midnight 12.x UI APIs with Classic
content). Current version: **0.7.7** (`SilkRoad/SilkRoad.toc`). Repository:
<https://github.com/Tentts/wow-silkroad>, released on CurseForge as "silkroad".

Pages in the SilkRoad window, in sidebar order:

| Page | File | What it does |
|---|---|---|
| Overview | `Modules/Overview.lua` | Dashboard |
| Recipes | `Modules/Recipes.lua` | Every recipe of every profession: sources, Cost, Raw cost, prices, profits, Sell to; Known only filter; favorites starred; right-click menu |
| Leveling Guide | `Modules/Guide.lua` | Dynamic crafting planner, gathering guides with map waypoints, training milestones (Forever: Journeyman 75, Expert 150, Artisan 225), shopping list |
| Buy Lists | `Modules/BuyLists.lua` | Create, rename, copy and delete buy lists and their items (managing only, no buying); item name suggestions |
| Price Database | `Modules/PriceDatabase.lua` | Item price lookups (with name suggestions) and recent lookups |
| Settings | `Modules/Settings.lua` | General, Prices and Data tabs (pinned to the bottom) |
| About | `Modules/About.lua` | Version, project links (copyable boxes), how to open an issue; pinned under Settings |

In the auction house window (tabs added with LibAHTab):

- **SilkRoad** tab (`UI/AuctionHouseTab.lua`): scan status, Scan now, auto-scan, shortcuts.
- **Buy Lists** tab (`UI/AuctionHouseBuyLists.lua`): buys a list item by item through
  `Core/AuctionBuyer.lua`.

The recipe right-click menu (`UI/RecipeMenu.lua`), shared by Recipes and Leveling Guide:
Track in objectives / Stop tracking, Add to / Remove from favorites, Add to a buy list...,
Add raw materials to a buy list... (only when something can be crafted), Where to get it.
Adding to a buy list adds every reagent; a notice (`Widgets.Notice`) lists the ones a
merchant was seen selling.

Item tooltips (`UI/Tooltip.lua`): vendor and auction prices (mode: off, single, stack,
both; Shift swaps single and stack) and the recipes that use the item (mode: off,
favorites, learned, all). Favorites are the game's own profession favorites
(`C_TradeSkillUI.IsRecipeFavorite`, learned recipes only), kept in step both ways, plus
SilkRoad's own for unlearned recipes, in `SilkRoadDB.favoriteRecipes`.

Full bags while looting (`Core/BagSpace.lua`, `UI/BagGlow.lua`, off by default): on the
"Inventory is full" UI error with a loot window open, the cheapest bag stacks worth less
than the best loot glow red. Slot buttons are found with `SR.Game.ForEachBagButton`
(any frame answering `GetBagID`, so bag addons work too); glows are kept in a weak table,
never stored on the buttons.

Blizzard's professions window (`UI/ProfessionPrices.lua`): a panel under the reagents of
the recipe shown, with materials, raw cost, auction and vendor prices and profits. It
post-hooks the schematic form's `Init` through `SR.Game.HookRecipeView`.

On login (`Core/AuctionScanner.lua`, `Scanner:ReportDataAge`): a chat warning when the
auction house's prices are more than 3 hours old, or when it has none but others do.

## Layout

```
SilkRoad/          the addon (copied or linked into Interface\AddOns)
  Core/            version-agnostic services (components)
  Game/Forever.lua SR.Game adapter: every Forever-specific API call (list in its header)
  Data/Forever/    Recipes.lua (generated, don't edit by hand), Gathering.lua (hand-kept facts)
  UI/              window, DataTable, Widgets, tooltips, AH tabs, menus, suggestions, glows
  Modules/         one file per page
  Locales/         enUS.lua (base) and esES.lua
  Libs/            LibStub, LibAHTab (unmodified)
tools/             generate_data.py (game data from wago.tools), locales.py (translation audit)
tests/             wow_mock.lua (mock client), scenario.lua (the test run), smoke_test.py (runner)
scripts/           link-addon.ps1, test.ps1
docs/              FOREVER_API_NOTES.md (API research), TRANSLATING.md
media/             artwork and branding (icon.png); not shipped in the addon folder
CHANGELOG.md       release notes of the version being released (uploaded as-is)
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
   it (for a table of labels, look them up when building it: `{ x = L["..."] }`). Game
   names (recipes, items, zones) come from the game and are never translated.
3. **Purchases only from clicks.** Buying (`StartCommoditiesPurchase`, `PlaceBid`) is
   restricted to hardware events. Code never buys on its own: Buy asks for a quote,
   Confirm buys exactly the quoted quantity, and any change drops the quote.
4. **Don't taint Blizzard UI.** Add auction house tabs with LibAHTab, not PanelTemplates.
   Prefer our own frames over calling methods on Blizzard frames; post-hook
   (`hooksecurefunc`) rather than replace; keep per-frame state in our own (weak) tables,
   not as fields on Blizzard frames; never call Blizzard-only functions (see Pitfalls).
5. **Copyright.** Use facts only from guide sites (wow-professions.com, wow.gg): numbers,
   zones, requirements. Never copy their text or routes. Credit sources in the README.
6. **Keep spellbook recipe detection.** Known recipes come from `C_SpellBook.IsSpellKnown`
   and from profession windows, by recipe ID. Forever's windows don't reliably say which
   profession they show, so don't rely on that.
7. **Never take the keyboard on SilkRoad's windows.** Escape closes them through
   `UISpecialFrames` only (as Questie, Baganator and Auctionator do). See Pitfalls.

## Patterns

- **Components:** `SR:NewComponent("Name")` with optional `OnInitialize` (saved
  variables ready) and `OnEnable` (player in the world). Reached as `SR.Name`.
- **Events:** `SR:RegisterEvent(event, function(event, ...) end)`. Event names by purpose
  are in `SR.Game.events` and `SR.Game.auctionEvents`.
- **Messages:** `SR:Fire(name, ...)` / `SR:RegisterCallback(name, fn)`: `SETTING_CHANGED`,
  `PRICES_UPDATED`, `RECIPES_UPDATED`, `SKILL_CHANGED`, `SCAN_STATUS`, `ITEM_INFO_RECEIVED`,
  `BUYLISTS_UPDATED`, `AUCTION_BUYER_UPDATED`. The main window refreshes its page on
  settings, prices, recipes and buy list changes (debounced).
- **Pages:** `SR.UI:RegisterPage{ id, order, title, description, icon, placement }`, then
  `Page:OnCreate(frame)` (built on first open) and `Page:Refresh()`. Pages with
  `placement = "bottom"` stack upwards from the bottom in `order` (About 990 sits under
  Settings 1000).
- **Tables:** `Widgets.CreateDataTable(parent, config)`. Columns can have `format`,
  `kind` (money, profit, item...), `onClick` and `tooltip`. Config can have `onRowClick(row,
  mouseButton, rowFrame)`, `onRowEnter`, `onRefresh`. `tbl:SetSelected(predicate)` before
  `SetRows` highlights rows. Right-clicking a clickable cell goes to the row's menu.
- **Widgets:** `CreateButton`, `CreateCheckbox`, `CreateDropdown`, `CreateInput`,
  `CreateSearchBox`, `CreateHeader` (set text with `header.Text`), `CreateTabBar`,
  `Confirm(text, onAccept)`, `Prompt(text, default, onAccept, numeric)`, `Notice(text)`
  (OK only), `AttachTooltip(frame, title, body)`, `AttachItemSuggestions(editBox, onPick)`
  (item name suggestions while typing, from `SR.ItemSearch:Find(text, limit)`;
  `SR.ItemSearch:FindByName(text)` for a full name typed without picking).
- **Settings page controls** go through `self:Track(control)` so Refresh updates them; the
  scenario unpacks `settingsPage.controls` in order, so a new control there means
  updating that `unpack` line in `tests/scenario.lua`. New settings need a default in
  `DB.ACCOUNT_DEFAULTS.settings` and an entry in `SETTING_PATHS` (reset notifies them).
- **Menus:** `SR.Game.ShowMenu(owner, title, options, onPick)` for flat context menus.
- **Prices:** always through `SR.Prices` (`GetAuctionPrice`, `GetNetAuctionPrice`,
  `GetVendorBuyPrice`, `GetVendorSellPrice`, `GetAcquireCost`). QuestieDB vendor lists are
  trusted for vendor *prices* only; "sold by vendors" (`Prices:IsSoldByVendor`) needs a
  merchant actually seen selling the item with unlimited stock (SilkRoad's records or
  Auctionator's).
- **Recipes:** `Recipes:Evaluate(recipe)` gives cost, rawCost, steps, raw materials, sale
  prices and profits. `Recipes:Breakdown(recipe, crafts, exact)` breaks a recipe down to raw
  materials. Skill-up thresholds come from `Recipes:GetSkillLevels(recipe)` (yellow, grey,
  points per skill-up): the game data corrected by the colours the professions window
  showed (`relativeDifficulty`, `SilkRoadDB.recipeColors`); never read `recipe.yellow` /
  `recipe.gray` directly. The planner ranks recipes with `RankingCost` (resale wins back at
  most 75% of the materials), so a profitable craft never counts as free.
- **Items:** `Util.GetItemDisplay(itemID)` for name, icon and quality (it asks the client
  for uncached items). Only react to `GET_ITEM_INFO_RECEIVED` for items requested through
  `Util.RequestItem`, because the client sends thousands of these.
- **Saved data:** defaults and the documented schema are in `Core/Database.lua`.
  Account-wide `SilkRoadDB`: settings, `markets[auctionHouseKey]` (auction prices per
  regional auction house, "PvP Horde"), `lastMarketKey`, `scanner`, `vendorPrices`
  (merchant prices = items sold by vendors), `recipes` (live recipes missing from the
  data), `buyLists`, `favoriteRecipes`, `recipeColors`, `recentLookups`. Per character
  `SilkRoadCharDB`: `knownRecipes`, `scannedProfessions`. Migrations of old saved data go
  in `DB:OnInitialize` (see the tooltip-setting and realm-market examples).

## Pitfalls (learned the hard way)

- **Lua multiple returns:** `local item, index = list and self:GetItem(list, id)` keeps only
  the first value (`index` is nil, and `table.remove(t, nil)` removes the **last** element).
  Call the function on its own line when you need more than one return value.
- **`SetScript("OnKeyDown")` turns keyboard input on** for that frame, which then swallows
  every key (Escape, movement) while visible. Call `frame:EnableKeyboard(false)` right after
  and enable it only while really capturing a key (Settings' key binding button).
- **Escape:** keyboard capture plus `SetPropagateKeyboardInput` broke W/A/S/D in game, and
  `RegisterGameMenuEscHandler` is Blizzard-only (errors on every Escape press). Use
  `UISpecialFrames` and nothing else.
- **Realm names:** with Forever's regional realms `GetRealmName()` is blank; always file
  per auction house through `SR.Game.GetAuctionHouseKey()` / `SR.DB:GetMarketKey()`.
- **Merchants and QuestieDB:** limited-stock offers (`numAvailable >= 0`) aren't vendor
  items; QuestieDB lists them as vendors anyway, so it can't decide "sold by vendors".
- **Local tables in tests:** `local market = SR.DB:GetMarket()` captured early goes stale
  after a data wipe replaces the table; fetch it again inside each test step.
- **Writing Python edit scripts in bash heredocs:** long heredocs with quotes can break the
  shell; write the script to a file and run it, and use raw strings or `\\` for `\` in TOC
  paths (`Core\\Foo.lua`).

## Testing

Run before every commit:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test.ps1
```

or, once set up, `tests/.venv/Scripts/python -I tests/smoke_test.py --api tests/.api/Resources`.

The runner loads the addon in real Lua 5.1 (lupa) against `tests/wow_mock.lua` and runs
`tests/scenario.lua` (about 540 checks), first as an English client and then as a Spanish one.
It also:

- checks every global, widget method and template used against Ketho's
  BlizzardInterfaceResources for the Forever branch. Names that exist in the game but are
  missing from those lists, and were checked in Blizzard's UI source, go in
  `VERIFIED_BY_SOURCE` in `tests/smoke_test.py` (with the source file in a comment);
- runs the translation audit (`tools/locales.py`);
- rejects anchor mistakes (for example `TOPLEFT` plus `RIGHT` on one region: use
  `SetWidth` or `TOPRIGHT` instead) and accidental globals.

When you add a feature, extend the mock with any new API it needs (assert the argument
types the real API expects) and add scenario steps for it. A bug fix gets a test that
fails on the old code: check it does (`git stash` the fix, run, `git stash pop`).

Mock helpers (`M` in the scenario): `M.Click(widget, button)`, `M.RunScript(widget, script,
...)`, `M.RunTimers()` (timers due within a short wait), `M.Advance(seconds)` (moves the
clock and runs timers), `M.FireEvent`, `M.AcceptPopup(text)` (types `text` into a prompt
first), `M.PickContextMenu(index or label)` (prefer labels), `M.PickDropdown(dropdown,
index)`, `M.Type(editBox, text)` (typing with userInput), `M.PressKey(editBox, key)`
("UP", "DOWN", "ENTER", "ESCAPE"), `M.LoadAuctionHouseUI` / `M.OpenAuctionHouse` /
`M.CloseAuctionHouse`, `M.LoadProfessionsUI`, `M.CreateBagButton(bag, slot, hidden)`.
State to set: `M.bags`, `M.containerItems`, `M.loot`, `M.merchant`, `M.replicate`,
`M.ahListings`, `M.ahNotCommodity`, `M.tradeSkill` (with `colors`), `M.professions`,
`M.nativeFavorites`, `M.regionalRealms`, `M.gameRules`, `M.faction`, `M.modifiers`,
`M.inCombat`, `M.mouseOver`, `M.tooltipInfo`.

Debugging a test: the runner prints the addon's chat output only when a check fails, so
to see values, `check(false, "DEBUG" .. string.char(10) .. text)` temporarily. The scenario
ends with `return checks`; new steps go before it (usually before an existing `step(...)`).
Visual layout still needs a `/reload` in game.

## Workflow

- **Branches:** `dev` is the development branch; `master` holds released code.
  - One **feature branch** per change (`feature/...`, `fix/...`, `docs/...`, `chore/...`),
    created from `dev`.
  - Feature branches merge into **`dev`**, only when the maintainer asks, as a fast-forward
    (`git merge --ff-only`; rebase the branch on `dev` first if needed). Delete the branch
    after merging.
  - `master` only receives `dev`, from time to time, when the maintainer asks. Never merge a
    feature branch straight into `master`.
  - **Push only when asked.** "Merge it" means into `dev`; pushing is a separate request.
- Commit messages: a short summary line and a body explaining the change. No
  co-author or "generated with" lines for coding agents, in commits, tags, pull
  requests or release notes: the changelog on CurseForge is built from commit messages.
- Keep the README (features, commands, roadmap), DEV.md (layout, architecture, testing)
  and this file current when features change. The README is for players: keep code
  details, tooling and release mechanics out of it.
- **Versions:** don't bump on your own initiative. When a bump is asked for, raise only
  the last number (0.7.6 → 0.7.7) unless the maintainer says otherwise. A bump touches
  `## Version` in the TOC, the README badge, the version here and the version checks in
  `tests/scenario.lua`.
- **Releases:** only when the maintainer asks. On a `chore/release-<version>` branch from
  `dev`: bump the version and rewrite `CHANGELOG.md` with the notes for that version only
  (the packager uploads the whole file as the release notes; write it for players, what's
  new, changed and fixed, never commit hashes or internal details). Merge it into `dev`,
  then `dev` into `master`, push both, and push an annotated tag `v<version>` (matching
  `## Version`) on `master`: `.github/workflows/release.yml` builds the zip and uploads it
  to CurseForge and GitHub Releases. `-beta1` / `-alpha1` suffixes make beta / alpha files.
  Check the build: <https://github.com/Tentts/wow-silkroad/actions> (or the public API,
  `api.github.com/repos/Tentts/wow-silkroad/actions/runs`). New top-level development
  files or folders must be added to the `ignore` list in `.pkgmeta`.
- `tools/generate_data.py` regenerates `Data/Forever/Recipes.lua` after a game patch;
  never edit that file by hand.

## Forever quirks worth knowing

Details are in `docs/FOREVER_API_NOTES.md`.

- `REPLICATE_ITEM_LIST_UPDATE` fires several times per full-scan request, and the first
  one can come with no listings yet. The scanner only processes while waiting, keeps
  waiting until listings arrive (or its timeout), and notices other addons' scans through
  a hook on `ReplicateItems`.
- Regional realms (`RegionalUniqueNamesEnabled()`, since the November 2026 patch):
  `GetRealmName()` is blank and an auction house is shared per ruleset and faction. Prices
  are filed under `SR.Game.GetAuctionHouseKey()` ("PvP Horde", as Auctionator does); older
  realm-named data is carried over once (`DB:AdoptRealmMarket`).
- Profession windows don't always report their profession (child profession ID 0), so
  known recipes are recorded by recipe ID. `C_TradeSkillUI.GetRecipeInfo` gives each
  listed recipe's colour at the current skill (`relativeDifficulty`: 0 orange, 1 yellow,
  2 green, 3 grey) and `numSkillUps`, but not the skill levels where colours change.
- Trainer recipes have no learn level in the client data; it's estimated and shown with `~`.
  Forever's trainers teach a rank only once the skill reaches the current cap (75, 150, 225).
- Recipe tracking is `C_TradeSkillUI.SetRecipeTracked(recipeID, tracked, isRecraft)`, with
  `TRACKED_RECIPE_UPDATE`. The game may refuse recipes the character can't craft;
  SilkRoad checks one second later and says so.
- Profession favorites: `C_TradeSkillUI.IsRecipeFavorite` / `SetRecipeFavorite`, learned
  recipes only, `TRADE_SKILL_FAVORITES_CHANGED (isFavorite, recipeID)`.
- Forever loads its own professions layout (`Blizzard_Professions/Camelot`,
  `Blizzard_ProfessionsTemplates/Camelot`): the recipe view is 360 px wide, reagents in two
  columns.
- Auction house buying: commodities use Start, then `COMMODITY_PRICE_UPDATED`, then Confirm;
  other items use `PlaceBid` at the buyout. `SendSearchQuery` is throttled
  (`IsThrottledMessageSystemReady`, `AUCTION_HOUSE_THROTTLED_SYSTEM_READY`).
- Merchants: `C_MerchantFrame.GetItemInfo(index).numAvailable` is -1 for unlimited stock.
- Full bags: `UI_ERROR_MESSAGE` with `ERR_INV_FULL`; loot through `GetNumLootItems`,
  `GetLootSlotType`, `GetLootSlotLink`, `GetLootSlotInfo`.

## State and next steps

Done (released up to 0.7.7):

- recipe index for every profession, with sources, waypoints, Cost and Raw cost
- auction scanning per regional auction house, with a login warning for old data
- spellbook-known recipes, recipe tracking, favorites shared with the game
- tooltips (price modes, stack prices, recipes using the item), key binding, settings,
  separate data wipes, About page
- translations (English, Spanish)
- dynamic levelling planner following the game's recipe colours, gathering guides,
  Forever training levels
- buy lists with auction house buying, item name suggestions, raw-material lists
- prices panel in Blizzard's professions window
- full-bags helper (optional)

Roadmap (README): crafting queue, price history and trends, more languages, other game
versions through the version layer.

Not yet verified in game: the Buy Lists tab's purchase flow end to end, the Raw cost
numbers for multi-step recipes, and the planner's colour corrections over a long levelling
session.

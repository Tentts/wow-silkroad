# WoW Forever addon API notes

Research notes for building SilkRoad on **World of Warcraft: Forever** (Blizzard's
"Classic+", launched 4 November 2026). Everything marked *verified* was checked
against Blizzard's own UI code for the Forever client (build `1.60.1.70938`) via
the community mirrors listed under [Sources](#sources).

## The client

| | |
|---|---|
| TOC interface | `16001` (also used by the Auctionator, Baganator and DBM builds installed in `_forever_`) |
| Game type | `camelot` internally; `Forever` is accepted as an alias in TOC suffixes and `[Game]` |
| Game family | `mainline`: Forever runs the **modern (Midnight 12.x) UI engine** with Classic content |
| Install folder | `World of Warcraft\_forever_\Interface\AddOns` |
| TOC file suffix | `MyAddon_Forever.toc` (optional; a plain `MyAddon.toc` works too) |

Practical meaning: **write retail-style code**. The legacy Classic APIs are gone
from this client. Blizzard's own Forever code is the retail code plus `Camelot/`
overrides.

## Addon restrictions

Forever ships with Midnight's addon "disarmament" rules, and Blizzard keeps the
two in sync:

- Combat information (health, names, creature IDs, cast and aura data in many
  contexts) arrives as **secret values** that addon code can display but not
  read or compute with.
- Addons may change how information is shown, not decide for the player.
- Creature and game-object GUIDs have obfuscated server and spawn IDs.
- Trial accounts can't send addon messages.

None of this touches SilkRoad's area: professions, the auction house, merchants
and our own out-of-combat UI work normally.

## APIs SilkRoad uses or will use

### Already used (verified)

- `C_AddOns.GetAddOnMetadata` (the global `GetAddOnMetadata` is gone)
- `C_Item.GetItemInfo` returns `sellPrice` as the 11th value (what a vendor pays you);
  `C_Item.GetItemInfoInstant`, `GetItemIconByID`, `GetItemNameByID`,
  `GetItemQualityByID`, `GetItemQualityColor`, `RequestLoadItemDataByID`;
  event `GET_ITEM_INFO_RECEIVED`. That event fires for **every** item anything
  loads (bags, tooltips, auction scans: thousands at a time), so only react to
  items you requested yourself (SilkRoad's `Util.RequestItem`).
- `GetProfessions`, `GetProfessionInfo`
- `GetMoneyString`, `WrapTextInColorCode`, `HandleModifiedItemClick`, `IsModifiedClick`
- `ChatFrameUtil.InsertLink` (replaces `ChatEdit_InsertLink`, which no longer exists)
- Item tooltips: `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn)`
  (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua); `fn(tooltip, data)` gets
  `data.id` (item ID) and `data.lines` (each with `leftText`), e.g. to spot "Soulbound"
- Names in the client's language: `C_Spell.GetSpellName(recipeID)`,
  `C_Item.GetItemNameByID(itemID)` (nil until cached),
  `C_TradeSkillUI.GetTradeSkillDisplayName(skillLineID)`; `GetLocale()`
- `Settings.RegisterCanvasLayoutCategory`, `Settings.RegisterAddOnCategory`
- Addon compartment: `AddonCompartmentFrame` exists in Forever
  (`Blizzard_Minimap/Camelot/AddonCompartment.xml`), so the TOC
  `AddonCompartmentFunc*` directives work
- UI templates: `ButtonFrameTemplate`, `InsetFrameTemplate`, `BackdropTemplate`,
  `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `InputBoxTemplate`,
  `SearchBoxTemplate`, `WowStyle1DropdownTemplate` (Blizzard_Menu; `UIDropDownMenu`
  is deprecated), `MinimalSliderWithSteppersTemplate`, `WowScrollBoxList` +
  `MinimalScrollBar` with `CreateScrollBoxListLinearView`,
  `ScrollUtil.InitScrollBoxListWithScrollBar` and `CreateDataProvider`
- `UISpecialFrames` (close with Escape), atlas `auctionhouse-ui-sortarrow`

### Auction house (used by the scanner, `Core/AuctionScanner.lua`)

Forever uses the **retail auction house** (`AuctionHouseFrame`, commodities and
items), not the Classic one. `GetAuctionItemInfo`, `QueryAuctionItems` and
`PlaceAuctionBid` don't exist.

- Full scan: `C_AuctionHouse.ReplicateItems()` → event `REPLICATE_ITEM_LIST_UPDATE` →
  `C_AuctionHouse.GetNumReplicateItems()` and `C_AuctionHouse.GetReplicateItemInfo(index)`.
  - Indices are **0-based** (the documented type is `number`, not `luaIndex`).
  - Returns, in order: `name, texture, count, qualityID, usable, level, levelType,
    minBid, minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName, owner,
    ownerFullName, saleStatus, itemID, hasAllInfo`. `count`, `buyoutPrice` and
    `itemID` are never nil; `name`/`texture` can be until the item is cached
    (`hasAllInfo`). The unit price is `buyoutPrice / count`.
  - Skip `buyoutPrice == 0` (bid-only) and `count == 0`. The server sometimes lists
    items that don't exist: filter with `C_Item.DoesItemExistByID`.
  - The server allows one `ReplicateItems` request per **15 minutes**; extra requests
    get no answer. It has no `HasRestrictions` flag, so it doesn't need a click and
    can run when the AH opens (Auctionator's auto-scan does the same).
  - `REPLICATE_ITEM_LIST_UPDATE` fires **several times per request** (again as item
    data for the listings arrives). Read only the first one after a request and
    ignore the rest; treating every event as a new scan loops forever.
  - It fires for any addon's request, so one addon's full scan can be recorded by
    every listening addon. To know when another addon sent one, hook it:
    `hooksecurefunc(C_AuctionHouse, "ReplicateItems", ...)`. Auctionator saves the time
    of its last one in `Auctionator.SavedState.TimeOfLastReplicateScan`.
  - The data is gone once the AH closes: abort a scan on `AUCTION_HOUSE_CLOSED`.
- Targeted queries: `C_AuctionHouse.SendBrowseQuery`, `GetBrowseResults`,
  `SendSearchQuery`, `GetCommoditySearchResultInfo`, `GetItemSearchResultInfo`;
  events `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`, `COMMODITY_SEARCH_RESULTS_UPDATED`,
  `ITEM_SEARCH_RESULTS_UPDATED`
- Throttling: `C_AuctionHouse.IsThrottledMessageSystemReady()`
- Open / close: `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`

#### Adding a tab to the auction house window

`Blizzard_AuctionHouseUI` loads on demand, the first time an auctioneer is
opened (watch `ADDON_LOADED`). Its tabs switch through
`AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.X)`, which shows
and hides subframes by name.

Don't add tabs with `PanelTemplates_SetNumTabs` / `AuctionHouseFrame.Tabs`:
that taints the AH and, through it, the player's bags (blocked actions even in
combat after leaving the AH). [LibAHTab](https://github.com/Auctionator/LibAHTab)
(MIT, by plusmouse, used by Auctionator) adds tabs on a separate row parented to
the AH, hooks `SetDisplayMode` with `hooksecurefunc`, and selects its own tabs
with `SetDisplayMode({})`. Because it's shared through LibStub, every addon using it
gets one tidy tab row. SilkRoad bundles it in `SilkRoad/Libs/`.

### Recipe data from the client tables (DB2)

wago.tools publishes Forever's client tables as product `wowf`
(`https://wago.tools/db2/<Table>/csv?build=1.60.1.70938`). `tools/generate_data.py`
uses them; findings:

- Professions are `SkillLine` rows with `CategoryID` 11 (primary) or 9 (secondary).
  Skip Poisons (40, a rogue skill), "Test Profession [DNT]" and "Comprehension".
- `SkillLineAbility` links recipe spells to professions. `MinSkillLineRank` is always
  1; `TrivialSkillLineRankLow` is the yellow threshold and `TrivialSkillLineRankHigh`
  the grey one. `AcquireMethod` 1 = learned together with the profession.
- The skill needed to **learn** a recipe is only in the data for recipe items
  (`ItemSparse.RequiredSkillRank` of the pattern/plan). Trainer requirements are
  server-side; the yellow threshold is the closest value (often equal, not always).
- Recipe items teach their spell through an `ItemEffect` with `TriggerType` 6, linked
  to the item via `ItemXItemEffect` (`ItemEffect` has no item column in this build).
- `SpellEffect` effect 24 = create item (`EffectItemType`, quantity in
  `EffectBasePointsF`); effect 53 = enchant item. Reagents: `SpellReagents`.
- The tables still contain Season of Discovery recipes (spell IDs 100000-999999),
  many making items that no longer exist. Forever re-created what it kept with IDs
  above 1,000,000, so drop that range and recipes whose product isn't in `ItemSparse`.
- `ItemSparse.BuyPrice` is the merchant price for `VendorStackCount` items; every item
  has one, so it only means something for items vendors actually sell.
- Where items are sold or dropped is not in the client tables.

### QuestieDB (optional runtime source)

The QuestieDB addon (Questie's data, with a Forever build) has a public API:
`LibQuestieDB.RequireContract(4)`, then `LibQuestieDB.Item.Get(itemID, key)`,
`.Npc.Get`, `.Object.Get`, `.Quest.Get`. Item keys used: `vendors`, `npcDrops`,
`objectDrops`, `questRewards`; NPC keys: `name`, `subName`, `spawns`
(`{ [areaID] = { { x, y }, ... } }`, percent), `zoneID`, `friendlyToFaction`
(`"A"`, `"H"`, `"AH"`). Area → map ID for waypoints is Questie's internal
`QuestieLoader:ImportModule("ZoneDB"):GetUiMapIdByAreaId(areaID)`. Zone names:
`C_Map.GetAreaInfo(areaID)`.

### Known recipes

- **The spellbook knows them.** Recipes are spells, and in Forever
  `C_SpellBook.IsSpellKnown(recipeSpellID)` returns true for learned recipes (confirmed
  in game). SilkRoad checks every recipe of the character's professions at login and
  on `LEARNED_SPELL_IN_SKILL_LINE` / `SKILL_LINES_CHANGED`; no window needed. (The old
  globals `IsSpellKnown` / `IsPlayerSpell` don't exist in this client.)
- **Profession windows don't always say which profession they show.** For some
  (Leatherworking, in testing) both `GetChildProfessionInfo()` and
  `GetBaseProfessionInfo()` come back with no ID or name. It doesn't matter: record
  `GetAllRecipeIDs()` + `GetRecipeInfo(id).learned` per recipe ID, and take each
  recipe's profession from the game data or `C_TradeSkillUI.GetProfessionInfoByRecipeID`.
  Addons that key on the window's profession name (DoesMyAltKnowThat, for one) can't
  record such windows.

### Professions (the profession window, used by `Core/Recipes.lua`)

Forever uses the **retail professions UI** (`ProfessionsFrame`, `C_TradeSkillUI`).
`GetTradeSkillInfo`, `GetNumTradeSkills`, `GetCraftInfo` and `TradeSkillFrame` don't exist.

- Events: `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_DATA_SOURCE_CHANGED`, `TRADE_SKILL_CLOSE`
- `C_TradeSkillUI.IsTradeSkillReady()`, `GetAllRecipeIDs()`, `GetFilteredRecipeIDs()`,
  `GetRecipeInfo(recipeID)`, `GetBaseProfessionInfo()`, `GetChildProfessionInfo()`,
  `GetProfessionInfoBySkillLineID(skillLineID)`, `GetRecipeOutputItemData`
- `C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)` returns
  `outputItemID`, `quantityMin`, `quantityMax`, `name`, `icon` and
  `reagentSlotSchematics`; each slot has `quantityRequired`, `required`,
  `reagentType` and `reagents = { { itemID } }`. That maps directly onto the
  recipe record documented in `SilkRoad/Core/Database.lua`.
- Most of these need the profession window open (opening it takes a hardware event).

### Merchants (used by `Core/Merchants.lua`)

- Events `MERCHANT_SHOW`, `MERCHANT_UPDATE`, `MERCHANT_CLOSED`
- `GetMerchantNumItems()`, `GetMerchantItemID(index)`, `GetMerchantItemLink(index)`
- `C_MerchantFrame.GetItemInfo(index)` returns a table with `price`, `stackCount`,
  `numAvailable`, `isPurchasable`, `hasExtendedCost` (the global
  `GetMerchantItemInfo` is gone). Price per item = `price / stackCount`; skip
  `hasExtendedCost` items (bought with currency or tokens) and limited-stock offers
  (`numAvailable` is -1 for unlimited stock, a count otherwise).
- QuestieDB's vendor lists include limited-stock offers, so SilkRoad uses them for vendor
  prices only, never to say an item is "sold by vendors".

### Auctionator (optional price source, already wired up)

`Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)` and
`GetAuctionAgeByItemID(callerID, itemID)` (whole days since last seen, `nil` after
21 days). SilkRoad calls them through `pcall`.

### Regional realms (November 2026 patch)

- `RegionalUniqueNamesEnabled()` returns true; `GetRealmName()` and
  `GetNormalizedRealmName()` are blank.
- One auction house is shared by every character of a ruleset and faction. The ruleset
  comes from `C_GameRules.IsGameRuleActive(Enum.GameRule.PvPRuleset / RPRuleset /
  HardcoreRuleset)`; SilkRoad files prices under "<ruleset> <faction>" ("PvP Horde"), as
  Auctionator does (`Auctionator.Variables.GetRegionalRulesetName`).
- After a full scan request, the first `REPLICATE_ITEM_LIST_UPDATE` can arrive with
  `GetNumReplicateItems() == 0`; the listings come with a later one.

### Recipe colours, skill-ups and favorites

- `C_TradeSkillUI.GetRecipeInfo(recipeID)` (recipes listed in the open window) has
  `relativeDifficulty` (`Enum.TradeskillRelativeDifficulty`: 0 Optimal = orange, 1 Medium
  = yellow, 2 Easy = green, 3 Trivial = grey) at the current skill, `numSkillUps`, and
  `favorite`. The skill levels where the colour changes aren't exposed.
- Favorites: `C_TradeSkillUI.IsRecipeFavorite(recipeID)`, `SetRecipeFavorite(recipeID,
  bool)`, event `TRADE_SKILL_FAVORITES_CHANGED (isFavorite, recipeID)`. Blizzard's UI only
  offers the star for learned recipes.
- Trainers teach Journeyman, Expert and Artisan only once the skill reaches the current
  cap (75, 150, 225), not 25 points earlier as in Classic.

### The professions window layout

- Forever loads its own files (`Blizzard_Professions/Camelot`,
  `Blizzard_ProfessionsTemplates/Camelot`): the recipe view
  (`ProfessionsFrame.CraftingPage.SchematicForm`) is 360 px wide, reagents in two columns
  of 160 px slots.
- `SchematicForm:Init(recipeInfo)` runs on every recipe shown and lays out `Reagents`,
  `OptionalReagents` and `FinishingReagents` inside it; a `hooksecurefunc` post-hook sees
  the finished layout.

### Tooltips, bags and loot

- `GameTooltip:GetPrimaryTooltipInfo()` gives `getterName` / `getterArgs`; for bag items
  `getterName == "GetBagItem"`, args `(bag, slot)`, and
  `C_Container.GetContainerItemInfo(bag, slot).stackCount` is the stack.
  `RebuildFromTooltipInfo()` reruns the post-calls (used when Shift changes).
- "Inventory is full" arrives as `UI_ERROR_MESSAGE (errorType, message)` with
  `message == ERR_INV_FULL`. The loot window: `GetNumLootItems`, `GetLootSlotType`
  (`Enum.LootSlotType`), `GetLootSlotLink`, `GetLootSlotInfo` (count is the third value).
- Bag slot buttons, Blizzard's and Baganator's, answer `GetBagID()` and `GetID()`.

### Things that don't work for addons

- `RegisterGameMenuEscHandler` is Blizzard-only: calling it from an addon raises errors on
  every Escape press. Use `UISpecialFrames`.
- A frame with an `OnKeyDown` script gets keyboard input turned on and swallows every key;
  `SetPropagateKeyboardInput` workarounds blocked movement keys in testing.

## Forever-specific details worth knowing

- Two primary professions plus Cooking, First Aid and Fishing. New recipes are
  sold by faction suppliers; high-end recipes cost Merchant's Favor and reputation.
- Reagent bags exist (dedicated slot), as in retail.
- Camping gives tradeskill buffs, and some camps act as crafting stations.

## Sources

- Blizzard UI source mirror, `forever` branch: <https://github.com/Gethe/wow-ui-source/tree/forever>
- Generated API lists, `forever` branch: <https://github.com/Ketho/BlizzardInterfaceResources/tree/forever>
- TOC format and interface numbers: <https://warcraft.wiki.gg/wiki/TOC_format>
- Patch 1.60.1 API changes: <https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes>
- Forever overview: <https://warcraft.wiki.gg/wiki/Forever>
- Addon restrictions write-up: <https://kami-labs.fr/en/wow-classic/wow-forever-addons-restreints-comme-sur-midnight/>
- Removed legacy calls in Forever (Everloot PR): <https://github.com/Everloot/everloot/pull/49>

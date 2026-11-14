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
  event `GET_ITEM_INFO_RECEIVED`
- `GetProfessions`, `GetProfessionInfo`
- `GetMoneyString`, `WrapTextInColorCode`, `HandleModifiedItemClick`, `IsModifiedClick`
- `ChatFrameUtil.InsertLink` (replaces `ChatEdit_InsertLink`, which no longer exists)
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

### Auction house (next: SilkRoad's own scanner)

Forever uses the **retail auction house** (`AuctionHouseFrame`, commodities and
items), not the Classic one. `GetAuctionItemInfo`, `QueryAuctionItems` and
`PlaceAuctionBid` don't exist.

- Full scan: `C_AuctionHouse.ReplicateItems()` → event `REPLICATE_ITEM_LIST_UPDATE` →
  `C_AuctionHouse.GetNumReplicateItems()` and
  `C_AuctionHouse.GetReplicateItemInfo(index)` (fields include `itemID`, `count`,
  `buyoutPrice`, `hasAllInfo`), `GetReplicateItemLink(index)`
- Targeted queries: `C_AuctionHouse.SendBrowseQuery`, `GetBrowseResults`,
  `SendSearchQuery`, `GetCommoditySearchResultInfo`, `GetItemSearchResultInfo`;
  events `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`, `COMMODITY_SEARCH_RESULTS_UPDATED`,
  `ITEM_SEARCH_RESULTS_UPDATED`
- Throttling: `C_AuctionHouse.IsThrottledMessageSystemReady()`
- Open / close: `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`

### Professions (next: recipe indexer)

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

### Merchants (next: vendor price recorder)

- Events `MERCHANT_SHOW`, `MERCHANT_UPDATE`, `MERCHANT_CLOSED`
- `GetMerchantNumItems()`, `GetMerchantItemID(index)`, `GetMerchantItemLink(index)`
- `C_MerchantFrame.GetItemInfo(index)` returns a table with `price`, `stackCount`,
  `numAvailable`, `isPurchasable`, `hasExtendedCost` (the global
  `GetMerchantItemInfo` is gone). Price per item = `price / stackCount`; skip
  `hasExtendedCost` items (bought with currency or tokens).

### Auctionator (optional price source, already wired up)

`Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)` and
`GetAuctionAgeByItemID(callerID, itemID)` (whole days since last seen, `nil` after
21 days). SilkRoad calls them through `pcall`.

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

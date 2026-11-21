--[[ SilkRoad - Game/Forever.lua
	The SR.Game adapter for World of Warcraft: Forever (modern "mainline" UI
	APIs with Classic content). The rest of SilkRoad never calls these game
	APIs directly; another game version gets its own Game/<Flavor>.lua with
	the same functions.

	SR.Game.events                         event names, by purpose
	SR.Game.GetPlayerProfessions()         { { skillLine, name, icon, rank, maxRank }, ... }
	SR.Game.ReadOpenProfession()           { [recipeID] = learned }, { [recipeID] = true } (favorites),
	                                       { [recipeID] = { difficulty, skillUps } } for the open
	                                       window, or nil, reason. difficulty: 0 orange,
	                                       1 yellow, 2 green, 3 grey (at the current skill)
	SR.Game.IsRecipeFavorite / SetRecipeFavorite(recipeID[, favorite])  the professions window's favorites
	SR.Game.GetRecipeProfession(recipeID)  { id, name } for recipes missing from the game data
	SR.Game.IsRecipeKnown(recipeID)        true / false from the spellbook, nil if unknown
	SR.Game.ReadRecipeSchematic(recipeID)  { name, icon, product, quantityMin, quantityMax, reagents }
	SR.Game.ReadMerchant()                 { { itemID, price (per item) }, ... }
	SR.Game.GetAreaName(areaID)            zone / dungeon name
	SR.Game.GetItemCount(itemID)           how many the character has (bags and bank)
	SR.Game.IsRecipeTracked / SetRecipeTracked(recipeID[, tracked])  the objective tracker's recipe list
	SR.Game.GetRecipeName / GetItemName / GetProfessionName(id)  names in the client's language, or nil
	SR.Game.SetWaypoint(uiMapID, x, y, title)  x, y in 0..1; returns true on success
	SR.Game.Auction*                       searching and buying one item at the auction house
	SR.Game.GetAuctionHouseKey()           which auction house the character uses ("PvP Horde"), or nil
	SR.Game.GetRulesetName()               "PvP", "PvE", "RP", "RPPvP" or "HC"
	SR.Game.HookRecipeView(onShow)         onShow(form, recipeID) whenever the professions window shows a recipe
	SR.Game.GetRecipeViewAnchor(form)      the lowest reagent list in that view, to place things under
]]
local _, SR = ...
if SR.flavor ~= "forever" then
	return
end

local Game = {}
SR.Game = Game

Game.events = {
	professionChanged = { "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" },
	merchantChanged = { "MERCHANT_SHOW", "MERCHANT_UPDATE" },
	spellsChanged = { "LEARNED_SPELL_IN_SKILL_LINE", "SKILL_LINES_CHANGED" },
	bagsChanged = { "BAG_UPDATE_DELAYED" },
	trackedRecipesChanged = { "TRACKED_RECIPE_UPDATE" },
	favoritesChanged = { "TRADE_SKILL_FAVORITES_CHANGED" }, -- (isFavorite, recipeID)
	modifiersChanged = { "MODIFIER_STATE_CHANGED" },
}

function Game.GetPlayerProfessions()
	local list = {}
	local indices = { n = select("#", GetProfessions()), GetProfessions() }
	for i = 1, indices.n do
		local index = indices[i]
		if index then
			local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
			if name then
				list[#list + 1] = { skillLine = skillLine, name = name, icon = icon, rank = rank, maxRank = maxRank }
			end
		end
	end
	return list
end

-- Recipes listed in the open profession window, learned or not:
-- { [recipeID] = learned }, plus { [recipeID] = true } for the window's
-- favorites. Which profession the window shows doesn't matter (and Forever
-- doesn't always say): every recipe ID belongs to one profession. Returns
-- nil plus the reason when there's nothing to read.
function Game.ReadOpenProfession()
	if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() then
		return nil, "another player's profession is shown"
	end
	local learned, favorites, colors, count = {}, {}, {}, 0
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe then
			learned[recipeID] = recipe.learned and true or false
			favorites[recipeID] = recipe.favorite and true or nil
			-- The colour the window shows the recipe in (Enum.TradeskillRelativeDifficulty).
			if recipe.relativeDifficulty then
				colors[recipeID] = { difficulty = recipe.relativeDifficulty, skillUps = recipe.numSkillUps }
			end
			count = count + 1
		end
	end
	if count == 0 then
		return nil, "the profession window has no recipes yet"
	end
	return learned, favorites, colors
end

-- The professions window's own favorites. Blizzard only lets learned
-- recipes be favorites; nil when the game can't say.
function Game.IsRecipeFavorite(recipeID)
	local ok, favorite = pcall(C_TradeSkillUI.IsRecipeFavorite, recipeID)
	if ok and favorite ~= nil then
		return favorite and true or false
	end
end

function Game.SetRecipeFavorite(recipeID, favorite)
	pcall(C_TradeSkillUI.SetRecipeFavorite, recipeID, favorite and true or false)
end

-- Profession of a recipe the game data doesn't have: { id, name } or nil.
function Game.GetRecipeProfession(recipeID)
	local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeID)
	if not ok or not info then
		return nil
	end
	local id = (info.parentProfessionID and info.parentProfessionID > 0 and info.parentProfessionID) or info.professionID
	if id and id > 0 then
		return { id = id, name = info.parentProfessionName or info.professionName }
	end
end

-- Whether this character knows a recipe, from the spellbook (recipes are
-- spells). nil when the game can't say.
function Game.IsRecipeKnown(recipeID)
	local ok, known = pcall(C_SpellBook.IsSpellKnown, recipeID)
	if ok and known ~= nil then
		return known and true or false
	end
end

function Game.ReadRecipeSchematic(recipeID)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if not schematic then
		return nil
	end
	local reagents = {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		local reagent = slot.reagents and slot.reagents[1]
		if slot.required and reagent and reagent.itemID then
			reagents[#reagents + 1] = { itemID = reagent.itemID, count = slot.quantityRequired }
		end
	end
	return {
		name = schematic.name,
		icon = schematic.icon,
		product = schematic.outputItemID,
		quantityMin = schematic.quantityMin,
		quantityMax = schematic.quantityMax,
		reagents = reagents,
	}
end

-- What the open merchant sells for gold, as a price per single item.
-- Skipped: items bought with tokens or currencies, and limited-stock offers
-- (numAvailable is -1 for unlimited): a merchant selling two Heavy Leather
-- now and then doesn't make it a vendor item.
function Game.ReadMerchant()
	local list = {}
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index)
		local info = C_MerchantFrame.GetItemInfo(index)
		local limited = info and info.numAvailable and info.numAvailable >= 0
		if itemID and info and info.price and info.price > 0 and not info.hasExtendedCost and not limited then
			list[#list + 1] = { itemID = itemID, price = info.price / math.max(1, info.stackCount or 1) }
		end
	end
	return list
end

-- Names in the client's language. The generated game data is English;
-- these return nil when the game can't answer right away (item names need
-- the item cached), and callers fall back to the English name.
function Game.GetRecipeName(recipeID)
	return C_Spell.GetSpellName(recipeID)
end

function Game.GetItemName(itemID)
	return C_Item.GetItemNameByID(itemID)
end

function Game.GetProfessionName(skillLineID)
	local name = C_TradeSkillUI.GetTradeSkillDisplayName(skillLineID)
	if name and name ~= "" then
		return name
	end
end

-- How many the character has: bags, reagent bag and bank.
function Game.GetItemCount(itemID)
	return C_Item.GetItemCount(itemID, true, false, true) or 0
end

-- Recipe tracking: the game's own profession recipe tracker in the
-- objective tracker (under the quests) lists tracked recipes with their
-- reagent counts.
function Game.IsRecipeTracked(recipeID)
	return C_TradeSkillUI.IsRecipeTracked(recipeID, false) and true or false
end

function Game.SetRecipeTracked(recipeID, tracked)
	C_TradeSkillUI.SetRecipeTracked(recipeID, tracked and true or false, false)
end

-- How many items are in the stack an item tooltip shows: for items in the
-- bags, bank or reagent bag. nil when the tooltip isn't about a bag slot.
function Game.GetTooltipStackCount(tooltip)
	local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
	local args = info and info.getterName == "GetBagItem" and info.getterArgs
	if args and args[1] and args[2] then
		local item = C_Container.GetContainerItemInfo(args[1], args[2])
		return item and item.stackCount or nil
	end
end

-- Builds a shown tooltip again, so post-call hooks add their lines anew.
function Game.RefreshTooltip(tooltip)
	if tooltip:IsShown() and tooltip.RebuildFromTooltipInfo and tooltip:GetPrimaryTooltipInfo() then
		tooltip:RebuildFromTooltipInfo()
	end
end

-- Blizzard's professions window (load-on-demand Blizzard_Professions).
-- Every time it shows a recipe, its schematic form runs Init(recipeInfo)
-- and lays out the reagents; a post-hook sees the finished layout. onShow
-- gets recipeID nil when the form is cleared.
local PROFESSIONS_ADDON = "Blizzard_Professions"

function Game.HookRecipeView(onShow)
	local function Hook()
		local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
		local form = page and page.SchematicForm
		if not form or form.silkRoadHooked then
			return
		end
		form.silkRoadHooked = true
		hooksecurefunc(form, "Init", function(f, recipeInfo)
			onShow(f, recipeInfo and recipeInfo.recipeID or nil)
		end)
	end
	if C_AddOns.IsAddOnLoaded(PROFESSIONS_ADDON) then
		Hook()
	else
		local function OnAddonLoaded(_, name)
			if name == PROFESSIONS_ADDON then
				SR:UnregisterEvent("ADDON_LOADED", OnAddonLoaded)
				Hook()
			end
		end
		SR:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
	end
end

-- The reagent list things go under: the optional reagents when the recipe
-- has any, else the basic reagents.
function Game.GetRecipeViewAnchor(form)
	if form.OptionalReagents and form.OptionalReagents:IsShown() then
		return form.OptionalReagents
	end
	return form.Reagents
end

-- Since Forever's regional realms (RegionalUniqueNamesEnabled), one
-- auction house is shared by every character of a ruleset and faction, and
-- GetRealmName() is blank. Prices are filed the way Auctionator files them.
function Game.GetRulesetName()
	local rules = Enum and Enum.GameRule
	local function Active(rule)
		return rules and rules[rule] and C_GameRules.IsGameRuleActive(rules[rule]) or false
	end
	local pvp, rp = Active("PvPRuleset"), Active("RPRuleset")
	if pvp and rp then
		return "RPPvP"
	elseif pvp then
		return "PvP"
	elseif rp then
		return "RP"
	elseif Active("HardcoreRuleset") then
		return "HC"
	end
	return "PvE"
end

local function Blank(text)
	return text == nil or text:match("^%s*$") ~= nil
end

-- The name prices are filed under: "<ruleset> <faction>" with regional
-- realms, else the realm name. nil while the game can't say yet.
function Game.GetAuctionHouseKey()
	if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
		local faction = UnitFactionGroup("player")
		if Blank(faction) then
			return nil
		end
		return Game.GetRulesetName() .. " " .. faction
	end
	local realm = GetRealmName()
	if Blank(realm) then
		realm = GetNormalizedRealmName()
	end
	if Blank(realm) then
		return nil
	end
	return realm
end

function Game.OpenMap(uiMapID)
	OpenWorldMap(uiMapID)
end

-- A small menu at the cursor: a title, then one entry per option;
-- onPick(option) runs for the one clicked. options = { { label, ... }, ... }
function Game.ShowMenu(owner, title, options, onPick)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:CreateTitle(title)
		for _, option in ipairs(options) do
			rootDescription:CreateButton(option.label, function()
				onPick(option)
			end)
		end
	end)
end

function Game.GetMapName(uiMapID)
	local info = uiMapID and C_Map.GetMapInfo(uiMapID)
	return info and info.name or nil
end

-- Loads a load-on-demand addon if it's installed and enabled; harmless otherwise.
function Game.LoadOptionalAddOn(name)
	if C_AddOns.IsAddOnLoaded(name) then
		return true
	end
	local ok, loaded = pcall(C_AddOns.LoadAddOn, name)
	return ok and loaded and true or false
end

function Game.GetAreaName(areaID)
	local name = areaID and C_Map.GetAreaInfo(areaID)
	return name
end

-- Uses TomTom when it's installed, otherwise the game's own map pin.
function Game.SetWaypoint(uiMapID, x, y, title)
	if not uiMapID or not x or not y then
		return false
	end
	if TomTom and TomTom.AddWaypoint then
		local ok = pcall(TomTom.AddWaypoint, TomTom, uiMapID, x, y, { title = title, from = SR.title })
		if ok then
			return true
		end
	end
	if C_Map.CanSetUserWaypointOnMap(uiMapID) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapID, x, y))
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Auction house: searching and buying one item (Buy Lists tab)
---------------------------------------------------------------------------

local PRICE_SORT = { { sortOrder = 0, reverseSort = false } } -- Enum.AuctionHouseSortOrder.Price

-- Events the buyer listens to, by purpose.
Game.auctionEvents = {
	results = { "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED" },
	price = "COMMODITY_PRICE_UPDATED",
	purchased = { "COMMODITY_PURCHASE_SUCCEEDED", "AUCTION_HOUSE_PURCHASE_COMPLETED" },
	failed = { "COMMODITY_PURCHASE_FAILED" },
	ready = "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
	closed = "AUCTION_HOUSE_CLOSED",
}

function Game.AuctionCanSearch()
	return C_AuctionHouse.IsThrottledMessageSystemReady()
end

function Game.AuctionSearch(itemID)
	C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(itemID), PRICE_SORT, false)
end

-- Whether stacks of the item are sold by quantity (commodities) rather than
-- as separate auctions. nil while the game doesn't know yet.
function Game.AuctionIsCommodity(itemID)
	local info = C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(itemID))
	if info then
		return info.isCommodity
	end
end

-- Listings of the last search, cheapest first:
-- { { auctionID, quantity, unitPrice, buyout (whole auction, items only) }, ... }
-- The character's own auctions are left out: they can't be bought.
function Game.AuctionReadResults(itemID)
	local listings = {}
	if Game.AuctionIsCommodity(itemID) then
		for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
			local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
			local buyable = result and result.quantity - (result.numOwnerItems or 0) or 0
			if buyable > 0 then
				listings[#listings + 1] = { auctionID = result.auctionID, quantity = buyable, unitPrice = result.unitPrice }
			end
		end
	else
		local itemKey = C_AuctionHouse.MakeItemKey(itemID)
		for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
			local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
			if result and result.buyoutAmount and not result.containsOwnerItem then
				listings[#listings + 1] = {
					auctionID = result.auctionID, quantity = result.quantity, buyout = result.buyoutAmount,
					unitPrice = math.floor(result.buyoutAmount / math.max(1, result.quantity)),
				}
			end
		end
		table.sort(listings, function(a, b) return a.unitPrice < b.unitPrice end)
	end
	return listings
end

-- Commodities: the game quotes the final price (COMMODITY_PRICE_UPDATED),
-- then the purchase is confirmed. Both need a click by the player.
function Game.AuctionStartCommodityPurchase(itemID, quantity)
	C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity)
end

function Game.AuctionConfirmCommodityPurchase(itemID, quantity)
	C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, quantity)
end

function Game.AuctionCancelCommodityPurchase()
	C_AuctionHouse.CancelCommoditiesPurchase()
end

-- Other items: buys one whole auction at its buyout price (needs a click).
function Game.AuctionBuyout(auctionID, buyout)
	C_AuctionHouse.PlaceBid(auctionID, buyout)
end

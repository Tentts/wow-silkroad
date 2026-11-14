--[[ SilkRoad - Game/Forever.lua
	The SR.Game adapter for World of Warcraft: Forever (modern "mainline" UI
	APIs with Classic content). The rest of SilkRoad never calls these game
	APIs directly; another game version gets its own Game/<Flavor>.lua with
	the same functions.

	SR.Game.events                         event names, by purpose
	SR.Game.GetPlayerProfessions()         { { skillLine, name, icon, rank, maxRank }, ... }
	SR.Game.ReadOpenProfession()           skillLine, { [recipeID] = learned }, or nil
	SR.Game.ReadRecipeSchematic(recipeID)  { name, icon, product, quantityMin, quantityMax, reagents }
	SR.Game.ReadMerchant()                 { { itemID, price (per item) }, ... }
	SR.Game.GetAreaName(areaID)            zone / dungeon name
	SR.Game.SetWaypoint(uiMapID, x, y, title)  x, y in 0..1; returns true on success
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

-- The profession window's recipes, when it shows one of the player's own
-- professions (not a linked or guild one, not an NPC crafting window).
function Game.ReadOpenProfession()
	if not C_TradeSkillUI.IsTradeSkillReady() or C_TradeSkillUI.IsTradeSkillLinked()
		or C_TradeSkillUI.IsTradeSkillGuild() or C_TradeSkillUI.IsNPCCrafting() then
		return nil
	end
	local info = C_TradeSkillUI.GetBaseProfessionInfo()
	if not info or not info.professionID then
		return nil
	end
	local learned = {}
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe then
			learned[recipeID] = recipe.learned and true or false
		end
	end
	return info.professionID, learned, info.professionName
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

-- What the open merchant sells for gold (items bought with tokens or
-- currencies are skipped), as a price per single item.
function Game.ReadMerchant()
	local list = {}
	for index = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(index)
		local info = C_MerchantFrame.GetItemInfo(index)
		if itemID and info and info.price and info.price > 0 and not info.hasExtendedCost then
			list[#list + 1] = { itemID = itemID, price = info.price / math.max(1, info.stackCount or 1) }
		end
	end
	return list
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

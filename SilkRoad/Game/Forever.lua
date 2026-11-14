--[[ SilkRoad - Game/Forever.lua
	The SR.Game adapter for World of Warcraft: Forever (modern "mainline" UI
	APIs with Classic content). The rest of SilkRoad never calls these game
	APIs directly; another game version gets its own Game/<Flavor>.lua with
	the same functions.

	SR.Game.events                         event names, by purpose
	SR.Game.GetPlayerProfessions()         { { skillLine, name, icon, rank, maxRank }, ... }
	SR.Game.ReadOpenProfession()           { [recipeID] = learned } for the open window, or nil, reason
	SR.Game.GetRecipeProfession(recipeID)  { id, name } for recipes missing from the game data
	SR.Game.IsRecipeKnown(recipeID)        true / false from the spellbook, nil if unknown
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
	spellsChanged = { "LEARNED_SPELL_IN_SKILL_LINE", "SKILL_LINES_CHANGED" },
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
-- { [recipeID] = learned }. Which profession the window shows doesn't
-- matter (and Forever doesn't always say): every recipe ID belongs to one
-- profession. Returns nil plus the reason when there's nothing to read.
function Game.ReadOpenProfession()
	if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() then
		return nil, "another player's profession is shown"
	end
	local learned, count = {}, 0
	for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
		local recipe = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if recipe then
			learned[recipeID] = recipe.learned and true or false
			count = count + 1
		end
	end
	if count == 0 then
		return nil, "the profession window has no recipes yet"
	end
	return learned
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

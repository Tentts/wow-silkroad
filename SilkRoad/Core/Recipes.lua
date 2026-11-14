--[[ SilkRoad - Core/Recipes.lua
	Every recipe of every profession, learned or not.

	Recipes come from the generated game data (Data/<Flavor>/Recipes.lua).
	Opening a profession window adds what only the game knows: which of the
	recipes this character has learned, and any recipe missing from the
	generated data (saved in SilkRoadDB.recipes).

	A recipe is a table:
	  id, skillLine, name, product (itemID or nil for enchants), quantity,
	  learn (skill needed to learn it), learnExact (false = approximate:
	  trainer recipes, whose requirement isn't in the client data),
	  yellow, gray (skill-up colour thresholds), auto (learned with the
	  profession), recipeItem (itemID that teaches it, if any),
	  reagents = { { itemID, count }, ... }

	Fires RECIPES_UPDATED when a profession window has been read.
]]
local _, SR = ...
local Util = SR.Util

local Recipes = SR:NewComponent("Recipes")

local decoded = {} -- [recipeID] = recipe
local bySkill = {} -- [skillLine] = { recipe, ... } (generated data only)

local function StaticData()
	return SR.StaticData or { professions = {}, recipes = {}, items = {} }
end

local function Decode(id, row)
	local reagents = {}
	local list = row[10]
	for i = 1, #list, 2 do
		reagents[#reagents + 1] = { itemID = list[i], count = list[i + 1] }
	end
	return {
		id = id, skillLine = row[1], name = row[2], product = row[3] or nil, quantity = row[4],
		learn = row[5], yellow = row[6], gray = row[7],
		learnExact = row[8] % 2 == 1, auto = math.floor(row[8] / 2) % 2 == 1,
		recipeItem = row[9] or nil, reagents = reagents,
	}
end

-- Recipes read from a profession window that the generated data lacks.
local function DecodeLive(id, saved)
	local quantityMin = saved.quantityMin or 1
	return {
		id = id, skillLine = saved.skillLineID, name = saved.name, product = saved.outputItemID,
		quantity = (quantityMin + (saved.quantityMax or quantityMin)) / 2, icon = saved.icon,
		reagents = saved.reagents or {}, live = true,
	}
end

function Recipes:GetRecipe(id)
	local recipe = decoded[id]
	if not recipe then
		local row = StaticData().recipes[id]
		local saved = SR.DB.global.recipes[id]
		recipe = (row and Decode(id, row)) or (saved and DecodeLive(id, saved))
		decoded[id] = recipe
	end
	return recipe
end

function Recipes:GetRecipes(skillLine)
	local list = bySkill[skillLine]
	if not list then
		list = {}
		for id, row in pairs(StaticData().recipes) do
			if row[1] == skillLine then
				list[#list + 1] = self:GetRecipe(id)
			end
		end
		bySkill[skillLine] = list
	end
	local result = { unpack(list) }
	for id, saved in pairs(SR.DB.global.recipes) do
		if saved.skillLineID == skillLine and not StaticData().recipes[id] then
			result[#result + 1] = self:GetRecipe(id)
		end
	end
	return result
end

function Recipes:CountAll()
	return Util.CountKeys(StaticData().recipes) + Util.CountKeys(SR.DB.global.recipes)
end

---------------------------------------------------------------------------
-- Professions and the character's knowledge
---------------------------------------------------------------------------

-- Every profession with recipes, with this character's skill when learned:
-- { id, name, icon, kind, learned, rank, maxRank }
function Recipes:GetProfessions()
	local mine = {}
	for _, profession in ipairs(SR.Game.GetPlayerProfessions()) do
		mine[profession.skillLine or -1] = profession
		mine[profession.name] = profession
	end
	local list = {}
	for _, profession in ipairs(StaticData().professions) do
		local learned = mine[profession.id] or mine[profession.name]
		list[#list + 1] = {
			id = profession.id, name = profession.name, icon = profession.icon, kind = profession.kind,
			learned = learned ~= nil, rank = learned and learned.rank, maxRank = learned and learned.maxRank,
		}
	end
	return list
end

-- true / false once the profession window has been read; nil before that.
function Recipes:IsKnown(recipe)
	if SR.DB.char.knownRecipes[recipe.id] then
		return true
	end
	if SR.DB.char.scannedProfessions[recipe.skillLine] then
		return false
	end
	return nil
end

function Recipes:HasRead(skillLine)
	return SR.DB.char.scannedProfessions[skillLine] ~= nil
end

function Recipes:CountKnown()
	return Util.CountKeys(SR.DB.char.knownRecipes)
end

-- Matches the window's profession to one in the game data, by ID first,
-- then by name. Falls back to the first ID when nothing matches.
local function ResolveSkillLine(ids, names)
	local professions = StaticData().professions
	for _, id in ipairs(ids) do
		for _, profession in ipairs(professions) do
			if profession.id == id then
				return profession.id
			end
		end
	end
	for _, name in ipairs(names) do
		for _, profession in ipairs(professions) do
			if profession.name == name then
				return profession.id
			end
		end
	end
	return ids[1]
end

function Recipes:ReadProfessionWindow()
	local window, reason = SR.Game.ReadOpenProfession()
	if not window then
		SR:Debug("Profession window not read:", reason)
		return
	end
	local skillLine = ResolveSkillLine(window.ids, window.names)
	if not skillLine then
		SR:Debug("Profession window not read: unknown profession", table.concat(window.names, ", "))
		return
	end
	local learned = window.learned
	local known = SR.DB.char.knownRecipes
	local added = 0
	for recipeID, isLearned in pairs(learned) do
		known[recipeID] = isLearned or nil
		if not StaticData().recipes[recipeID] and not SR.DB.global.recipes[recipeID] then
			local schematic = SR.Game.ReadRecipeSchematic(recipeID)
			if schematic and #schematic.reagents > 0 then
				SR.DB.global.recipes[recipeID] = {
					recipeID = recipeID, name = schematic.name, icon = schematic.icon,
					skillLineID = skillLine, outputItemID = schematic.product,
					quantityMin = schematic.quantityMin, quantityMax = schematic.quantityMax,
					reagents = schematic.reagents,
				}
				added = added + 1
			end
		end
	end
	SR.DB.char.scannedProfessions[skillLine] = time()
	SR:Debug("Read profession window:", skillLine, "recipes:", Util.CountKeys(learned), "new:", added)
	SR:Fire("RECIPES_UPDATED", skillLine)
end

function Recipes:OnEnable()
	local read = Util.Debounce(0.5, function()
		self:ReadProfessionWindow()
	end)
	for _, event in ipairs(SR.Game.events.professionChanged) do
		SR:RegisterEvent(event, read)
	end
end

---------------------------------------------------------------------------
-- Costs and profit
---------------------------------------------------------------------------

--[[ Prices one craft:
	cost         cheapest materials (vendor or auction house, per reagent);
	             nil when some reagent has no price (partialCost has the rest)
	auctionPrice lowest auction buyout of the result, times the quantity made
	auctionNet   the same after the auction house cut
	vendorPrice  what a vendor pays for the result, times the quantity made
	profit       best of auctionNet / vendorPrice, minus cost
	bestSale     "auction" | "vendor"
	reagents     { { itemID, count, unitCost, source = "vendor"|"auction"|nil }, ... }
]]
function Recipes:Evaluate(recipe)
	local prices = SR.Prices
	local cost, complete, reagents = 0, true, {}
	for _, reagent in ipairs(recipe.reagents) do
		local unitCost, source = prices:GetAcquireCost(reagent.itemID)
		reagents[#reagents + 1] = { itemID = reagent.itemID, count = reagent.count, unitCost = unitCost, source = source }
		if unitCost then
			cost = cost + unitCost * reagent.count
		else
			complete = false
		end
	end

	local result = { cost = complete and cost or nil, partialCost = cost, reagents = reagents }
	local product = recipe.product
	if product then
		local quantity = recipe.quantity or 1
		local auction = prices:GetAuctionPrice(product)
		local net = prices:GetNetAuctionPrice(product)
		local vendor = prices:GetVendorSellPrice(product)
		result.auctionPrice = auction and auction * quantity or nil
		result.auctionNet = net and net * quantity or nil
		result.vendorPrice = (vendor and vendor > 0) and vendor * quantity or nil
		local best = math.max(result.auctionNet or -1, result.vendorPrice or -1)
		if best >= 0 then
			result.bestSale = (result.auctionNet or -1) >= (result.vendorPrice or -1) and "auction" or "vendor"
			if complete then
				result.profit = best - cost
			end
		end
	end
	return result
end

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
	-- The generated names are English; other clients get the game's own.
	local name = row[2]
	if SR.locale ~= "enUS" then
		name = SR.Game.GetRecipeName(id) or name
	end
	return {
		id = id, skillLine = row[1], name = name, product = row[3] or nil, quantity = row[4],
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
		local name = profession.name
		if SR.locale ~= "enUS" then
			name = (learned and learned.name) or SR.Game.GetProfessionName(profession.id) or name
		end
		list[#list + 1] = {
			id = profession.id, name = name, icon = profession.icon, kind = profession.kind,
			learned = learned ~= nil, rank = learned and learned.rank, maxRank = learned and learned.maxRank,
		}
	end
	return list
end

-- true / false once SilkRoad knows the character's recipes for that
-- profession (from the spellbook or a profession window); nil before that.
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

-- Profession of a recipe ID: from the game data, from recipes saved earlier,
-- or by asking the game.
local function RecipeSkillLine(recipeID)
	local row = StaticData().recipes[recipeID]
	if row then
		return row[1]
	end
	local saved = SR.DB.global.recipes[recipeID]
	if saved and saved.skillLineID then
		return saved.skillLineID
	end
	local profession = SR.Game.GetRecipeProfession(recipeID)
	return profession and profession.id
end

-- Saves a recipe the game data lacks, from the open profession window.
local function SaveLiveRecipe(recipeID, skillLine)
	local schematic = SR.Game.ReadRecipeSchematic(recipeID)
	if schematic and #schematic.reagents > 0 and skillLine then
		SR.DB.global.recipes[recipeID] = {
			recipeID = recipeID, name = schematic.name, icon = schematic.icon,
			skillLineID = skillLine, outputItemID = schematic.product,
			quantityMin = schematic.quantityMin, quantityMax = schematic.quantityMax,
			reagents = schematic.reagents,
		}
		return true
	end
	return false
end

-- Records which of the listed recipes the character has learned. Which
-- profession the window shows doesn't matter: each recipe ID belongs to one
-- profession, and every profession seen this way counts as read.
function Recipes:ReadProfessionWindow()
	local learned, reason = SR.Game.ReadOpenProfession()
	if not learned then
		SR:Debug("Profession window not read:", reason)
		return
	end
	local known, read = SR.DB.char.knownRecipes, SR.DB.char.scannedProfessions
	local professions, added, now = {}, 0, time()
	for recipeID, isLearned in pairs(learned) do
		known[recipeID] = isLearned or nil
		local skillLine = RecipeSkillLine(recipeID)
		if skillLine then
			professions[skillLine] = (professions[skillLine] or 0) + 1
			read[skillLine] = now
		end
		if not StaticData().recipes[recipeID] and not SR.DB.global.recipes[recipeID] and SaveLiveRecipe(recipeID, skillLine) then
			added = added + 1
		end
	end
	if SR.DB.settings.debug then
		local parts = {}
		for skillLine, count in pairs(professions) do
			parts[#parts + 1] = skillLine .. "=" .. count
		end
		SR:Debug("Read profession window:", Util.CountKeys(learned), "recipes, professions:", table.concat(parts, " "), "new:", added)
	end
	SR:Fire("RECIPES_UPDATED")
end

-- Asks the spellbook which recipes of the character's professions are
-- learned, so no profession window has to be opened (works in Forever).
-- Only trusted for a profession when the spellbook knows at least one of
-- its recipes, in case the game ever stops answering for recipes; the
-- profession window then still fills in.
function Recipes:ReadSpellbook()
	local known, read, now = SR.DB.char.knownRecipes, SR.DB.char.scannedProfessions, time()
	local changed = false
	for _, profession in ipairs(self:GetProfessions()) do
		if profession.learned then
			local found = {}
			for _, recipe in ipairs(self:GetRecipes(profession.id)) do
				if SR.Game.IsRecipeKnown(recipe.id) then
					found[#found + 1] = recipe.id
				end
			end
			SR:Debug("Spellbook:", profession.name, #found, "known recipes")
			if #found > 0 then
				for _, recipeID in ipairs(found) do
					changed = changed or not known[recipeID]
					known[recipeID] = true
				end
				changed = changed or read[profession.id] == nil
				read[profession.id] = read[profession.id] or now
			end
		end
	end
	if changed then
		SR:Fire("RECIPES_UPDATED")
	end
end

-- Forgets recipes of professions the character no longer has, so they
-- don't count as known (or as read) after dropping a profession.
function Recipes:ForgetDroppedProfessions()
	local mine = {}
	for _, profession in ipairs(self:GetProfessions()) do
		if profession.learned then
			mine[profession.id] = true
		end
	end
	local read, known = SR.DB.char.scannedProfessions, SR.DB.char.knownRecipes
	for skillLine in pairs(read) do
		if not mine[skillLine] then
			read[skillLine] = nil
			SR:Debug("Forgetting recipes of a dropped profession:", skillLine)
		end
	end
	for recipeID in pairs(known) do
		local skillLine = RecipeSkillLine(recipeID)
		if skillLine and not mine[skillLine] then
			known[recipeID] = nil
		end
	end
end

function Recipes:OnEnable()
	self:ForgetDroppedProfessions()
	local read = Util.Debounce(0.5, function()
		self:ReadProfessionWindow()
	end)
	for _, event in ipairs(SR.Game.events.professionChanged) do
		SR:RegisterEvent(event, read)
	end
	local readSpellbook = Util.Debounce(1, function()
		self:ReadSpellbook()
		SR:Fire("SKILL_CHANGED") -- profession skill may have gone up
	end)
	for _, event in ipairs(SR.Game.events.spellsChanged) do
		SR:RegisterEvent(event, readSpellbook)
	end
	readSpellbook()
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
	auctionProfit auctionNet minus cost (nil without an auction price or a full cost)
	vendorProfit  vendorPrice minus cost
	profit       the better of the two
	bestSale     "auction" | "vendor": where the result earns more
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
				result.auctionProfit = result.auctionNet and result.auctionNet - cost or nil
				result.vendorProfit = result.vendorPrice and result.vendorPrice - cost or nil
			end
		end
	end
	return result
end

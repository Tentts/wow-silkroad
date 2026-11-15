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

	Evaluate(recipe) prices one craft: cost (buying the reagents), rawCost
	(crafting every intermediate yourself from raw materials, see
	Breakdown), sale prices and profits.

	Fires RECIPES_UPDATED when a profession window has been read.
]]
local _, SR = ...
local Util = SR.Util

local Recipes = SR:NewComponent("Recipes")

local decoded = {} -- [recipeID] = recipe
local bySkill = {} -- [skillLine] = { recipe, ... } (generated data only)
local producers -- [itemID] = { recipe, ... } that make it, built on first use
local users -- [itemID] = { recipe, ... } that use it as a reagent, built on first use

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
		producers, users = nil, nil -- the new recipe may make or use something
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

---------------------------------------------------------------------------
-- Tracking (the game's objective tracker)
---------------------------------------------------------------------------

local TRACK_CHECK_DELAY = 1

function Recipes:IsTracked(recipe)
	return SR.Game.IsRecipeTracked(recipe.id)
end

-- Tracks or stops tracking a recipe. The game may refuse some recipes
-- (ones the character can't craft, for instance); a moment later SilkRoad
-- checks and says so.
function Recipes:SetTracked(recipe, tracked)
	SR.Game.SetRecipeTracked(recipe.id, tracked)
	C_Timer.After(TRACK_CHECK_DELAY, function()
		if SR.Game.IsRecipeTracked(recipe.id) ~= (tracked and true or false) then
			SR:Print(SR.L["The game didn't track %s; it may only track recipes this character can craft."]:format(recipe.name or "?"))
		end
		SR:Fire("RECIPES_UPDATED")
	end)
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
	for _, event in ipairs(SR.Game.events.trackedRecipesChanged) do
		SR:RegisterEvent(event, function()
			SR:Fire("RECIPES_UPDATED")
		end)
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
---------------------------------------------------------------------------
-- Favorites (account-wide, marked from a recipe's right-click menu)
---------------------------------------------------------------------------

Recipes.FAVORITE_ICON = "|A:auctionhouse-icon-favorite:12:12|a"

function Recipes:IsFavorite(recipe)
	return SR.DB.global.favoriteRecipes[recipe.id] == true
end

function Recipes:SetFavorite(recipe, favorite)
	SR.DB.global.favoriteRecipes[recipe.id] = favorite and true or nil
	SR:Fire("RECIPES_UPDATED")
end

---------------------------------------------------------------------------
-- Recipes that use an item
---------------------------------------------------------------------------

-- Every recipe that needs the item as a reagent.
function Recipes:GetRecipesUsing(itemID)
	if not users then
		users = {}
		local function Add(recipe)
			for _, reagent in ipairs(recipe and recipe.reagents or {}) do
				local list = users[reagent.itemID]
				if not list then
					list = {}
					users[reagent.itemID] = list
				end
				if list[#list] ~= recipe then -- a recipe listing the item twice counts once
					list[#list + 1] = recipe
				end
			end
		end
		for id in pairs(StaticData().recipes) do
			Add(self:GetRecipe(id))
		end
		for id in pairs(SR.DB.global.recipes) do
			if not StaticData().recipes[id] then
				Add(self:GetRecipe(id))
			end
		end
	end
	return users[itemID] or {}
end

---------------------------------------------------------------------------
-- Raw materials: crafting every step yourself
---------------------------------------------------------------------------

local MAX_BREAKDOWN_DEPTH = 6

-- Recipes that make an item.
function Recipes:GetProducers(itemID)
	if not producers then
		producers = {}
		local function Add(recipe)
			if recipe and recipe.product then
				producers[recipe.product] = producers[recipe.product] or {}
				table.insert(producers[recipe.product], recipe)
			end
		end
		for id in pairs(StaticData().recipes) do
			Add(self:GetRecipe(id))
		end
		for id in pairs(SR.DB.global.recipes) do
			if not StaticData().recipes[id] then
				Add(self:GetRecipe(id))
			end
		end
	end
	return producers[itemID] or {}
end

-- The recipe to make a reagent with when crafting every step of a recipe
-- of `skillLine`: one of the same profession, or one of another profession
-- this character knows (an alchemist leatherworker brews their own
-- elixirs). Known recipes first, then the lowest skill. nil = buy it.
function Recipes:GetBreakdownProducer(itemID, skillLine)
	local best, bestKnown
	for _, recipe in ipairs(self:GetProducers(itemID)) do
		local known = self:IsKnown(recipe) and true or false
		if recipe.skillLine == skillLine or known then
			if not best or (known and not bestKnown)
				or (known == bestKnown and (recipe.learn or 0) < (best.learn or 0)) then
				best, bestKnown = recipe, known
			end
		end
	end
	return best
end

-- Whether everything a producer needs can be bought or crafted, so that
-- crafting the item is possible from priced materials.
function Recipes:CanSourceMaterials(producer, skillLine, depth, visiting)
	for _, reagent in ipairs(producer.reagents) do
		if not SR.Prices:GetAcquireCost(reagent.itemID) then
			local deeper = depth < MAX_BREAKDOWN_DEPTH and self:GetBreakdownProducer(reagent.itemID, skillLine)
			if not deeper or visiting[deeper.id] then
				return false
			end
			visiting[deeper.id] = true
			local ok = self:CanSourceMaterials(deeper, skillLine, depth + 1, visiting)
			visiting[deeper.id] = nil
			if not ok then
				return false
			end
		end
	end
	return true
end

-- Breaks a recipe down to raw materials: every reagent another recipe
-- makes (see GetBreakdownProducer) is crafted instead of bought. A reagent
-- that has a price itself is bought when its own materials can't be (Light
-- Leather from Ruined Leather Scraps nobody sells).
--   crafts  how many times the recipe is made (default 1)
--   exact   true: fractional amounts, for prices; otherwise whole crafts
-- Returns raw = { { itemID, count }, ... } and steps = { { recipe, crafts }, ... }
-- (the intermediate crafts, deepest first). steps is empty when nothing
-- can be broken down.
function Recipes:Breakdown(recipe, crafts, exact)
	local raw, rawIndex, steps, stepIndex = {}, {}, {}, {}
	local visiting = { [recipe.id] = true }
	local function AddRaw(itemID, count)
		local entry = rawIndex[itemID]
		if not entry then
			entry = { itemID = itemID, count = 0 }
			rawIndex[itemID] = entry
			raw[#raw + 1] = entry
		end
		entry.count = entry.count + count
	end
	local function Expand(current, times, depth)
		for _, reagent in ipairs(current.reagents) do
			local need = reagent.count * times
			local producer = depth < MAX_BREAKDOWN_DEPTH and self:GetBreakdownProducer(reagent.itemID, recipe.skillLine)
			if producer and (visiting[producer.id] or (SR.Prices:GetAcquireCost(reagent.itemID)
				and not self:CanSourceMaterials(producer, recipe.skillLine, depth + 1, visiting))) then
				producer = nil
			end
			if producer then
				local made = math.max(1, producer.quantity or 1)
				local subCrafts = exact and need / made or math.ceil(need / made - 1e-9)
				visiting[producer.id] = true
				Expand(producer, subCrafts, depth + 1)
				visiting[producer.id] = nil
				local step = stepIndex[producer.id]
				if not step then
					step = { recipe = producer, crafts = 0 }
					stepIndex[producer.id] = step
					steps[#steps + 1] = step
				end
				step.crafts = step.crafts + subCrafts
			else
				AddRaw(reagent.itemID, need)
			end
		end
	end
	Expand(recipe, crafts or 1, 0)
	return raw, steps
end

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

	-- Crafting every step: the raw materials at their cheapest price.
	local raw, steps = self:Breakdown(recipe, 1, true)
	if #steps == 0 then
		result.rawCost = result.cost
	else
		local rawCost, rawComplete = 0, true
		result.raw, result.steps = {}, steps
		for _, entry in ipairs(raw) do
			local unitCost, source = prices:GetAcquireCost(entry.itemID)
			result.raw[#result.raw + 1] = { itemID = entry.itemID, count = entry.count, unitCost = unitCost, source = source }
			if unitCost then
				rawCost = rawCost + unitCost * entry.count
			else
				rawComplete = false
			end
		end
		result.rawCost = rawComplete and rawCost or nil
	end
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

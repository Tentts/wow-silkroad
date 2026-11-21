--[[ SilkRoad - Core/Planner.lua
	Plans the cheapest way to level a crafting profession, from current
	prices, the recipes this character knows and how the others are obtained.

	How a plan is made:
	  * Skill-up chance of a recipe at skill s: 1 while orange (below its
	    yellow threshold), then (gray - s) / (gray - yellow), 0 once gray.
	    A craft is worth that many expected points.
	  * Cost of a craft: materials at the cheapest price per reagent (buying
	    it, or crafting it yourself when that's cheaper, e.g. bolts), minus
	    what the result sells for if resale is counted (vendor only, or the
	    better of vendor and auction after the cut). For choosing recipes,
	    selling the result wins back at most MAX_RESALE_SHARE of the
	    materials: a craft that sells for more than it costs isn't free when
	    levelling (materials up front, time, selling dozens of items), so
	    the number of crafts a recipe needs always counts.
	  * A recipe this character doesn't know adds its learning cost (recipe
	    item from a vendor or the auction house; trainer fees aren't in the
	    game data), spread over the points it can still give.
	  * Which recipes may be used depends on the availability level chosen:
	    known only, + trainer, + vendor recipes, + auction recipes, + drops.
	  * For every skill point from the start to the target, the recipe with
	    the lowest cost per expected point wins; consecutive points with the
	    same recipe become one step.

	Planner:Plan(skillLine, options) returns
	  { steps = { step, ... }, totalCost, learningCost, gaps, shopping = { item, ... } }
	  step     = { recipe, from, to, crafts, cost (net, all crafts), materialCost,
	               resale, learn = nil | { kind, cost }, unpriced, gap }
	  shopping = { itemID, need, have, buy, unitCost, source, total }
]]
local _, SR = ...
local Util = SR.Util

local Planner = SR:NewComponent("Planner")

-- Availability levels, cumulative.
Planner.AVAILABILITY = { "known", "trainer", "vendor", "auction", "drop" }
local AVAILABILITY_RANK = {}
for rank, level in ipairs(Planner.AVAILABILITY) do
	AVAILABILITY_RANK[level] = rank
end

Planner.RESALE = { "none", "vendor", "best" }

-- Score for recipes with an unpriced reagent: only used when nothing else can give the point.
local UNPRICED_PENALTY = 1e12

-- Share of the materials that selling the result can win back when recipes
-- are compared (the plan still shows the real cost).
local MAX_RESALE_SHARE = 0.75

-- What one craft costs when comparing recipes.
local function RankingCost(candidate)
	return math.max(candidate.craftCost, candidate.materialCost * (1 - MAX_RESALE_SHARE), 0)
end

function Planner.SkillUpChance(recipe, skill)
	local yellow, gray = recipe.yellow, recipe.gray
	if not yellow or not gray or skill >= gray then
		return 0
	elseif skill < yellow or gray <= yellow then
		return 1
	end
	return (gray - skill) / (gray - yellow)
end

-- How the character can get a recipe: "known", "trainer", "vendor",
-- "auction", "drop" (or nil when it can't be had at all), and what it costs.
function Planner:Acquisition(recipe)
	if recipe.auto or SR.Recipes:IsKnown(recipe) then
		return "known", 0
	end
	if not recipe.recipeItem then
		return "trainer", 0
	end
	local sources = SR.Sources:GetRecipeSources(recipe)
	for _, source in ipairs(sources) do
		if source.kind == "vendor" and not source.hostile then
			local static = SR.StaticData and SR.StaticData.items[recipe.recipeItem]
			local price = static and static[5] > 0 and static[5] / static[6] or 0
			return "vendor", price, source
		end
	end
	local auction = SR.Prices:GetAuctionPrice(recipe.recipeItem)
	if auction then
		return "auction", auction
	end
	return "drop", 0, sources[1]
end

local function ResaleValue(evaluation, resale)
	if resale == "vendor" then
		return evaluation.vendorPrice or 0
	elseif resale == "best" then
		return math.max(evaluation.vendorPrice or 0, evaluation.auctionNet or 0)
	end
	return 0
end

local MAX_CRAFT_DEPTH = 3 -- intermediates of intermediates (e.g. bolt -> cloth)

-- Prices reagents for a plan: the cheaper of buying one (vendor or auction
-- house) and crafting it yourself with a recipe the plan may use (bolts of
-- cloth, smelted bars, ...). Returns unitCost, "vendor"|"auction"|"craft", recipe.
local function NewReagentPricer(producers)
	local memo, visiting = {}, {}
	local function Price(itemID, depth)
		depth = depth or 0
		local cached = memo[itemID]
		if cached then
			return cached[1], cached[2], cached[3]
		end
		local best, source = SR.Prices:GetAcquireCost(itemID)
		local via
		if depth < MAX_CRAFT_DEPTH and not visiting[itemID] then
			visiting[itemID] = true
			for _, recipe in ipairs(producers[itemID] or {}) do
				local cost, complete = 0, true
				for _, reagent in ipairs(recipe.reagents) do
					local unit = Price(reagent.itemID, depth + 1)
					if not unit then
						complete = false
						break
					end
					cost = cost + unit * reagent.count
				end
				cost = cost / math.max(1, recipe.quantity or 1)
				if complete and (not best or cost < best) then
					best, source, via = cost, "craft", recipe
				end
			end
			visiting[itemID] = nil
		end
		if depth == 0 then
			memo[itemID] = { best, source, via }
		end
		return best, source, via
	end
	return Price
end

-- Recipes this plan may use, with what one craft costs, and the reagent
-- pricer they were priced with.
function Planner:Candidates(skillLine, options)
	local allowed = AVAILABILITY_RANK[options.availability or "trainer"] or 2
	local usable = {}
	for _, recipe in ipairs(SR.Recipes:GetRecipes(skillLine)) do
		local kind, learnCost, source = self:Acquisition(recipe)
		if kind and AVAILABILITY_RANK[kind] <= allowed then
			usable[#usable + 1] = { recipe = recipe, kind = kind, learnCost = learnCost, source = source }
		end
	end

	local producers = {}
	for _, entry in ipairs(usable) do
		local product = entry.recipe.product
		if product then
			producers[product] = producers[product] or {}
			table.insert(producers[product], entry.recipe)
		end
	end
	local price = NewReagentPricer(producers)

	local list = {}
	for _, entry in ipairs(usable) do
		local recipe = entry.recipe
		if recipe.learn and recipe.yellow and recipe.gray and recipe.gray > recipe.learn then
			local materialCost, unpriced = 0, false
			for _, reagent in ipairs(recipe.reagents) do
				local unit = price(reagent.itemID)
				if unit then
					materialCost = materialCost + unit * reagent.count
				else
					unpriced = true
				end
			end
			local evaluation = SR.Recipes:Evaluate(recipe)
			local resale = ResaleValue(evaluation, options.resale or "vendor")
			list[#list + 1] = {
				recipe = recipe, evaluation = evaluation,
				materialCost = materialCost, resale = resale,
				craftCost = materialCost - resale, unpriced = unpriced,
				learnKind = entry.kind, learnCost = entry.learnCost, learnSource = entry.source,
			}
		end
	end
	return list, price
end

local function BestAt(candidates, skill, acquired)
	local best, bestScore, bestChance
	for _, candidate in ipairs(candidates) do
		local recipe = candidate.recipe
		if recipe.learn <= skill then
			local chance = Planner.SkillUpChance(recipe, skill)
			if chance > 0 then
				local score = RankingCost(candidate) / chance
				if candidate.learnKind ~= "known" and not acquired[recipe.id] then
					score = score + candidate.learnCost / math.max(1, recipe.gray - skill)
				end
				if candidate.unpriced then
					score = score + UNPRICED_PENALTY
				end
				-- Prefer cheaper; on equal cost, the more reliable skill-up.
				if not best or score < bestScore or (score == bestScore and chance > bestChance) then
					best, bestScore, bestChance = candidate, score, chance
				end
			end
		end
	end
	return best, bestChance
end

function Planner:Plan(skillLine, options)
	options = options or {}
	local from = math.max(1, math.floor(options.from or 1))
	local to = math.floor(options.to or 300)
	local candidates, price = self:Candidates(skillLine, options)

	local steps, acquired, gaps = {}, {}, 0
	local current
	for skill = from, to - 1 do
		local best, chance = BestAt(candidates, skill, acquired)
		if not best then
			gaps = gaps + 1
			if current and current.gap then
				current.to = skill + 1
			else
				current = { gap = true, from = skill, to = skill + 1 }
				steps[#steps + 1] = current
			end
		else
			if not (current and current.candidate == best) then
				current = {
					candidate = best, recipe = best.recipe, from = skill, to = skill, expectedCrafts = 0,
					unpriced = best.unpriced,
				}
				if best.learnKind ~= "known" and not acquired[best.recipe.id] then
					current.learn = { kind = best.learnKind, cost = best.learnCost, source = best.learnSource }
					acquired[best.recipe.id] = true
				end
				steps[#steps + 1] = current
			end
			current.to = skill + 1
			current.expectedCrafts = current.expectedCrafts + 1 / chance
		end
	end

	-- Totals and the shopping list. Reagents cheaper to craft than to buy
	-- are listed as their own materials, and noted on the step.
	local totalCost, learningCost, needs, unpriced = 0, 0, {}, false
	local function AddNeed(itemID, count, step, depth)
		local _, source, via = price(itemID)
		if source == "craft" and via and depth < MAX_CRAFT_DEPTH then
			local crafts = math.ceil(count / math.max(1, via.quantity or 1))
			step.intermediates[#step.intermediates + 1] = { recipe = via, crafts = crafts }
			for _, reagent in ipairs(via.reagents) do
				AddNeed(reagent.itemID, reagent.count * crafts, step, depth + 1)
			end
		else
			needs[itemID] = (needs[itemID] or 0) + count
		end
	end
	for _, step in ipairs(steps) do
		if not step.gap then
			local candidate = step.candidate
			step.crafts = math.ceil(step.expectedCrafts - 1e-9)
			step.materialCost = candidate.materialCost * step.crafts
			step.resale = candidate.resale * step.crafts
			step.cost = step.materialCost - step.resale
			totalCost = totalCost + step.cost
			unpriced = unpriced or step.unpriced
			if step.learn then
				learningCost = learningCost + step.learn.cost
			end
			step.intermediates = {}
			for _, reagent in ipairs(step.recipe.reagents) do
				AddNeed(reagent.itemID, reagent.count * step.crafts, step, 0)
			end
		end
	end

	local shopping = {}
	for itemID, need in pairs(needs) do
		local have = SR.Game.GetItemCount(itemID)
		local unitCost, source = price(itemID)
		local buy = math.max(0, need - have)
		shopping[#shopping + 1] = {
			itemID = itemID, need = need, have = have, buy = buy,
			unitCost = unitCost, source = source, total = unitCost and unitCost * buy or nil,
		}
	end
	table.sort(shopping, function(a, b)
		return (a.total or -1) > (b.total or -1)
	end)

	return { steps = steps, totalCost = totalCost, learningCost = learningCost, gaps = gaps, shopping = shopping,
		unpriced = unpriced, from = from, to = to }
end

-- The step a character at `skill` is on (nil when outside the plan).
function Planner.CurrentStep(plan, skill)
	for index, step in ipairs(plan.steps) do
		if skill >= step.from and skill < step.to then
			return index, step
		end
	end
end

-- Highest skill any recipe of the profession can still raise.
function Planner:MaxSkill(skillLine)
	local maxGray = 0
	for _, recipe in ipairs(SR.Recipes:GetRecipes(skillLine)) do
		if recipe.gray and recipe.gray > maxGray then
			maxGray = recipe.gray
		end
	end
	return maxGray
end


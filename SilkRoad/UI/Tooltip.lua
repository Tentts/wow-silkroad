--[[ SilkRoad - UI/Tooltip.lua
	Adds SilkRoad's prices to item tooltips, like Auctionator's lines:
	  SilkRoad vendor    what a vendor pays for one
	  SilkRoad auction   lowest auction buyout, for items that can be sold
	                     (not bind-on-pickup, soulbound, account-bound or quest items)
	Settings > General picks the mode: off, single item, whole stack, or
	single and stack (one line each: "SilkRoad vendor" and "SilkRoad vendor
	x20"). Stacks are the ones in the bags, bank and reagent bag; holding
	Shift swaps single and stack while hovering.

	Below the prices, the recipes that use the item as a reagent: favorites
	only, learned ones, all, or none (Settings > General), at most
	MAX_RECIPE_LINES of them, favorites and learned recipes first.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util

local Tooltip = SR:NewComponent("Tooltip")

local LABEL_R, LABEL_G, LABEL_B = 0.9, 0.76, 0.36 -- SilkRoad gold
local MAX_RECIPE_LINES = 8

-- Tooltip lines that mean the item can't go on the auction house.
local function IsBound(data)
	local bindTexts = {}
	for _, text in ipairs({ ITEM_SOULBOUND, ITEM_BIND_ON_PICKUP, ITEM_BIND_QUEST, ITEM_ACCOUNTBOUND, ITEM_BNETACCOUNTBOUND }) do
		if text then
			bindTexts[text] = true
		end
	end
	for _, line in ipairs(data.lines or {}) do
		if line.leftText and bindTexts[line.leftText] then
			return true
		end
	end
	return false
end

-- What to show for a stack of `count`: "single", "stack" or "both".
-- Shift swaps single and stack while held.
local function ShownAs(mode, count)
	if count <= 1 then
		return "single"
	elseif mode == "both" then
		return "both"
	end
	local stack = mode == "stack"
	if IsShiftKeyDown() then
		stack = not stack
	end
	return stack and "stack" or "single"
end

local function AddLine(tooltip, label, value)
	tooltip:AddDoubleLine(label, value, LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
end

-- One price as shown: the single line, the stack line, or both lines.
local function AddPrice(tooltip, singleLabel, stackLabel, price, count, shownAs)
	if shownAs ~= "stack" then
		AddLine(tooltip, singleLabel, Util.FormatMoney(price))
	end
	if shownAs ~= "single" then
		AddLine(tooltip, stackLabel:format(count), Util.FormatMoney(price * count))
	end
end

function Tooltip:AddPriceLines(tooltip, data)
	local mode = SR:GetSetting("tooltipMode")
	if mode == "off" or not data or type(data.id) ~= "number" then
		return false
	end
	local itemID = data.id
	local added = false
	local count = SR.Game.GetTooltipStackCount(tooltip) or 1
	local shownAs = ShownAs(mode, count)

	local vendor = SR.Prices:GetVendorSellPrice(itemID)
	if vendor and vendor > 0 then
		AddPrice(tooltip, L["SilkRoad vendor"], L["SilkRoad vendor x%d"], vendor, count, shownAs)
		added = true
	end

	if not IsBound(data) then
		local auction = SR.Prices:GetAuctionPrice(itemID)
		if auction then
			AddPrice(tooltip, L["SilkRoad auction"], L["SilkRoad auction x%d"], auction, count, shownAs)
		else
			AddLine(tooltip, L["SilkRoad auction"], Util.ColorText(L["no data"], "ff808080"))
		end
		added = true
	end

	return added
end

-- Recipes using the item, as the "Recipes in item tooltips" setting picks.
function Tooltip:GetRecipesShown(itemID)
	local mode = SR:GetSetting("tooltipRecipes")
	if mode == "off" then
		return {}
	end
	local recipes = SR.Recipes
	local shown = {}
	for _, recipe in ipairs(recipes:GetRecipesUsing(itemID)) do
		local favorite = recipes:IsFavorite(recipe)
		local known = recipes:IsKnown(recipe) == true
		if mode == "all" or favorite or (mode == "learned" and known) then
			shown[#shown + 1] = { recipe = recipe, favorite = favorite, known = known }
		end
	end
	table.sort(shown, function(a, b)
		if a.favorite ~= b.favorite then
			return a.favorite
		elseif a.known ~= b.known then
			return a.known
		elseif (a.recipe.learn or 0) ~= (b.recipe.learn or 0) then
			return (a.recipe.learn or 0) < (b.recipe.learn or 0)
		end
		return (a.recipe.name or "") < (b.recipe.name or "")
	end)
	return shown
end

function Tooltip:AddRecipeLines(tooltip, data)
	if not data or type(data.id) ~= "number" then
		return false
	end
	local shown = self:GetRecipesShown(data.id)
	if #shown == 0 then
		return false
	end
	local professionNames = {}
	for _, profession in ipairs(SR.Recipes:GetProfessions()) do
		professionNames[profession.id] = profession.name
	end
	tooltip:AddDoubleLine(L["SilkRoad: used in"], "", LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
	for index = 1, math.min(#shown, MAX_RECIPE_LINES) do
		local entry = shown[index]
		local name = entry.recipe.name or "?"
		if entry.favorite then
			name = SR.Recipes.FAVORITE_ICON .. " " .. name
		end
		local r, g, b = 1, 1, 1
		if not entry.known then
			r, g, b = 0.6, 0.6, 0.6 -- not learned
		end
		tooltip:AddDoubleLine("  " .. name, professionNames[entry.recipe.skillLine] or "", r, g, b, 0.6, 0.6, 0.6)
	end
	if #shown > MAX_RECIPE_LINES then
		tooltip:AddDoubleLine("  " .. L["and %d more"]:format(#shown - MAX_RECIPE_LINES), "", 0.6, 0.6, 0.6, 1, 1, 1)
	end
	return true
end

function Tooltip:OnItemTooltip(tooltip, data)
	local prices = self:AddPriceLines(tooltip, data)
	local recipes = self:AddRecipeLines(tooltip, data)
	if (prices or recipes) and tooltip:IsShown() then
		tooltip:Show() -- resize to fit the new lines
	end
end

function Tooltip:OnEnable()
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		self:OnItemTooltip(tooltip, data)
	end)
	-- Pressing or releasing Shift while hovering switches between one item and the stack.
	for _, event in ipairs(SR.Game.events.modifiersChanged) do
		SR:RegisterEvent(event, function(_, key)
			local mode = SR:GetSetting("tooltipMode")
			if (key == "LSHIFT" or key == "RSHIFT") and (mode == "single" or mode == "stack")
				and GameTooltip:IsShown() and SR.Game.GetTooltipStackCount(GameTooltip) then
				SR.Game.RefreshTooltip(GameTooltip)
			end
		end)
	end
end

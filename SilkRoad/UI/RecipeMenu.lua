--[[ SilkRoad - UI/RecipeMenu.lua
	The right-click menu for a recipe, shared by the Recipes and Leveling
	Guide pages: track it in the game's objective tracker (its reagents are
	listed under the quests), mark it as a favorite, add its reagents (or the
	raw materials, for crafting every step) to a buy list, or see where to
	get it.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

-- Asks how many crafts, then adds the reagents (raw: the raw materials)
-- to the list (nil = a new one).
local function AddToBuyList(recipe, listID, crafts, raw)
	Widgets.Prompt(L["How many times will you craft %s?"]:format(recipe.name or L["Recipe"]), crafts or 1, function(text)
		local count = math.max(1, math.floor(tonumber(text) or 1))
		local list, added, skipped = SR.BuyLists:AddRecipe(listID, recipe, count, raw)
		local names = {}
		for _, itemID in ipairs(skipped) do
			names[#names + 1] = Util.GetItemDisplay(itemID).name
		end
		if not list then
			SR:Print(L["Nothing to buy for %s: vendors sell all its reagents (%s)."]:format(
				recipe.name or L["Recipe"], table.concat(names, ", ")))
			return
		end
		local message = L["Added %d reagents to the buy list %s."]:format(added, list.name)
		if #names > 0 then
			message = message .. " " .. L["Left out, sold by vendors: %s."]:format(table.concat(names, ", "))
		end
		SR:Print(message)
	end, true)
end

local function ShowBuyListMenu(recipe, owner, crafts, raw)
	local options = { { label = L["New buy list"], listID = nil } }
	for _, list in ipairs(SR.BuyLists:GetLists()) do
		options[#options + 1] = { label = list.name, listID = list.id }
	end
	SR.Game.ShowMenu(owner, raw and L["Add raw materials to a buy list"] or L["Add to a buy list"], options, function(option)
		AddToBuyList(recipe, option.listID, crafts, raw)
	end)
end

-- crafts: suggested number of crafts (the guide step's), default 1.
function SR.UI:ShowRecipeMenu(recipe, owner, crafts)
	if not recipe then
		return
	end
	local tracked = SR.Recipes:IsTracked(recipe)
	local favorite = SR.Recipes:IsFavorite(recipe)
	local options = {
		{ label = tracked and L["Stop tracking"] or L["Track in objectives"], action = "track" },
		{ label = favorite and L["Remove from favorites"] or L["Add to favorites"], action = "favorite" },
		{ label = L["Add to a buy list..."], action = "buylist" },
	}
	-- Only when some reagent can be crafted (see Recipes:Breakdown).
	local _, steps = SR.Recipes:Breakdown(recipe, 1, true)
	if #steps > 0 then
		options[#options + 1] = { label = L["Add raw materials to a buy list..."], action = "buylist", raw = true }
	end
	options[#options + 1] = { label = L["Where to get it"], action = "sources" }
	SR.Game.ShowMenu(owner, recipe.name or L["Recipe"], options, function(option)
		if option.action == "track" then
			SR.Recipes:SetTracked(recipe, not tracked)
		elseif option.action == "favorite" then
			SR.Recipes:SetFavorite(recipe, not favorite)
		elseif option.action == "buylist" then
			ShowBuyListMenu(recipe, owner, crafts, option.raw)
		else
			SR.SourcePopup:Show(recipe)
		end
	end)
end

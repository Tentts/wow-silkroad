--[[ SilkRoad - UI/RecipeMenu.lua
	The right-click menu for a recipe, shared by the Recipes and Leveling
	Guide pages: track it in the game's objective tracker (its reagents are
	listed under the quests), or see where to get it.
]]
local _, SR = ...
local L = SR.L

function SR.UI:ShowRecipeMenu(recipe, owner)
	if not recipe then
		return
	end
	local tracked = SR.Recipes:IsTracked(recipe)
	local options = {
		{ label = tracked and L["Stop tracking"] or L["Track in objectives"], action = "track" },
		{ label = L["Where to get it"], action = "sources" },
	}
	SR.Game.ShowMenu(owner, recipe.name or L["Recipe"], options, function(option)
		if option.action == "track" then
			SR.Recipes:SetTracked(recipe, not tracked)
		else
			SR.SourcePopup:Show(recipe)
		end
	end)
end

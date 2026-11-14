--[[ SilkRoad - Modules/Recipes.lua
	Every indexed recipe with what its materials cost and what the result
	sells for, so profitable crafts stand out.

	Material cost uses the cheapest known source per reagent (vendor or
	auction house). Sale values are per craft: auction price after the cut,
	and vendor sell price, both times the average number of items made.
	Profit = best sale value - material cost, and is only shown when every
	reagent has a price.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local ALL = "__all"

local Page = SR.UI:RegisterPage({
	id = "recipes",
	order = 20,
	title = L["Recipes"],
	description = L.RECIPES_DESC,
	icon = "Interface\\Icons\\INV_Scroll_03",
})

local function EvaluateRecipe(recipe)
	local cost, complete = 0, true
	for _, reagent in ipairs(recipe.reagents or {}) do
		local unitCost = SR.Prices:GetAcquireCost(reagent.itemID)
		if unitCost then
			cost = cost + unitCost * (reagent.quantity or 1)
		else
			complete = false
		end
	end

	local itemID = recipe.outputItemID
	local quantityMin = recipe.quantityMin or 1
	local quantity = (quantityMin + (recipe.quantityMax or quantityMin)) / 2

	local auctionUnit = itemID and SR.Prices:GetNetAuctionPrice(itemID)
	local vendorUnit = itemID and SR.Prices:GetVendorSellPrice(itemID)
	local auctionValue = auctionUnit and auctionUnit * quantity or nil
	local vendorValue = (vendorUnit and vendorUnit > 0) and vendorUnit * quantity or nil

	local profit
	if complete and (auctionValue or vendorValue) then
		profit = math.max(auctionValue or 0, vendorValue or 0) - cost
	end

	local name = recipe.name or (itemID and C_Item.GetItemNameByID(itemID)) or L["Recipe #%d"]:format(recipe.recipeID or 0)
	return {
		recipeID = recipe.recipeID,
		itemID = itemID,
		name = name,
		searchText = name:lower(),
		icon = recipe.icon or (itemID and C_Item.GetItemIconByID(itemID)),
		quality = itemID and C_Item.GetItemQualityByID(itemID) or nil,
		profession = recipe.profession or UNKNOWN,
		cost = complete and cost or nil,
		auctionValue = auctionValue,
		vendorValue = vendorValue,
		profit = profit,
	}
end

function Page:OnCreate(frame)
	self.profession = ALL
	self.search = ""

	self.ProfessionDropdown = Widgets.CreateDropdown(frame, 190, function()
		return self:GetProfessionOptions()
	end, function()
		return self.profession
	end, function(value)
		self.profession = value
		self.Table:Refresh()
	end)
	self.ProfessionDropdown:SetPoint("TOPLEFT", 0, 0)

	self.Search = Widgets.CreateSearchBox(frame, 220, function(text)
		self.search = text:lower()
		self.Table:Refresh()
	end)
	self.Search:SetPoint("LEFT", self.ProfessionDropdown, "RIGHT", 16, 0)

	self.Count = Widgets.CreateLabel(frame, "", "GameFontDisableSmall", "RIGHT")
	self.Count:SetPoint("RIGHT", frame, "TOPRIGHT", -4, -12)

	self.Table = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "name", title = L["Recipe"], kind = "item" },
			{ key = "profession", title = L["Profession"], width = 110 },
			{ key = "cost", title = L["Materials"], width = 110, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "auctionValue", title = L["Auction (net)"], width = 110, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "vendorValue", title = L["Vendor"], width = 100, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "profit", title = L["Profit"], width = 115, kind = "profit", align = "RIGHT", sortDescFirst = true },
		},
		sortKey = "profit",
		sortDesc = true,
		emptyIcon = "Interface\\Icons\\INV_Scroll_03",
		emptyTitle = L.RECIPES_EMPTY_TITLE,
		emptyBody = L.RECIPES_EMPTY_BODY,
		onRefresh = function(_, shown, total)
			self.Count:SetText(L["%d of %d recipes"]:format(shown, total))
		end,
	})
	self.Table:SetPoint("TOPLEFT", self.ProfessionDropdown, "BOTTOMLEFT", 0, -10)
	self.Table:SetPoint("BOTTOMRIGHT")
	self.Table:SetFilter(function(row)
		return self:MatchesFilter(row)
	end)
end

function Page:MatchesFilter(row)
	if self.profession ~= ALL and row.profession ~= self.profession then
		return false
	end
	if self.search ~= "" and not row.searchText:find(self.search, 1, true) then
		return false
	end
	return true
end

-- "All professions", then every profession that has indexed recipes or that
-- this character knows.
function Page:GetProfessionOptions()
	local names, seen = {}, {}
	local function add(name)
		if name and not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	for _, profession in ipairs(Util.GetPlayerProfessions()) do
		add(profession.name)
	end
	for _, recipe in pairs(SR.DB.global.recipes) do
		add(recipe.profession)
	end
	table.sort(names)

	local options = { { value = ALL, label = L["All professions"] } }
	for _, name in ipairs(names) do
		options[#options + 1] = { value = name, label = name }
	end
	return options
end

function Page:Refresh()
	local rows = {}
	for _, recipe in pairs(SR.DB.global.recipes) do
		rows[#rows + 1] = EvaluateRecipe(recipe)
	end
	self.Table:SetRows(rows)
	self.ProfessionDropdown:Refresh()
end

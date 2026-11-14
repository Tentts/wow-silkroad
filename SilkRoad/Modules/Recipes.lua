--[[ SilkRoad - Modules/Recipes.lua
	Every recipe of the selected profession, learned or not, with where it's
	obtained, what its materials cost and what the result sells for.

	Columns: recipe, skill level (coloured like the profession window for
	this character), obtained at (click for locations), material cost
	(cheapest of vendor and auction house per reagent), auction price,
	vendor price and profit (best sale after the auction cut, minus cost).
	Hovering a row breaks the cost down per reagent.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local Page = SR.UI:RegisterPage({
	id = "recipes",
	order = 20,
	title = L["Recipes"],
	description = L.RECIPES_DESC,
	icon = "Interface\\Icons\\INV_Scroll_03",
})

local COLORS = {
	red = "ffff4040", orange = "ffff8040", yellow = "ffffff00",
	green = "ff40c040", gray = "ff808080", link = "ff66bbff",
}
local SOURCE_TAGS = { vendor = L["vendor"], auction = L["AH"] }

-- Skill-up colour of a recipe for a character at `rank`, like the game shows it.
local function DifficultyColor(recipe, rank)
	if not rank then
		return nil
	elseif recipe.learn and rank < recipe.learn then
		return COLORS.red
	elseif not recipe.yellow or not recipe.gray then
		return nil
	elseif rank < recipe.yellow then
		return COLORS.orange
	elseif rank < (recipe.yellow + recipe.gray) / 2 then
		return COLORS.yellow
	elseif rank < recipe.gray then
		return COLORS.green
	end
	return COLORS.gray
end

local function RecipeIcon(recipe, profession)
	local static = SR.StaticData and SR.StaticData.items
	local item = recipe.product or recipe.recipeItem
	return recipe.icon or (item and static and static[item] and static[item][3])
		or (item and C_Item.GetItemIconByID(item)) or (profession and profession.icon)
end

function Page:BuildRow(recipe, profession)
	local evaluation = SR.Recipes:Evaluate(recipe)
	local known = SR.Recipes:IsKnown(recipe)
	local display = recipe.product and Util.GetItemDisplay(recipe.product)
	local name = recipe.name or (display and display.name) or "?"
	local levelText = recipe.learn and ((recipe.learnExact and "" or "~") .. recipe.learn) or "-"
	local color = DifficultyColor(recipe, profession.learned and profession.rank)
	return {
		recipe = recipe, evaluation = evaluation, known = known,
		itemID = recipe.product, icon = RecipeIcon(recipe, profession),
		quality = display and display.quality, name = name, searchText = name:lower(),
		learn = recipe.learn or 0,
		levelText = color and Util.ColorText(levelText, color) or levelText,
		source = SR.Sources:Summarize(recipe),
		cost = evaluation.cost, auctionPrice = evaluation.auctionPrice,
		vendorPrice = evaluation.vendorPrice, profit = evaluation.profit,
	}
end

local function FormatName(_, row)
	local text = row.name
	if row.known == false then
		return Util.ColorText(text, COLORS.gray)
	end
	return Util.ColorByQuality(text, row.quality)
end

local function ShowRecipeTooltip(rowFrame, row)
	local tooltip = GameTooltip
	tooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
	if row.itemID then
		tooltip:SetItemByID(row.itemID)
	else
		tooltip:SetText(row.name, 1, 1, 1)
	end
	local evaluation = row.evaluation
	tooltip:AddLine(" ")
	tooltip:AddLine(L["Materials"], 1, 0.82, 0)
	for _, reagent in ipairs(evaluation.reagents) do
		local reagentName = Util.GetItemDisplay(reagent.itemID).name
		local price = reagent.unitCost and (Util.FormatMoney(reagent.unitCost * reagent.count)
			.. " |cff808080" .. (SOURCE_TAGS[reagent.source] or "") .. "|r") or Util.ColorText(L["no price"], COLORS.red)
		tooltip:AddDoubleLine(("%d x %s"):format(reagent.count, reagentName), price, 1, 1, 1, 1, 1, 1)
	end
	tooltip:AddDoubleLine(L["Total"], evaluation.cost and Util.FormatMoney(evaluation.cost)
		or (Util.FormatMoney(evaluation.partialCost) .. " +?"), 1, 0.82, 0, 1, 1, 1)
	if evaluation.auctionNet then
		tooltip:AddDoubleLine(L["Auction house, after the %d%% cut"]:format(SR:GetSetting("auctionCutPercent")),
			Util.FormatMoney(evaluation.auctionNet), 1, 0.82, 0, 1, 1, 1)
	end
	if row.known == false then
		tooltip:AddLine(" ")
		tooltip:AddLine(L["You haven't learned this recipe."], 1, 0.25, 0.25)
	end
	tooltip:Show()
end

local function ShowSourceTooltip(row, tooltip)
	tooltip:SetText(row.source, 1, 1, 1)
	local sources = SR.Sources:GetRecipeSources(row.recipe)
	local kind = sources[1].kind
	if kind == "trainer" then
		tooltip:AddLine(L.SOURCE_TRAINER_HINT, 1, 0.82, 0, true)
	elseif kind == "auto" then
		tooltip:AddLine(L.SOURCE_AUTO_HINT, 1, 0.82, 0, true)
	else
		tooltip:AddLine(L["Click to see every source and set waypoints."], 0.4, 0.75, 1, true)
		if not SR.Sources:HasQuestie() then
			tooltip:AddLine(L.NO_QUESTIE_HINT, 1, 0.82, 0, true)
		end
	end
end

function Page:OnCreate(frame)
	local settings = SR.DB.settings.recipes
	self.search = ""

	self.ProfessionDropdown = Widgets.CreateDropdown(frame, 210, function()
		return self:GetProfessionOptions()
	end, function()
		return self.skillLine
	end, function(value)
		self.skillLine = value
		settings.profession = value
		self:Refresh()
	end)
	self.ProfessionDropdown:SetPoint("TOPLEFT", 0, 0)

	self.Search = Widgets.CreateSearchBox(frame, 200, function(text)
		self.search = text:lower()
		self.Table:Refresh()
	end)
	self.Search:SetPoint("LEFT", self.ProfessionDropdown, "RIGHT", 16, 0)

	self.KnownOnly = Widgets.CreateCheckbox(frame, L["Known only"], L.KNOWN_ONLY_TOOLTIP,
		function()
			return settings.knownOnly
		end,
		function(checked)
			settings.knownOnly = checked
			self.Table:Refresh()
		end)
	self.KnownOnly:SetPoint("LEFT", self.Search, "RIGHT", 12, 0)
	-- Keep the tooltip working while disabled, so it can say why.
	self.KnownOnly:SetMotionScriptsWhileDisabled(true)

	self.Count = Widgets.CreateLabel(frame, "", "GameFontDisableSmall", "RIGHT")
	self.Count:SetPoint("RIGHT", frame, "TOPRIGHT", -4, -12)

	-- One line about the profession: not learned / not read yet / skill and known count.
	self.Status = Widgets.CreateLabel(frame, "", "GameFontHighlight")
	self.Status:SetPoint("TOPLEFT", self.ProfessionDropdown, "BOTTOMLEFT", 2, -8)

	self.Table = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "name", title = L["Recipe"], kind = "item", format = FormatName },
			{ key = "learn", title = L["Level"], width = 52, align = "RIGHT", format = function(_, row) return row.levelText end },
			{
				key = "source", title = L["Obtained at"], width = 175,
				format = function(value) return Util.ColorText(value, COLORS.link) end,
				onClick = function(row) SR.SourcePopup:Show(row.recipe) end,
				tooltip = ShowSourceTooltip,
			},
			{ key = "cost", title = L["Cost"], width = 100, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "auctionPrice", title = L["AH price"], width = 100, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "vendorPrice", title = L["Vendor price"], width = 92, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "profit", title = L["Profit"], width = 108, kind = "profit", align = "RIGHT", sortDescFirst = true },
		},
		sortKey = "profit",
		sortDesc = true,
		emptyIcon = "Interface\\Icons\\INV_Scroll_03",
		emptyTitle = L.RECIPES_EMPTY_TITLE,
		emptyBody = L.RECIPES_EMPTY_BODY,
		onRowEnter = ShowRecipeTooltip,
		onRefresh = function(_, shown, total)
			self.Count:SetText(L["%d of %d recipes"]:format(shown, total))
		end,
	})
	self.Table:SetPoint("TOPLEFT", self.ProfessionDropdown, "BOTTOMLEFT", 0, -30)
	self.Table:SetPoint("BOTTOMRIGHT")
	self.Table:SetFilter(function(row)
		return self:MatchesFilter(row)
	end)
end

function Page:MatchesFilter(row)
	if SR.DB.settings.recipes.knownOnly and self.KnownOnly:IsEnabled() and row.known == false then
		return false
	end
	if self.search ~= "" and not row.searchText:find(self.search, 1, true) then
		return false
	end
	return true
end

function Page:GetProfessionOptions()
	local options = {}
	for _, profession in ipairs(SR.Recipes:GetProfessions()) do
		local label = profession.name
		if profession.learned then
			label = ("%s |cff808080(%d/%d)|r"):format(label, profession.rank or 0, profession.maxRank or 0)
		else
			label = label .. " " .. Util.ColorText(L["(not learned)"], COLORS.gray)
		end
		options[#options + 1] = { value = profession.id, label = label }
	end
	return options
end

-- The profession to show: the last one picked, else this character's first.
function Page:CurrentProfession()
	local professions = SR.Recipes:GetProfessions()
	local wanted = self.skillLine or SR.DB.settings.recipes.profession
	local firstLearned
	for _, profession in ipairs(professions) do
		if profession.id == wanted then
			return profession
		end
		firstLearned = firstLearned or (profession.learned and profession)
	end
	return firstLearned or professions[1]
end

function Page:UpdateStatus(profession, knownCount, total)
	if not profession.learned then
		self.Status:SetText(Util.ColorText(L["You don't have this profession."], COLORS.red))
	elseif not SR.Recipes:HasRead(profession.id) then
		self.Status:SetText(Util.ColorText(L["Open your %s window once so SilkRoad can mark the recipes you know."]:format(profession.name), COLORS.gray))
	else
		self.Status:SetText(L["%s %d/%d: you know %d of %d recipes."]:format(
			profession.name, profession.rank or 0, profession.maxRank or 0, knownCount, total))
	end
	local canFilter = profession.learned and SR.Recipes:HasRead(profession.id)
	self.KnownOnly:SetEnabled(canFilter)
	local shade = canFilter and 1 or 0.5
	self.KnownOnly.Text:SetTextColor(shade, shade, shade)
end

function Page:Refresh()
	local profession = self:CurrentProfession()
	if not profession then
		self.Table:SetRows({})
		return
	end
	self.skillLine = profession.id

	local rows, knownCount = {}, 0
	for _, recipe in ipairs(SR.Recipes:GetRecipes(profession.id)) do
		local row = self:BuildRow(recipe, profession)
		if row.known then
			knownCount = knownCount + 1
		end
		rows[#rows + 1] = row
	end
	self:UpdateStatus(profession, knownCount, #rows)
	self.Table:SetRows(rows)
	self.KnownOnly:Refresh()
	self.ProfessionDropdown:Refresh()
end

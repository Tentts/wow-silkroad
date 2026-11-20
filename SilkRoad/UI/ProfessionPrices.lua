--[[ SilkRoad - UI/ProfessionPrices.lua
	SilkRoad's numbers inside Blizzard's professions window, under the
	reagent list of the recipe shown:

	  SilkRoad
	  Materials (cheapest)         1g 20s
	  Raw cost (every step)        95s        only when a reagent can be crafted
	  Auction house, after cut     2g 10s
	  Auction profit               +90s
	  Vendor pays                  45s
	  Vendor profit                -75s

	Prices per craft (times the quantity made). Turned on and off in
	Settings > General.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local ProfessionPrices = SR:NewComponent("ProfessionPrices")

local PANEL_WIDTH = 300
local LINE_HEIGHT = 14
local LABEL_R, LABEL_G, LABEL_B = 0.9, 0.76, 0.36 -- SilkRoad gold
local LINES = { "materials", "raw", "auction", "auctionProfit", "vendor", "vendorProfit" }

function ProfessionPrices:OnEnable()
	SR.Game.HookRecipeView(function(form, recipeID)
		self:Show(form, recipeID)
	end)
	SR:RegisterCallback("PRICES_UPDATED", function()
		self:Update()
	end)
	SR:RegisterCallback("SETTING_CHANGED", function(_, path)
		if path == "professionPrices" then
			self:Update()
		end
	end)
end

function ProfessionPrices:CreatePanel(form)
	local panel = CreateFrame("Frame", nil, form)
	panel:SetSize(PANEL_WIDTH, LINE_HEIGHT * (#LINES + 1) + 4)

	panel.Title = Widgets.CreateLabel(panel, SR.title, "GameFontNormalSmall")
	panel.Title:SetPoint("TOPLEFT", 0, 0)
	panel.Title:SetTextColor(LABEL_R, LABEL_G, LABEL_B)

	panel.lines = {}
	for index, key in ipairs(LINES) do
		local line = {}
		line.Label = Widgets.CreateLabel(panel, "", "GameFontHighlightSmall")
		line.Label:SetPoint("TOPLEFT", 0, -index * LINE_HEIGHT - 2)
		line.Value = Widgets.CreateLabel(panel, "", "GameFontHighlightSmall", "RIGHT")
		line.Value:SetPoint("TOPRIGHT", 0, -index * LINE_HEIGHT - 2)
		panel.lines[key] = line
	end
	panel.lines.materials.Label:SetText(L["Materials (cheapest)"])
	panel.lines.raw.Label:SetText(L["Raw cost (every step)"])
	panel.lines.auction.Label:SetText(L["Auction house, after cut"])
	panel.lines.auctionProfit.Label:SetText(L["Auction profit"])
	panel.lines.vendor.Label:SetText(L["Vendor pays"])
	panel.lines.vendorProfit.Label:SetText(L["Vendor profit"])
	return panel
end

-- Called whenever the professions window shows a recipe (nil: none).
function ProfessionPrices:Show(form, recipeID)
	self.form = form
	self.recipeID = recipeID
	self.panel = self.panel or self:CreatePanel(form)
	self:Update()
end

local function Money(copper)
	return copper and Util.FormatMoney(copper) or Util.ColorText("?", "ff808080")
end

function ProfessionPrices:Update()
	local panel, form = self.panel, self.form
	if not panel then
		return
	end
	local recipe = self.recipeID and SR.Recipes:GetRecipe(self.recipeID)
	if not recipe or not SR:GetSetting("professionPrices") then
		panel:Hide()
		return
	end
	local anchor = SR.Game.GetRecipeViewAnchor(form)
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)

	local evaluation = SR.Recipes:Evaluate(recipe)
	local lines = panel.lines
	lines.materials.Value:SetText(evaluation.cost and Util.FormatMoney(evaluation.cost)
		or (Util.FormatMoney(evaluation.partialCost) .. " +?"))

	-- Lines shown, top to bottom, without gaps.
	local shown = { "materials" }
	if evaluation.steps then
		lines.raw.Value:SetText(Money(evaluation.rawCost))
		shown[#shown + 1] = "raw"
	end
	if recipe.product then
		lines.auction.Value:SetText(evaluation.auctionNet and Util.FormatMoney(evaluation.auctionNet)
			or Util.ColorText(L["no data"], "ff808080"))
		lines.auctionProfit.Value:SetText(Util.FormatProfit(evaluation.auctionProfit))
		lines.vendor.Value:SetText(Money(evaluation.vendorPrice))
		lines.vendorProfit.Value:SetText(Util.FormatProfit(evaluation.vendorProfit))
		for _, key in ipairs({ "auction", "auctionProfit", "vendor", "vendorProfit" }) do
			shown[#shown + 1] = key
		end
	end
	for _, line in pairs(lines) do
		line.Label:Hide()
		line.Value:Hide()
	end
	for index, key in ipairs(shown) do
		local line = lines[key]
		line.Label:ClearAllPoints()
		line.Label:SetPoint("TOPLEFT", 0, -index * LINE_HEIGHT - 2)
		line.Value:ClearAllPoints()
		line.Value:SetPoint("TOPRIGHT", 0, -index * LINE_HEIGHT - 2)
		line.Label:Show()
		line.Value:Show()
	end
	panel:SetHeight(LINE_HEIGHT * (#shown + 1) + 4)
	panel:Show()
end

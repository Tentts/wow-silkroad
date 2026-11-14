--[[ SilkRoad - Modules/Overview.lua
	Landing page: headline numbers, the character's professions, which price
	sources are active, and a short guide.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local MAX_PROFESSION_LINES = 6
local CARD_GAP = 10
local COLUMN_GAP = 24

local Page = SR.UI:RegisterPage({
	id = "overview",
	order = 10,
	title = L["Overview"],
	description = L.OVERVIEW_DESC,
	icon = "Interface\\Icons\\INV_Misc_Map_01",
})

local function CreateLine(parent)
	local line = CreateFrame("Frame", nil, parent)
	line:SetHeight(24)
	line.Icon = line:CreateTexture(nil, "ARTWORK")
	line.Icon:SetSize(20, 20)
	line.Icon:SetPoint("LEFT")
	line.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	line.Label = Widgets.CreateLabel(line, "", "GameFontHighlight")
	line.Label:SetPoint("LEFT", line.Icon, "RIGHT", 8, 0)
	line.Value = Widgets.CreateLabel(line, "", "GameFontHighlightSmall", "RIGHT")
	line.Value:SetPoint("RIGHT")
	return line
end

function Page:OnCreate(frame)
	-- Headline numbers
	self.cards = {
		recipes = Widgets.CreateStatCard(frame, L["Recipes indexed"]),
		auction = Widgets.CreateStatCard(frame, L["Auction prices"]),
		vendor = Widgets.CreateStatCard(frame, L["Vendor prices"]),
		scan = Widgets.CreateStatCard(frame, L["Last auction scan"]),
	}
	self.cardOrder = { self.cards.recipes, self.cards.auction, self.cards.vendor, self.cards.scan }

	-- Two columns under the cards: professions | price sources
	local columnHeight = MAX_PROFESSION_LINES * 26 + 26
	local left = CreateFrame("Frame", nil, frame)
	left:SetPoint("TOPLEFT", self.cardOrder[1], "BOTTOMLEFT", 0, -20)
	left:SetHeight(columnHeight)
	local right = CreateFrame("Frame", nil, frame)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", COLUMN_GAP, 0)
	right:SetPoint("TOPRIGHT", self.cardOrder[#self.cardOrder], "BOTTOMRIGHT", 0, -20)
	right:SetHeight(columnHeight)
	self.left, self.right = left, right

	local professionsHeader = Widgets.CreateHeader(left, L["Your professions"])
	professionsHeader:SetPoint("TOPLEFT")
	professionsHeader:SetPoint("TOPRIGHT")

	self.professionLines = {}
	for i = 1, MAX_PROFESSION_LINES do
		local line = CreateLine(left)
		line:SetPoint("TOPLEFT", professionsHeader, "BOTTOMLEFT", 0, -6 - (i - 1) * 26)
		line:SetPoint("TOPRIGHT", professionsHeader, "BOTTOMRIGHT", 0, -6 - (i - 1) * 26)
		self.professionLines[i] = line
	end
	self.noProfessions = Widgets.CreateLabel(left, L["This character hasn't learned a profession yet."], "GameFontDisable")
	self.noProfessions:SetPoint("TOPLEFT", professionsHeader, "BOTTOMLEFT", 0, -10)

	local sourcesHeader = Widgets.CreateHeader(right, L["Price sources"])
	sourcesHeader:SetPoint("TOPLEFT")
	sourcesHeader:SetPoint("TOPRIGHT")

	self.sourceLines = {}
	for i, provider in ipairs(SR.Prices:GetProviders()) do
		local line = CreateLine(right)
		line:SetPoint("TOPLEFT", sourcesHeader, "BOTTOMLEFT", 0, -6 - (i - 1) * 26)
		line:SetPoint("TOPRIGHT", sourcesHeader, "BOTTOMRIGHT", 0, -6 - (i - 1) * 26)
		line.provider = provider
		self.sourceLines[i] = line
	end

	-- Guide
	local guideHeader = Widgets.CreateHeader(frame, L["Getting started"])
	guideHeader:SetPoint("TOPLEFT", left, "BOTTOMLEFT", 0, -12)
	guideHeader:SetPoint("TOPRIGHT", right, "BOTTOMRIGHT", 0, -12)

	local guide = Widgets.CreateLabel(frame, L.OVERVIEW_GETTING_STARTED, "GameFontHighlight")
	guide:SetPoint("TOPLEFT", guideHeader, "BOTTOMLEFT", 0, -8)
	guide:SetPoint("TOPRIGHT", guideHeader, "BOTTOMRIGHT", 0, -8)
	guide:SetJustifyV("TOP")
	guide:SetSpacing(3)

	frame:SetScript("OnSizeChanged", function(_, width)
		self:Layout(width)
	end)
end

function Page:Layout(width)
	if not width or width <= 0 then
		return
	end
	local cardWidth = (width - CARD_GAP * (#self.cardOrder - 1)) / #self.cardOrder
	for i, card in ipairs(self.cardOrder) do
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", self.frame, "TOPLEFT", (i - 1) * (cardWidth + CARD_GAP), 0)
		card:SetWidth(cardWidth)
	end
	self.left:SetWidth((width - COLUMN_GAP) / 2)
end

function Page:Refresh()
	self:Layout(self.frame:GetWidth())

	local stats = SR.Prices:GetStats()
	local recipeCount = Util.CountKeys(SR.DB.global.recipes)
	local knownCount = Util.CountKeys(SR.DB.char.knownRecipes)

	self.cards.recipes:SetData(recipeCount, L["%d known by this character"]:format(knownCount))
	self.cards.auction:SetData(stats.auctionItems, L["From SilkRoad scans on %s"]:format(stats.marketKey))
	self.cards.vendor:SetData(stats.vendorItems, L["Recorded from merchants"])
	self.cards.scan:SetData(Util.TimeAgo(stats.lastScan), stats.marketKey)

	local professions = Util.GetPlayerProfessions()
	for i, line in ipairs(self.professionLines) do
		local profession = professions[i]
		if profession then
			line.Icon:SetTexture(profession.icon)
			line.Label:SetText(profession.name)
			line.Value:SetText(("%d / %d"):format(profession.rank or 0, profession.maxRank or 0))
			line:Show()
		else
			line:Hide()
		end
	end
	self.noProfessions:SetShown(#professions == 0)

	for _, line in ipairs(self.sourceLines) do
		local provider = line.provider
		local available = provider:IsAvailable()
		line.Icon:SetTexture(provider.id == "auctionator" and "Interface\\Icons\\INV_Misc_Coin_01" or SR.icon)
		line.Icon:SetDesaturated(not available)
		line.Label:SetText(provider.label)
		line.Label:SetTextColor(available and 1 or 0.5, available and 1 or 0.5, available and 1 or 0.5)
		line.Value:SetText(provider.GetStatus and provider:GetStatus() or "")
	end
end

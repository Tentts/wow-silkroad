--[[ SilkRoad - UI/AuctionHouseBuyLists.lua
	The "Buy Lists" tab of the auction house window: pick a list, then buy
	what's left of it item by item. Each purchase takes two clicks (Buy,
	then Confirm at the price the server quotes); the game doesn't let
	addons buy without a click. Lists are managed in SilkRoad's Buy Lists
	page.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local Tab = SR:NewComponent("BuyListsTab")

local TAB_ID = "SilkRoadBuyLists"
local CARD_WIDTH = 300

function Tab:OnEnable()
	SR:RegisterCallback("BUYLISTS_UPDATED", function()
		self:Refresh()
	end)
	SR:RegisterCallback("AUCTION_BUYER_UPDATED", function()
		self:UpdateCard()
	end)
	SR:RegisterCallback("PRICES_UPDATED", function()
		self:Refresh()
	end)
	local bagsChanged = Util.Debounce(0.5, function()
		self:Refresh()
	end)
	for _, event in ipairs(SR.Game.events.bagsChanged) do
		SR:RegisterEvent(event, bagsChanged)
	end
end

-- Called by AuctionHouseTab once Blizzard's auction house UI exists.
function Tab:Create(LibAHTab)
	if self.panel or LibAHTab:DoesIDExist(TAB_ID) then
		return
	end
	local panel = CreateFrame("Frame", "SilkRoadBuyListsPanel", AuctionHouseFrame)
	panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 12, -64)
	panel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -12, 32)
	self.panel = panel

	-- Top row: which list, its progress, and a way to manage lists.
	self.ListDropdown = Widgets.CreateDropdown(panel, 220, function()
		local options = {}
		for _, list in ipairs(SR.BuyLists:GetLists()) do
			options[#options + 1] = { value = list.id, label = list.name }
		end
		return options
	end, function()
		return SR.DB.settings.buyLists.selected
	end, function(id)
		SR.DB.settings.buyLists.selected = id
		self.itemID = nil
		SR.AuctionBuyer:Reset()
		self:Refresh()
	end)
	self.ListDropdown:SetPoint("TOPLEFT", 0, 0)

	local manage = Widgets.CreateButton(panel, L["Manage lists"], 130, function()
		SR.UI:OpenPage("buylists")
	end)
	manage:SetPoint("TOPRIGHT", 0, 0)

	self.Summary = Widgets.CreateLabel(panel, "", "GameFontHighlightSmall")
	self.Summary:SetPoint("LEFT", self.ListDropdown, "RIGHT", 14, 0)
	self.Summary:SetPoint("RIGHT", manage, "LEFT", -10, 0)

	self:CreateCard(panel)

	self.Items = Widgets.CreateDataTable(panel, {
		columns = {
			{ key = "name", title = L["Item"], kind = "item" },
			{
				key = "remaining", title = L["Left"], width = 56, align = "RIGHT", sortDescFirst = true,
				format = function(value)
					return value == 0 and Util.ColorText(L["done"], "ff55ff55") or tostring(value)
				end,
			},
			{ key = "unitPrice", title = L["Each (AH)"], width = 96, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "cost", title = L["Total"], width = 104, kind = "money", align = "RIGHT", sortDescFirst = true },
		},
		sortKey = "name",
		emptyIcon = "Interface\\Icons\\INV_Misc_Note_01",
		emptyTitle = L["No buy lists"],
		emptyBody = L.AH_BUYLISTS_EMPTY_BODY,
		onRowClick = function(row)
			self:SelectItem(row.itemID)
		end,
	})
	self.Items:SetPoint("TOPLEFT", self.ListDropdown, "BOTTOMLEFT", 0, -12)
	self.Items:SetPoint("BOTTOMRIGHT", self.Card, "BOTTOMLEFT", -12, 0)

	panel:SetScript("OnShow", function()
		self:Refresh()
	end)

	LibAHTab:CreateTab(TAB_ID, panel, L["Buy Lists"], L["Buy Lists"])
end

function Tab:CreateCard(panel)
	local card = Widgets.CreatePanel(panel, 0.35)
	card:SetPoint("TOPRIGHT", 0, -34)
	card:SetPoint("BOTTOMRIGHT")
	card:SetWidth(CARD_WIDTH)
	self.Card = card

	card.Icon = card:CreateTexture(nil, "ARTWORK")
	card.Icon:SetSize(36, 36)
	card.Icon:SetPoint("TOPLEFT", 12, -12)

	card.Name = Widgets.CreateLabel(card, "", "GameFontNormalLarge")
	card.Name:SetPoint("TOPLEFT", card.Icon, "TOPRIGHT", 10, -2)
	card.Name:SetWidth(CARD_WIDTH - 70)
	card.Name:SetWordWrap(false)

	card.Need = Widgets.CreateLabel(card, "", "GameFontHighlightSmall")
	card.Need:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -4)

	card.Market = Widgets.CreateLabel(card, "", "GameFontHighlight")
	card.Market:SetPoint("TOPLEFT", card.Icon, "BOTTOMLEFT", 0, -14)
	card.Market:SetWidth(CARD_WIDTH - 24)
	card.Market:SetSpacing(3)

	local quantityLabel = Widgets.CreateLabel(card, L["Quantity"], "GameFontNormal")
	quantityLabel:SetPoint("TOPLEFT", card.Market, "BOTTOMLEFT", 0, -16)

	card.Quantity = Widgets.CreateInput(card, 70, function()
		self:UpdateCard()
	end)
	card.Quantity:SetNumeric(true)
	card.Quantity:SetPoint("LEFT", quantityLabel, "RIGHT", 12, 0)
	card.Quantity:HookScript("OnTextChanged", function()
		self:UpdateCard()
	end)

	card.Cost = Widgets.CreateLabel(card, "", "GameFontHighlightSmall")
	card.Cost:SetPoint("TOPLEFT", quantityLabel, "BOTTOMLEFT", 0, -12)
	card.Cost:SetWidth(CARD_WIDTH - 24)

	card.BuyButton = Widgets.CreateButton(card, L["Buy"], CARD_WIDTH - 24, function()
		self:OnBuyClicked()
	end)
	card.BuyButton:SetPoint("TOPLEFT", card.Cost, "BOTTOMLEFT", 0, -14)

	card.CancelButton = Widgets.CreateButton(card, L["Cancel"], (CARD_WIDTH - 30) / 2, function()
		SR.AuctionBuyer:Cancel()
	end)
	card.CancelButton:SetPoint("TOPLEFT", card.BuyButton, "BOTTOMLEFT", 0, -6)

	card.NextButton = Widgets.CreateButton(card, L["Next item"], (CARD_WIDTH - 30) / 2, function()
		self:SelectNext()
	end)
	card.NextButton:SetPoint("TOPRIGHT", card.BuyButton, "BOTTOMRIGHT", 0, -6)

	card.Message = Widgets.CreateLabel(card, "", "GameFontDisableSmall")
	card.Message:SetPoint("TOPLEFT", card.CancelButton, "BOTTOMLEFT", 0, -12)
	card.Message:SetWidth(CARD_WIDTH - 24)
	card.Message:SetSpacing(2)

	card.Hint = Widgets.CreateLabel(card, L.AH_BUYLISTS_HINT, "GameFontDisable", "CENTER")
	card.Hint:SetPoint("CENTER")
	card.Hint:SetWidth(CARD_WIDTH - 40)
end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------

function Tab:CurrentList()
	local settings = SR.DB.settings.buyLists
	local list = SR.BuyLists:GetList(settings.selected)
	if not list then
		list = SR.BuyLists:GetLists()[1]
		settings.selected = list and list.id or nil
	end
	return list
end

function Tab:EntryFor(itemID)
	for _, entry in ipairs(self.entries or {}) do
		if entry.itemID == itemID then
			return entry
		end
	end
end

function Tab:SelectItem(itemID)
	self.itemID = itemID
	local entry = self:EntryFor(itemID)
	self.Card.Quantity:SetText(tostring(entry and math.max(entry.remaining, 1) or 1))
	SR.AuctionBuyer:Select(itemID)
	self:Refresh()
end

-- The next item still to buy, after the selected one (in list order).
function Tab:SelectNext()
	local entries = self.entries or {}
	local start = 0
	for index, entry in ipairs(entries) do
		if entry.itemID == self.itemID then
			start = index
		end
	end
	for offset = 1, #entries do
		local entry = entries[(start + offset - 1) % #entries + 1]
		if entry.remaining > 0 and entry.itemID ~= self.itemID then
			self:SelectItem(entry.itemID)
			return
		end
	end
end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------

function Tab:GetQuantity()
	return math.max(0, math.floor(tonumber(self.Card.Quantity:GetText()) or 0))
end

function Tab:OnBuyClicked()
	local buyer = SR.AuctionBuyer
	if buyer.state == "confirm" then
		buyer:Confirm()
	elseif buyer.state == "ready" then
		buyer:Buy(self:GetQuantity())
	end
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

function Tab:Refresh()
	if not self.panel or not self.panel:IsVisible() then
		return
	end
	local list = self:CurrentList()
	local rows, totals = SR.BuyLists:BuildItemRows(list)
	self.entries = rows
	self.Summary:SetText(list and SR.BuyLists:DescribeTotals(totals) or "")
	self.Items:SetSelected(function(row) return row.itemID == self.itemID end)
	self.Items:SetRows(rows)
	self.ListDropdown:Refresh()
	if self.itemID and not self:EntryFor(self.itemID) then
		self.itemID = nil
		SR.AuctionBuyer:Reset()
	end
	self:UpdateCard()
end

local STATE_LABELS = {
	throttled = L["Waiting for the auction house..."],
	searching = L["Searching..."],
	quoting = L["Getting the price..."],
	buying = L["Buying..."],
}

function Tab:UpdateCard()
	local card = self.Card
	if not card or not self.panel:IsVisible() then
		return
	end
	local buyer = SR.AuctionBuyer
	local entry = self.itemID and self:EntryFor(self.itemID)
	local selected = entry ~= nil
	for _, region in ipairs({ card.Icon, card.Name, card.Need, card.Market, card.Quantity, card.Cost,
		card.BuyButton, card.CancelButton, card.NextButton, card.Message }) do
		region:SetShown(selected)
	end
	card.Hint:SetShown(not selected)
	if not selected then
		return
	end

	card.Icon:SetTexture(entry.icon)
	card.Name:SetText(Util.ColorByQuality(entry.name, entry.quality))
	if entry.remaining > 0 then
		card.Need:SetText(L["%d more to buy (you have %d of %d)"]:format(entry.remaining, entry.have, entry.quantity))
	else
		card.Need:SetText(Util.ColorText(L["Done: you have %d of %d"]:format(entry.have, entry.quantity), "ff55ff55"))
	end

	local quantity = self:GetQuantity()
	local state = buyer.state
	local hasResults = buyer.itemID == entry.itemID and (state == "ready" or state == "quoting" or state == "confirm" or state == "buying")
	if not hasResults then
		card.Market:SetText(STATE_LABELS[state] or STATE_LABELS.searching)
		card.Cost:SetText("")
	elseif #buyer.listings == 0 then
		card.Market:SetText(Util.ColorText(L["None for sale right now."], "ffff4040"))
		card.Cost:SetText("")
	else
		card.Market:SetText(L["%s for sale, from %s each"]:format(Util.FormatNumber(buyer:GetAvailable()),
			Util.FormatMoney(buyer.listings[1].unitPrice)))
		if buyer.commodity then
			local total, count = buyer:Estimate(quantity)
			local text = L["%d cost about %s"]:format(count, Util.FormatMoney(total))
			if count < quantity then
				text = text .. " " .. Util.ColorText(L["(only %d for sale)"]:format(count), "ffff8040")
			end
			card.Cost:SetText(quantity > 0 and text or "")
		else
			local listing = buyer.listings[1]
			card.Cost:SetText(L["Cheapest auction: %d for %s"]:format(listing.quantity, Util.FormatMoney(listing.buyout)))
		end
	end

	local button = card.BuyButton
	if state == "confirm" and buyer.quote then
		button:SetText(L["Confirm: %d for %s"]:format(buyer.quote.quantity, Util.FormatMoney(buyer.quote.total or 0)))
		button:SetEnabled(true)
	elseif state == "ready" and hasResults and #buyer.listings > 0 then
		if buyer.commodity then
			local _, count = buyer:Estimate(quantity)
			button:SetText(L["Buy %d"]:format(count))
			button:SetEnabled(count > 0)
		else
			button:SetText(L["Buy %d"]:format(buyer.listings[1].quantity))
			button:SetEnabled(true)
		end
	else
		button:SetText(STATE_LABELS[state] or L["Buy"])
		button:SetEnabled(false)
	end
	card.CancelButton:SetEnabled(state == "confirm" or state == "quoting")
	card.Message:SetText(buyer.message or "")
end

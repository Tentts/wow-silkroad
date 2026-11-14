--[[ SilkRoad - Modules/VendorFlips.lua
	Items a merchant sells for less than they fetch on the auction house
	(after the auction house cut): buy from the vendor, list on the AH.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local Page = SR.UI:RegisterPage({
	id = "flips",
	order = 30,
	title = L["Vendor Flips"],
	description = L.FLIPS_DESC,
	icon = "Interface\\Icons\\INV_Misc_Coin_02",
})

local function BuildRow(itemID, vendorEntry)
	local row = Util.GetItemDisplay(itemID)
	row.searchText = row.name:lower()
	row.vendorPrice = vendorEntry.price
	row.auctionPrice = SR.Prices:GetNetAuctionPrice(itemID)
	if row.auctionPrice and row.vendorPrice and row.vendorPrice > 0 then
		row.profit = row.auctionPrice - row.vendorPrice
		row.margin = row.profit / row.vendorPrice
	end
	return row
end

function Page:OnCreate(frame)
	self.search = ""
	self.onlyProfitable = true

	self.Search = Widgets.CreateSearchBox(frame, 220, function(text)
		self.search = text:lower()
		self.Table:Refresh()
	end)
	self.Search:SetPoint("TOPLEFT", 6, -2)

	self.ProfitableOnly = Widgets.CreateCheckbox(frame, L["Profitable only"],
		L["Hide items that don't sell on the auction house for more than the vendor price."],
		function()
			return self.onlyProfitable
		end,
		function(checked)
			self.onlyProfitable = checked
			self.Table:Refresh()
		end)
	self.ProfitableOnly:SetPoint("LEFT", self.Search, "RIGHT", 16, 0)

	self.Count = Widgets.CreateLabel(frame, "", "GameFontDisableSmall", "RIGHT")
	self.Count:SetPoint("RIGHT", frame, "TOPRIGHT", -4, -12)

	self.Table = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "name", title = L["Item"], kind = "item" },
			{ key = "vendorPrice", title = L["Vendor price"], width = 115, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "auctionPrice", title = L["Auction (net)"], width = 115, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "profit", title = L["Profit"], width = 115, kind = "profit", align = "RIGHT", sortDescFirst = true },
			{ key = "margin", title = L["Margin"], width = 80, kind = "percent", align = "RIGHT", sortDescFirst = true },
		},
		sortKey = "profit",
		sortDesc = true,
		emptyIcon = "Interface\\Icons\\INV_Misc_Coin_02",
		emptyTitle = L.FLIPS_EMPTY_TITLE,
		emptyBody = L.FLIPS_EMPTY_BODY,
		onRefresh = function(_, shown, total)
			self.Count:SetText(L["%d of %d items"]:format(shown, total))
		end,
	})
	self.Table:SetPoint("TOPLEFT", 0, -34)
	self.Table:SetPoint("BOTTOMRIGHT")
	self.Table:SetFilter(function(row)
		if self.onlyProfitable and not (row.profit and row.profit > 0) then
			return false
		end
		return self.search == "" or row.searchText:find(self.search, 1, true) ~= nil
	end)
end

function Page:Refresh()
	local rows = {}
	for itemID, entry in pairs(SR.DB.global.vendorPrices) do
		rows[#rows + 1] = BuildRow(itemID, entry)
	end
	self.Table:SetRows(rows)
end

--[[ SilkRoad - Modules/PriceDatabase.lua
	Item price lookup (vendor, merchant and every auction source side by
	side) and a browser for SilkRoad's own auction scan data.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local LINE_HEIGHT = 18
local LABEL_WIDTH = 230

local Page = SR.UI:RegisterPage({
	id = "prices",
	order = 40,
	title = L["Price Database"],
	description = L.PRICES_DESC,
	icon = "Interface\\Icons\\INV_Misc_Book_09",
})

local function CreatePriceLine(parent, anchor, offsetY)
	local line = {}
	line.Label = Widgets.CreateLabel(parent, "", "GameFontNormal")
	line.Label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
	line.Label:SetWidth(LABEL_WIDTH)
	line.Value = Widgets.CreateLabel(parent, "", "GameFontHighlight")
	line.Value:SetPoint("LEFT", line.Label, "RIGHT", 8, 0)
	return line
end

function Page:OnCreate(frame)
	-- Lookup row
	local inputLabel = Widgets.CreateLabel(frame, L["Item"], "GameFontNormal")
	inputLabel:SetPoint("TOPLEFT", 0, -6)

	self.Input = Widgets.CreateInput(frame, 300, function(text)
		self:Lookup(text)
	end)
	self.Input:SetPoint("LEFT", inputLabel, "RIGHT", 14, 0)

	local lookupButton = Widgets.CreateButton(frame, L["Look up"], 100, function()
		self.Input:ClearFocus()
		self:Lookup(self.Input:GetText())
	end)
	lookupButton:SetPoint("LEFT", self.Input, "RIGHT", 8, 0)

	-- Shift-clicking an item while the box has focus drops its link in.
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
			if link and self.Input:HasFocus() then
				self.Input:SetText(link)
				self:Lookup(link)
			end
		end)
	end

	-- Result panel
	local providers = SR.Prices:GetProviders()
	local panel = Widgets.CreatePanel(frame, 0.35)
	panel:SetPoint("TOPLEFT", 0, -34)
	panel:SetPoint("TOPRIGHT", 0, -34)
	panel:SetHeight(12 + 40 + 12 + (3 + #providers) * LINE_HEIGHT + 10)
	self.Panel = panel

	panel.Icon = panel:CreateTexture(nil, "ARTWORK")
	panel.Icon:SetSize(40, 40)
	panel.Icon:SetPoint("TOPLEFT", 12, -12)

	panel.Name = Widgets.CreateLabel(panel, "", "GameFontNormalLarge")
	panel.Name:SetPoint("TOPLEFT", panel.Icon, "TOPRIGHT", 10, -3)

	panel.ItemID = Widgets.CreateLabel(panel, "", "GameFontDisableSmall")
	panel.ItemID:SetPoint("TOPLEFT", panel.Name, "BOTTOMLEFT", 0, -4)

	panel.Hint = Widgets.CreateLabel(panel, L.LOOKUP_HINT, "GameFontDisable", "CENTER")
	panel.Hint:SetPoint("CENTER")
	panel.Hint:SetWidth(460)

	self.lines = {}
	local anchor = panel.Icon
	local offsetY = -12
	local function addLine(key)
		local line = CreatePriceLine(panel, anchor, offsetY)
		self.lines[key] = line
		anchor, offsetY = line.Label, -(LINE_HEIGHT - 12)
		return line
	end
	addLine("vendorSell").Label:SetText(L["Vendors pay you"])
	addLine("vendorBuy").Label:SetText(L["Merchants charge (recorded)"])
	for _, provider in ipairs(providers) do
		addLine("provider:" .. provider.id).Label:SetText(L["Auction: %s"]:format(provider.label))
	end
	addLine("net")

	-- Own scan data
	local header = Widgets.CreateHeader(frame, L["SilkRoad auction data"])
	header:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -16)
	header:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -16)
	self.DataHeader = header

	self.Table = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "name", title = L["Item"], kind = "item" },
			{ key = "price", title = L["Price"], width = 120, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "quantity", title = L["Available"], width = 90, align = "RIGHT", sortDescFirst = true },
			{
				key = "seen", title = L["Seen"], width = 110, align = "RIGHT", sortDescFirst = true,
				format = function(value) return Util.TimeAgo(value) end,
			},
		},
		sortKey = "name",
		emptyIcon = "Interface\\Icons\\INV_Misc_Book_09",
		emptyTitle = L.PRICES_EMPTY_TITLE,
		emptyBody = L.PRICES_EMPTY_BODY,
		onRowClick = function(row)
			self.Input:SetText(row.link or tostring(row.itemID))
			self:Lookup(row.itemID)
		end,
	})
	self.Table:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
	self.Table:SetPoint("BOTTOMRIGHT")
end

function Page:Lookup(input)
	self.itemID = Util.ParseItemID(input)
	self.lookupFailed = input ~= nil and input ~= "" and self.itemID == nil
	self:RefreshResult()
end

function Page:RefreshResult()
	local panel = self.Panel
	local itemID = self.itemID
	local hasItem = itemID ~= nil

	panel.Icon:SetShown(hasItem)
	panel.Name:SetShown(hasItem)
	panel.ItemID:SetShown(hasItem)
	for _, line in pairs(self.lines) do
		line.Label:SetShown(hasItem)
		line.Value:SetShown(hasItem)
	end
	panel.Hint:SetShown(not hasItem)
	panel.Hint:SetText(self.lookupFailed and L.LOOKUP_NOT_FOUND or L.LOOKUP_HINT)
	if not hasItem then
		return
	end

	local item = Util.GetItemDisplay(itemID)
	panel.Icon:SetTexture(item.icon or 134400)
	panel.Name:SetText(item.loading and L["Loading item data..."] or Util.ColorByQuality(item.name, item.quality))
	panel.ItemID:SetText(L["Item ID %d"]:format(itemID))

	local sellPrice = SR.Prices:GetVendorSellPrice(itemID)
	if sellPrice == 0 then
		self.lines.vendorSell.Value:SetText("|cff808080" .. L["Can't be sold to vendors"] .. "|r")
	else
		self.lines.vendorSell.Value:SetText(Util.FormatMoney(sellPrice))
	end

	self.lines.vendorBuy.Value:SetText(Util.FormatMoney(SR.Prices:GetVendorBuyPrice(itemID)))

	for _, provider in ipairs(SR.Prices:GetProviders()) do
		local line = self.lines["provider:" .. provider.id]
		if not provider:IsAvailable() then
			line.Value:SetText("|cff808080" .. (provider.GetStatus and provider:GetStatus() or L["Unavailable"]) .. "|r")
		else
			local text = Util.FormatMoney(provider:GetPrice(itemID))
			local age = provider.GetAgeText and provider:GetAgeText(itemID)
			if age then
				text = text .. "  |cff808080(" .. age .. ")|r"
			end
			line.Value:SetText(text)
		end
	end

	local net, source = SR.Prices:GetNetAuctionPrice(itemID)
	self.lines.net.Label:SetText(L["You'd receive after the %d%% cut"]:format(SR:GetSetting("auctionCutPercent")))
	local netText = Util.FormatMoney(net)
	if source then
		netText = netText .. "  |cff808080(" .. SR.Prices:GetProvider(source).label .. ")|r"
	end
	self.lines.net.Value:SetText(netText)
end

function Page:Refresh()
	self:RefreshResult()

	local market = SR.DB:GetMarket()
	self.DataHeader.Text:SetText(L["SilkRoad auction data: %s"]:format(SR.DB:GetMarketKey()))
	local rows = {}
	for itemID, entry in pairs(market.auction) do
		local row = Util.GetItemDisplay(itemID)
		row.price = entry.price
		row.quantity = entry.quantity
		row.seen = entry.seen
		rows[#rows + 1] = row
	end
	self.Table:SetRows(rows)
end

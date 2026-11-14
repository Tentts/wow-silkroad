--[[ SilkRoad - UI/Tooltip.lua
	Adds SilkRoad's prices to item tooltips, like Auctionator's lines:
	  SilkRoad vendor    what a vendor pays for one
	  SilkRoad auction   lowest auction buyout, for items that can be sold
	                     (not bind-on-pickup, soulbound, account-bound or quest items)
	Turned on and off in Settings > General.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util

local Tooltip = SR:NewComponent("Tooltip")

local LABEL_R, LABEL_G, LABEL_B = 0.9, 0.76, 0.36 -- SilkRoad gold

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

function Tooltip:AddPriceLines(tooltip, data)
	if not SR:GetSetting("tooltipPrices") or not data or type(data.id) ~= "number" then
		return
	end
	local itemID = data.id
	local added = false

	local vendor = SR.Prices:GetVendorSellPrice(itemID)
	if vendor and vendor > 0 then
		tooltip:AddDoubleLine(L["SilkRoad vendor"], Util.FormatMoney(vendor), LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
		added = true
	end

	if not IsBound(data) then
		local auction = SR.Prices:GetAuctionPrice(itemID)
		tooltip:AddDoubleLine(L["SilkRoad auction"], auction and Util.FormatMoney(auction) or Util.ColorText(L["no data"], "ff808080"),
			LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
		added = true
	end

	if added and tooltip:IsShown() then
		tooltip:Show() -- resize to fit the new lines
	end
end

function Tooltip:OnEnable()
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		self:AddPriceLines(tooltip, data)
	end)
end

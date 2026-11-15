--[[ SilkRoad - UI/Tooltip.lua
	Adds SilkRoad's prices to item tooltips, like Auctionator's lines:
	  SilkRoad vendor    what a vendor pays for one
	  SilkRoad auction   lowest auction buyout, for items that can be sold
	                     (not bind-on-pickup, soulbound, account-bound or quest items)
	Settings > General picks the mode: off, single item, whole stack, or
	single and stack ("SilkRoad vendor 1 / 20   5c / 1s"). Stacks are the
	ones in the bags, bank and reagent bag; holding Shift swaps single and
	stack while hovering.
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

-- What to show for a stack of `count`: "single", "stack" or "both".
-- Shift swaps single and stack while held.
local function ShownAs(mode, count)
	if count <= 1 then
		return "single"
	elseif mode == "both" then
		return "both"
	end
	local stack = mode == "stack"
	if IsShiftKeyDown() then
		stack = not stack
	end
	return stack and "stack" or "single"
end

-- The label and value of one price line.
local function PriceLine(singleLabel, stackLabel, bothLabel, price, count, shownAs)
	if shownAs == "stack" then
		return stackLabel:format(count), Util.FormatMoney(price * count)
	elseif shownAs == "both" then
		return bothLabel:format(count), Util.FormatMoney(price) .. " / " .. Util.FormatMoney(price * count)
	end
	return singleLabel, Util.FormatMoney(price)
end

function Tooltip:AddPriceLines(tooltip, data)
	local mode = SR:GetSetting("tooltipMode")
	if mode == "off" or not data or type(data.id) ~= "number" then
		return
	end
	local itemID = data.id
	local added = false
	local count = SR.Game.GetTooltipStackCount(tooltip) or 1
	local shownAs = ShownAs(mode, count)

	local vendor = SR.Prices:GetVendorSellPrice(itemID)
	if vendor and vendor > 0 then
		local label, value = PriceLine(L["SilkRoad vendor"], L["SilkRoad vendor x%d"], L["SilkRoad vendor 1 / %d"],
			vendor, count, shownAs)
		tooltip:AddDoubleLine(label, value, LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
		added = true
	end

	if not IsBound(data) then
		local auction = SR.Prices:GetAuctionPrice(itemID)
		if auction then
			local label, value = PriceLine(L["SilkRoad auction"], L["SilkRoad auction x%d"], L["SilkRoad auction 1 / %d"],
				auction, count, shownAs)
			tooltip:AddDoubleLine(label, value, LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
		else
			tooltip:AddDoubleLine(L["SilkRoad auction"], Util.ColorText(L["no data"], "ff808080"), LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
		end
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
	-- Pressing or releasing Shift while hovering switches between one item and the stack.
	for _, event in ipairs(SR.Game.events.modifiersChanged) do
		SR:RegisterEvent(event, function(_, key)
			local mode = SR:GetSetting("tooltipMode")
			if (key == "LSHIFT" or key == "RSHIFT") and (mode == "single" or mode == "stack")
				and GameTooltip:IsShown() and SR.Game.GetTooltipStackCount(GameTooltip) then
				SR.Game.RefreshTooltip(GameTooltip)
			end
		end)
	end
end

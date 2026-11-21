--[[ SilkRoad - Core/BagSpace.lua
	Full bags while looting: which bag items are worth less than the loot,
	so the right ones can be thrown away. Off by default (Settings > General).

	When looting fails because the bags are full, the most valuable item
	left in the loot window is compared with every stack in the bags. Value
	= the best of what a vendor pays and the auction price after the cut
	(no auction price for bound items), times the stack size: throwing a
	stack away loses all of it. Up to MAX_SUGGESTIONS of the cheapest stacks
	worth less than the loot glow red for a few seconds (UI/BagGlow.lua), and
	chat lists them.

	Items without any known value (quest items, the Hearthstone...) are never
	suggested.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util

local BagSpace = SR:NewComponent("BagSpace")

local MAX_SUGGESTIONS = 3
local THROTTLE = 3 -- seconds: each failed loot attempt raises the error again

-- What one item is worth to the player: vendor or auction (after the cut).
function BagSpace:ItemValue(itemID, bound)
	local vendor = SR.Prices:GetVendorSellPrice(itemID)
	local auction = not bound and SR.Prices:GetNetAuctionPrice(itemID) or nil
	if (vendor or 0) <= 0 and not auction then
		return nil -- no idea: never suggest throwing it away
	end
	return math.max(vendor or 0, auction or 0)
end

-- The most valuable item left in the loot window: { itemID, count, value }.
function BagSpace:GetBestLoot()
	local best
	for _, item in ipairs(SR.Game.GetLootItems()) do
		local value = (self:ItemValue(item.itemID, false) or 0) * item.count
		if not best or value > best.value then
			best = { itemID = item.itemID, count = item.count, value = value }
		end
	end
	return best
end

-- The cheapest bag stacks worth less than `value`, cheapest first:
-- { { bag, slot, itemID, count, value }, ... }
function BagSpace:FindCheaper(value)
	local cheaper = {}
	for _, item in ipairs(SR.Game.GetBagItems()) do
		local unit = self:ItemValue(item.itemID, item.bound)
		if unit then
			item.value = unit * item.count
			if item.value < value then
				cheaper[#cheaper + 1] = item
			end
		end
	end
	table.sort(cheaper, function(a, b)
		return a.value < b.value
	end)
	local result = {}
	for i = 1, math.min(#cheaper, MAX_SUGGESTIONS) do
		result[i] = cheaper[i]
	end
	return result
end

function BagSpace:OnInventoryFull()
	if not SR:GetSetting("lootSpaceHelper") then
		return
	end
	local now = GetTime()
	if self.lastRun and now - self.lastRun < THROTTLE then
		return
	end
	local loot = self:GetBestLoot()
	if not loot or loot.value <= 0 then
		return -- not looting, or nothing of known value to make room for
	end
	self.lastRun = now
	local cheaper = self:FindCheaper(loot.value)
	local lootName = Util.GetItemDisplay(loot.itemID).name
	if #cheaper == 0 then
		SR:Print(L["Bags full: nothing in them is worth less than %s (%s)."]:format(lootName, Util.FormatMoney(loot.value)))
		return
	end
	local names = {}
	for _, item in ipairs(cheaper) do
		local name = Util.GetItemDisplay(item.itemID).name
		if item.count > 1 then
			name = ("%s x%d"):format(name, item.count)
		end
		names[#names + 1] = ("%s (%s)"):format(name, Util.FormatMoney(item.value))
	end
	SR:Print(L["Bags full: %s (%s) is worth more than %s."]:format(lootName, Util.FormatMoney(loot.value), table.concat(names, ", ")))
	SR.BagGlow:Show(cheaper)
end

function BagSpace:OnEnable()
	for _, event in ipairs(SR.Game.events.uiError) do
		SR:RegisterEvent(event, function(_, _, message)
			if SR.Game.IsInventoryFullError(message) then
				self:OnInventoryFull()
			end
		end)
	end
end

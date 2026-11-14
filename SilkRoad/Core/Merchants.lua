--[[ SilkRoad - Core/Merchants.lua
	Records what merchants charge whenever a merchant window opens, as a
	bonus on top of the generated data. Nobody has to visit vendors for
	SilkRoad to know common vendor prices (see Prices:GetVendorBuyPrice), but
	a recorded price is exact, including any reputation discount.
]]
local _, SR = ...
local Util = SR.Util

local Merchants = SR:NewComponent("Merchants")

function Merchants:Record()
	local prices = SR.DB.global.vendorPrices
	local now, changed = time(), false
	for _, entry in ipairs(SR.Game.ReadMerchant()) do
		local stored = prices[entry.itemID]
		if stored then
			changed = changed or stored.price ~= entry.price
			stored.price, stored.seen = entry.price, now
		else
			prices[entry.itemID] = { price = entry.price, seen = now }
			changed = true
		end
	end
	if changed then
		SR:Fire("PRICES_UPDATED")
	end
end

function Merchants:OnEnable()
	local record = Util.Debounce(0.5, function()
		self:Record()
	end)
	for _, event in ipairs(SR.Game.events.merchantChanged) do
		SR:RegisterEvent(event, record)
	end
end

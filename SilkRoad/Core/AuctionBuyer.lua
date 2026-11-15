--[[ SilkRoad - Core/AuctionBuyer.lua
	Buys one item at a time at the auction house, for the Buy Lists tab.

	  Select(itemID)     searches the item (cheapest first)
	  Buy(quantity)      asks for the price: commodities get a quote from the
	                     server; other items take the cheapest whole auction
	  Confirm(quantity)  buys at the quoted price; refused (and the quote
	                     dropped) if quantity isn't what was quoted
	  Cancel()           drops the quote

	The game only allows buying from a click, so Buy and Confirm must be
	called from button clicks. Nothing here buys on its own.

	state: "idle" | "throttled" (waiting to search) | "searching" | "ready"
	       | "quoting" | "confirm" | "buying"
	Fires AUCTION_BUYER_UPDATED whenever the state or results change.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util

local Buyer = SR:NewComponent("AuctionBuyer")

Buyer.state = "idle"
Buyer.listings = {}

local function Update()
	SR:Fire("AUCTION_BUYER_UPDATED")
end

function Buyer:OnEnable()
	local events = SR.Game.auctionEvents
	if not events then
		return -- this game version has no auction house buying support
	end
	for _, event in ipairs(events.results) do
		SR:RegisterEvent(event, function(_, key)
			local itemID = type(key) == "table" and key.itemID or key
			self:OnResults(itemID)
		end)
	end
	SR:RegisterEvent(events.price, function(_, unitPrice, totalPrice)
		self:OnQuote(unitPrice, totalPrice)
	end)
	for _, event in ipairs(events.purchased) do
		SR:RegisterEvent(event, function()
			self:OnPurchaseFinished(true)
		end)
	end
	for _, event in ipairs(events.failed) do
		SR:RegisterEvent(event, function()
			self:OnPurchaseFinished(false)
		end)
	end
	SR:RegisterEvent(events.ready, function()
		if self.state == "throttled" then
			self:Search()
		end
	end)
	SR:RegisterEvent(events.closed, function()
		self:Reset()
	end)
end

function Buyer:Reset()
	self.state = "idle"
	self.itemID = nil
	self.listings = {}
	self.quote = nil
	self.message = nil
	Update()
end

---------------------------------------------------------------------------
-- Searching
---------------------------------------------------------------------------

function Buyer:Select(itemID)
	if self.quote then
		self:Cancel()
	end
	self.itemID = itemID
	self.listings = {}
	self.message = nil
	self:Search()
end

function Buyer:Search()
	if not self.itemID then
		return
	end
	if SR.Game.AuctionCanSearch() then
		self.state = "searching"
		SR.Game.AuctionSearch(self.itemID)
	else
		self.state = "throttled"
	end
	Update()
end

function Buyer:OnResults(itemID)
	if itemID ~= self.itemID or (self.state ~= "searching" and self.state ~= "ready") then
		return
	end
	self.commodity = SR.Game.AuctionIsCommodity(itemID)
	self.listings = SR.Game.AuctionReadResults(itemID)
	self.state = "ready"
	Update()
end

-- What buying `quantity` from the current listings would cost:
-- total, how many can actually be bought, highest unit price paid.
function Buyer:Estimate(quantity)
	local total, count, highest = 0, 0, nil
	for _, listing in ipairs(self.listings) do
		if count >= quantity then
			break
		end
		local take = math.min(listing.quantity, quantity - count)
		total = total + take * listing.unitPrice
		count = count + take
		highest = listing.unitPrice
	end
	return total, count, highest
end

function Buyer:GetAvailable()
	local available = 0
	for _, listing in ipairs(self.listings) do
		available = available + listing.quantity
	end
	return available
end

---------------------------------------------------------------------------
-- Buying (from clicks only)
---------------------------------------------------------------------------

function Buyer:Buy(quantity)
	if self.state ~= "ready" or not self.itemID or #self.listings == 0 then
		return
	end
	if self.commodity then
		quantity = math.min(math.floor(quantity or 0), self:GetAvailable())
		if quantity <= 0 then
			return
		end
		self.quote = { quantity = quantity }
		self.state = "quoting"
		SR.Game.AuctionStartCommodityPurchase(self.itemID, quantity)
	else
		-- Separate auctions: the cheapest one, whole.
		local listing = self.listings[1]
		self.quote = { quantity = listing.quantity, total = listing.buyout, unitPrice = listing.unitPrice, auctionID = listing.auctionID }
		self.state = "confirm"
	end
	Update()
end

function Buyer:OnQuote(unitPrice, totalPrice)
	if self.state ~= "quoting" or not self.quote then
		return
	end
	self.quote.unitPrice = unitPrice
	self.quote.total = totalPrice
	self.state = "confirm"
	Update()
end

function Buyer:Confirm(quantity)
	local quote = self.quote
	if self.state ~= "confirm" or not quote then
		return
	end
	if not quote.auctionID and quantity and quantity ~= quote.quantity then
		self:Cancel() -- the quantity changed after the quote: ask again
		return
	end
	self.state = "buying"
	if quote.auctionID then
		SR.Game.AuctionBuyout(quote.auctionID, quote.total)
	else
		SR.Game.AuctionConfirmCommodityPurchase(self.itemID, quote.quantity)
	end
	Update()
end

function Buyer:Cancel()
	if self.quote and not self.quote.auctionID and (self.state == "quoting" or self.state == "confirm") then
		SR.Game.AuctionCancelCommodityPurchase()
	end
	self.quote = nil
	if self.state == "quoting" or self.state == "confirm" then
		self.state = "ready"
	end
	Update()
end

function Buyer:OnPurchaseFinished(succeeded)
	if self.state ~= "buying" then
		return
	end
	local quote = self.quote
	self.quote = nil
	local name = Util.GetItemDisplay(self.itemID).name
	if succeeded and quote then
		self.message = L["Bought %d x %s for %s."]:format(quote.quantity, name, Util.FormatMoney(quote.total or 0))
	else
		self.message = L["The purchase of %s failed; prices may have changed."]:format(name)
	end
	SR:Print(self.message)
	self.state = "ready"
	self:Search() -- fresh listings after buying
end

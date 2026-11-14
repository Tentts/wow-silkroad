--[[ SilkRoad - Core/Prices.lua
	The price layer every page reads from.

	Vendor sell prices come straight from the game client. Vendor buy prices
	and SilkRoad's own auction data come from the saved variables. Auction
	prices are served by "providers" so new sources (SilkRoad's scanner,
	other addons, imported data) can be plugged in without touching the UI.

	Provider interface:
	  id                     unique string, also stored in settings.priceSource
	  label                  display name
	  IsAvailable(self)      -> boolean
	  GetPrice(self, itemID) -> copper per unit before the auction house cut, or nil
	  GetAgeText(self, itemID) -> "seen 2 days ago" style text, or nil (optional)
	  GetStatus(self)        -> short human-readable status line (optional)
]]
local addonName, SR = ...
local L = SR.L
local Util = SR.Util

local Prices = SR:NewComponent("Prices")

local providers = {}
local providerOrder = {}

function Prices:OnInitialize()
	SR:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
		if Util.TakeRequestedItem(itemID) and success then
			SR:Fire("ITEM_INFO_RECEIVED", itemID)
		end
	end)
end

---------------------------------------------------------------------------
-- Providers
---------------------------------------------------------------------------

function Prices:RegisterProvider(provider)
	assert(type(provider.id) == "string" and provider.GetPrice, "SilkRoad: invalid price provider")
	if not providers[provider.id] then
		providerOrder[#providerOrder + 1] = provider.id
	end
	providers[provider.id] = provider
end

function Prices:GetProvider(id)
	return providers[id]
end

-- Providers in priority order (the order used by the "auto" setting).
function Prices:GetProviders()
	local list = {}
	for i, id in ipairs(providerOrder) do
		list[i] = providers[id]
	end
	return list
end

local function QueryProvider(provider, itemID)
	if provider and provider:IsAvailable() then
		return provider:GetPrice(itemID)
	end
end

---------------------------------------------------------------------------
-- Price queries (all prices are copper per single item)
---------------------------------------------------------------------------

-- Auction price from the preferred provider, falling back to the others in
-- priority order. Returns price, providerID.
function Prices:GetAuctionPrice(itemID)
	if not itemID then
		return nil
	end
	local preferredID = SR:GetSetting("priceSource")
	local price = QueryProvider(providers[preferredID], itemID)
	if price then
		return price, preferredID
	end
	for _, id in ipairs(providerOrder) do
		if id ~= preferredID then
			price = QueryProvider(providers[id], itemID)
			if price then
				return price, id
			end
		end
	end
	return nil
end

function Prices:GetAuctionCut()
	return (SR:GetSetting("auctionCutPercent") or 0) / 100
end

-- What you actually receive when an auction sells, after the auction house cut.
function Prices:GetNetAuctionPrice(itemID)
	local price, source = self:GetAuctionPrice(itemID)
	if not price then
		return nil
	end
	return math.floor(price * (1 - self:GetAuctionCut())), source
end

local function StaticItem(itemID)
	return SR.StaticData and SR.StaticData.items[itemID]
end

-- What a vendor pays you for the item. 0 means vendors won't buy it, nil
-- means unknown: not in the generated data and not loaded by the client yet
-- (it is requested here).
function Prices:GetVendorSellPrice(itemID)
	if not itemID then
		return nil
	end
	local static = StaticItem(itemID)
	if static then
		return static[4]
	end
	local sellPrice = select(11, C_Item.GetItemInfo(itemID))
	if sellPrice == nil then
		Util.RequestItem(itemID)
	end
	return sellPrice
end

-- What a merchant charges for one item, and where that price comes from:
--   "recorded"    SilkRoad saw it at a merchant (exact, incl. reputation discounts)
--   "auctionator" Auctionator saw it at a merchant
--   "data"        the client's item data, for items vendors are known to sell
--                 (QuestieDB's vendor lists or a merchant SilkRoad has visited)
function Prices:GetVendorBuyPrice(itemID)
	if not itemID then
		return nil
	end
	local entry = SR.DB.global.vendorPrices[itemID]
	if entry then
		return entry.price, "recorded"
	end
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetVendorPriceByItemID then
		local ok, price = pcall(api.GetVendorPriceByItemID, addonName, itemID)
		if ok and type(price) == "number" and price > 0 then
			return price, "auctionator"
		end
	end
	local static = StaticItem(itemID)
	if static and static[5] > 0 and SR.Sources:IsSoldByVendor(itemID) then
		return static[5] / static[6], "data"
	end
	return nil
end

-- Cheapest known way to get one unit: returns price, "vendor" | "auction".
function Prices:GetAcquireCost(itemID)
	local vendor = self:GetVendorBuyPrice(itemID)
	local auction = self:GetAuctionPrice(itemID)
	if vendor and (not auction or vendor <= auction) then
		return vendor, "vendor"
	elseif auction then
		return auction, "auction"
	end
	return nil
end

function Prices:GetStats()
	local market = SR.DB:GetMarket()
	return {
		marketKey = SR.DB:GetMarketKey(),
		auctionItems = Util.CountKeys(market.auction),
		lastScan = market.lastScan,
		vendorItems = Util.CountKeys(SR.DB.global.vendorPrices),
	}
end

---------------------------------------------------------------------------
-- Built-in providers
---------------------------------------------------------------------------

-- SilkRoad's own auction scans for the current realm.
Prices:RegisterProvider({
	id = "silkroad",
	label = L["SilkRoad scans"],
	IsAvailable = function()
		return true
	end,
	GetPrice = function(_, itemID)
		local entry = SR.DB:GetMarket().auction[itemID]
		return entry and entry.price or nil
	end,
	GetAgeText = function(_, itemID)
		local entry = SR.DB:GetMarket().auction[itemID]
		if entry and entry.seen then
			return L["seen %s"]:format(Util.TimeAgo(entry.seen))
		end
	end,
	GetStatus = function()
		local stats = Prices:GetStats()
		if stats.auctionItems == 0 then
			return L["No scans yet"]
		end
		return L["%d items, last scan %s"]:format(stats.auctionItems, Util.TimeAgo(stats.lastScan))
	end,
})

-- Auctionator's public API (Auctionator.API.v1). Calls are wrapped in pcall
-- so a change in another addon can never break SilkRoad.
local function AuctionatorAPI()
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetAuctionPriceByItemID then
		return api
	end
end

Prices:RegisterProvider({
	id = "auctionator",
	label = "Auctionator",
	IsAvailable = function()
		return AuctionatorAPI() ~= nil
	end,
	GetPrice = function(_, itemID)
		local ok, price = pcall(AuctionatorAPI().GetAuctionPriceByItemID, addonName, itemID)
		if ok then
			return price
		end
	end,
	GetAgeText = function(_, itemID)
		local api = AuctionatorAPI()
		if not (api and api.GetAuctionAgeByItemID) then
			return nil
		end
		-- Auctionator reports whole days since the item was last seen (nil after 21 days).
		local ok, days = pcall(api.GetAuctionAgeByItemID, addonName, itemID)
		if not (ok and days) then
			return nil
		elseif days == 0 then
			return L["seen today"]
		elseif days == 1 then
			return L["seen yesterday"]
		end
		return L["seen %d days ago"]:format(days)
	end,
	GetStatus = function(self)
		return self:IsAvailable() and L["Detected"] or L["Not installed"]
	end,
})

--[[ SilkRoad - Core/AuctionScanner.lua
	A lightweight full scan of the auction house.

	One C_AuctionHouse.ReplicateItems() request returns every listing on the
	auction house at once. The server only allows that request once every
	15 minutes, so SilkRoad never sends it more often, whether the scan is
	automatic or manual. The listings are then read a batch per frame so the
	game stays smooth.

	For each item SilkRoad keeps the lowest unit buyout and the total
	quantity listed, in markets[realm].auction (see Core/Database.lua).
	Items missing from a scan keep their last price with quantity 0.

	When another addon (Auctionator, for example) runs a full scan, SilkRoad
	sees the request through a hook on C_AuctionHouse.ReplicateItems and
	records the results without sending a request of its own.

	Callbacks fired: SCAN_STATUS (state, progress) whenever the state or
	progress changes, and PRICES_UPDATED when a scan has been saved.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util

local Scanner = SR:NewComponent("Scanner")

Scanner.COOLDOWN = 15 * 60  -- the server allows one full scan per 15 minutes
local AUTO_SCAN_DELAY = 3   -- seconds after the AH opens, so Blizzard's first query goes first
local RESPONSE_TIMEOUT = 120 -- seconds to wait for the server's answer (busy AHs can be slow)
local BATCH_SIZE = 1000     -- listings read per frame

Scanner.state = "idle" -- "idle" | "waiting" (request sent) | "processing" (reading listings)
Scanner.progress = 0   -- 0..1 while processing
Scanner.isAuctionHouseOpen = false

-- Scan in progress. scanID changes whenever a scan starts or stops, so
-- timers and batches left over from an earlier scan know to do nothing.
local scanID = 0
local minPrice, quantity       -- [itemID] = lowest unit buyout / total quantity
local itemCount, listingCount  -- distinct items / listings with a buyout
local nextIndex, totalListings -- replicate indices are 0-based
local startedAt                -- GetTime() when the scan started

local function SetState(state, progress)
	Scanner.state = state
	Scanner.progress = progress or 0
	SR:Fire("SCAN_STATUS", state, Scanner.progress)
end

---------------------------------------------------------------------------
-- Cooldown
---------------------------------------------------------------------------

-- When the last full scan was requested. Auctionator saves the time of its
-- own full scans; counting those too means the two addons never ask the
-- server twice within 15 minutes (its results reach SilkRoad anyway).
local function LastRequestTime()
	local lastRequest = SR.DB.global.scanner.lastRequest
	local auctionatorState = Auctionator and Auctionator.SavedState
	local auctionatorRequest = type(auctionatorState) == "table" and tonumber(auctionatorState.TimeOfLastReplicateScan)
	if auctionatorRequest and (not lastRequest or auctionatorRequest > lastRequest) then
		return auctionatorRequest
	end
	return lastRequest
end

-- Seconds until the server accepts another full scan (0 = ready). The time
-- of the last request is saved account-wide, so it survives /reload.
function Scanner:GetCooldownRemaining()
	local lastRequest = LastRequestTime()
	if not lastRequest then
		return 0
	end
	return math.max(0, lastRequest + self.COOLDOWN - time())
end

local function NextScanText()
	return L["Next full scan available in %s."]:format(Util.FormatDuration(Scanner:GetCooldownRemaining()))
end

function Scanner:CanScan()
	if not self.isAuctionHouseOpen then
		return false, L["Open the auction house to scan it."]
	elseif self.state ~= "idle" then
		return false, L["A scan is already running."]
	elseif self:GetCooldownRemaining() > 0 then
		return false, NextScanText()
	end
	return true
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------

function Scanner:Fail(message)
	scanID = scanID + 1
	minPrice, quantity = nil, nil
	SetState("idle")
	SR:Print(message)
end

local function SaveResults()
	local market = SR.DB:GetMarket()
	local now = time()

	for itemID, stored in pairs(market.auction) do
		if not minPrice[itemID] then
			stored.quantity = 0
		end
	end
	for itemID, unitPrice in pairs(minPrice) do
		local price = math.max(1, math.floor(unitPrice + 0.5))
		local stored = market.auction[itemID]
		if stored then
			stored.price, stored.quantity, stored.seen = price, quantity[itemID], now
		else
			market.auction[itemID] = { price = price, quantity = quantity[itemID], seen = now }
		end
	end

	local seconds = Util.Round(GetTime() - startedAt, 1)
	market.lastScan = now
	market.lastScanStats = { items = itemCount, listings = listingCount, seconds = seconds }
	return seconds
end

local function Finish()
	local seconds = SaveResults()
	scanID = scanID + 1
	minPrice, quantity = nil, nil
	SetState("idle")
	SR:Print(L["Auction scan complete: %s items from %s auctions (%.1f s)."]:format(
		Util.FormatNumber(itemCount), Util.FormatNumber(listingCount), seconds))
	SR:Fire("PRICES_UPDATED")
end

local function ProcessBatch(id)
	if id ~= scanID or Scanner.state ~= "processing" then
		return
	end
	local lastIndex = math.min(nextIndex + BATCH_SIZE, totalListings) - 1
	for index = nextIndex, lastIndex do
		local _, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(index)
		-- Skip bid-only auctions (no buyout) and listings with no quantity.
		if itemID and count and count > 0 and buyoutPrice and buyoutPrice > 0 then
			local unitPrice = buyoutPrice / count
			local lowest = minPrice[itemID]
			if lowest then
				if unitPrice < lowest then
					minPrice[itemID] = unitPrice
				end
				quantity[itemID] = quantity[itemID] + count
				listingCount = listingCount + 1
			elseif C_Item.DoesItemExistByID(itemID) then
				-- The server occasionally lists items that don't exist; ignore those.
				minPrice[itemID] = unitPrice
				quantity[itemID] = count
				itemCount = itemCount + 1
				listingCount = listingCount + 1
			end
		end
	end
	nextIndex = lastIndex + 1

	if nextIndex >= totalListings then
		Finish()
	else
		SetState("processing", nextIndex / totalListings)
		C_Timer.After(0, function()
			ProcessBatch(id)
		end)
	end
end

-- REPLICATE_ITEM_LIST_UPDATE fires several times per request (again as item
-- data for the listings arrives), so only the first one after a request is
-- read; the rest are ignored.
local function OnReplicateListUpdate()
	if Scanner.state ~= "waiting" then
		return
	end
	local total = C_AuctionHouse.GetNumReplicateItems()
	if total == 0 then
		return -- listings not in yet: the event fires again as they arrive (or the wait times out)
	end

	scanID = scanID + 1
	local id = scanID
	minPrice, quantity = {}, {}
	itemCount, listingCount = 0, 0
	nextIndex, totalListings = 0, total
	SetState("processing", 0)
	C_Timer.After(0, function()
		ProcessBatch(id)
	end)
end

-- Sends the full scan request. Automatic scans fail silently when they
-- can't run; manual ones explain why.
function Scanner:StartScan(isAutomatic)
	local ok, reason = self:CanScan()
	if not ok then
		if not isAutomatic then
			SR:Print(reason)
		end
		return false
	end

	SR:Print(isAutomatic and L["Scanning the auction house (automatic, at most once every 15 minutes)..."]
		or L["Scanning the auction house..."])
	self:BeginWaiting(false)
	C_AuctionHouse.ReplicateItems()
	return true
end

-- A full scan request was just sent, by SilkRoad or by another addon: wait
-- for its results, and give up if the server doesn't answer.
function Scanner:BeginWaiting(isExternal)
	scanID = scanID + 1
	local id = scanID
	startedAt = GetTime()
	SR.DB.global.scanner.lastRequest = time()
	SetState("waiting")

	C_Timer.After(RESPONSE_TIMEOUT, function()
		if id ~= scanID or self.state ~= "waiting" then
			return
		end
		if isExternal then
			-- The other addon's request went unanswered; nothing to report.
			scanID = scanID + 1
			SetState("idle")
		else
			self:Fail(L.SCAN_NO_RESPONSE)
		end
	end)
end

-- Every ReplicateItems call goes through this hook, SilkRoad's own included
-- (it is already waiting by then). A call from another addon means its
-- results are coming: record them too, without a request of our own.
local function OnAnyReplicateRequest()
	if Scanner.state == "idle" and Scanner.isAuctionHouseOpen then
		SR:Print(L["Recording prices from a full scan started by another addon."])
		Scanner:BeginWaiting(true)
	end
end

if C_AuctionHouse and type(C_AuctionHouse.ReplicateItems) == "function" then
	hooksecurefunc(C_AuctionHouse, "ReplicateItems", OnAnyReplicateRequest)
end

---------------------------------------------------------------------------
-- Auction house open / close
---------------------------------------------------------------------------

local function OnAuctionHouseShow()
	Scanner.isAuctionHouseOpen = true
	SR:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE", OnReplicateListUpdate)
	SR:Fire("SCAN_STATUS", Scanner.state, Scanner.progress)

	if SR:GetSetting("autoScan") and Scanner:GetCooldownRemaining() == 0 then
		C_Timer.After(AUTO_SCAN_DELAY, function()
			if Scanner.isAuctionHouseOpen and SR:GetSetting("autoScan") then
				Scanner:StartScan(true)
			end
		end)
	end
end

local function OnAuctionHouseClosed()
	Scanner.isAuctionHouseOpen = false
	SR:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE", OnReplicateListUpdate)
	if Scanner.state ~= "idle" then
		Scanner:Fail(L["Auction scan cancelled because the auction house was closed."] .. " " .. NextScanText())
	else
		SR:Fire("SCAN_STATUS", Scanner.state, Scanner.progress)
	end
end

---------------------------------------------------------------------------
-- How old the saved scan data is, said once after logging in
---------------------------------------------------------------------------

local STALE_AFTER = 3 * 60 * 60 -- seconds
local LOGIN_REPORT_DELAY = 8    -- after the login chat messages

-- Scan data is kept per realm (SilkRoadDB.markets, saved by the game on
-- logout or /reload). Says when this realm's data is more than 3 hours
-- old, or, when this realm has none, which realms do have scans: the
-- realm name the game reports is what files the data.
function Scanner:ReportDataAge()
	local key = SR.DB:GetMarketKey()
	local markets = SR.DB.global.markets
	local market = SR.DB:GetMarket()
	if market.lastScan then
		if time() - market.lastScan > STALE_AFTER then
			SR:Print(L["Auction prices for %s are from %s. Open the auction house to scan again."]:format(
				key, Util.TimeAgo(market.lastScan)))
		end
		return
	end
	local others = {}
	for otherKey, other in pairs(markets) do
		if otherKey ~= key and other.lastScan then
			others[#others + 1] = otherKey
		end
	end
	if #others > 0 then
		table.sort(others)
		SR:Print(L["No auction scans for %s yet; SilkRoad has scans for %s."]:format(key, table.concat(others, ", ")))
	end
end

function Scanner:OnEnable()
	SR:RegisterEvent("AUCTION_HOUSE_SHOW", OnAuctionHouseShow)
	SR:RegisterEvent("AUCTION_HOUSE_CLOSED", OnAuctionHouseClosed)
	C_Timer.After(LOGIN_REPORT_DELAY, function()
		self:ReportDataAge()
	end)
end

SR:RegisterSlashCommand("scan", L["scan the auction house (it must be open)"], function()
	Scanner:StartScan(false)
end)

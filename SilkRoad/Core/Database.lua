--[[ SilkRoad - Core/Database.lua
	Saved variables, defaults, schema migrations and settings access.

	SilkRoadDB (account-wide)
	  schemaVersion  number
	  settings       see ACCOUNT_DEFAULTS.settings
	  markets        [marketKey] = {
	                   auction  = { [itemID] = { price = lowest unit buyout, quantity = n listed, seen = time() } },
	                   lastScan = time() | nil,
	                   lastScanStats = { items = n, listings = n, seconds = n } | nil,
	                 }
	                 Auction prices are kept per market (realm) because every
	                 realm has its own auction house economy. quantity is 0
	                 for items that were missing from the latest full scan.
	  lastMarketKey  the last auction house key the game reported (stands in while it can't)
	  scanner        { lastRequest = time() | nil }
	                 When the last full scan was requested (by SilkRoad or
	                 another addon). Account-wide, to respect the server's
	                 15-minute limit across characters and reloads.
	  recentLookups  { itemID, ... } most recent first, at most 20 (Price Database page)
	  vendorPrices   [itemID] = { price = copper per unit, seen = time() }
	                 What merchants charge. Vendor prices are the same everywhere.
	  recipes        [recipeID] = {
	                   recipeID, name, icon,
	                   skillLineID  = number,
	                   outputItemID = number | nil (enchants have no item),
	                   quantityMin, quantityMax,
	                   reagents     = { { itemID = n, count = n }, ... },
	                 }
	                 Recipes read from a profession window that the generated
	                 game data (Data/<Flavor>/Recipes.lua) doesn't have.
	                 Shared by all characters.
	  buyLists       { nextID = n, lists = { [id] = { id, name, created = time(),
	                   items = { { itemID, quantity }, ... } } } }
	                 Buy lists (Core/BuyLists.lua), shared by all characters.
	  recipeColors   [recipeID] = { yellowMin, yellowMax, greenMin, greenMax, grayMin, grayMax,
	                 skillUps }: what the professions window's colours proved about a
	                 recipe's skill-up thresholds (Recipes:GetSkillLevels)
	  favoriteRecipes [recipeID] = true, favorite recipes: the game's own favorites of
	                 learned recipes, mirrored, plus favorites of recipes not learned yet

	SilkRoadCharDB (per character)
	  schemaVersion  number
	  knownRecipes   [recipeID] = true
	  scannedProfessions [skillLineID] = time() the profession window was last read
]]
local _, SR = ...
local Util = SR.Util

local DB = SR:NewComponent("DB")

local SCHEMA_VERSION = 1

DB.ACCOUNT_DEFAULTS = {
	settings = {
		debug = false,
		minimap = {
			hide = false,
			angle = 200, -- degrees around the minimap, 0 = east
		},
		window = {
			width = 1180,
			height = 600,
			scale = 1,
			lastPage = "overview",
			-- point = { point, relativePoint, x, y } once the window is moved
		},
		auctionCutPercent = 5,
		priceSource = "auto", -- "auto" or a price provider id (see Core/Prices.lua)
		autoScan = true,      -- full auction scan when the AH opens (at most every 15 minutes)
		tooltipMode = "single", -- prices in item tooltips: "off" | "single" | "stack" | "both"
		tooltipRecipes = "learned", -- recipes using the item in its tooltip: "off" | "favorites" | "learned" | "all"
		professionPrices = true, -- costs, prices and profits under the reagents in the professions window
		settingsTab = "general", -- last tab shown on the Settings page
		guide = {
			profession = nil,         -- skillLineID last shown on the Leveling Guide page
			availability = "trainer", -- see Planner.AVAILABILITY
			resale = "vendor",        -- see Planner.RESALE
			target = nil,             -- target skill; nil = the profession's current maximum
		},
		recipes = {
			profession = nil,  -- skillLineID last shown on the Recipes page
			knownOnly = false,
		},
		buyLists = {
			selected = nil,    -- id of the list last shown (Buy Lists page and auction house tab)
		},
	},
	markets = {},
	scanner = {},
	recentLookups = {},
	vendorPrices = {},
	recipes = {},
	buyLists = {},
	favoriteRecipes = {},
	recipeColors = {},
}

DB.CHARACTER_DEFAULTS = {
	knownRecipes = {},
	scannedProfessions = {},
}

-- Schema upgrades: migrations[n] turns a version n-1 table into version n.
local accountMigrations = {}
local characterMigrations = {}

local function Migrate(db, migrations)
	local version = db.schemaVersion or SCHEMA_VERSION
	while version < SCHEMA_VERSION do
		version = version + 1
		if migrations[version] then
			migrations[version](db)
		end
	end
	db.schemaVersion = SCHEMA_VERSION
end

function DB:OnInitialize()
	if type(SilkRoadDB) ~= "table" then
		SilkRoadDB = {}
	end
	if type(SilkRoadCharDB) ~= "table" then
		SilkRoadCharDB = {}
	end

	Migrate(SilkRoadDB, accountMigrations)
	-- 0.7.0 had an on/off switch for tooltip prices; it became a mode.
	local settings = SilkRoadDB.settings
	if type(settings) == "table" and settings.tooltipPrices ~= nil then
		settings.tooltipMode = settings.tooltipMode or (settings.tooltipPrices == false and "off" or "single")
		settings.tooltipPrices = nil
	end
	Migrate(SilkRoadCharDB, characterMigrations)
	Util.CopyDefaults(SilkRoadDB, self.ACCOUNT_DEFAULTS)
	Util.CopyDefaults(SilkRoadCharDB, self.CHARACTER_DEFAULTS)

	self.global = SilkRoadDB
	self.char = SilkRoadCharDB
	self.settings = SilkRoadDB.settings
end

---------------------------------------------------------------------------
-- Markets
---------------------------------------------------------------------------

-- Which auction house's prices to use: see SR.Game.GetAuctionHouseKey.
-- The last known key stands in while the game can't say (early on login).
function DB:GetMarketKey()
	local key = SR.Game.GetAuctionHouseKey()
	if key then
		self.global.lastMarketKey = key
		return key
	end
	return self.global.lastMarketKey or "Unknown"
end

-- Prices scanned before Forever's regional realms were filed under the
-- realm's name ("CAMWOW EU4 Realm 6 PvP"). The first time a regional
-- auction house ("PvP Horde") has no prices, the most recent realm with the
-- same ruleset passes its prices on, so they aren't lost.
function DB:AdoptRealmMarket(key)
	local ruleset = key:match("^(%S+) ")
	if not ruleset then
		return nil
	end
	local bestKey, best
	for otherKey, market in pairs(self.global.markets) do
		local lastWord = otherKey:match("(%S+)$")
		if otherKey ~= key and otherKey:find(" ", 1, true) and otherKey:find("%d") -- realm names, not "PvE Alliance"
			and lastWord and lastWord:lower() == ruleset:lower() and market.lastScan
			and (not best or market.lastScan > best.lastScan) then
			bestKey, best = otherKey, market
		end
	end
	if best then
		self.global.markets[bestKey] = nil
		SR:Print(SR.L["Auction prices scanned on %s now belong to %s, the auction house shared by your realm group."]:format(bestKey, key))
	end
	return best
end

function DB:GetMarket()
	local key = self:GetMarketKey()
	local market = self.global.markets[key]
	if not market then
		market = self:AdoptRealmMarket(key) or { auction = {} }
		self.global.markets[key] = market
	end
	return market
end

---------------------------------------------------------------------------
-- Settings, addressed by dotted path: "auctionCutPercent", "minimap.hide"
---------------------------------------------------------------------------

local function Resolve(path)
	local node = DB.settings
	local parentNode, lastKey
	for key in path:gmatch("[^%.]+") do
		if lastKey then
			node = node[lastKey]
			assert(type(node) == "table", "SilkRoad: invalid setting path " .. path)
		end
		parentNode, lastKey = node, key
	end
	return parentNode, lastKey
end

function SR:GetSetting(path)
	local node, key = Resolve(path)
	return node[key]
end

function SR:SetSetting(path, value)
	local node, key = Resolve(path)
	if node[key] == value then
		return
	end
	node[key] = value
	self:Fire("SETTING_CHANGED", path, value)
end

function DB:ResetWindowLayout()
	local window = self.settings.window
	local defaults = self.ACCOUNT_DEFAULTS.settings.window
	window.point = nil
	window.width = defaults.width
	window.height = defaults.height
	window.scale = defaults.scale
end

---------------------------------------------------------------------------
-- Wiping data (Settings > Data)
---------------------------------------------------------------------------

local function Clear(tbl)
	for key in pairs(tbl) do
		tbl[key] = nil
	end
end

-- What each wipe would remove, for the Settings page.
function DB:GetDataSummary()
	local auctionPrices, realms = 0, 0
	for _, market in pairs(self.global.markets) do
		local count = Util.CountKeys(market.auction)
		if count > 0 then
			realms = realms + 1
			auctionPrices = auctionPrices + count
		end
	end
	return {
		auctionPrices = auctionPrices,
		realms = realms,
		vendorPrices = Util.CountKeys(self.global.vendorPrices),
	}
end

-- Auction prices from every scan, on every auction house. The scanner's
-- last-request time stays: the server's 15-minute limit doesn't reset with
-- SilkRoad's data.
function DB:WipeAuctionData()
	Clear(self.global.markets)
	SR:Fire("PRICES_UPDATED")
end

-- Merchant prices recorded at vendors, which are also SilkRoad's list of
-- items sold by vendors. (What vendors pay for items comes from the game's
-- own item data and isn't stored.)
function DB:WipeMerchantData()
	Clear(self.global.vendorPrices)
	SR:Fire("PRICES_UPDATED")
end

-- Both of the above.
function DB:WipeMarketData()
	self:WipeAuctionData()
	self:WipeMerchantData()
end

-- Every setting back to its default. Done in place, so code holding the
-- settings table keeps working; listeners are told about each setting.
local SETTING_PATHS = { "minimap.hide", "minimap.angle", "window.scale", "auctionCutPercent", "priceSource", "autoScan", "tooltipMode", "tooltipRecipes", "professionPrices", "debug" }

function DB:ResetSettings()
	Clear(self.settings)
	Util.CopyDefaults(self.settings, self.ACCOUNT_DEFAULTS.settings)
	for _, path in ipairs(SETTING_PATHS) do
		SR:Fire("SETTING_CHANGED", path, SR:GetSetting(path))
	end
end

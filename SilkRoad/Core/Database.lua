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
	  scanner        { lastRequest = time() | nil }
	                 When the last full scan was requested (by SilkRoad or
	                 another addon). Account-wide, to respect the server's
	                 15-minute limit across characters and reloads.
	  vendorPrices   [itemID] = { price = copper per unit, seen = time() }
	                 What merchants charge. Vendor prices are the same everywhere.
	  recipes        [recipeID] = {
	                   recipeID, name, icon,
	                   profession   = localized profession name,
	                   skillLineID  = number,
	                   outputItemID = number | nil (enchants have no item),
	                   quantityMin, quantityMax,
	                   reagents     = { { itemID = n, quantity = n }, ... },
	                 }
	                 Recipe definitions are shared by all characters.

	SilkRoadCharDB (per character)
	  schemaVersion  number
	  knownRecipes   [recipeID] = true
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
			width = 960,
			height = 600,
			scale = 1,
			lastPage = "overview",
			-- point = { point, relativePoint, x, y } once the window is moved
		},
		auctionCutPercent = 5,
		priceSource = "auto", -- "auto" or a price provider id (see Core/Prices.lua)
		autoScan = true,      -- full auction scan when the AH opens (at most every 15 minutes)
	},
	markets = {},
	scanner = {},
	vendorPrices = {},
	recipes = {},
}

DB.CHARACTER_DEFAULTS = {
	knownRecipes = {},
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

function DB:GetMarketKey()
	return GetRealmName() or "Unknown"
end

function DB:GetMarket()
	local key = self:GetMarketKey()
	local market = self.global.markets[key]
	if not market then
		market = { auction = {} }
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

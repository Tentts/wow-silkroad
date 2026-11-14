--[[ Smoke-test scenario, run by smoke_test.py after the mock client and the
	addon files are loaded. It drives SilkRoad the way a player would and
	checks the results. Any Lua error or failed check fails the run.
]]
local M = MOCK
local SR = SilkRoad
local checks = 0

local function check(condition, message)
	checks = checks + 1
	if not condition then
		error("check failed: " .. message, 2)
	end
end

local function step(name)
	M.output[#M.output + 1] = "== " .. name
end

local function CountOutput(text)
	local count = 0
	for _, line in ipairs(M.output) do
		if line:find(text, 1, true) then
			count = count + 1
		end
	end
	return count
end

local function OutputContains(text)
	for _, line in ipairs(M.output) do
		if line:find(text, 1, true) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
step("login")
M.FireEvent("ADDON_LOADED", "SomeOtherAddon")
check(SR.DB.global == nil, "other addons' ADDON_LOADED is ignored")
M.FireEvent("ADDON_LOADED", "SilkRoad")
check(type(SilkRoadDB) == "table" and SilkRoadDB.schemaVersion == 1, "account saved variables created")
check(type(SilkRoadCharDB) == "table" and SilkRoadCharDB.schemaVersion == 1, "character saved variables created")
check(SR:GetSetting("auctionCutPercent") == 5, "default auction cut")
check(SR:GetSetting("minimap.hide") == false, "nested default setting")
M.FireEvent("PLAYER_LOGIN")
check(SilkRoadMinimapButton ~= nil and SilkRoadMinimapButton:IsShown(), "minimap button created")
check(M.settingsRegistered, "options panel registered with Blizzard settings")
check(SR.version == "0.3.0", "version read from the TOC")

---------------------------------------------------------------------------
step("open window")
check(not SR.UI:IsShown(), "window starts hidden")
SlashCmdList.SILKROAD("")
check(SR.UI:IsShown(), "/silkroad opens the window")
check(SR.UI.currentPageID == "overview", "opens on the overview page")
check(SilkRoadMainFrame.PageTitle:GetText() == "Overview", "page title shown")
check(UISpecialFrames[1] == "SilkRoadMainFrame", "window closes with Escape")
local nav = SR.UI.navButtons
check(#nav == 5, "five pages in the sidebar")

---------------------------------------------------------------------------
step("overview")
local overview = SR.UI.pageFrames.overview
check(overview:IsVisible(), "overview visible")
local cards = nil
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "overview" then cards = page.cards end
end
check(SR.Recipes:CountAll() > 2000, "generated recipe data loaded")
check(cards.recipes.Value:GetText() == SR.Util.FormatNumber(SR.Recipes:CountAll()), "recipe count card")
check(cards.scan.Value:GetText() == "Never", "last scan card")

---------------------------------------------------------------------------
step("every page opens")
for _, page in ipairs(SR.UI:GetPages()) do
	SlashCmdList.SILKROAD(page.id)
	check(SR.UI.currentPageID == page.id, "page " .. page.id .. " selected")
	check(SR.UI.pageFrames[page.id]:IsVisible(), "page " .. page.id .. " visible")
	for otherID, frame in pairs(SR.UI.pageFrames) do
		if otherID ~= page.id then
			check(not frame:IsShown(), "page " .. otherID .. " hidden while " .. page.id .. " is open")
		end
	end
end
M.RunTimers()

---------------------------------------------------------------------------
step("recipes: every profession")
local recipesPage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "recipes" then recipesPage = page end
end
local function RowFor(recipeID)
	for _, row in ipairs(recipesPage.Table.rows) do
		if row.recipe.id == recipeID then return row end
	end
end
local function PickProfession(skillLine)
	for index, item in ipairs(recipesPage.ProfessionDropdown.__menu.items) do
		if item.data == nil and SR.Recipes:GetProfessions()[index].id == skillLine then
			M.PickDropdown(recipesPage.ProfessionDropdown, index)
			return
		end
	end
	error("profession not in the dropdown: " .. skillLine)
end

SR.UI:OpenPage("recipes")
local menu = recipesPage.ProfessionDropdown.__menu
check(#menu.items == #SR.StaticData.professions and #menu.items >= 9, "every profession is selectable")
local labels = {}
for _, item in ipairs(menu.items) do labels[#labels + 1] = item.text end
local allLabels = table.concat(labels, "|")
check(allLabels:find("Tailoring |cff808080(75/150)|r", 1, true), "learned professions show the character's skill")
check(allLabels:find("Alchemy |cff808080(not learned)|r", 1, true), "unlearned professions are marked")
check(recipesPage.skillLine == 333, "starts on the character's first profession (Enchanting)")

PickProfession(171) -- Alchemy, not learned
check(recipesPage.Status:GetText():find("You don't have this profession.", 1, true), "red notice for professions the character lacks")
check(#recipesPage.Table.rows > 100, "an unlearned profession still lists its recipes")
check(not recipesPage.KnownOnly:IsEnabled(), "'Known only' is off for unlearned professions")

step("recipes: values")
local market = SR.DB:GetMarket()
market.auction[2589] = { price = 50, quantity = 200, seen = time() - 120 }  -- Linen Cloth
market.auction[2996] = { price = 300, quantity = 40, seen = time() - 120 }  -- Bolt of Linen Cloth
market.auction[4306] = { price = 400, quantity = 10, seen = time() - 7200 } -- Silk Cloth
market.lastScan = time() - 120
SR.DB.global.vendorPrices[2320] = { price = 10, seen = time() }   -- Coarse Thread, recorded at a merchant
SR.DB.global.vendorPrices[4306] = { price = 150, seen = time() }  -- Silk Cloth, cheap at a vendor
PickProfession(197) -- Tailoring
SR:Fire("PRICES_UPDATED")
M.RunTimers()
check(SR.DB.settings.recipes.profession == 197, "the chosen profession is remembered")
check(recipesPage.Status:GetText():find("Open your Tailoring window once", 1, true), "asks to open the profession window")

local bolt = RowFor(2963) -- Bolt of Linen Cloth: 2 Linen Cloth, learned with the profession
check(bolt.name == "Bolt of Linen Cloth" and bolt.itemID == 2996, "name and product from the game data")
check(bolt.cost == 100, "cost = 2 x 50c Linen Cloth from the auction house")
check(bolt.auctionPrice == 300, "AH price of the product")
check(bolt.vendorPrice == SR.StaticData.items[2996][4], "vendor price from the game data, no item loading")
check(bolt.profit == 285 - 100, "profit = auction price after the 5% cut - cost")
check(bolt.source == "Learned with the profession", "auto-learned recipes say so")
check(bolt.levelText == "|cff808080" .. "1|r", "skill level coloured grey: Tailoring 75 is past its grey threshold")

local belt = RowFor(8776) -- Linen Belt: Bolt of Linen Cloth + Coarse Thread, from a trainer
check(belt.cost == 300 + 10, "cost mixes auction (bolt) and recorded vendor (thread) prices")
check(belt.profit == belt.vendorPrice - 310, "no auction price: profit uses the vendor price")
check(belt.source == "Trainer", "trainer recipes")
check(belt.levelText == "|cff40c040~50|r", "approximate trainer requirement, coloured green for skill 75")

local itemRecipe
for _, row in ipairs(recipesPage.Table.rows) do
	if row.recipe.recipeItem and not itemRecipe then itemRecipe = row end
end
local recipeItemName = SR.StaticData.items[itemRecipe.recipe.recipeItem][1]
check(itemRecipe.source == "Recipe: " .. recipeItemName, "without QuestieDB the recipe item is named")

step("recipes: sorting, search and tooltips")
check(recipesPage.Table.ScrollBox.__active[1].row.profit ~= nil, "sorted by profit, most profitable first")
recipesPage.Search:SetText("bolt of linen")
check(recipesPage.Count:GetText():match("^1 of %d+ recipes$"), "search filters rows")
local rowFrame = recipesPage.Table.ScrollBox.__active[1]
M.RunScript(rowFrame, "OnEnter")
M.RunScript(rowFrame, "OnLeave")
M.modifiedClick = true
M.Click(rowFrame)
check(M.lastModifiedLink and M.lastModifiedLink:find("item:"), "shift-click links the crafted item")
M.modifiedClick = false
recipesPage.Search:SetText("")

step("recipes: 'Known only' before the profession window is read")
check(not recipesPage.KnownOnly:IsEnabled(), "'Known only' disabled until the window has been read")
check(recipesPage.KnownOnly.__scripts.OnEnter ~= nil, "its tooltip explains why")
SR.DB.settings.recipes.knownOnly = true
recipesPage.Table:Refresh()
check(not recipesPage.Count:GetText():match("^0 of"), "a saved 'Known only' doesn't empty the list while unavailable")
SR.DB.settings.recipes.knownOnly = false
recipesPage.Table:Refresh()

step("recipes: reading the profession window")
-- Forever's window: the child profession (ID 2830) names Tailoring (197) as its parent.
M.tradeSkill = { professionID = 197, name = "Tailoring", recipes = { [2963] = true, [8776] = false, [999001] = true } }
M.schematics[999001] = {
	name = "Silkroad Test Robe", icon = 132149, outputItemID = 4306, quantityMin = 1, quantityMax = 1,
	reagentSlotSchematics = {
		{ required = true, quantityRequired = 3, reagents = { { itemID = 2589 } } },
		{ required = false, quantityRequired = 1, reagents = { { itemID = 2320 } } }, -- optional: ignored
	},
}
M.FireEvent("TRADE_SKILL_SHOW")
M.FireEvent("TRADE_SKILL_LIST_UPDATE")
M.RunTimers()
check(SR.DB.char.knownRecipes[2963] and not SR.DB.char.knownRecipes[8776], "learned recipes recorded for the character")
check(SR.DB.char.scannedProfessions[197] == time(), "profession marked as read")
check(SR.DB.global.recipes[999001] and #SR.DB.global.recipes[999001].reagents == 1, "recipes missing from the game data are added from the window")
check(RowFor(999001) and RowFor(999001).cost == 150, "and priced like the rest (3 x 50c)")
check(recipesPage.Status:GetText():find("you know 2 of", 1, true), "status counts known recipes")
check(RowFor(8776).known == false, "unknown recipes marked")
check(recipesPage.KnownOnly:IsEnabled(), "'Known only' enabled once the window has been read")
M.Click(recipesPage.KnownOnly)
check(recipesPage.Count:GetText():match("^2 of %d+ recipes$"), "'Known only' shows just the learned ones")
M.Click(recipesPage.KnownOnly)
check(not recipesPage.Count:GetText():match("^2 of"), "unchecking shows everything again")

-- A window that only gives a name still maps to the right profession.
M.tradeSkill = { professionID = nil, childID = 3000, name = "Enchanting", recipes = { [7421] = true } }
M.FireEvent("TRADE_SKILL_LIST_UPDATE")
M.RunTimers()
check(SR.DB.char.scannedProfessions[333] == time() and SR.DB.char.knownRecipes[7421], "profession matched by name")

-- Nothing to read: explained in debug output, nothing recorded.
SR:SetSetting("debug", true)
M.tradeSkill = { professionID = 164, name = "Blacksmithing", recipes = {} }
M.FireEvent("TRADE_SKILL_LIST_UPDATE")
M.RunTimers()
check(SR.DB.char.scannedProfessions[164] == nil and OutputContains("Profession window not read: the profession window has no recipes yet"),
	"an empty window isn't recorded, and debug output says why")
SR:SetSetting("debug", false)
M.tradeSkill = nil

step("recipes: sources from QuestieDB")
local recipeItem = itemRecipe.recipe.recipeItem
local npcs = {
	[3364] = { name = "Borya", subName = "Tailoring Supplies", spawns = { [1637] = { { 63.0, 51.0 } } }, friendlyToFaction = "H" },
	[1347] = { name = "Alexandra Bolero", subName = "Tailoring Supplies", spawns = { [1519] = { { 43.0, 74.0 } } }, friendlyToFaction = "A" },
	[3836] = { name = "Mountaineer Pebblebitty", spawns = { [17] = { { 50.0, 50.0 } } }, friendlyToFaction = "AH" },
}
rawset(_G, "LibQuestieDB", {
	RequireContract = function(version) return version == 4 end,
	Item = { Get = function(id, key)
		if id == recipeItem and key == "vendors" then return { 1347, 3364 } end
		if id == recipeItem and key == "npcDrops" then return { 3836 } end
		if id == 2321 and key == "vendors" then return { 3364 } end -- Fine Thread
	end },
	Npc = { Get = function(id, key) return npcs[id] and npcs[id][key] end },
	Quest = { Get = function() return nil end },
	Object = { Get = function() return nil end },
})
rawset(_G, "QuestieLoader", { ImportModule = function(_, name)
	assert(name == "ZoneDB", "unexpected Questie module")
	return { GetUiMapIdByAreaId = function(_, areaID) return areaID == 1637 and 85 or nil end }
end })
SR.Sources:ResetCache()
SR.UI:RefreshCurrentPage()
itemRecipe = RowFor(itemRecipe.recipe.id)
check(itemRecipe.source == "Vendor: Borya (+1)", "vendors listed, own faction first")
check(SR.Prices:GetVendorBuyPrice(2321) == SR.StaticData.items[2321][5] / SR.StaticData.items[2321][6],
	"vendor-sold reagents priced from the game data")
check(select(2, SR.Prices:GetVendorBuyPrice(2321)) == "data", "and say where the price comes from")
check(SR.Prices:GetVendorBuyPrice(2589) == nil, "items no vendor sells have no vendor price")

step("recipes: obtained-at window and waypoints")
for _, frame in ipairs(recipesPage.Table.ScrollBox.__active) do
	if frame.row == itemRecipe then rowFrame = frame end
end
M.RunScript(rowFrame.cells[3].Button, "OnEnter")
M.Click(rowFrame.cells[3].Button)
local popup = SilkRoadSourceFrame
check(popup:IsShown() and popup.__title == itemRecipe.name, "clicking 'Obtained at' opens the sources window")
local sourceRows = popup.Table.rows
check(#sourceRows == 3 and sourceRows[1].source.name == "Borya", "every source listed, friendly vendors first")
check(sourceRows[1].location == "Orgrimmar (63.0, 51.0)", "zone and coordinates")
check(sourceRows[2].source.hostile, "other-faction vendor flagged")
check(sourceRows[3].kindLabel == "Drop" and sourceRows[3].location == "The Barrens (50.0, 50.0)", "drops listed too")
M.Click(popup.Table.ScrollBox.__active[1])
local waypoint = M.waypoints[#M.waypoints]
check(waypoint and waypoint.uiMapID == 85 and math.abs(waypoint.x - 0.63) < 1e-9, "clicking a source sets a waypoint")
check(OutputContains("Waypoint set: Borya"), "waypoint confirmed in chat")
rawset(_G, "TomTom", { AddWaypoint = function(self, mapID, x, y, options)
	M.tomtom = { mapID = mapID, x = x, y = y, title = options.title }
end })
M.Click(popup.Table.ScrollBox.__active[1])
check(M.tomtom and M.tomtom.mapID == 85 and M.tomtom.title == "Borya", "TomTom used when installed")
rawset(_G, "TomTom", nil)
popup:Hide()
rawset(_G, "LibQuestieDB", nil)
rawset(_G, "QuestieLoader", nil)
SR.Sources:ResetCache()

---------------------------------------------------------------------------
step("vendor flips")
SR.UI:OpenPage("flips")
local flipsPage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "flips" then flipsPage = page end
end
check(flipsPage.Count:GetText() == "1 of 2 items", "only profitable flips by default")
local silk = flipsPage.Table.ScrollBox.__active[1].row
check(silk.itemID == 4306 and silk.profit == 380 - 150, "silk flip profit uses the net auction price")
M.Click(flipsPage.ProfitableOnly)
check(flipsPage.Count:GetText() == "2 of 2 items", "unchecking shows every vendor item")

---------------------------------------------------------------------------
step("price database")
SR.UI:OpenPage("prices")
local pricesPage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "prices" then pricesPage = page end
end
check(pricesPage.Panel.Hint:IsShown(), "lookup hint before any search")
pricesPage.Input:SetText("2589")
M.RunScript(pricesPage.Input, "OnEnterPressed")
check(pricesPage.itemID == 2589, "lookup by item ID")
check(pricesPage.lines.vendorSell.Value:GetText() == "0g 0s 13c", "vendor sell price shown")
check(pricesPage.lines["provider:silkroad"].Value:GetText():find("0g 0s 50c", 1, true), "own scan price shown")
check(pricesPage.lines["provider:auctionator"].Value:GetText():find("Not installed", 1, true), "Auctionator reported missing")
pricesPage:Lookup("Hearthstone")
check(pricesPage.itemID == 6948, "lookup by cached item name")
check(pricesPage.lines.vendorSell.Value:GetText():find("Can't be sold", 1, true), "unsellable items say so")
pricesPage:Lookup("Not A Real Item")
check(pricesPage.lookupFailed and pricesPage.Panel.Hint:IsShown(), "unknown names explain the failure")

step("shift-click into the lookup box")
pricesPage.Input:SetFocus()
ChatFrameUtil.InsertLink("|cffffffff|Hitem:2996::::::::60:::::|h[Bolt of Linen Cloth]|h|r")
check(pricesPage.itemID == 2996, "linked item looked up")
pricesPage.Input:ClearFocus()

step("items that are still loading")
M.items[60001] = { name = "Test Cloak", quality = 1, icon = 132492, sellPrice = 50 } -- not in the generated data
M.pendingItems[60001] = true
pricesPage:Lookup(60001)
check(pricesPage.Panel.Name:GetText() == "Loading item data...", "loading placeholder")
M.RunTimers() -- delivers GET_ITEM_INFO_RECEIVED, then the debounced refresh
M.RunTimers()
check(pricesPage.Panel.Name:GetText():find("Test Cloak", 1, true), "refreshes when the item arrives")

step("item data loaded by others doesn't refresh pages")
local originalRefresh = pricesPage.Refresh
local refreshes = 0
pricesPage.Refresh = function(...)
	refreshes = refreshes + 1
	return originalRefresh(...)
end
for itemID = 100001, 100500 do -- e.g. an auction scan or bags loading items
	M.FireEvent("GET_ITEM_INFO_RECEIVED", itemID, true)
end
M.RunTimers()
check(refreshes == 0, "500 unrelated item loads cause no refresh")
pricesPage.Refresh = originalRefresh

step("recent lookups instead of the full scan data")
check(pricesPage.Summary:GetText() == "SilkRoad scan data on Test Realm: 3 items, last scan 2 min ago.", "scan data summarised in one line")
local recent = SR.DB.global.recentLookups
check(table.concat(recent, ",") == "60001,2996,6948,2589", "lookups remembered, most recent first, failed ones skipped")
check(#pricesPage.Table.rows == 4 and pricesPage.Table.rows[1].itemID == 60001, "recent lookups listed in order")
check(pricesPage.Table.rows[3].price == nil and pricesPage.Table.rows[4].price == 50, "rows show the scanned price when there is one")
pricesPage:Lookup(2589)
check(table.concat(recent, ",") == "2589,60001,2996,6948", "looking an item up again moves it to the top")
M.Click(pricesPage.Table.ScrollBox.__active[3])
check(pricesPage.itemID == 2996 and recent[1] == 2996, "clicking a recent row looks it up")
for itemID = 50001, 50025 do
	M.items[itemID] = { name = "Test Item " .. itemID, quality = 1, icon = 134400, sellPrice = 1 }
	pricesPage:Lookup(itemID)
end
check(#recent == 20 and recent[1] == 50025, "at most 20 recent lookups kept")
for itemID = 50001, 50025 do
	M.items[itemID] = nil
end
for i = #recent, 1, -1 do
	recent[i] = nil
end

---------------------------------------------------------------------------
step("Auctionator integration")
rawset(_G, "Auctionator", { API = { v1 = {
	GetAuctionPriceByItemID = function(caller, itemID)
		assert(caller == "SilkRoad", "Auctionator caller ID")
		if itemID == 2320 then return 30 end
		if itemID == 2589 then return 70 end
	end,
	GetAuctionAgeByItemID = function(caller, itemID)
		return itemID == 2320 and 0 or 3
	end,
} } })
local price, source = SR.Prices:GetAuctionPrice(2320)
check(price == 30 and source == "auctionator", "falls back to Auctionator when own scans lack a price")
price, source = SR.Prices:GetAuctionPrice(2589)
check(price == 50 and source == "silkroad", "auto prefers own scans")
SR:SetSetting("priceSource", "auctionator")
price, source = SR.Prices:GetAuctionPrice(2589)
check(price == 70 and source == "auctionator", "preferred source wins when it has a price")
check(SR.Prices:GetProvider("auctionator"):GetAgeText(2320) == "seen today", "Auctionator age text")
_G.Auctionator.API.v1.GetAuctionPriceByItemID = function() error("broken addon") end
price, source = SR.Prices:GetAuctionPrice(2589)
check(price == 50 and source == "silkroad", "a failing Auctionator call falls back safely")
SR:SetSetting("priceSource", "auto")
rawset(_G, "Auctionator", nil)

---------------------------------------------------------------------------
step("settings")
SR.UI:OpenPage("settings")
local settingsPage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "settings" then settingsPage = page end
end
local minimapCheck, scaleSlider, cutSlider, sourceDropdown = unpack(settingsPage.controls)
check(minimapCheck:GetChecked() == true, "minimap checkbox reflects the setting")
M.Click(minimapCheck)
check(SR:GetSetting("minimap.hide") == true and not SilkRoadMinimapButton:IsShown(), "minimap button hidden")
M.Click(minimapCheck)
check(SilkRoadMinimapButton:IsShown(), "minimap button shown again")
scaleSlider.Slider:SetValue(1.2500001)
check(SR:GetSetting("window.scale") == 1.25, "scale slider stores a rounded value")
cutSlider.Slider:SetValue(3)
check(SR:GetSetting("auctionCutPercent") == 3, "auction cut slider")
M.RunTimers()
M.PickDropdown(sourceDropdown, 3)
check(SR:GetSetting("priceSource") == "auctionator", "price source dropdown")
M.PickDropdown(sourceDropdown, 1)
check(SR:GetSetting("priceSource") == "auto", "price source back to automatic")

---------------------------------------------------------------------------
step("launchers")
SR.UI:Hide()
SilkRoad_OnAddonCompartmentClick("SilkRoad", "LeftButton")
check(SR.UI:IsShown(), "compartment left-click opens")
SilkRoad_OnAddonCompartmentClick("SilkRoad", "LeftButton")
check(not SR.UI:IsShown(), "compartment left-click closes")
SilkRoad_OnAddonCompartmentClick("SilkRoad", "RightButton")
check(SR.UI.currentPageID == "settings", "compartment right-click opens settings")
SilkRoad_OnAddonCompartmentEnter("SilkRoad", UIParent)
SilkRoad_OnAddonCompartmentLeave("SilkRoad", UIParent)
M.Click(SilkRoadMinimapButton, "LeftButton")
check(not SR.UI:IsShown(), "minimap button toggles")
M.RunScript(SilkRoadMinimapButton, "OnDragStart")
M.RunScript(SilkRoadMinimapButton, "OnUpdate")
M.RunScript(SilkRoadMinimapButton, "OnDragStop")
-- The mock minimap centre is (1000, 700) and the cursor (1100, 800): 45 degrees.
check(math.abs(SR:GetSetting("minimap.angle") - 45) < 0.01, "dragging stores the angle")

step("window geometry")
SR.UI:Show()
M.RunScript(SilkRoadMainFrame, "OnDragStop")
check(SR.DB.settings.window.point ~= nil, "position saved after moving")
SlashCmdList.SILKROAD("reset")
check(SR.DB.settings.window.point == nil and SR.DB.settings.window.scale == 1, "reset restores defaults")

step("Blizzard options panel")
local panel = M.settingsCategory.frame
check(panel ~= nil, "options panel frame registered")

step("slash commands")
SlashCmdList.SILKROAD("help")
check(OutputContains("/silkroad minimap"), "help lists commands")
check(OutputContains("/silkroad scan"), "help lists the scan command")
SlashCmdList.SILKROAD("version")
check(OutputContains("0.3.0"), "version command")
SlashCmdList.SILKROAD("bogus")
check(OutputContains("Unknown command:"), "unknown commands are reported")
SlashCmdList.SILKROAD("debug")
check(SR:GetSetting("debug") == true, "debug toggled on")
SR:Debug("hello")
check(OutputContains("hello"), "debug output printed")
SlashCmdList.SILKROAD("debug")
SlashCmdList.SILKROAD("minimap")
check(not SilkRoadMinimapButton:IsShown(), "/silkroad minimap hides the button")
SlashCmdList.SILKROAD("  MINIMAP  ")
check(SilkRoadMinimapButton:IsShown(), "commands are case- and space-insensitive")

step("escape closes")
SR.UI:Show()
SilkRoadMainFrame:Hide()
check(not SR.UI:IsShown(), "hidden by the client")
SR.UI:Toggle()
check(SR.UI:IsShown() and SR.UI.currentPageID == "settings", "reopens on the last page")
SR.UI:Hide()

---------------------------------------------------------------------------
step("auction house tab")
local LibAHTab = LibStub("LibAHTab-1-0")
check(not LibAHTab:DoesIDExist("SilkRoad"), "no tab before the auction house UI loads")
M.LoadAuctionHouseUI()
check(LibAHTab:DoesIDExist("SilkRoad"), "tab created when Blizzard_AuctionHouseUI loads")
local ahPanel = SilkRoadAuctionHousePanel
check(not ahPanel:IsShown(), "tab content starts hidden")

step("automatic scan when the auction house opens")
M.replicate = {
	{ 2589, 20, 900 },  -- Linen Cloth, 45c each
	{ 2589, 5, 300 },   -- Linen Cloth, 60c each
	{ 4306, 1, 380 },   -- Silk Cloth, 380c
	{ 4306, 10, 4500 }, -- Silk Cloth, 450c each
	{ 2589, 3, 0 },     -- bid only: ignored
	{ 4306, 0, 100 },   -- no quantity: ignored
	{ 99999, 1, 5 },    -- an item that doesn't exist: ignored
}
for i = 1, 2500 do -- enough listings to need several batches
	M.replicate[#M.replicate + 1] = { 2320, 1, 20 + (i % 7) } -- Coarse Thread, 20-26c
end
local scanStartedAt = time()
M.OpenAuctionHouse()
check(SR.Scanner.isAuctionHouseOpen, "scanner knows the auction house is open")
check(M.replicateRequests == 0, "the automatic scan waits a moment after opening")
M.RunTimers()
check(M.replicateRequests == 1, "one full scan requested automatically")
local market = SR.DB:GetMarket()
local auction = market.auction
check(auction[2589].price == 45 and auction[2589].quantity == 25, "lowest unit buyout and total quantity")
check(auction[4306].price == 380 and auction[4306].quantity == 11, "a single cheap listing sets the lowest price")
check(auction[2320].price == 20 and auction[2320].quantity == 2500, "listings spread over several batches")
check(auction[99999] == nil, "items that don't exist are ignored")
check(auction[2996].price == 300 and auction[2996].quantity == 0, "items missing from the scan keep their price with quantity 0")
check(market.lastScan == scanStartedAt, "scan time saved")
check(market.lastScanStats.items == 3 and market.lastScanStats.listings == 2504, "scan statistics saved")
check(OutputContains("Auction scan complete: 3 items from 2,504 auctions"), "completion reported in chat")
check(SR.Prices:GetAuctionPrice(2589) == 45, "the price layer serves the new prices")
check(SR.Scanner:GetCooldownRemaining() == 900, "the 15-minute cooldown starts")
-- The client sent the result event three times for that one request.
check(CountOutput("Auction scan complete") == 1, "repeated result events don't start another pass")
check(not OutputContains("started by another addon"), "repeated result events aren't mistaken for another addon's scan")
check(SR.Scanner.state == "idle", "scanner idle after the scan")
M.FireEvent("REPLICATE_ITEM_LIST_UPDATE")
M.RunTimers()
check(SR.Scanner.state == "idle" and CountOutput("Auction scan complete") == 1, "stray result events while idle are ignored")

step("the 15-minute limit")
M.CloseAuctionHouse()
M.Advance(300)
M.OpenAuctionHouse()
M.RunTimers()
check(M.replicateRequests == 1, "no automatic scan within 15 minutes")
SlashCmdList.SILKROAD("scan")
check(M.replicateRequests == 1, "no manual scan within 15 minutes either")
check(OutputContains("Next full scan available in 10:00."), "the manual scan explains the wait")
LibAHTab:SetSelected("SilkRoad")
check(ahPanel:IsVisible(), "selecting the tab shows SilkRoad's panel")
check(AuctionHouseFrame.__title == "SilkRoad", "auction house title follows the tab")
check(not ahPanel.ScanButton:IsEnabled(), "scan button disabled during the cooldown")
check(ahPanel.Cooldown:GetText() == "Next scan in 10:00", "countdown shown")
check(ahPanel.LastScan:GetText() == "Last scan: 5 min ago", "last scan time shown")
check(ahPanel.ScanDetail:GetText() == "3 items from 2,504 auctions on Test Realm", "scan statistics shown")
check(ahPanel.AutoScan:GetChecked(), "automatic scan checkbox reflects the setting")
M.Advance(600)
M.RunScript(ahPanel, "OnUpdate", 1)
check(ahPanel.ScanButton:IsEnabled() and ahPanel.Cooldown:GetText():find("Ready to scan", 1, true), "ready again after 15 minutes")

step("manual scan from the tab")
M.replicate[1] = { 2589, 20, 800 } -- Linen Cloth now 40c
M.Click(ahPanel.ScanButton)
check(SR.Scanner.state == "waiting" and ahPanel.Progress:IsShown(), "progress shown while waiting for the server")
check(ahPanel.Progress.Text:GetText() == "Waiting for the auction house...", "waiting text")
M.RunTimers()
check(M.replicateRequests == 2 and auction[2589].price == 40, "manual scan updates prices")
check(not ahPanel.Progress:IsShown() and not ahPanel.ScanButton:IsEnabled(), "progress hidden and cooldown restarted")

step("closing the auction house cancels a scan")
M.Advance(900)
check(SR.Scanner:StartScan(false), "scan started")
M.CloseAuctionHouse()
check(SR.Scanner.state == "idle" and OutputContains("Auction scan cancelled"), "scan cancelled on close")
M.replicate[1] = { 2589, 20, 600 }
M.RunTimers() -- the server's late answer arrives after closing and is ignored
check(auction[2589].price == 40, "a cancelled scan saves nothing")
SR.Scanner:StartScan(false)
check(OutputContains("Open the auction house to scan it."), "scanning needs the auction house open")

step("no answer from the server")
M.Advance(900)
M.ahThrottled = true
M.OpenAuctionHouse()
M.RunTimers() -- the automatic request gets no answer
check(M.replicateRequests == 4 and SR.Scanner.state == "waiting", "still waiting shortly after the request")
M.Advance(121)
check(SR.Scanner.state == "idle", "gives up after the timeout")
check(OutputContains("didn't send scan results"), "explains why")
M.ahThrottled = false

step("full scans started by other addons are recorded")
M.Advance(60)
local completedBefore = CountOutput("Auction scan complete")
C_AuctionHouse.ReplicateItems() -- e.g. Auctionator's full scan
check(SR.Scanner.state == "waiting" and OutputContains("started by another addon"), "another addon's request noticed")
M.RunTimers()
check(auction[2589].price == 30, "prices from another addon's scan saved")
check(CountOutput("Auction scan complete") == completedBefore + 1, "recorded once")
check(SR.Scanner:GetCooldownRemaining() == 900, "cooldown restarts after another addon's scan")
check(M.replicateRequests == 5, "SilkRoad sent no request of its own")
M.ahThrottled = true
M.Advance(900)
C_AuctionHouse.ReplicateItems() -- another addon's request that goes unanswered
M.Advance(121)
check(SR.Scanner.state == "idle", "an unanswered request from another addon times out")
check(CountOutput("didn't send scan results") == 1, "quietly: that addon reports its own failure")
M.ahThrottled = false

step("automatic scan can be turned off")
M.CloseAuctionHouse()
M.Advance(900)
M.Click(ahPanel.AutoScan)
check(SR:GetSetting("autoScan") == false, "checkbox turns automatic scans off")
M.OpenAuctionHouse()
M.RunTimers()
check(M.replicateRequests == 6, "no automatic scan when turned off")
SR:SetSetting("autoScan", true)

step("Auctionator's full scans count toward the cooldown")
M.CloseAuctionHouse()
M.Advance(900)
check(SR.Scanner:GetCooldownRemaining() == 0, "ready before Auctionator scans")
rawset(_G, "Auctionator", { SavedState = { TimeOfLastReplicateScan = time() - 60 } })
check(SR.Scanner:GetCooldownRemaining() == 840, "Auctionator's recent scan starts the cooldown")
M.OpenAuctionHouse()
M.RunTimers()
check(M.replicateRequests == 6, "SilkRoad doesn't send a second request")
rawset(_G, "Auctionator", { SavedState = "unexpected" })
check(SR.Scanner:GetCooldownRemaining() == 0, "unexpected Auctionator data is ignored")
rawset(_G, "Auctionator", nil)

step("Blizzard's tabs take over again")
LibAHTab:SetSelected("SilkRoad")
check(ahPanel:IsVisible(), "SilkRoad tab open")
AuctionHouseFrame:SetDisplayMode({ "AuctionsFrame" })
check(not ahPanel:IsShown(), "switching to a Blizzard tab hides SilkRoad's panel")
M.CloseAuctionHouse()

---------------------------------------------------------------------------
step("merchant prices are recorded")
M.merchant = {
	{ 2678, 40, 1 },        -- Mild Spices, 40c each
	{ 6260, 500, 5 },       -- Blue Dye, sold in fives for 5s
	{ 9999, 100, 1, true }, -- bought with tokens: skipped
}
M.FireEvent("MERCHANT_SHOW")
M.FireEvent("MERCHANT_UPDATE")
M.RunTimers()
local vendorPrices = SR.DB.global.vendorPrices
check(vendorPrices[2678].price == 40 and vendorPrices[2678].seen == time(), "merchant price recorded")
check(vendorPrices[6260].price == 100, "stacks recorded per item")
check(vendorPrices[9999] == nil, "token purchases skipped")
check(SR.Prices:GetVendorBuyPrice(2678) == 40 and select(2, SR.Prices:GetVendorBuyPrice(2678)) == "recorded", "recorded prices win")

M.RunTimers()
return checks

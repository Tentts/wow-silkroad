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
check(SR.version == "0.1.0", "version read from the TOC")

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
check(cards.recipes.Value:GetText() == "0", "recipe count card")
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
step("empty states")
local recipesPage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "recipes" then recipesPage = page end
end
SR.UI:OpenPage("recipes")
check(recipesPage.Table.Empty:IsShown(), "recipes empty state shown with no data")
check(recipesPage.Count:GetText() == "0 of 0 recipes", "recipe count label")

---------------------------------------------------------------------------
step("price data flows into the pages")
local market = SR.DB:GetMarket()
market.auction[2589] = { price = 50, quantity = 200, seen = time() - 120 }  -- Linen Cloth
market.auction[2996] = { price = 300, quantity = 40, seen = time() - 120 }  -- Bolt of Linen Cloth
market.auction[4306] = { price = 400, quantity = 10, seen = time() - 7200 } -- Silk Cloth
market.lastScan = time() - 120
SR.DB.global.vendorPrices[2320] = { price = 10, seen = time() }   -- Coarse Thread, AH unknown
SR.DB.global.vendorPrices[4306] = { price = 150, seen = time() }  -- Silk Cloth, cheap at a vendor
SR.DB.global.recipes[2963] = {
	recipeID = 2963, name = "Bolt of Linen Cloth", profession = "Tailoring", skillLineID = 197,
	outputItemID = 2996, quantityMin = 1, quantityMax = 1,
	reagents = { { itemID = 2589, quantity = 2 } },
}
SR.DB.global.recipes[8776] = {
	recipeID = 8776, name = "Linen Belt", profession = "Tailoring", skillLineID = 197,
	outputItemID = 7026, quantityMin = 1, quantityMax = 1,
	reagents = { { itemID = 2589, quantity = 6 }, { itemID = 9999, quantity = 1 } },
}
SR:Fire("PRICES_UPDATED")
M.RunTimers()

check(recipesPage.Count:GetText() == "2 of 2 recipes", "recipes listed")
local rows = recipesPage.Table.rows
local bolt
for _, row in ipairs(rows) do
	if row.recipeID == 2963 then bolt = row end
end
check(bolt.cost == 100, "material cost = 2 x 50c")
check(bolt.auctionValue == 285, "auction value after the 5% cut")
check(bolt.vendorValue == 25, "vendor value")
check(bolt.profit == 185, "profit = best sale - cost")
check(rows[1].recipeID == 2963, "sorted by profit, unknown profit last")
local belt = rows[2]
check(belt.cost == nil and belt.profit == nil, "missing reagent price leaves cost and profit empty")

step("sorting and filtering")
local profitHeader = recipesPage.Table.headerButtons[6]
M.Click(profitHeader)
check(recipesPage.Table.sortDesc == false, "clicking the active column flips direction")
check(recipesPage.Table.rows[1].recipeID == 2963, "nil profit still sorts last ascending")
M.Click(recipesPage.Table.headerButtons[1])
check(recipesPage.Table.sortKey == "name", "clicking another column sorts by it")
recipesPage.Search:SetText("bolt")
check(recipesPage.Count:GetText() == "1 of 2 recipes", "search filters rows")
recipesPage.Search:SetText("nothing like this")
check(recipesPage.Table.Empty:IsShown(), "no-match state when the filter hides everything")
recipesPage.Search:SetText("")
local menu = recipesPage.ProfessionDropdown.__menu
check(menu.items[1].text == "All professions", "profession filter starts with All")
local professionNames = {}
for _, item in ipairs(menu.items) do
	professionNames[#professionNames + 1] = item.text
end
check(table.concat(professionNames, ",") == "All professions,Cooking,Enchanting,Tailoring", "profession list")
M.PickDropdown(recipesPage.ProfessionDropdown, 2)
check(recipesPage.Count:GetText() == "0 of 2 recipes", "profession filter applied")
M.PickDropdown(recipesPage.ProfessionDropdown, 1)

step("row interaction")
local rowFrame = recipesPage.Table.ScrollBox.__active[1]
check(rowFrame ~= nil and rowFrame.row ~= nil, "rows rendered")
M.RunScript(rowFrame, "OnEnter")
M.RunScript(rowFrame, "OnLeave")
M.modifiedClick = true
M.Click(rowFrame)
check(M.lastModifiedLink and M.lastModifiedLink:find("item:"), "shift-click links the item")
M.modifiedClick = false

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
M.items[7026] = { name = "Linen Belt", quality = 1, icon = 132492, sellPrice = 50 }
M.pendingItems[7026] = true
pricesPage:Lookup(7026)
check(pricesPage.Panel.Name:GetText() == "Loading item data...", "loading placeholder")
M.RunTimers() -- delivers GET_ITEM_INFO_RECEIVED, then the debounced refresh
M.RunTimers()
check(pricesPage.Panel.Name:GetText():find("Linen Belt", 1, true), "refreshes when the item arrives")

check(#pricesPage.Table.rows == 3, "own scan data listed")
M.Click(pricesPage.Table.ScrollBox.__active[1])
check(pricesPage.itemID ~= nil, "clicking a scan row looks it up")

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
SlashCmdList.SILKROAD("version")
check(OutputContains("0.1.0"), "version command")
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

M.RunTimers()
return checks

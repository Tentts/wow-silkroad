--[[ Smoke-test scenario, run by smoke_test.py after the mock client and the
	addon files are loaded. It drives SilkRoad the way a player would and
	checks the results. Any Lua error or failed check fails the run.
]]
local M = MOCK
local SR = SilkRoad
local Util = SR.Util
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
check(SR.version == "0.7.1", "version read from the TOC")

---------------------------------------------------------------------------
step("open window")
check(not SR.UI:IsShown(), "window starts hidden")
SlashCmdList.SILKROAD("")
check(SR.UI:IsShown(), "/silkroad opens the window")
check(SR.UI.currentPageID == "overview", "opens on the overview page")
check(SilkRoadMainFrame.PageTitle:GetText() == "Overview", "page title shown")
check(UISpecialFrames[1] == "SilkRoadMainFrame", "window closes with Escape")
local nav = SR.UI.navButtons
check(#nav == 7, "seven pages in the sidebar")
local bottomPages = {}
for _, page in ipairs(SR.UI:GetPages()) do
	if page.placement == "bottom" then bottomPages[#bottomPages + 1] = page.id end
end
check(bottomPages[1] == "about" and bottomPages[2] == "settings", "About is pinned at the very bottom, under Settings")

---------------------------------------------------------------------------
step("about page")
SR.UI:OpenPage("about")
local aboutPage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "about" then aboutPage = page end
end
check(aboutPage.Version:GetText() == "Version " .. SR.version, "shows the version")
check(#aboutPage.LinkBoxes == 3 and aboutPage.LinkBoxes[1]:GetText() == "https://github.com/Tentts/wow-silkroad"
	and aboutPage.LinkBoxes[3]:GetText() == "https://github.com/Tentts", "links to the project and the author")
check(aboutPage.IssuesBox:GetText() == "https://github.com/Tentts/wow-silkroad/issues", "where to open an issue")
aboutPage.LinkBoxes[2]:SetText("typed over")
check(aboutPage.LinkBoxes[2]:GetText():find("curseforge", 1, true), "links can't be edited, only copied")
SR.UI:OpenPage("overview")

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
check(bolt.auctionProfit == 185 and bolt.vendorProfit == bolt.vendorPrice - 100, "AH and vendor profit columns")
check(bolt.bestSale == "auction", "sell to: auction")
check(bolt.source == "Learned with the profession", "auto-learned recipes say so")
check(bolt.levelText == "|cff808080" .. "1|r", "skill level coloured grey: Tailoring 75 is past its grey threshold")

local belt = RowFor(8776) -- Linen Belt: Bolt of Linen Cloth + Coarse Thread, from a trainer
check(belt.cost == 300 + 10, "cost mixes auction (bolt) and recorded vendor (thread) prices")
check(belt.profit == belt.vendorPrice - 310, "no auction price: profit uses the vendor price")
check(belt.auctionProfit == nil and belt.bestSale == "vendor", "no auction price: no AH profit, sell to vendor")
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
M.recipeProfessions[999001] = 197 -- not in the generated data: the game says it's Tailoring
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

-- Forever's Leatherworking window reports no profession at all: the recipe
-- IDs alone say whose they are.
local leatherworking = {}
for recipeID, row in pairs(SR.StaticData.recipes) do
	if row[1] == 165 and #leatherworking < 2 then leatherworking[#leatherworking + 1] = recipeID end
end
M.professions[2] = { "Leatherworking", 136247, 30, 75, 0, 0, 165 }
M.tradeSkill = { anonymous = true, name = "Leatherworking", recipes = { [leatherworking[1]] = true, [leatherworking[2]] = false } }
M.FireEvent("TRADE_SKILL_SHOW")
M.RunTimers()
check(SR.DB.char.scannedProfessions[165] == time() and SR.DB.char.knownRecipes[leatherworking[1]]
	and not SR.DB.char.knownRecipes[leatherworking[2]], "a window that doesn't say its profession is still recorded")
M.professions[2] = { "Enchanting", 136244, 40, 75, 0, 0, 333 }

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

step("recipes: known recipes from the spellbook, no window needed")
local cooking = {}
for recipeID, row in pairs(SR.StaticData.recipes) do
	if row[1] == 185 and #cooking < 3 then cooking[#cooking + 1] = recipeID end
end
check(not SR.Recipes:HasRead(185), "Cooking not known yet")
M.knownSpells[cooking[1]] = true
M.knownSpells[cooking[2]] = true
M.FireEvent("LEARNED_SPELL_IN_SKILL_LINE")
M.RunTimers()
check(SR.Recipes:HasRead(185) and SR.DB.char.knownRecipes[cooking[1]] and SR.DB.char.knownRecipes[cooking[2]],
	"learned recipes found in the spellbook")
check(SR.Recipes:IsKnown(SR.Recipes:GetRecipe(cooking[3])) == false, "the rest count as not learned")
check(not SR.Recipes:HasRead(171), "professions the character lacks aren't checked")

step("recipes: dropping a profession forgets its recipes")
local enchanting = M.professions[2]
M.professions[2] = nil
SR.Recipes:ForgetDroppedProfessions()
check(not SR.Recipes:HasRead(333) and not SR.DB.char.knownRecipes[7421], "dropped profession forgotten")
check(SR.Recipes:HasRead(197) and SR.DB.char.knownRecipes[2963], "the others are kept")
M.professions[2] = enchanting

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

step("recipes: right-click to track in the objectives")
M.Click(rowFrame, "RightButton")
check(M.contextMenu and M.contextMenu.items[1].text == itemRecipe.name, "right-click opens the recipe menu")
M.PickContextMenu(1)
M.RunTimers()
check(SR.Game.IsRecipeTracked(itemRecipe.recipe.id), "'Track in objectives' tracks it in the game")
SR.UI:RefreshCurrentPage()
M.RunTimers()
itemRecipe = RowFor(itemRecipe.recipe.id)
for _, frame in ipairs(recipesPage.Table.ScrollBox.__active) do
	if frame.row == itemRecipe then rowFrame = frame end
end
check(rowFrame.cells[1].Text:GetText():find("(tracked)", 1, true), "tracked recipes are marked")
M.Click(rowFrame.cells[3].Button, "RightButton")
check(not popup:IsShown(), "right-clicking a clickable cell opens the menu, not the cell's action")
M.PickContextMenu(1)
M.RunTimers()
check(not SR.Game.IsRecipeTracked(itemRecipe.recipe.id), "'Stop tracking' untracks it")
M.trackRefuse = true
M.Click(rowFrame, "RightButton")
M.PickContextMenu(1)
M.RunTimers()
check(OutputContains("didn't track"), "says so when the game refuses to track a recipe")
M.trackRefuse = nil
M.Click(rowFrame, "RightButton")
M.PickContextMenu("Where to get it")
check(popup:IsShown(), "'Where to get it' opens the sources window")
popup:Hide()
rawset(_G, "LibQuestieDB", nil)
rawset(_G, "QuestieLoader", nil)
SR.Sources:ResetCache()

---------------------------------------------------------------------------
step("buy lists: managing them")
SR.UI:OpenPage("buylists")
local buyPage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "buylists" then buyPage = page end
end
check(#buyPage.Lists.rows == 0, "no lists at first")
check(not buyPage.ItemInput:IsEnabled(), "nothing to add to without a list")
M.Click(buyPage.ListButtons[1]) -- New
M.AcceptPopup("Cloth")
M.RunTimers()
check(#buyPage.Lists.rows == 1 and buyPage:SelectedList().name == "Cloth", "New asks for a name and selects the list")
local clothID = buyPage:SelectedList().id
buyPage.ItemInput:SetText("2589")
buyPage.AmountInput:SetText("20")
M.Click(buyPage.AddButton)
M.RunTimers()
check(#buyPage.Items.rows == 1 and buyPage.Items.rows[1].quantity == 20, "items are added with an amount")
M.bags[2589] = 5
buyPage.ItemInput:SetText("item:2589")
buyPage.AmountInput:SetText("10")
M.Click(buyPage.AddButton)
M.RunTimers()
local linenRow = buyPage.Items.rows[1]
check(linenRow.quantity == 30 and linenRow.have == 5 and linenRow.remaining == 25, "adding again adds to the amount; have and left")
check(linenRow.unitPrice == 50 and linenRow.cost == 25 * 50, "priced from the auction scan")
check(buyPage.Summary:GetText():find("0 of 1 items done", 1, true), "progress summary")
M.Click(buyPage.Items.ScrollBox.__active[1])
M.AcceptPopup("8")
M.RunTimers()
check(buyPage.Items.rows[1].quantity == 8, "clicking an item changes its amount")
M.Click(buyPage.Items.ScrollBox.__active[1], "RightButton")
M.PickContextMenu(1)
M.AcceptPopup("4")
M.RunTimers()
check(buyPage.Items.rows[1].remaining == 0 and buyPage.Items.rows[1].quality == 0, "items you have enough of are done (grey)")
check(buyPage.Lists.rows[1].name:find("(complete)", 1, true), "a list with everything is complete")
M.Click(buyPage.ListButtons[3]) -- Copy
M.RunTimers()
check(#buyPage.Lists.rows == 2 and buyPage:SelectedList().name == "Cloth (2)" and #buyPage:SelectedList().items == 1,
	"Copy duplicates the list with a free name")
M.Click(buyPage.ListButtons[2]) -- Rename
M.AcceptPopup("Spare")
M.RunTimers()
check(buyPage:SelectedList().name == "Spare", "Rename")
M.Click(buyPage.Items.ScrollBox.__active[1], "RightButton")
M.PickContextMenu(2)
M.RunTimers()
check(#buyPage.Items.rows == 0, "Remove takes an item out")
M.Click(buyPage.ListButtons[4]) -- Delete
M.AcceptPopup()
M.RunTimers()
check(#buyPage.Lists.rows == 1 and buyPage:SelectedList().id == clothID, "Delete asks first, then removes the list")
M.bags[2589] = nil

step("buy lists: a recipe's reagents from its right-click menu")
SR.UI:OpenPage("recipes")
PickProfession(197)
M.RunTimers()
local boltRow = RowFor(2963)
for _, frame in ipairs(recipesPage.Table.ScrollBox.__active) do
	if frame.row == boltRow then rowFrame = frame end
end
M.Click(rowFrame, "RightButton")
check(M.contextMenu.items[4].text == "Add to a buy list...", "the recipe menu offers buy lists")
M.PickContextMenu("Add to a buy list...")
check(M.contextMenu.items[1].text == "Add to a buy list" and M.contextMenu.items[2].text == "New buy list"
	and M.contextMenu.items[3].text == "Cloth", "pick a new or an existing list")
M.PickContextMenu(1)
check(M.lastPopup and M.lastPopup.text:find("How many times", 1, true), "asks how many crafts")
M.AcceptPopup("10")
M.RunTimers()
local boltList = SR.BuyLists:FindByName("Bolt of Linen Cloth x10")
check(boltList and #boltList.items == 1 and boltList.items[1].itemID == 2589 and boltList.items[1].quantity == 20,
	"a new list named after the recipe, with reagents x crafts")
check(OutputContains("Added 1 reagents to the buy list Bolt of Linen Cloth x10"), "confirmed in chat")
local threadRecipe
for _, recipe in ipairs(SR.Recipes:GetRecipes(197)) do
	for _, reagent in ipairs(recipe.reagents) do
		if reagent.itemID == 2320 and #recipe.reagents > 1 then threadRecipe = threadRecipe or recipe end
	end
end
local threadList, added, skipped = SR.BuyLists:AddRecipe(clothID, threadRecipe, 2)
check(threadList.id == clothID and skipped >= 1 and added == #threadRecipe.reagents - skipped, "vendor-sold reagents (thread) are left out")
check(not SR.BuyLists:GetItem(threadList, 2320), "no thread in the list")
SR.BuyLists:Delete(clothID)

step("raw materials: crafting every step")
local forceful = SR.Recipes:GetRecipe(1255123) -- Forceful Medium Armor Kit: Medium Armor Kit, 2 Strange Dust, 2 Elixir of Lion's Strength
market.auction[2318] = { price = 10, quantity = 100, seen = time() }   -- Light Leather
market.auction[2319] = { price = 100, quantity = 100, seen = time() }  -- Medium Leather
market.auction[10940] = { price = 30, quantity = 100, seen = time() }  -- Strange Dust
market.auction[2454] = { price = 25, quantity = 100, seen = time() }   -- Elixir of Lion's Strength
local raw, steps = SR.Recipes:Breakdown(forceful, 1)
local function RawCount(list, itemID)
	for _, entry in ipairs(list) do
		if entry.itemID == itemID then return entry.count end
	end
end
check(#steps == 2 and steps[1].recipe.id == 20648 and steps[1].crafts == 4 and steps[2].recipe.id == 2165 and steps[2].crafts == 1,
	"intermediates, deepest first: 4 Medium Leather, then the Medium Armor Kit")
check(RawCount(raw, 2318) == 16 and RawCount(raw, 2320) == 1 and RawCount(raw, 10940) == 2 and RawCount(raw, 2454) == 2
	and not RawCount(raw, 2313) and not RawCount(raw, 2319), "down to 16 Light Leather, thread, dust and elixirs")
check(SR.Recipes:GetBreakdownProducer(2454, 165) == nil, "another profession's recipe isn't used unless the character knows it")
market.auction[2318] = nil
raw = SR.Recipes:Breakdown(forceful, 1)
check(RawCount(raw, 2319) == 4 and not RawCount(raw, 2934), "without a price for Light Leather, Medium Leather is bought instead")
market.auction[2318] = { price = 10, quantity = 100, seen = time() }
SR.DB.char.knownRecipes[2329] = true -- this character brews Elixir of Lion's Strength
for _, herb in ipairs({ 2449, 765, 3371 }) do market.auction[herb] = { price = 5, quantity = 100, seen = time() } end
raw = SR.Recipes:Breakdown(forceful, 1)
check(not RawCount(raw, 2454) and RawCount(raw, 2449) == 2, "known recipes of other professions are crafted too")
SR.DB.char.knownRecipes[2329] = nil
raw = SR.Recipes:Breakdown(forceful, 3)
check(RawCount(raw, 2318) == 48, "times the crafts")
local exactRaw = SR.Recipes:Breakdown(SR.Recipes:GetRecipe(2165), 0.5, true)
check(RawCount(exactRaw, 2318) == 8, "fractional amounts for prices")

local kitEval = SR.Recipes:Evaluate(SR.Recipes:GetRecipe(2165))
check(kitEval.cost == 4 * 100 + 10 and kitEval.rawCost == 16 * 10 + 10, "Raw cost: Medium Leather made from Light Leather")
check(#kitEval.steps == 1 and #kitEval.raw == 2, "with the steps and raw materials for the tooltip")
local boltEval = SR.Recipes:Evaluate(SR.Recipes:GetRecipe(2963))
check(boltEval.steps == nil and boltEval.rawCost == boltEval.cost, "nothing to break down: same as Cost")
local forcefulEval = SR.Recipes:Evaluate(forceful)
check(forcefulEval.rawCost == 16 * 10 + 10 + 2 * 30 + 2 * 25, "every step priced")

PickProfession(165) -- Leatherworking
M.RunTimers()
local kitRow = RowFor(2165)
check(kitRow.rawCost == kitEval.rawCost and kitRow.hasSteps, "Raw cost column on the Recipes page")
for _, frame in ipairs(recipesPage.Table.ScrollBox.__active) do
	if frame.row == kitRow then rowFrame = frame end
end
M.tooltipLines = {}
M.RunScript(rowFrame, "OnEnter")
local tooltipText = table.concat(M.tooltipLines, "\n")
check(tooltipText:find("16 x Light Leather|", 1, true) and tooltipText:find("Raw cost|", 1, true),
	"the tooltip shows the raw materials and their cost")
M.Click(rowFrame, "RightButton")
M.PickContextMenu("Add raw materials to a buy list...")
check(M.contextMenu.items[1].text == "Add raw materials to a buy list", "raw materials go to a buy list too")
M.PickContextMenu("New buy list")
M.AcceptPopup("2")
M.RunTimers()
local rawList = SR.BuyLists:FindByName("Medium Armor Kit x2 (raw)")
check(rawList and #rawList.items == 1 and rawList.items[1].itemID == 2318 and rawList.items[1].quantity == 32,
	"a list of raw materials (thread left out: vendors sell it)")
local boltFrame
for _, frame in ipairs(recipesPage.Table.ScrollBox.__active) do
	if frame.row and frame.row.hasSteps == false then boltFrame = frame end
end
M.Click(boltFrame, "RightButton")
local hasRawOption = false
for _, item in ipairs(M.contextMenu.items) do
	if item.text == "Add raw materials to a buy list..." then hasRawOption = true end
end
check(not hasRawOption, "no raw option when nothing can be crafted")
SR.BuyLists:Delete(rawList.id)
for _, id in ipairs({ 2318, 2319, 10940, 2454, 2449, 765, 3371 }) do market.auction[id] = nil end
PickProfession(197)
M.RunTimers()

---------------------------------------------------------------------------
step("leveling planner")
local Planner = SR.Planner
local chance = Planner.SkillUpChance
local sample = { yellow = 25, gray = 50 }
check(chance(sample, 10) == 1 and chance(sample, 25) == 1, "orange and the start of yellow always skill up")
check(math.abs(chance(sample, 37.5) - 0.5) < 1e-9 and chance(sample, 50) == 0, "chance falls to 0 at grey")
check(chance({ yellow = 105, gray = 105 }, 104) == 1, "recipes without a yellow range are orange until grey")

local function Contiguous(plan)
	for index = 2, #plan.steps do
		if plan.steps[index].from ~= plan.steps[index - 1].to then return false end
	end
	return plan.steps[1].from == plan.from and plan.steps[#plan.steps].to == plan.to
end

local knownPlan = Planner:Plan(197, { from = 1, to = 50, availability = "known", resale = "none" })
check(Contiguous(knownPlan), "steps cover every point from start to target")
check(knownPlan.gaps == 0, "the starter recipes cover skill 1-50")
local sum = 0
for _, step in ipairs(knownPlan.steps) do
	sum = sum + step.cost
	check(step.crafts >= step.to - step.from, "at least one craft per point (" .. step.recipe.name .. ")")
	check(step.learn == nil, "known-only plans learn nothing")
end
check(sum == knownPlan.totalCost, "total = sum of the steps")
-- The first step is the cheapest recipe usable at skill 1 (all orange there).
local cheapest
for _, candidate in ipairs(Planner:Candidates(197, { availability = "known", resale = "none" })) do
	if candidate.recipe.learn <= 1 and not candidate.unpriced and (not cheapest or candidate.craftCost < cheapest) then
		cheapest = candidate.craftCost
	end
end
check(knownPlan.steps[1].candidate.craftCost == cheapest, "picks the cheapest craft per skill point")

local knownTo100 = Planner:Plan(197, { from = 1, to = 100, availability = "known" })
local trainerTo100 = Planner:Plan(197, { from = 1, to = 100, availability = "trainer" })
check(knownTo100.gaps > 0, "known recipes alone can't reach 100")
check(trainerTo100.gaps < knownTo100.gaps, "allowing trainer recipes fills the gaps")
local learns = 0
for _, step in ipairs(trainerTo100.steps) do
	if step.learn then
		learns = learns + 1
		check(step.learn.kind == "trainer", "trainer recipes marked to learn")
	end
end
check(learns > 0, "the plan says which recipes to learn")

local noResale = Planner:Plan(197, { from = 1, to = 50, availability = "known", resale = "none" })
local vendorResale = Planner:Plan(197, { from = 1, to = 50, availability = "known", resale = "vendor" })
check(vendorResale.totalCost <= noResale.totalCost, "counting vendor resale never makes the plan dearer")

M.bags[2589] = 10
local shoppingPlan = Planner:Plan(197, { from = 1, to = 50, availability = "known", resale = "none" })
local linen
for _, entry in ipairs(shoppingPlan.shopping) do
	if entry.itemID == 2589 then linen = entry end
end
check(linen and linen.have == 10 and linen.buy == math.max(0, linen.need - 10), "shopping list subtracts what's in the bags")
check(linen.unitCost == 50 and linen.source == "auction" and linen.total == linen.buy * 50, "priced at the cheapest source")

step("leveling guide page")
SR.UI:OpenPage("guide")
local guidePage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "guide" then guidePage = page end
end
guidePage.skillLine = nil
SR.DB.settings.guide.profession = 197
SR.DB.settings.guide.availability = "trainer"
guidePage:Refresh()
check(guidePage.SkillLabel:GetText() == "Skill 75, plan up to" and guidePage.TargetInput:GetText() == tostring(SR.Planner:MaxSkill(197)),
	"plans from the character's skill to the profession's maximum")
local trainRows = {}
for _, row in ipairs(guidePage.Steps.rows) do
	if row.step.milestone then trainRows[#trainRows + 1] = row.name end
end
check(table.concat(trainRows, ",") == "Train Expert Tailoring,Train Artisan Tailoring",
	"training milestones for the ranks not trained yet (Tailoring 75/150: Journeyman done)")
local expertRow
for _, row in ipairs(guidePage.Steps.rows) do
	if row.name == "Train Expert Tailoring" then expertRow = row end
end
check(expertRow.from < 125 and expertRow.note == "Learnable at skill 125; needed to go past 150.", "placed where the rank can be learned")
local stepRows = guidePage.Steps.rows
local planRows = 0
for _, row in ipairs(stepRows) do
	if not row.step.milestone then planRows = planRows + 1 end
end
check(planRows == #guidePage.plan.steps and planRows > 0, "one row per step, plus training rows")
check(stepRows[1].current and stepRows[1].step.from == 75, "the current step is highlighted")
check(guidePage.Status:GetText():find("step 1 of", 1, true) or guidePage.Status:GetText():find("no usable recipe", 1, true), "status line")
check(#guidePage.Shopping.rows == #guidePage.plan.shopping, "shopping list shown")
M.RunScript(guidePage.Steps.ScrollBox.__active[1], "OnEnter")

guidePage.TargetInput:SetText("100")
M.RunScript(guidePage.TargetInput, "OnEnterPressed")
check(SR.DB.settings.guide.target == 100 and guidePage.plan.to == 100, "a new target re-plans")

M.professions[1][3] = 90 -- Tailoring skill went up
M.FireEvent("SKILL_LINES_CHANGED")
M.RunTimers()
check(guidePage.SkillLabel:GetText() == "Skill 90, plan up to", "re-plans when the skill goes up")
check(guidePage.plan.from == 90, "plan starts at the new skill")
M.professions[1][3] = 75
SR.DB.settings.guide.target = nil
M.bags[2589] = nil

step("gathering guides")
local Gathering = SR.Gathering
check(Gathering:KindOf(186) == "mining" and Gathering:KindOf(393) == "skinning" and Gathering:KindOf(197) == nil, "gathering professions recognised")

local mining = Gathering:Plan("mining", 1, 300)
check(not mining.hasNodeData, "no node locations without GatherMate2")
check(table.concat(mining.steps[1].zones, ",") == "Durotar,Duskwood,Silverpine Forest,Redridge Mountains",
	"zones from SilkRoad's own list without GatherMate2: Horde and contested only")
check(mining.steps[1].zoneIDs[1] == 1411, "with their map IDs")
check(M.loadAddOnCalls[1] == "GatherMate2_Data", "tries to load GatherMate2's data")
local miningTargets = {}
for _, gatherStep in ipairs(mining.steps) do miningTargets[#miningTargets + 1] = gatherStep.targets[1] end
check(table.concat(miningTargets, ",") == "Copper Vein,Tin Vein,Silver Vein,Iron Deposit,Gold Vein,Mithril Deposit,Truesilver Deposit,Small Thorium Vein,Rich Thorium Vein",
	"one bracket per best node, from copper to rich thorium")
check(mining.steps[2].from == 65 and mining.steps[2].to == 75, "brackets start at each node's requirement")
check(mining.steps[2].note == "needs 65; orange until 90, yellow until 115", "skill-up colours in the note")
check(#mining.steps[3].targets >= 2, "nodes still yellow are suggested too")

rawset(_G, "GatherMateData2MineDB", {
	[1411] = { [1] = 201, [2] = 201, [3] = 202 }, -- Durotar
	[1413] = { [1] = 201 },                       -- The Barrens
	[1429] = { [1] = 201, [2] = 201, [3] = 201 }, -- Elwynn Forest (Alliance)
})
local located = Gathering:Plan("mining", 1, 70)
check(located.hasNodeData, "node locations from GatherMate2's data")
check(located.steps[1].zones[1] == "Durotar (2 nodes)" and located.steps[1].zones[2] == "The Barrens (1 nodes)",
	"zones ranked by node count")
for _, zone in ipairs(located.steps[1].zones) do
	check(not zone:find("Elwynn", 1, true), "the other faction's zones are left out")
end
rawset(_G, "GatherMateData2MineDB", nil)
Gathering:ResetCache()

check(Gathering.MaxSkinnableLevel(50) == 15 and Gathering.MaxSkinnableLevel(100) == 20 and Gathering.MaxSkinnableLevel(200) == 40,
	"skinnable level from skill")
local skinning = Gathering:Plan("skinning", 1, 300)
check(#skinning.steps == 6 and skinning.steps[1].targets[1] == "Beasts level 1-10", "skinning brackets from the data")
check(table.concat(skinning.steps[1].zones, ",") == "Mulgore,Durotar,Tirisfal Glades,The Barrens,Moonglade", "skinning zones for this faction")
M.faction = "Alliance"
local alliancePeacebloom = Gathering:Plan("herbalism", 1, 15).steps[1]
check(table.concat(alliancePeacebloom.zones, ",") == "Dun Morogh,Elwynn Forest,Teldrassil,Darkshore", "an Alliance character gets Alliance zones")
local allianceCopper = Gathering:Plan("mining", 1, 65).steps[1]
check(table.concat(allianceCopper.zones, ",") == "Westfall,Duskwood,Loch Modan,Redridge Mountains", "and Alliance mining zones")
local allianceSkinning = Gathering:Plan("skinning", 1, 10).steps[1]
check(table.concat(allianceSkinning.zones, ",") == "Dun Morogh,Elwynn Forest,Teldrassil,Darkshore,Moonglade", "and Alliance skinning zones")
M.faction = "Horde"
check(skinning.steps[2].targets[1] == "Beasts level 11-20" and skinning.steps[2].from == 10 and skinning.steps[2].to == 100, "11-20 beasts up to skill 100")
for _, zone in ipairs(skinning.steps[1].zones) do
	check(zone ~= "Elwynn Forest" and zone ~= "Dun Morogh" and zone ~= "Teldrassil", "skinning zones of this faction")
end
local fishing = Gathering:Plan("fishing", 1, 300)
check(#fishing.steps == 4 and fishing.steps[1].zones[1] == "Durotar", "fishing brackets and zones")

SR.UI:OpenPage("guide")
guidePage.skillLine = 186
SR.DB.settings.guide.profession = 186
guidePage:Refresh()
check(guidePage.GatherSteps:IsShown() and not guidePage.Steps:IsShown() and not guidePage.Shopping:IsShown(), "gathering view replaces the crafting plan")
check(not guidePage.AvailabilityDropdown:IsShown(), "no recipe options for gathering")
local gatherRows, gatherTrain = 0, 0
for _, row in ipairs(guidePage.GatherSteps.rows) do
	if row.step.milestone then gatherTrain = gatherTrain + 1 else gatherRows = gatherRows + 1 end
end
check(gatherRows == 9 and gatherTrain == 3, "one row per bracket, plus all three training ranks (not learned)")
check(guidePage.Status:GetText():find("You don't have this profession", 1, true), "not learned: plan from 1")
check(guidePage.Summary:GetText():find("GatherMate2", 1, true), "suggests GatherMate2 for zones")
M.RunScript(guidePage.GatherSteps.ScrollBox.__active[1], "OnEnter")
guidePage.skillLine = 197
SR.DB.settings.guide.profession = 197
guidePage:Refresh()
check(guidePage.Steps:IsShown() and not guidePage.GatherSteps:IsShown(), "back to the crafting plan for Tailoring")

step("gathering locations on the map")
rawset(_G, "GatherMateData2MineDB", {
	[1411] = { [4000500000] = 201, [4200520000] = 201, [8000100000] = 201, [3000300000] = 202 }, -- Durotar
	[1413] = { [5000500000] = 201 },                                                          -- The Barrens
})
Gathering:ResetCache()
local x, y = Gathering:NodeSpot("mining", 201, 1411)
check(x == 0.4 and y == 0.5, "densest spot: the copper vein closest to the average position")
check(Gathering:NodeSpot("mining", 201, 1429) == nil, "no spot where there are no nodes")
guidePage.skillLine = 186
SR.DB.settings.guide.profession = 186
guidePage:Refresh()
local copperRow = guidePage.GatherSteps.ScrollBox.__active[1]
check(copperRow.row.step.nodeID == 201 and #copperRow.row.step.zoneIDs == 2, "the step knows its node and zones")
M.RunScript(copperRow, "OnEnter")
M.Click(copperRow)
check(M.contextMenu and M.contextMenu.items[1].text == "Show on the map", "several zones: a menu to pick one")
M.PickContextMenu(1)
local waypoint = M.waypoints[#M.waypoints]
check(M.openedMap == 1411, "the world map opens on the zone")
check(waypoint.uiMapID == 1411 and waypoint.x == 0.4 and waypoint.y == 0.5, "with a waypoint at the densest spot")
check(OutputContains("Copper Vein in Durotar: waypoint set (40.0, 50.0)."), "confirmed in chat")
local skinningStep = Gathering:Plan("skinning", 1, 25).steps[1]
skinningStep.zoneIDs = { skinningStep.zoneIDs[1] }
skinningStep.zones = { skinningStep.zones[1] }
local waypointsBefore = #M.waypoints
guidePage:ShowStepOnMap(skinningStep, copperRow)
check(M.openedMap == skinningStep.zoneIDs[1] and #M.waypoints == waypointsBefore, "one zone: straight to the map, no waypoint for creatures")
rawset(_G, "GatherMateData2MineDB", nil)
Gathering:ResetCache()
guidePage.skillLine = 197
SR.DB.settings.guide.profession = 197

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
local minimapCheck, tooltipModeDropdown, tooltipRecipesDropdown, scaleSlider, cutSlider, sourceDropdown = unpack(settingsPage.controls)
check(SR:GetSetting("tooltipRecipes") == "learned", "tooltips list learned recipes and favorites by default")
M.PickDropdown(tooltipRecipesDropdown, 4)
check(SR:GetSetting("tooltipRecipes") == "all", "the tooltip recipes selector")
M.PickDropdown(tooltipRecipesDropdown, 3)
check(SR:GetSetting("tooltipMode") == "single", "tooltip prices for one item by default")
M.PickDropdown(tooltipModeDropdown, 4)
check(SR:GetSetting("tooltipMode") == "both", "the tooltip mode selector")
M.PickDropdown(tooltipModeDropdown, 2)
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
check(OutputContains("0.7.1"), "version command")
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

step("buy lists in the auction house")
check(LibAHTab:DoesIDExist("SilkRoadBuyLists"), "a Buy Lists tab in the auction house")
M.OpenAuctionHouse()
M.RunTimers()
SR.DB.settings.buyLists.selected = boltList.id
LibAHTab:SetSelected("SilkRoadBuyLists")
local buyTab = SR.BuyListsTab
check(SilkRoadBuyListsPanel:IsVisible() and #buyTab.Items.rows == 1, "the selected list's items")
check(buyTab.Card.Hint:IsShown(), "hint until an item is picked")
M.ahListings[2589] = { { 5, 40, own = 5 }, { 12, 45 }, { 100, 60 } }
M.Click(buyTab.Items.ScrollBox.__active[1])
check(SR.AuctionBuyer.state == "searching" and M.ahSearches[#M.ahSearches] == 2589, "clicking an item searches it")
M.RunTimers()
check(SR.AuctionBuyer.state == "ready" and SR.AuctionBuyer:GetAvailable() == 112, "results without the player's own auctions")
check(buyTab.Card.Quantity:GetText() == "20", "quantity defaults to what's left")
check(buyTab.Card.Cost:GetText():find("20 cost about", 1, true), "estimated cost")
check(buyTab.Card.BuyButton:GetText() == "Buy 20" and buyTab.Card.BuyButton:IsEnabled(), "Buy button")
M.Click(buyTab.Card.BuyButton)
check(M.ahPending and M.ahPending.quantity == 20 and SR.AuctionBuyer.state == "quoting", "Buy asks the server for the price")
M.RunTimers()
local expected = 12 * 45 + 8 * 60
check(SR.AuctionBuyer.state == "confirm" and buyTab.Card.BuyButton:GetText():find("Confirm: 20 for", 1, true),
	"then Confirm at the quoted price")
M.Click(buyTab.Card.CancelButton)
check(M.ahCancelled == 1 and SR.AuctionBuyer.state == "ready", "Cancel drops the quote")
M.Click(buyTab.Card.BuyButton)
M.RunTimers()
buyTab.Card.Quantity:SetText("5")
check(M.ahCancelled == 2 and SR.AuctionBuyer.state == "ready" and SR.AuctionBuyer.quote == nil,
	"changing the quantity drops the quote")
check(buyTab.Card.BuyButton:GetText() == "Buy 5", "and the button asks to buy the new quantity")
M.Click(buyTab.Card.BuyButton)
M.RunTimers()
SR.AuctionBuyer.quote.quantity = 7 -- as if the box changed without the quote noticing
M.Click(buyTab.Card.BuyButton)
check(M.ahCancelled == 3 and SR.AuctionBuyer.state == "ready" and M.bags[2589] == nil,
	"Confirm refuses a quantity that wasn't quoted")
buyTab.Card.Quantity:SetText("20")
M.Click(buyTab.Card.BuyButton)
M.RunTimers()
M.Click(buyTab.Card.BuyButton)
check(SR.AuctionBuyer.state == "buying", "Confirm buys")
M.RunTimers()
check(M.bags[2589] == 20 and OutputContains("Bought 20 x Linen Cloth for " .. SR.Util.FormatMoney(expected)), "bought and reported")
M.RunTimers()
check(buyTab.Items.rows[1].remaining == 0 and buyTab.Card.Need:GetText():find("Done", 1, true), "the list updates from the bags")
SR.BuyLists:AddItem(boltList.id, 2996, 2)
SR.BuyLists:AddItem(boltList.id, 4306, 3)
M.ahNotCommodity[2996] = true
M.ahListings[2996] = { { 1, 500 }, { 2, 400 } }
M.ahListings[4306] = { { 50, 420 } }
M.RunTimers()
M.Click(buyTab.Card.NextButton)
M.RunTimers()
check(buyTab.itemID ~= 2589 and buyTab.itemID ~= nil, "Next item picks one still to buy")
buyTab:SelectItem(2996)
M.RunTimers()
check(SR.AuctionBuyer.commodity == false and SR.AuctionBuyer.listings[1].unitPrice == 200, "separate auctions, cheapest per item first")
M.Click(buyTab.Card.BuyButton)
check(buyTab.Card.BuyButton:GetText():find("Confirm: 2 for", 1, true), "whole auction at its buyout")
M.Click(buyTab.Card.BuyButton)
M.RunTimers()
check(M.ahBids[1].auctionID == 102 and M.ahBids[1].amount == 400 and M.bags[2996] == 2, "buys the auction")
buyTab:SelectItem(4306)
M.RunTimers()
M.ahPurchaseFails = true
M.Click(buyTab.Card.BuyButton)
M.RunTimers()
M.Click(buyTab.Card.BuyButton)
M.RunTimers()
check(OutputContains("purchase of Silk Cloth failed") and SR.AuctionBuyer.state == "ready", "failed purchases are reported, then searched again")
M.ahSearchThrottled = true
SR.AuctionBuyer:Search()
check(SR.AuctionBuyer.state == "throttled", "waits when the auction house is busy")
M.ahSearchThrottled = false
M.FireEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
M.RunTimers()
check(SR.AuctionBuyer.state == "ready", "and searches once it's ready")
M.CloseAuctionHouse()
check(SR.AuctionBuyer.state == "idle", "closing the auction house resets the buyer")
M.OpenAuctionHouse()
M.RunTimers()

step("Blizzard's tabs take over again")
LibAHTab:SetSelected("SilkRoad")
check(ahPanel:IsVisible(), "SilkRoad tab open")
AuctionHouseFrame:SetDisplayMode({ "AuctionsFrame" })
check(not ahPanel:IsShown(), "switching to a Blizzard tab hides SilkRoad's panel")
M.CloseAuctionHouse()

---------------------------------------------------------------------------
step("settings tabs")
SR.UI:OpenPage("settings")
local settingsPage
for _, page in ipairs(SR.UI:GetPages()) do
	if page.id == "settings" then settingsPage = page end
end
local tabButtons = settingsPage.TabBar.buttons
check(#tabButtons == 3, "General, Prices and Data tabs")
M.Click(tabButtons[2])
check(settingsPage.tabs.prices:IsVisible() and not settingsPage.tabs.general:IsShown(), "switching tabs")
check(SR.DB.settings.settingsTab == "prices", "last tab remembered")
M.Click(tabButtons[1])

step("key binding")
check(BINDING_NAME_SILKROAD_TOGGLE == "Open / close SilkRoad" and BINDING_HEADER_SILKROAD == "SilkRoad", "binding names for Blizzard's key binding window")
check(settingsPage.KeyButton:GetText() == "Not Bound", "no key at first")
M.bindings["CTRL-S"] = "SOME_OTHER_ACTION"
M.Click(settingsPage.KeyButton)
check(settingsPage.KeyButton:GetText() == "Press a key...", "waiting for a key")
M.modifiers.ctrl = true
M.RunScript(settingsPage.KeyButton, "OnKeyDown", "LCTRL")
check(settingsPage.capturingKey, "a modifier alone keeps waiting")
M.RunScript(settingsPage.KeyButton, "OnKeyDown", "S")
M.modifiers.ctrl = false
check(M.bindings["CTRL-S"] == "SILKROAD_TOGGLE" and M.bindingsSaved == 1, "Ctrl-S bound and saved")
check(settingsPage.KeyButton:GetText() == "Ctrl-S", "button shows the key")
check(OutputContains("Ctrl-S now opens SilkRoad (it was bound to SOME_OTHER_ACTION)."), "warns about the replaced binding")
M.Click(settingsPage.KeyButton)
M.RunScript(settingsPage.KeyButton, "OnKeyDown", "F7")
check(M.bindings["F7"] == "SILKROAD_TOGGLE" and M.bindings["CTRL-S"] == nil, "a new key replaces SilkRoad's old one")
M.Click(settingsPage.KeyButton)
M.RunScript(settingsPage.KeyButton, "OnKeyDown", "ESCAPE")
check(not settingsPage.capturingKey and M.bindings["F7"] == "SILKROAD_TOGGLE", "Escape cancels")
M.inCombat = true
M.Click(settingsPage.KeyButton, "RightButton")
check(M.bindings["F7"] == "SILKROAD_TOGGLE" and OutputContains("can't be changed in combat"), "no changes in combat")
M.inCombat = false
M.Click(settingsPage.KeyButton, "RightButton")
check(M.bindings["F7"] == nil and settingsPage.KeyButton:GetText() == "Not Bound", "right-click clears the key")
-- What Bindings.xml runs when the key is pressed:
local shownBefore = SR.UI:IsShown()
SilkRoad.UI:Toggle()
check(SR.UI:IsShown() ~= shownBefore, "the binding toggles the window")
SilkRoad.UI:Toggle()

step("wiping data")
SR.UI:OpenPage("settings")
M.Click(tabButtons[3])
check(settingsPage.PersonalSummary == nil and settingsPage.WipePersonalButton == nil, "no personal data wipe")
check(settingsPage.MarketSummary:GetText():find("auction prices on 1 realm(s)", 1, true), "market data summarised")
local lastRequest = SR.DB.global.scanner.lastRequest
M.Click(settingsPage.WipeMarketButton)
M.AcceptPopup()
M.RunTimers()
local wiped = SR.DB:GetDataSummary()
check(wiped.auctionPrices == 0 and wiped.realms == 0 and next(SR.DB.global.vendorPrices) == nil, "auction and merchant prices wiped")
check(settingsPage.MarketSummary:GetText():find("^0 auction prices on 0 realm"), "summary updated")
check(SR.DB.global.scanner.lastRequest == lastRequest, "the scan cooldown survives the wipe")
check(SR.Prices:GetAuctionPrice(2589) == nil, "prices gone from the price layer")

step("resetting settings")
SR:SetSetting("auctionCutPercent", 9)
SR:SetSetting("minimap.hide", true)
SR:SetSetting("autoScan", false)
M.Click(settingsPage.ResetSettingsButton)
M.AcceptPopup()
M.RunTimers()
check(SR:GetSetting("auctionCutPercent") == 5 and SR:GetSetting("autoScan") == true, "settings back to defaults")
check(SilkRoadMinimapButton:IsShown(), "listeners notified (minimap button back)")
check(SR.DB.settings == SilkRoadDB.settings, "settings table kept in place")
check(settingsPage.tabs.data:IsVisible(), "stays on the Data tab")
SR.UI:Hide()

---------------------------------------------------------------------------
step("prices in item tooltips")
local addTooltipLines = M.tooltipPostCalls[Enum.TooltipDataType.Item]
check(addTooltipLines ~= nil, "item tooltip hook registered")
SR:SetSetting("tooltipRecipes", "off") -- price lines alone first; recipe lines are checked below
SR.DB:GetMarket().auction[2589] = { price = 47, quantity = 10, seen = time() }
M.tooltipLines = {}
addTooltipLines(GameTooltip, { id = 2589, lines = { { leftText = "Linen Cloth" } } })
check(M.tooltipLines[1] == "SilkRoad vendor|" .. Util.FormatMoney(SR.StaticData.items[2589][4]), "vendor price line")
check(M.tooltipLines[2] == "SilkRoad auction|" .. Util.FormatMoney(47), "auction price line")
M.tooltipLines = {}
addTooltipLines(GameTooltip, { id = 2589, lines = { { leftText = "Linen Cloth" }, { leftText = "Soulbound" } } })
check(#M.tooltipLines == 1 and M.tooltipLines[1]:find("^SilkRoad vendor"), "no auction line for soulbound items")
M.tooltipLines = {}
addTooltipLines(GameTooltip, { id = 60001, lines = {} })
check(M.tooltipLines[#M.tooltipLines] == "SilkRoad auction|" .. "|cff808080no data|r", "items without an auction price say so")
SR:SetSetting("tooltipMode", "off")
M.tooltipLines = {}
addTooltipLines(GameTooltip, { id = 2589, lines = {} })
check(#M.tooltipLines == 0, "turned off in settings")
SR:SetSetting("tooltipMode", "single")

-- Stacks in the bags: Shift, and the tooltip modes.
local rebuildsBefore
local linenVendor = SR.StaticData.items[2589][4]
M.containerItems[0] = { [3] = { 2589, 20 } }
M.tooltipInfo = { getterName = "GetBagItem", getterArgs = { 0, 3, n = 2 } }
M.tooltipData = { id = 2589, lines = { { leftText = "Linen Cloth" } } }
GameTooltip:Show()
M.tooltipLines = {}
addTooltipLines(GameTooltip, M.tooltipData)
check(M.tooltipLines[1] == "SilkRoad vendor|" .. Util.FormatMoney(linenVendor), "one item's price without Shift")
M.modifiers.shift = true
M.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
check(M.tooltipRebuilds == 1, "pressing Shift rebuilds the tooltip")
check(M.tooltipLines[1] == "SilkRoad vendor x20|" .. Util.FormatMoney(linenVendor * 20)
	and M.tooltipLines[2] == "SilkRoad auction x20|" .. Util.FormatMoney(47 * 20), "Shift: prices for the whole stack")
M.modifiers.shift = false
M.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
check(M.tooltipRebuilds == 2 and M.tooltipLines[1] == "SilkRoad vendor|" .. Util.FormatMoney(linenVendor), "releasing Shift goes back to one")
M.FireEvent("MODIFIER_STATE_CHANGED", "LCTRL", 1)
check(M.tooltipRebuilds == 2, "other keys don't rebuild it")
SR:SetSetting("tooltipMode", "stack")
M.tooltipLines = {}
addTooltipLines(GameTooltip, M.tooltipData)
check(M.tooltipLines[1] == "SilkRoad vendor x20|" .. Util.FormatMoney(linenVendor * 20), "Whole stack mode: the stack by default")
M.modifiers.shift = true
M.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
check(M.tooltipLines[1] == "SilkRoad vendor|" .. Util.FormatMoney(linenVendor), "and Shift shows one item")
M.modifiers.shift = false
SR:SetSetting("tooltipMode", "both")
M.tooltipLines = {}
addTooltipLines(GameTooltip, M.tooltipData)
check(#M.tooltipLines == 4
	and M.tooltipLines[1] == "SilkRoad vendor|" .. Util.FormatMoney(linenVendor)
	and M.tooltipLines[2] == "SilkRoad vendor x20|" .. Util.FormatMoney(linenVendor * 20)
	and M.tooltipLines[3] == "SilkRoad auction|" .. Util.FormatMoney(47)
	and M.tooltipLines[4] == "SilkRoad auction x20|" .. Util.FormatMoney(47 * 20),
	"Single and stack mode: a line for one item and a line for the stack")
rebuildsBefore = M.tooltipRebuilds
M.modifiers.shift = true
M.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
check(M.tooltipRebuilds == rebuildsBefore, "Shift has nothing to swap when both are shown")
M.modifiers.shift = false
M.containerItems[0][3] = { 2589, 1 }
M.tooltipLines = {}
addTooltipLines(GameTooltip, M.tooltipData)
check(M.tooltipLines[1] == "SilkRoad vendor|" .. Util.FormatMoney(linenVendor), "a single item shows one price in any mode")
M.containerItems[0][3] = { 2589, 20 }
SR:SetSetting("tooltipMode", "single")
M.modifiers.shift = true
rebuildsBefore = M.tooltipRebuilds
M.tooltipInfo = { getterName = "GetItemByID", getterArgs = { 2589, n = 1 } }
M.tooltipLines = {}
addTooltipLines(GameTooltip, M.tooltipData)
check(M.tooltipLines[1] == "SilkRoad vendor|" .. Util.FormatMoney(linenVendor), "items not in the bags stay single")
M.FireEvent("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
check(M.tooltipRebuilds == rebuildsBefore, "and Shift leaves those tooltips alone")
M.modifiers.shift = false
M.tooltipInfo, M.tooltipData = nil, nil
GameTooltip:Hide()
-- 0.7.0's on/off switch becomes a mode.
SR.DB.settings.tooltipMode, SR.DB.settings.tooltipPrices = nil, false
SR.DB:OnInitialize()
check(SR:GetSetting("tooltipMode") == "off" and SR.DB.settings.tooltipPrices == nil, "tooltip prices turned off in 0.7.0 stay off")
SR.DB.settings.tooltipMode, SR.DB.settings.tooltipPrices = nil, true
SR.DB:OnInitialize()
check(SR:GetSetting("tooltipMode") == "single", "turned on: one item's price")

---------------------------------------------------------------------------
step("recipes in item tooltips, and favorites")
SR:SetSetting("tooltipMode", "off") -- recipe lines alone
local linenUsers = SR.Recipes:GetRecipesUsing(2589)
check(#linenUsers > 8, "every recipe that uses Linen Cloth is indexed")
local wasKnown, wasScanned = SR.DB.char.knownRecipes[2963], SR.DB.char.scannedProfessions[197]
SR.DB.char.knownRecipes[2963] = true -- Bolt of Linen Cloth
SR.DB.char.scannedProfessions[197] = SR.DB.char.scannedProfessions[197] or time()
local function RecipeLines()
	M.tooltipLines = {}
	addTooltipLines(GameTooltip, { id = 2589, lines = { { leftText = "Linen Cloth" } } })
	return M.tooltipLines
end
SR:SetSetting("tooltipRecipes", "learned")
local lines = RecipeLines()
local function HasLine(list, text)
	for _, line in ipairs(list) do
		if line == text then return true end
	end
	return false
end
check(lines[1] == "SilkRoad: used in|" and HasLine(lines, "  Bolt of Linen Cloth|Tailoring"), "learned recipes that use the item")
local unknownUser
for _, recipe in ipairs(linenUsers) do
	if SR.Recipes:IsKnown(recipe) ~= true then unknownUser = unknownUser or recipe end
end
check(#lines == 1 + #(function()
	local known = {}
	for _, recipe in ipairs(linenUsers) do if SR.Recipes:IsKnown(recipe) == true then known[#known + 1] = recipe end end
	return known
end)(), "only learned ones")
SR:SetSetting("tooltipRecipes", "favorites")
check(#RecipeLines() == 0, "Favorites only: nothing without favorites")
SR.Recipes:SetFavorite(unknownUser, true)
lines = RecipeLines()
check(#lines == 2 and lines[2]:find("  " .. SR.Recipes.FAVORITE_ICON .. " " .. unknownUser.name .. "|", 1, true) == 1,
	"favorites are listed and starred, learned or not")
SR:SetSetting("tooltipRecipes", "learned")
lines = RecipeLines()
check(lines[2]:find(unknownUser.name, 1, true) and HasLine(lines, "  Bolt of Linen Cloth|Tailoring"), "favorites come first")
SR:SetSetting("tooltipRecipes", "all")
lines = RecipeLines()
check(#lines == 1 + 8 + 1 and lines[10] == "  and " .. (#linenUsers - 8) .. " more|", "All: at most 8 recipes, then how many more")
SR:SetSetting("tooltipRecipes", "off")
check(#RecipeLines() == 0, "Off: no recipe lines")
M.tooltipLines = {}
addTooltipLines(GameTooltip, { id = 6948, lines = {} }) -- Hearthstone: no recipe uses it
check(#M.tooltipLines == 0, "items no recipe uses get no lines")

SR.UI:OpenPage("recipes")
PickProfession(197)
M.RunTimers()
local boltFrameForMenu
for _, frame in ipairs(recipesPage.Table.ScrollBox.__active) do
	if frame.row and frame.row.recipe.id == 2963 then boltFrameForMenu = frame end
end
M.Click(boltFrameForMenu, "RightButton")
M.PickContextMenu("Add to favorites")
check(SR.Recipes:IsFavorite(SR.Recipes:GetRecipe(2963)), "Add to favorites from the right-click menu")
M.RunTimers()
for _, frame in ipairs(recipesPage.Table.ScrollBox.__active) do
	if frame.row and frame.row.recipe.id == 2963 then boltFrameForMenu = frame end
end
check(boltFrameForMenu.cells[1].Text:GetText():find(SR.Recipes.FAVORITE_ICON, 1, true), "favorites are starred on the Recipes page")
check(M.nativeFavorites[2963] == true, "a learned recipe is starred in the game's professions window too")
M.Click(boltFrameForMenu, "RightButton")
M.PickContextMenu("Remove from favorites")
check(not SR.Recipes:IsFavorite(SR.Recipes:GetRecipe(2963)) and not M.nativeFavorites[2963], "and Remove from favorites, in both")
check(M.nativeFavorites[unknownUser.id] == nil, "recipes not learned stay SilkRoad's own favorites")
-- Stars set in Blizzard's professions window show in SilkRoad.
C_TradeSkillUI.SetRecipeFavorite(2963, true)
check(SR.Recipes:IsFavorite(SR.Recipes:GetRecipe(2963)), "a star set in the professions window is a SilkRoad favorite")
C_TradeSkillUI.SetRecipeFavorite(2963, false)
check(not SR.Recipes:IsFavorite(SR.Recipes:GetRecipe(2963)), "and clearing it there clears it here")
M.nativeFavorites[2963] = true -- starred before SilkRoad was installed
M.tradeSkill = { professionID = 197, name = "Tailoring", recipes = { [2963] = true } }
M.FireEvent("TRADE_SKILL_LIST_UPDATE")
M.RunTimers()
check(SR.DB.global.favoriteRecipes[2963] == true, "the professions window's existing favorites are read")
M.nativeFavorites[2963] = nil
M.FireEvent("TRADE_SKILL_LIST_UPDATE")
M.RunTimers()
check(SR.DB.global.favoriteRecipes[2963] == nil, "and so are removals")
M.tradeSkill = nil
SR.Recipes:SetFavorite(unknownUser, false)
SR.DB.char.knownRecipes[2963], SR.DB.char.scannedProfessions[197] = wasKnown, wasScanned
SR:SetSetting("tooltipMode", "single")
SR:SetSetting("tooltipRecipes", "learned")
SR.UI:Hide()

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

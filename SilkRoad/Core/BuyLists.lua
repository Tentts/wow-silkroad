--[[ SilkRoad - Core/BuyLists.lua
	Buy lists: named sets of items to buy at the auction house, each with
	how many to get. Managed on the Buy Lists page, filled from a recipe's
	right-click menu, and bought from the Buy Lists tab of the auction house.

	Lists are shared by all characters (SilkRoadDB.buyLists). What is still
	to buy compares the wanted amount with what the current character has.

	Fires BUYLISTS_UPDATED when a list is created, changed or deleted.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util

local BuyLists = SR:NewComponent("BuyLists")

local MAX_QUANTITY = 99999

function BuyLists:OnInitialize()
	local store = SR.DB.global.buyLists
	store.lists = store.lists or {}
	store.nextID = store.nextID or 1
	self.store = store
end

local function Changed()
	SR:Fire("BUYLISTS_UPDATED")
end

local function ClampQuantity(quantity)
	quantity = math.floor(tonumber(quantity) or 0)
	return math.min(MAX_QUANTITY, math.max(0, quantity))
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------

-- Every list, sorted by name.
function BuyLists:GetLists()
	local lists = {}
	for _, list in pairs(self.store.lists) do
		lists[#lists + 1] = list
	end
	table.sort(lists, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return lists
end

function BuyLists:GetList(id)
	return id and self.store.lists[id] or nil
end

function BuyLists:FindByName(name)
	for _, list in pairs(self.store.lists) do
		if list.name:lower() == name:lower() then
			return list
		end
	end
end

-- "Name", or "Name (2)", "Name (3)"... when the name is taken.
function BuyLists:UniqueName(name, exceptID)
	name = (name or ""):match("^%s*(.-)%s*$")
	if name == "" then
		name = L["Buy list"]
	end
	local candidate, n = name, 1
	while true do
		local existing = self:FindByName(candidate)
		if not existing or existing.id == exceptID then
			return candidate
		end
		n = n + 1
		candidate = ("%s (%d)"):format(name, n)
	end
end

function BuyLists:Create(name)
	local id = self.store.nextID
	self.store.nextID = id + 1
	local list = { id = id, name = self:UniqueName(name), items = {}, created = time() }
	self.store.lists[id] = list
	Changed()
	return list
end

function BuyLists:Rename(id, name)
	local list = self:GetList(id)
	if list then
		list.name = self:UniqueName(name, id)
		Changed()
	end
	return list
end

function BuyLists:Duplicate(id)
	local source = self:GetList(id)
	if not source then
		return nil
	end
	local copy = self:Create(source.name)
	for _, item in ipairs(source.items) do
		copy.items[#copy.items + 1] = { itemID = item.itemID, quantity = item.quantity }
	end
	Changed()
	return copy
end

function BuyLists:Delete(id)
	if self.store.lists[id] then
		self.store.lists[id] = nil
		Changed()
	end
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

function BuyLists:GetItem(list, itemID)
	for index, item in ipairs(list.items) do
		if item.itemID == itemID then
			return item, index
		end
	end
end

-- Adds to the amount wanted (creating the entry if needed).
function BuyLists:AddItem(id, itemID, quantity, silent)
	local list = self:GetList(id)
	quantity = ClampQuantity(quantity)
	if not list or not itemID or quantity <= 0 then
		return nil
	end
	local item = self:GetItem(list, itemID)
	if item then
		item.quantity = ClampQuantity(item.quantity + quantity)
	else
		item = { itemID = itemID, quantity = quantity }
		list.items[#list.items + 1] = item
	end
	if not silent then
		Changed()
	end
	return item
end

-- Sets the amount wanted; 0 removes the item.
function BuyLists:SetQuantity(id, itemID, quantity)
	local list = self:GetList(id)
	local item, index = list and self:GetItem(list, itemID)
	if not item then
		return
	end
	quantity = ClampQuantity(quantity)
	if quantity == 0 then
		table.remove(list.items, index)
	else
		item.quantity = quantity
	end
	Changed()
end

function BuyLists:RemoveItem(id, itemID)
	self:SetQuantity(id, itemID, 0)
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

-- Reagents a recipe needs for `crafts` crafts, without the ones a vendor
-- sells (those are cheaper and simpler to buy from the vendor). raw = true
-- lists the raw materials instead, for crafting every intermediate step
-- yourself (see Recipes:Breakdown).
-- Returns { { itemID, quantity }, ... }, skippedCount.
function BuyLists:RecipeReagents(recipe, crafts, raw)
	crafts = math.max(1, math.floor(tonumber(crafts) or 1))
	local list = recipe.reagents or {}
	if raw then
		list = SR.Recipes:Breakdown(recipe, crafts)
		crafts = 1 -- Breakdown's counts are for every craft already
	end
	local reagents, skipped = {}, 0
	for _, reagent in ipairs(list) do
		if SR.Prices:GetVendorBuyPrice(reagent.itemID) then
			skipped = skipped + 1
		else
			reagents[#reagents + 1] = { itemID = reagent.itemID, quantity = reagent.count * crafts }
		end
	end
	return reagents, skipped
end

-- Adds a recipe's reagents (raw = true: its raw materials) to a list;
-- listID nil creates a new list named after the recipe. Returns the list,
-- how many reagents were added and how many were left out because a vendor
-- sells them.
function BuyLists:AddRecipe(listID, recipe, crafts, raw)
	local reagents, skipped = self:RecipeReagents(recipe, crafts, raw)
	local list = self:GetList(listID)
	if not list then
		local name = L["%s x%d"]:format(recipe.name or L["Recipe"], math.max(1, math.floor(tonumber(crafts) or 1)))
		if raw then
			name = name .. " " .. L["(raw)"]
		end
		list = self:Create(name)
	end
	for _, reagent in ipairs(reagents) do
		self:AddItem(list.id, reagent.itemID, reagent.quantity, true)
	end
	Changed()
	return list, #reagents, skipped
end

---------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------

-- What's left to buy: entries { itemID, quantity, have, remaining,
-- unitPrice (lowest auction buyout, or nil), cost (remaining x unitPrice) },
-- plus totals { items, done, cost, unpriced }.
function BuyLists:GetProgress(list)
	local entries = {}
	local totals = { items = 0, done = 0, cost = 0, unpriced = 0 }
	for _, item in ipairs(list and list.items or {}) do
		local have = SR.Game.GetItemCount(item.itemID)
		local remaining = math.max(0, item.quantity - have)
		local unitPrice = SR.Prices:GetAuctionPrice(item.itemID)
		local entry = {
			itemID = item.itemID, quantity = item.quantity, have = have, remaining = remaining,
			unitPrice = unitPrice, cost = unitPrice and unitPrice * remaining or nil,
		}
		entries[#entries + 1] = entry
		totals.items = totals.items + 1
		if remaining == 0 then
			totals.done = totals.done + 1
		elseif entry.cost then
			totals.cost = totals.cost + entry.cost
		else
			totals.unpriced = totals.unpriced + 1
		end
	end
	return entries, totals
end

-- Table rows for a list's items (Buy Lists page and auction house tab):
-- progress entries plus name, icon and quality.
function BuyLists:BuildItemRows(list)
	local entries, totals = self:GetProgress(list)
	for _, entry in ipairs(entries) do
		local display = Util.GetItemDisplay(entry.itemID)
		entry.name, entry.icon, entry.link = display.name, display.icon, display.link
		entry.quality = entry.remaining == 0 and 0 or display.quality -- done: shown grey
	end
	return entries, totals
end

-- One line: items done and what's left to spend.
function BuyLists:DescribeTotals(totals)
	if totals.items == 0 then
		return ""
	end
	local text = L["%d of %d items done"]:format(totals.done, totals.items)
	if totals.done < totals.items then
		text = text .. "  |  " .. L["about %s left to spend"]:format(Util.FormatMoney(totals.cost))
		if totals.unpriced > 0 then
			text = text .. " " .. L["(%d without a price)"]:format(totals.unpriced)
		end
	end
	return text
end

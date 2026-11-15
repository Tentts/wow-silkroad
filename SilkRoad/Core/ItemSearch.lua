--[[ SilkRoad - Core/ItemSearch.lua
	Finds items by part of their name, for suggestion lists while typing
	(the Buy Lists page's item box).

	Searched: every item in the game data (all reagents and crafted items),
	items on buy lists and recently looked-up items. Names are in the
	client's language when the game has the item cached, English otherwise.

	SR.ItemSearch:Find(text, limit) -> { itemID, ... }, best matches first:
	names starting with the text, then a word starting with it, then names
	containing it; shorter names first within each group.
	SR.ItemSearch:FindByName(text) -> itemID of an item with exactly that name.
]]
local _, SR = ...
local Util = SR.Util

local ItemSearch = SR:NewComponent("ItemSearch")

local MIN_LENGTH = 2
local index -- { { itemID, name (lower case) }, ... }

-- Called when the list may be stale (new buy list items, localized names
-- arriving): the next search builds it again.
function ItemSearch:Reset()
	index = nil
end

local function Build()
	local seen, list = {}, {}
	local function Add(itemID)
		if itemID and not seen[itemID] then
			local display = Util.GetItemDisplay(itemID)
			if display.name and not display.loading then
				seen[itemID] = true
				list[#list + 1] = { itemID = itemID, name = display.name:lower() }
			end
		end
	end
	for itemID in pairs(SR.StaticData and SR.StaticData.items or {}) do
		Add(itemID)
	end
	for _, buyList in pairs(SR.DB.global.buyLists.lists or {}) do
		for _, item in ipairs(buyList.items) do
			Add(item.itemID)
		end
	end
	for _, itemID in ipairs(SR.DB.global.recentLookups or {}) do
		Add(itemID)
	end
	return list
end

local function Rank(name, text)
	local position = name:find(text, 1, true)
	if not position then
		return nil
	elseif position == 1 then
		return 1 -- "light" -> "Light Leather"
	elseif name:sub(position - 1, position - 1):find("[%s%-%(']") then
		return 2 -- "leather" -> "Light Leather"
	end
	return 3 -- "eath" -> "Light Leather"
end

function ItemSearch:Find(text, limit)
	text = (text or ""):match("^%s*(.-)%s*$"):lower()
	if #text < MIN_LENGTH then
		return {}
	end
	index = index or Build()
	local matches = {}
	for _, entry in ipairs(index) do
		local rank = Rank(entry.name, text)
		if rank then
			matches[#matches + 1] = { itemID = entry.itemID, name = entry.name, rank = rank }
		end
	end
	table.sort(matches, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		elseif #a.name ~= #b.name then
			return #a.name < #b.name
		end
		return a.name < b.name
	end)
	local result = {}
	for i = 1, math.min(#matches, limit or 8) do
		result[i] = matches[i].itemID
	end
	return result
end

-- A name typed in full, without picking it from the suggestions.
function ItemSearch:FindByName(text)
	text = (text or ""):match("^%s*(.-)%s*$"):lower()
	local best = self:Find(text, 1)[1]
	if best and (Util.GetItemDisplay(best).name or ""):lower() == text then
		return best
	end
end

function ItemSearch:OnEnable()
	SR:RegisterCallback("BUYLISTS_UPDATED", function()
		self:Reset()
	end)
	SR:RegisterCallback("ITEM_INFO_RECEIVED", function()
		self:Reset()
	end)
end

--[[ SilkRoad - Core/Util.lua
	Small helpers shared by every part of the addon.
]]
local _, SR = ...
local L = SR.L

local Util = {}
SR.Util = Util

local MISSING_TEXT = "|cff808080--|r"

-- Recursively fills missing keys in target from defaults. Existing values win.
function Util.CopyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			Util.CopyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
	return target
end

function Util.Clamp(value, minValue, maxValue)
	if value < minValue then
		return minValue
	elseif value > maxValue then
		return maxValue
	end
	return value
end

function Util.Round(value, decimals)
	local factor = 10 ^ (decimals or 0)
	return math.floor(value * factor + 0.5) / factor
end

function Util.CountKeys(tbl)
	local count = 0
	if tbl then
		for _ in pairs(tbl) do
			count = count + 1
		end
	end
	return count
end

-- Calls func at most once per `delay` seconds, however often the returned function runs.
function Util.Debounce(delay, func)
	local pending = false
	return function()
		if pending then
			return
		end
		pending = true
		C_Timer.After(delay, function()
			pending = false
			func()
		end)
	end
end

---------------------------------------------------------------------------
-- Text formatting
---------------------------------------------------------------------------

-- Copper amount as gold/silver/copper with coin icons. nil shows a grey dash.
function Util.FormatMoney(copper)
	if copper == nil then
		return MISSING_TEXT
	end
	copper = math.floor(copper + 0.5)
	local negative = copper < 0
	if negative then
		copper = -copper
	end
	local text = GetMoneyString(copper, true)
	if negative then
		text = "|cffff5555-|r" .. text
	end
	return text
end

-- Like FormatMoney, but marks gains in green and losses in red.
function Util.FormatProfit(copper)
	if copper == nil then
		return MISSING_TEXT
	end
	if copper > 0 then
		return "|cff55ff55+|r" .. Util.FormatMoney(copper)
	end
	return Util.FormatMoney(copper)
end

-- 0.153 -> "15.3%"
function Util.FormatPercent(ratio)
	if ratio == nil then
		return MISSING_TEXT
	end
	local text = ("%.1f%%"):format(ratio * 100)
	if ratio > 0 then
		return "|cff55ff55" .. text .. "|r"
	elseif ratio < 0 then
		return "|cffff5555" .. text .. "|r"
	end
	return text
end

function Util.TimeAgo(timestamp)
	if not timestamp then
		return L["Never"]
	end
	local seconds = time() - timestamp
	if seconds < 60 then
		return L["Just now"]
	elseif seconds < 3600 then
		return L["%d min ago"]:format(math.floor(seconds / 60))
	elseif seconds < 86400 then
		return L["%d h ago"]:format(math.floor(seconds / 3600))
	end
	return L["%d days ago"]:format(math.floor(seconds / 86400))
end

function Util.ColorText(text, hex)
	return "|c" .. hex .. text .. "|r"
end

function Util.ColorByQuality(text, quality)
	if quality then
		local _, _, _, hex = C_Item.GetItemQualityColor(quality)
		if hex then
			return Util.ColorText(text, hex)
		end
	end
	return text
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

-- Accepts an item ID (number or digits), an item link / item string, or an
-- item name. Names only resolve for items the client already has cached.
function Util.ParseItemID(input)
	if type(input) == "number" then
		return input
	end
	if type(input) ~= "string" then
		return nil
	end
	input = input:match("^%s*(.-)%s*$")
	if input == "" then
		return nil
	end
	local id = input:match("item:(%d+)") or input:match("^(%d+)$")
	if id then
		return tonumber(id)
	end
	return (C_Item.GetItemInfoInstant(input))
end

-- Basic display data for an item. Fields are nil while the client is still
-- loading the item; a GET_ITEM_INFO_RECEIVED event follows once it is ready.
function Util.GetItemDisplay(itemID)
	local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID)
		return {
			itemID = itemID,
			name = L["Item #%d"]:format(itemID),
			icon = C_Item.GetItemIconByID(itemID),
			loading = true,
		}
	end
	return { itemID = itemID, name = name, link = link, quality = quality, icon = icon }
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------

-- The current character's professions: { name, icon, rank, maxRank, skillLine }.
function Util.GetPlayerProfessions()
	local list = {}
	local indices = { n = select("#", GetProfessions()), GetProfessions() }
	for i = 1, indices.n do
		local index = indices[i]
		if index then
			local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
			if name then
				list[#list + 1] = { name = name, icon = icon, rank = rank, maxRank = maxRank, skillLine = skillLine }
			end
		end
	end
	return list
end

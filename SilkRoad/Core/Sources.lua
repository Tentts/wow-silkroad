--[[ SilkRoad - Core/Sources.lua
	Where things come from: how a recipe is learned (trainer, recipe item
	sold by a vendor, dropped by creatures, rewarded by a quest...) and
	whether a reagent is sold by vendors.

	The client's data only says whether a recipe is taught by a recipe item.
	Who sells or drops that item is server-side knowledge, read at runtime
	from QuestieDB (the database addon behind Questie) when it's installed.
	Without it, SilkRoad still names the recipe item.

	A source is a table:
	  kind     "trainer" | "auto" | "vendor" | "drop" | "container" | "quest" | "item"
	  name     NPC, object, quest or item name (nil for trainer/auto)
	  detail   NPC title, e.g. "Tailoring Supplies"
	  areaID   zone or dungeon; zone = its name
	  x, y     coordinates in percent, when known
	  hostile  true for NPCs of the other faction
]]
local _, SR = ...
local L = SR.L

local Sources = SR:NewComponent("Sources")

local QUESTIE_CONTRACT = 4  -- QuestieDB API version SilkRoad is written against
local MAX_DROP_SOURCES = 40  -- world drops can list hundreds of creatures
local WORLD_DROP_THRESHOLD = 8

local recipeSources = {} -- [recipeID] = { sources }
local vendorSold = {}    -- [itemID] = true / false

---------------------------------------------------------------------------
-- QuestieDB access (optional; every call is protected)
---------------------------------------------------------------------------

local questie -- LibQuestieDB, false when unavailable, nil until checked

local function Questie()
	if questie == nil then
		local lib = LibQuestieDB
		local ok = type(lib) == "table" and type(lib.RequireContract) == "function"
			and lib.RequireContract(QUESTIE_CONTRACT) and lib.Item and lib.Npc
		questie = ok and lib or false
	end
	return questie or nil
end

function Sources:HasQuestie()
	return Questie() ~= nil
end

-- Forget cached lookups (e.g. after QuestieDB loads or changes).
function Sources:ResetCache()
	questie = nil
	recipeSources = {}
	vendorSold = {}
end

local function Get(entityName, id, key)
	local lib = Questie()
	local entity = lib and lib[entityName]
	if not entity or not id then
		return nil
	end
	local ok, value = pcall(entity.Get, id, key)
	if ok then
		return value
	end
end

local PLAYER_FACTION_KEYS = { Alliance = "A", Horde = "H" }

local function IsHostile(npcID)
	local friendly = Get("Npc", npcID, "friendlyToFaction")
	local mine = PLAYER_FACTION_KEYS[UnitFactionGroup("player")]
	return type(friendly) == "string" and mine ~= nil and not friendly:find(mine, 1, true)
end

-- First spawn point: areaID, x, y. Questie stores spawns as
-- { [areaID] = { { x, y }, ... } } with coordinates in percent.
local function FirstSpawn(spawns, fallbackArea)
	if type(spawns) == "table" then
		for areaID, points in pairs(spawns) do
			local point = type(points) == "table" and points[1]
			if type(point) == "table" then
				return areaID, point[1], point[2]
			end
			return areaID
		end
	end
	return fallbackArea
end

local function NpcSource(kind, npcID)
	local name = Get("Npc", npcID, "name")
	if not name then
		return nil
	end
	local areaID, x, y = FirstSpawn(Get("Npc", npcID, "spawns"), Get("Npc", npcID, "zoneID"))
	return {
		kind = kind, npcID = npcID, name = name, detail = Get("Npc", npcID, "subName"),
		areaID = areaID, zone = SR.Game.GetAreaName(areaID), x = x, y = y,
		hostile = IsHostile(npcID),
	}
end

local function ObjectSource(objectID)
	local name = Get("Object", objectID, "name")
	if not name then
		return nil
	end
	local areaID, x, y = FirstSpawn(Get("Object", objectID, "spawns"), Get("Object", objectID, "zoneID"))
	return { kind = "container", name = name, areaID = areaID, zone = SR.Game.GetAreaName(areaID), x = x, y = y }
end

local function AddAll(list, ids, limit, build)
	if type(ids) ~= "table" then
		return
	end
	local added = 0
	for _, id in ipairs(ids) do
		local source = build(id)
		if source then
			list[#list + 1] = source
			added = added + 1
			if limit and added >= limit then
				return
			end
		end
	end
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

local function FriendlyFirst(a, b)
	if (a.hostile or false) ~= (b.hostile or false) then
		return not a.hostile
	end
	return (a.name or "") < (b.name or "")
end

function Sources:GetRecipeSources(recipe)
	local cached = recipeSources[recipe.id]
	if cached then
		return cached
	end

	local list = {}
	if recipe.auto then
		list[1] = { kind = "auto" }
	elseif not recipe.recipeItem then
		list[1] = { kind = "trainer" }
	else
		local item = recipe.recipeItem
		local vendors, drops, others = {}, {}, {}
		AddAll(vendors, Get("Item", item, "vendors"), nil, function(id) return NpcSource("vendor", id) end)
		AddAll(drops, Get("Item", item, "npcDrops"), MAX_DROP_SOURCES, function(id) return NpcSource("drop", id) end)
		AddAll(others, Get("Item", item, "questRewards"), nil, function(id)
			local name = Get("Quest", id, "name")
			return name and { kind = "quest", questID = id, name = name } or nil
		end)
		AddAll(others, Get("Item", item, "objectDrops"), MAX_DROP_SOURCES, ObjectSource)
		table.sort(vendors, FriendlyFirst)
		table.sort(drops, FriendlyFirst)
		for _, group in ipairs({ vendors, others, drops }) do
			for _, source in ipairs(group) do
				list[#list + 1] = source
			end
		end
		if #list == 0 then
			list[1] = { kind = "item", name = SR.Util.GetItemDisplay(item).name, itemID = item }
		end
	end
	recipeSources[recipe.id] = list
	return list
end

local function CountKind(list, kind)
	local count, first = 0, nil
	for _, source in ipairs(list) do
		if source.kind == kind then
			count = count + 1
			first = first or source
		end
	end
	return count, first
end

-- Short text for the "Obtained at" column.
function Sources:Summarize(recipe)
	local list = self:GetRecipeSources(recipe)
	local first = list[1]
	if first.kind == "auto" then
		return L["Learned with the profession"]
	elseif first.kind == "trainer" then
		return L["Trainer"]
	elseif first.kind == "item" then
		return L["Recipe: %s"]:format(first.name or "?")
	end

	local vendors, vendor = CountKind(list, "vendor")
	if vendors > 0 then
		local text = L["Vendor: %s"]:format(vendor.name)
		return vendors > 1 and (text .. " " .. L["(+%d)"]:format(vendors - 1)) or text
	end
	local quests, quest = CountKind(list, "quest")
	if quests > 0 then
		return L["Quest: %s"]:format(quest.name)
	end
	local drops, drop = CountKind(list, "drop")
	if drops == 1 then
		return L["Drop: %s"]:format(drop.name)
	elseif drops >= WORLD_DROP_THRESHOLD then
		return L["World drop"]
	elseif drops > 1 then
		local zone = drop.zone
		for _, source in ipairs(list) do
			if source.kind == "drop" and source.zone ~= zone then
				zone = nil
				break
			end
		end
		return zone and L["Drop: %s"]:format(zone) or L["Drop: %d creatures"]:format(drops)
	end
	local _, container = CountKind(list, "container")
	return L["Container: %s"]:format(container and container.name or "?")
end

---------------------------------------------------------------------------
-- Reagents and waypoints
---------------------------------------------------------------------------

-- True when QuestieDB lists vendors for the item, or SilkRoad has seen a
-- merchant sell it.
function Sources:IsSoldByVendor(itemID)
	if SR.DB.global.vendorPrices[itemID] then
		return true
	end
	local known = vendorSold[itemID]
	if known == nil then
		local vendors = Get("Item", itemID, "vendors")
		known = type(vendors) == "table" and #vendors > 0
		vendorSold[itemID] = known
	end
	return known
end

-- Map ID for an area, through Questie's zone table (QuestieDB itself has no
-- public lookup). nil when Questie isn't loaded.
function Sources:GetUiMapID(areaID)
	local loader = QuestieLoader
	if not areaID or type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
		return nil
	end
	local ok, mapID = pcall(function()
		return loader:ImportModule("ZoneDB"):GetUiMapIdByAreaId(areaID)
	end)
	if ok and type(mapID) == "number" and mapID > 0 then
		return mapID
	end
end

function Sources:CanWaypoint(source)
	return source.x ~= nil and source.y ~= nil and self:GetUiMapID(source.areaID) ~= nil
end

function Sources:SetWaypoint(source)
	local mapID = self:GetUiMapID(source.areaID)
	if source.x and mapID and SR.Game.SetWaypoint(mapID, source.x / 100, source.y / 100, source.name) then
		SR:Print(L["Waypoint set: %s (%s %.1f, %.1f)."]:format(source.name or "?", source.zone or "?", source.x, source.y))
		return true
	end
	SR:Print(L["No map location known for %s."]:format(source.name or "?"))
	return false
end

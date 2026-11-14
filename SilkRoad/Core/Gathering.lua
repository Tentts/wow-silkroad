--[[ SilkRoad - Core/Gathering.lua
	Levelling guides for gathering professions: what to gather at each skill
	and where.

	  Mining, Herbalism  for every skill point, the best node: the one with the
	                     highest requirement the character can gather (orange
	                     or yellow, so every gather gives a point). Zones are
	                     ranked by how many of those nodes GatherMate2's node
	                     database (GatherMate2_Data, read at runtime) puts there.
	  Skinning           creatures up to the highest level the skill allows
	                     (level 10 + skill / 10 below 100 skill, skill / 5 above),
	                     in zones of that level.
	  Fishing            zones where fish rarely get away at that skill.

	The facts (node requirements, zone levels, fishing zones) are in
	Data/<Flavor>/Gathering.lua. Zones of the other faction are left out.

	Gathering:Plan(kind, from, to) returns
	  { steps = { { from, to, targets = { text, ... }, zones = { text, ... }, note }, ... },
	    hasNodeData }
]]
local _, SR = ...
local L = SR.L

local Gathering = SR:NewComponent("Gathering")

Gathering.KINDS = { [186] = "mining", [182] = "herbalism", [393] = "skinning", [356] = "fishing" }

local MAX_ZONES = 3
local SKINNING_BRACKET = 25
local SKINNING_LEVEL_WINDOW = 5
local NODE_DATABASES = {
	-- GatherMate2_Data's database first, then GatherMate2's own (imported or collected) nodes.
	mining = { "GatherMateData2MineDB", "GatherMate2MineDB" },
	herbalism = { "GatherMateData2HerbDB", "GatherMate2HerbDB" },
}
local GATHERMATE_TYPES = { mining = "Mining", herbalism = "Herb Gathering" }

local zoneCounts = {} -- [kind] = { [nodeID] = { [mapID] = count } }

local function Data()
	return SR.GatheringData
end

function Gathering:KindOf(skillLine)
	return Data() and self.KINDS[skillLine]
end

local function PlayerFactionKey()
	local faction = UnitFactionGroup("player")
	return faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
end

-- Zone usable by this character: contested or its own faction's.
local function ZoneAllowed(mapID)
	local zone = Data().zones[mapID]
	return not zone or not zone[3] or zone[3] == PlayerFactionKey()
end

function Gathering:ZoneName(mapID)
	local zone = Data().zones[mapID]
	return SR.Game.GetMapName(mapID) or (zone and zone[4]) or ("#" .. mapID)
end

---------------------------------------------------------------------------
-- Node locations (GatherMate2, optional)
---------------------------------------------------------------------------

local function NodeDatabase(kind)
	SR.Game.LoadOptionalAddOn("GatherMate2_Data")
	for _, name in ipairs(NODE_DATABASES[kind] or {}) do
		local db = rawget(_G, name)
		if type(db) == "table" and next(db) then
			return db
		end
	end
end

function Gathering:ZoneCounts(kind)
	local counts = zoneCounts[kind]
	if counts then
		return counts
	end
	counts = {}
	local db = NodeDatabase(kind)
	if db then
		for mapID, nodes in pairs(db) do
			if type(nodes) == "table" then
				for _, nodeID in pairs(nodes) do
					local byZone = counts[nodeID]
					if not byZone then
						byZone = {}
						counts[nodeID] = byZone
					end
					byZone[mapID] = (byZone[mapID] or 0) + 1
				end
			end
		end
	end
	if next(counts) then
		zoneCounts[kind] = counts -- only cache once there's data
	end
	return counts
end

function Gathering:ResetCache()
	zoneCounts = {}
end

function Gathering:HasNodeData(kind)
	return next(self:ZoneCounts(kind)) ~= nil
end

-- Node name in the client's language (from GatherMate2), else English.
function Gathering:NodeName(kind, node)
	local aceAddon = LibStub and LibStub("AceAddon-3.0", true)
	local gatherMate = aceAddon and aceAddon:GetAddon("GatherMate2", true)
	if gatherMate and gatherMate.GetNameForNode then
		local ok, name = pcall(gatherMate.GetNameForNode, gatherMate, GATHERMATE_TYPES[kind], node[1])
		if ok and type(name) == "string" then
			return name
		end
	end
	return node[2]
end

function Gathering:TopZones(kind, nodeID)
	local list = {}
	for mapID, count in pairs(self:ZoneCounts(kind)[nodeID] or {}) do
		if ZoneAllowed(mapID) then
			list[#list + 1] = { mapID = mapID, count = count }
		end
	end
	table.sort(list, function(a, b)
		return a.count > b.count
	end)
	local zones = {}
	for i = 1, math.min(MAX_ZONES, #list) do
		zones[i] = L["%s (%d nodes)"]:format(self:ZoneName(list[i].mapID), list[i].count)
	end
	return zones
end

---------------------------------------------------------------------------
-- Plans
---------------------------------------------------------------------------

local function BestNode(nodes, skill)
	local best
	for _, node in ipairs(nodes) do
		if node[3] <= skill and (not best or node[3] > best[3]) then
			best = node
		end
	end
	return best
end

function Gathering:PlanNodes(kind, from, to)
	local nodes = Data().nodes[kind]
	local colors = Data().colors
	local steps, current = {}, nil
	for skill = from, to - 1 do
		local node = BestNode(nodes, skill)
		if node then
			if not (current and current.node == node) then
				current = { node = node, from = skill, to = skill }
				steps[#steps + 1] = current
			end
			current.to = skill + 1
		end
	end
	for _, step in ipairs(steps) do
		local node = step.node
		step.targets = { self:NodeName(kind, node) }
		-- Other nodes still yellow at the start of the step are worth gathering too.
		for _, other in ipairs(nodes) do
			if other ~= node and other[3] <= step.from and step.from < other[3] + colors.green then
				step.targets[#step.targets + 1] = self:NodeName(kind, other)
			end
		end
		step.zones = self:TopZones(kind, node[1])
		step.note = L["needs %d; orange until %d, yellow until %d"]:format(node[3], node[3] + colors.yellow, node[3] + colors.green)
	end
	return steps
end

-- Highest creature level a skinning skill allows.
function Gathering.MaxSkinnableLevel(skill)
	if skill < 100 then
		return 10 + math.floor(skill / 10)
	end
	return math.floor(skill / 5)
end

local function ZonesForLevels(low, high)
	local list = {}
	for mapID, zone in pairs(Data().zones) do
		if zone[1] <= high and zone[2] >= low and ZoneAllowed(mapID) then
			list[#list + 1] = { mapID = mapID, distance = math.abs(zone[2] - high) }
		end
	end
	table.sort(list, function(a, b)
		return a.distance < b.distance or (a.distance == b.distance and a.mapID < b.mapID)
	end)
	return list
end

function Gathering:PlanSkinning(from, to)
	local steps = {}
	local skill = from
	while skill < to do
		local stepTo = math.min(to, (math.floor(skill / SKINNING_BRACKET) + 1) * SKINNING_BRACKET)
		local maxLevel = self.MaxSkinnableLevel(skill)
		local minLevel = math.max(1, maxLevel - SKINNING_LEVEL_WINDOW)
		local zones = {}
		for i, zone in ipairs(ZonesForLevels(minLevel, maxLevel)) do
			if i > MAX_ZONES then break end
			zones[i] = self:ZoneName(zone.mapID)
		end
		steps[#steps + 1] = {
			from = skill, to = stepTo,
			targets = { L["Beasts level %d-%d"]:format(minLevel, maxLevel) },
			zones = zones,
			note = L["skin creatures up to level %d"]:format(maxLevel),
		}
		skill = stepTo
	end
	return steps
end

function Gathering:PlanFishing(from, to)
	local steps = {}
	for _, bracket in ipairs(Data().fishing) do
		local low, high = math.max(from, bracket[1]), math.min(to, bracket[2])
		if low < high then
			local zones = {}
			for _, mapID in ipairs(bracket[3]) do
				if ZoneAllowed(mapID) and #zones < MAX_ZONES + 1 then
					zones[#zones + 1] = self:ZoneName(mapID)
				end
			end
			steps[#steps + 1] = {
				from = low, to = high, targets = { L["Fish in open water or pools"] }, zones = zones,
				note = L["fish here so they don't get away"],
			}
		end
	end
	return steps
end

function Gathering:Plan(kind, from, to)
	from, to = math.max(1, math.floor(from)), math.floor(to)
	local steps
	if kind == "skinning" then
		steps = self:PlanSkinning(from, to)
	elseif kind == "fishing" then
		steps = self:PlanFishing(from, to)
	else
		steps = self:PlanNodes(kind, from, to)
	end
	return { steps = steps, from = from, to = to, kind = kind,
		hasNodeData = (kind ~= "mining" and kind ~= "herbalism") or self:HasNodeData(kind) }
end

function Gathering:MaxSkill()
	return Data().maxSkill
end

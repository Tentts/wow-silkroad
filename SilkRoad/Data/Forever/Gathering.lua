-- SilkRoad gathering facts for Forever. Hand-maintained (not generated):
-- the client's tables don't link gathering nodes to the skill they need,
-- so these are the game's well-known values.
--   nodes   GatherMate2 node ID, English name (fallback; GatherMate2 names
--           them in the client's language), skill needed to gather
--   zones   map ID -> lowest and highest creature level, faction ("A", "H"
--           or nil for contested), English name (fallback for C_Map)
--   fishing skill brackets with zones where fish rarely get away
-- Where nodes actually are comes from GatherMate2's data at runtime.
local _, SR = ...
if SR.flavor ~= "forever" then return end

SR.GatheringData = {
	maxSkill = 300,

	-- Skill-up colours for nodes: orange until skill+25, yellow until +50,
	-- green until +100, grey after that.
	colors = { yellow = 25, green = 50, gray = 100 },

	nodes = {
		mining = {
			{ 201, "Copper Vein", 1 },
			{ 202, "Tin Vein", 65 },
			{ 204, "Silver Vein", 75 },
			{ 203, "Iron Deposit", 125 },
			{ 205, "Gold Vein", 155 },
			{ 206, "Mithril Deposit", 175 },
			{ 208, "Truesilver Deposit", 230 },
			{ 217, "Dark Iron Deposit", 230 },
			{ 214, "Small Thorium Vein", 245 },
			{ 215, "Rich Thorium Vein", 275 },
		},
		herbalism = {
			{ 401, "Peacebloom", 1 },
			{ 402, "Silverleaf", 1 },
			{ 403, "Earthroot", 15 },
			{ 404, "Mageroyal", 50 },
			{ 405, "Briarthorn", 70 },
			{ 407, "Stranglekelp", 85 },
			{ 408, "Bruiseweed", 100 },
			{ 409, "Wild Steelbloom", 115 },
			{ 410, "Grave Moss", 120 },
			{ 411, "Kingsblood", 125 },
			{ 412, "Liferoot", 150 },
			{ 413, "Fadeleaf", 160 },
			{ 414, "Goldthorn", 170 },
			{ 415, "Khadgar's Whisker", 185 },
			{ 416, "Wintersbite", 195 },
			{ 417, "Firebloom", 205 },
			{ 418, "Purple Lotus", 210 },
			{ 420, "Arthas' Tears", 220 },
			{ 421, "Sungrass", 230 },
			{ 422, "Blindweed", 235 },
			{ 423, "Ghost Mushroom", 245 },
			{ 424, "Gromsblood", 250 },
			{ 425, "Golden Sansam", 260 },
			{ 426, "Dreamfoil", 270 },
			{ 427, "Mountain Silversage", 280 },
			{ 428, "Plaguebloom", 285 },
			{ 429, "Icecap", 290 },
			{ 431, "Black Lotus", 300 },
		},
	},

	zones = {
		[1429] = { 1, 10, "A", "Elwynn Forest" },
		[1426] = { 1, 10, "A", "Dun Morogh" },
		[1438] = { 1, 10, "A", "Teldrassil" },
		[1411] = { 1, 10, "H", "Durotar" },
		[1412] = { 1, 10, "H", "Mulgore" },
		[1420] = { 1, 10, "H", "Tirisfal Glades" },
		[1436] = { 10, 20, "A", "Westfall" },
		[1432] = { 10, 20, "A", "Loch Modan" },
		[1439] = { 10, 20, "A", "Darkshore" },
		[1413] = { 10, 25, "H", "The Barrens" },
		[1421] = { 10, 20, "H", "Silverpine Forest" },
		[1433] = { 15, 25, "A", "Redridge Mountains" },
		[1442] = { 15, 27, nil, "Stonetalon Mountains" },
		[1440] = { 18, 30, nil, "Ashenvale" },
		[1431] = { 18, 30, "A", "Duskwood" },
		[1424] = { 20, 30, nil, "Hillsbrad Foothills" },
		[1437] = { 20, 30, "A", "Wetlands" },
		[1441] = { 25, 35, nil, "Thousand Needles" },
		[1416] = { 30, 40, nil, "Alterac Mountains" },
		[1417] = { 30, 40, nil, "Arathi Highlands" },
		[1443] = { 30, 40, nil, "Desolace" },
		[1434] = { 30, 45, nil, "Stranglethorn Vale" },
		[1445] = { 35, 45, nil, "Dustwallow Marsh" },
		[1418] = { 35, 45, nil, "Badlands" },
		[1435] = { 35, 45, nil, "Swamp of Sorrows" },
		[1444] = { 40, 50, nil, "Feralas" },
		[1425] = { 40, 50, nil, "The Hinterlands" },
		[1446] = { 40, 50, nil, "Tanaris" },
		[1427] = { 43, 50, nil, "Searing Gorge" },
		[1447] = { 45, 55, nil, "Azshara" },
		[1419] = { 45, 55, nil, "Blasted Lands" },
		[1449] = { 48, 55, nil, "Un'Goro Crater" },
		[1448] = { 48, 55, nil, "Felwood" },
		[1428] = { 50, 58, nil, "Burning Steppes" },
		[1422] = { 51, 58, nil, "Western Plaguelands" },
		[1423] = { 53, 60, nil, "Eastern Plaguelands" },
		[1452] = { 53, 60, nil, "Winterspring" },
		[1451] = { 55, 60, nil, "Silithus" },
	},

	fishing = {
		{ 1, 75, { 1429, 1426, 1438, 1411, 1412, 1420 } },
		{ 75, 150, { 1436, 1432, 1439, 1413, 1421, 1442 } },
		{ 150, 225, { 1434, 1443, 1417, 1445, 1435, 1424 } },
		{ 225, 300, { 1446, 1444, 1447, 1425, 1449, 1448 } },
	},
}

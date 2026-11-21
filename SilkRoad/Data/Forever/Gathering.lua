-- SilkRoad gathering facts for Forever. Hand-maintained (not generated):
-- the client's tables don't link gathering nodes to the skill they need,
-- so these are the game's well-known values.
--   nodes   GatherMate2 node ID, English name (fallback; GatherMate2 names
--           them in the client's language), skill needed to gather, and the
--           zones it's found in (best first)
--   skinning skill brackets with creature levels and zones
--   zones   map ID -> lowest and highest creature level, faction ("A", "H"
--           or nil for contested), English name (fallback for C_Map)
--   fishing skill brackets with zones where fish rarely get away
-- Node and skinning zones (every zone, best first) are facts from wow.gg's
-- Forever gathering guides. When GatherMate2's node database is available, it ranks
-- zones by node count and pinpoints nodes for waypoints instead.
local _, SR = ...
if SR.flavor ~= "forever" then return end

SR.GatheringData = {
	maxSkill = 300,

	-- Skill-up colours for nodes: orange until skill+25, yellow until +50,
	-- green until +100, grey after that.
	colors = { yellow = 25, green = 50, gray = 100 },

	nodes = {
		mining = {
			{ 201, "Copper Vein", 1, { 1411, 1436, 1431, 1421, 1432, 1433, 1437, 1429, 1424 } },
			{ 202, "Tin Vein", 65, { 1437, 1431, 1421, 1432, 1433, 1424, 1440 } },
			{ 204, "Silver Vein", 75, { 1417, 1416, 1434, 1437, 1431, 1421, 1432 } },
			{ 203, "Iron Deposit", 125, { 1417, 1416, 1434, 1431, 1441, 1443 } },
			{ 205, "Gold Vein", 155, { 1417, 1416, 1434, 1431, 1425, 1418 } },
			{ 206, "Mithril Deposit", 175, { 1418, 1425, 1416, 1427, 1446, 1447 } },
			{ 208, "Truesilver Deposit", 230, { 1418, 1425, 1416, 1427, 1446, 1447 } },
			{ 217, "Dark Iron Deposit", 230, { 1427 } },
			{ 214, "Small Thorium Vein", 245, { 1452, 1435, 1419 } },
			{ 215, "Rich Thorium Vein", 275, { 1452, 1447 } },
		},
		herbalism = {
			{ 401, "Peacebloom", 1, { 1413, 1411, 1412, 1420, 1426, 1429, 1438, 1421, 1439, 1432, 1436, 1433 } },
			{ 402, "Silverleaf", 1, { 1411, 1413, 1412, 1432, 1429, 1420, 1439, 1426, 1421, 1438, 1436 } },
			{ 403, "Earthroot", 15, { 1413, 1411, 1420, 1426, 1429, 1433, 1436, 1412, 1438, 1439, 1421 } },
			{ 404, "Mageroyal", 50, { 1413, 1440, 1439, 1436, 1421, 1433, 1432, 1431, 1437 } },
			{ 405, "Briarthorn", 70, { 1413, 1431, 1440, 1436, 1439, 1437, 1424, 1433 } },
			{ 407, "Stranglekelp", 85, { 1434, 1437, 1440, 1439, 1413, 1424, 1436, 1444 } },
			{ 408, "Bruiseweed", 100, { 1442, 1413, 1424, 1437, 1440, 1433, 1431 } },
			{ 409, "Wild Steelbloom", 115, { 1417, 1442, 1434, 1437, 1441, 1413, 1418 } },
			{ 410, "Grave Moss", 120, { 1431, 1443, 1437, 1417, 1416, 1413, 1423 } },
			{ 411, "Kingsblood", 125, { 1434, 1437, 1440, 1424, 1413, 1431, 1417 } },
			{ 412, "Liferoot", 150, { 1434, 1437, 1417, 1416, 1444, 1445 } },
			{ 413, "Fadeleaf", 160, { 1417, 1435, 1416, 1434, 1425, 1418 } },
			{ 414, "Goldthorn", 170, { 1434, 1417, 1435, 1416, 1425, 1444 } },
			{ 415, "Khadgar's Whisker", 185, { 1434, 1417, 1435, 1416, 1444, 1425 } },
			{ 416, "Wintersbite", 195, { 1416 } },
			{ 417, "Firebloom", 205, { 1446, 1427, 1418 } },
			{ 418, "Purple Lotus", 210, { 1447, 1425, 1446, 1444, 1434, 1440 } },
			{ 420, "Arthas' Tears", 220, { 1422, 1423, 1448 } },
			{ 421, "Sungrass", 230, { 1447, 1425, 1444, 1423, 1449, 1428 } },
			{ 422, "Blindweed", 235, { 1435, 1449 } },
			{ 423, "Ghost Mushroom", 245, { 1425, 1443 } },
			{ 424, "Gromsblood", 250, { 1448, 1443 } },
			{ 425, "Golden Sansam", 260, { 1449, 1447, 1423, 1448, 1425, 1428 } },
			{ 426, "Dreamfoil", 270, { 1447, 1423, 1449, 1448, 1428, 1422 } },
			{ 427, "Mountain Silversage", 280, { 1452, 1449, 1447, 1428, 1423, 1422 } },
			{ 428, "Plaguebloom", 285, { 1423, 1422 } },
			{ 429, "Icecap", 290, { 1452 } },
			{ 431, "Black Lotus", 300, { 1428, 1452, 1423, 1451 } },
		},
	},

	-- Profession ranks (every profession): train the next rank once the
	-- skill reaches learnAt, to go past the current cap. Unlike Classic
	-- (25 points early), Forever's trainers only teach a rank once the skill
	-- has reached the current cap (checked in game: Expert Leatherworking at
	-- 150). The starting-zone trainers only teach up to 75.
	ranks = {
		{ name = "Journeyman", learnAt = 75, cap = 75 },
		{ name = "Expert", learnAt = 150, cap = 150 },
		{ name = "Artisan", learnAt = 225, cap = 225 },
	},

	zones = {
		[2521] = { 1, 10, nil, "Zephras Isle" }, -- Forever's Skyborne starting zone
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
		[1433] = { 15, 25, nil, "Redridge Mountains" },
		[1442] = { 15, 27, nil, "Stonetalon Mountains" },
		[1440] = { 18, 30, nil, "Ashenvale" },
		[1431] = { 18, 30, nil, "Duskwood" },
		[1424] = { 20, 30, nil, "Hillsbrad Foothills" },
		[1437] = { 20, 30, nil, "Wetlands" },
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
		[1450] = { 1, 60, nil, "Moonglade" },
	},

	skinning = {
		{ 1, 10, 1, 10, { 1412, 1411, 1426, 1429, 1420, 1438, 1413, 1439, 1450, 1421, 1433 } },
		{ 10, 100, 11, 20, { 1413, 1439, 1421, 1432, 1440, 1436, 1433, 1431, 1442 } },
		{ 100, 150, 21, 30, { 1437, 1440, 1424, 1441, 1431, 1413, 1417 } },
		{ 150, 200, 31, 40, { 1445, 1443, 1434, 1418, 1441, 1417 } },
		{ 200, 250, 41, 50, { 1446, 1444, 1425, 1448, 1445, 1449 } },
		{ 250, 300, 51, 60, { 1452, 1447, 1451, 1423, 1449, 1428 } },
	},

	fishing = {
		{ 1, 75, { 1429, 1426, 1438, 1411, 1412, 1420 } },
		{ 75, 150, { 1436, 1432, 1439, 1413, 1421, 1442 } },
		{ 150, 225, { 1434, 1443, 1417, 1445, 1435, 1424 } },
		{ 225, 300, { 1446, 1444, 1447, 1425, 1449, 1448 } },
	},
}

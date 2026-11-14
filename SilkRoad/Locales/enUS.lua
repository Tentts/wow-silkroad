--[[ SilkRoad - Locales/enUS.lua
	English, and the base for every other language.

	Short labels use their English text as the key, so L["Recipes"] simply
	returns "Recipes" unless a translation overrides it. Longer texts use
	symbolic keys (L.RECIPES_DESC) and are defined below.

	Translations live in Locales/<locale>.lua, load after this file and only
	take effect on a client in that language. Game names (recipes, items,
	professions, zones, NPCs) come from the game in its own language and need
	no translating. See docs/TRANSLATING.md and tools/locales.py.
]]
local _, SR = ...

local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
SR.L = L

L.TAGLINE = "Crafting & trading helper"

L.OVERVIEW_DESC = "Your crafting and trading dashboard."
L.RECIPES_DESC = "Every recipe of every profession: where to get it, what it costs to craft and what it sells for."
L.PRICES_DESC = "Look up everything SilkRoad knows about an item's price."
L.SETTINGS_DESC = "Configure SilkRoad."

L.OVERVIEW_GETTING_STARTED = table.concat({
	"|cffffd100/silkroad|r (or |cffffd100/silk|r) opens and closes this window. Type |cffffd100/silkroad help|r for all commands.",
	"",
	"|cffffd100Recipes|r compares what a recipe's materials cost with what the result sells for, on the auction house and at a vendor, and shows where each recipe is obtained.",
	"|cffffd100Price Database|r shows every price SilkRoad knows for an item.",
	"",
	"When you open the auction house, SilkRoad scans it automatically (at most once every 15 minutes) and saves the lowest price of every item. The |cffffd100SilkRoad|r tab in the auction house shows the scan status and lets you scan manually. Auctionator's prices are used too when it is installed.",
	"",
	"|cffffd100Recipes|r lists every profession, learned or not, and marks the recipes you know (read from your spellbook). Vendor prices for reagents come from the game data (with Questie installed) and from every merchant you open.",
}, "\n")

L.RECIPES_EMPTY_TITLE = "No recipes"
L.RECIPES_EMPTY_BODY = "SilkRoad has no recipes for this profession in its game data."
L.SOURCE_TRAINER_HINT = "Taught by profession trainers."
L.SOURCE_AUTO_HINT = "Learned automatically together with the profession."
L.KNOWN_ONLY_TOOLTIP = "Only show recipes this character has learned. Available for professions this character has, once SilkRoad has read its recipes (from the spellbook, or by opening the profession window)."
L.NO_QUESTIE_HINT = "Install Questie (with QuestieDB) to see which vendors, creatures and quests give recipe items, and where they are."
L.RECENT_EMPTY_TITLE = "No lookups yet"
L.RECENT_EMPTY_BODY = "Items you look up are listed here so you can check them again with one click."
L.NO_SCAN_DATA = "No SilkRoad scan data yet: open the auction house and SilkRoad scans it automatically (at most once every 15 minutes)."
L.NO_MATCHES_TITLE = "Nothing matches"
L.NO_MATCHES_BODY = "Try a different search or filter."
L.LOOKUP_HINT = "Type an item ID or name, or shift-click an item link into the box."
L.LOOKUP_NOT_FOUND = "SilkRoad doesn't recognise that item. Names only work for items your client has already seen; item IDs and links always work."
L.NO_AUCTION_SOURCE = "none yet"

L.SCAN_NO_RESPONSE = "The auction house didn't send scan results. The server allows one full scan every 15 minutes, and another addon may have used it; SilkRoad will try again next time."
L.AH_SCAN_NOTE = "The server allows one full scan every 15 minutes. Full scans started by other addons, such as Auctionator, are recorded too."
L.AH_ABOUT = "Auction prices from these scans feed SilkRoad's recipe costs, profits and price lookups."
L.AUTO_SCAN_TOOLTIP = "When the auction house opens, scan it if the last full scan was at least 15 minutes ago."

L.KEY_BINDING_TOOLTIP = "Click, then press the key (with Shift, Ctrl or Alt if you like) that should open and close SilkRoad. Escape cancels; right-click clears it."
L.KEY_BINDING_NOTE = "The same binding is listed under Options > Keybindings > AddOns > SilkRoad."
L.WIPE_MARKET_DESC = "Auction prices from every scan, on every realm, and the merchant prices SilkRoad recorded. The server's 15-minute scan limit still applies afterwards."
L.WIPE_MARKET_CONFIRM = "Wipe all auction and merchant prices SilkRoad has recorded? This can't be undone."
L.RESET_SETTINGS_DESC = "Puts every SilkRoad setting back to its default, including the window size and position. Your data and key binding stay."
L.RESET_SETTINGS_CONFIRM = "Reset every SilkRoad setting to its default?"
L.TOOLTIP_PRICES_TOOLTIP = "Adds what a vendor pays and the lowest auction price to item tooltips. The auction line only shows for items that can be sold there."

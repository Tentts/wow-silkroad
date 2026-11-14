--[[ SilkRoad - Core/Init.lua
	Namespace, game event and internal callback dispatch, component
	lifecycle and slash commands.

	Lifecycle: every component created with SR:NewComponent() may define
	  OnInitialize()  -- after SilkRoad's saved variables are loaded (ADDON_LOADED)
	  OnEnable()      -- once the player is in the world (PLAYER_LOGIN)
	Components run in the order their files are listed in the TOC.
]]
local addonName, SR = ...
local L = SR.L

-- Public handle, for /dump SilkRoad while debugging and for future integrations.
_G.SilkRoad = SR

SR.name = addonName
SR.title = "SilkRoad"
SR.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
SR.icon = "Interface\\Icons\\INV_Fabric_Silk_02"
SR.colorHex = "ffe6c35c"

---------------------------------------------------------------------------
-- Game version ("flavor")
--
-- SilkRoad's core is version-agnostic. Everything that differs between game
-- versions lives in two places, both selected by SR.flavor:
--   Data/<Flavor>/   generated game data (recipes, items), see tools/generate_data.py
--   Game/<Flavor>.lua the SR.Game adapter: the version's own APIs (profession
--                     window, merchants, map waypoints)
-- Supporting another version means adding both for it.
---------------------------------------------------------------------------

local FLAVORS = {
	-- { lowest interface, highest interface, flavor }
	{ 16000, 16999, "forever" },
}

SR.interface = select(4, GetBuildInfo())
SR.locale = GetLocale()
SR.flavor = "unsupported"
for _, entry in ipairs(FLAVORS) do
	if SR.interface >= entry[1] and SR.interface <= entry[2] then
		SR.flavor = entry[3]
	end
end

---------------------------------------------------------------------------
-- Listener registries (shared by game events and internal callbacks)
---------------------------------------------------------------------------

local function AddListener(registry, key, func)
	local list = registry[key]
	local isFirst = list == nil
	if isFirst then
		list = {}
		registry[key] = list
	end
	list[#list + 1] = func
	return isFirst
end

-- Returns true when the last listener for the key was removed.
local function RemoveListener(registry, key, func)
	local list = registry[key]
	if not list then
		return false
	end
	for i = #list, 1, -1 do
		if list[i] == func then
			table.remove(list, i)
		end
	end
	if #list == 0 then
		registry[key] = nil
		return true
	end
	return false
end

local function Dispatch(registry, key, ...)
	local list = registry[key]
	if not list then
		return
	end
	if #list == 1 then
		list[1](key, ...)
		return
	end
	-- Iterate over a snapshot so listeners can unregister themselves safely.
	local snapshot = { unpack(list) }
	for i = 1, #snapshot do
		snapshot[i](key, ...)
	end
end

local eventFrame = CreateFrame("Frame")
local eventListeners = {}
local callbackListeners = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
	Dispatch(eventListeners, event, ...)
end)

-- Game events. Handlers are called as handler(event, ...).
function SR:RegisterEvent(event, handler)
	if AddListener(eventListeners, event, handler) then
		eventFrame:RegisterEvent(event)
	end
end

function SR:UnregisterEvent(event, handler)
	if RemoveListener(eventListeners, event, handler) then
		eventFrame:UnregisterEvent(event)
	end
end

-- Internal callbacks between SilkRoad components. Handlers are called as
-- handler(name, ...). Messages in use:
--   SETTING_CHANGED (path, value)  a setting changed through SR:SetSetting
--   PRICES_UPDATED ()              price data changed (scan, import, ...)
--   ITEM_INFO_RECEIVED (itemID)    an item SilkRoad requested (Util.RequestItem) finished loading
--   SCAN_STATUS (state, progress)  the auction scanner's state changed
function SR:RegisterCallback(name, handler)
	AddListener(callbackListeners, name, handler)
end

function SR:UnregisterCallback(name, handler)
	RemoveListener(callbackListeners, name, handler)
end

function SR:Fire(name, ...)
	Dispatch(callbackListeners, name, ...)
end

---------------------------------------------------------------------------
-- Components
---------------------------------------------------------------------------

local components = {}

function SR:NewComponent(name)
	assert(self[name] == nil, "SilkRoad: component name already in use: " .. tostring(name))
	local component = { name = name }
	components[#components + 1] = component
	self[name] = component
	return component
end

local function RunLifecycle(method)
	for _, component in ipairs(components) do
		if component[method] then
			component[method](component)
		end
	end
end

local function OnAddonLoaded(_, loadedName)
	if loadedName ~= addonName then
		return
	end
	SR:UnregisterEvent("ADDON_LOADED", OnAddonLoaded)
	RunLifecycle("OnInitialize")
end

local function OnPlayerLogin()
	SR:UnregisterEvent("PLAYER_LOGIN", OnPlayerLogin)
	RunLifecycle("OnEnable")
end

SR:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
SR:RegisterEvent("PLAYER_LOGIN", OnPlayerLogin)

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

function SR:Print(...)
	print(WrapTextInColorCode(self.title, self.colorHex) .. ":", ...)
end

function SR:Debug(...)
	if self.DB and self.DB.settings and self.DB.settings.debug then
		print(WrapTextInColorCode(self.title .. " debug", "ff888888") .. ":", ...)
	end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local commands = {}
local commandOrder = {}

-- Registers "/silkroad <name> [args]". The handler receives the rest of the line.
function SR:RegisterSlashCommand(name, description, handler)
	name = name:lower()
	if not commands[name] then
		commandOrder[#commandOrder + 1] = name
	end
	commands[name] = { description = description, handler = handler }
end

local function PrintHelp()
	SR:Print(L["Commands:"])
	print("  |cffffd100/silkroad|r - " .. L["open or close the window"])
	for _, name in ipairs(commandOrder) do
		print(("  |cffffd100/silkroad %s|r - %s"):format(name, commands[name].description))
	end
	local pageIDs = {}
	for _, page in ipairs(SR.UI:GetPages()) do
		pageIDs[#pageIDs + 1] = page.id
	end
	print("  |cffffd100/silkroad <" .. table.concat(pageIDs, "||") .. ">|r - " .. L["open a page directly"])
end

local function HandleSlashCommand(message)
	local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
	command = (command or ""):lower()

	if command == "" then
		SR.UI:Toggle()
	elseif commands[command] then
		commands[command].handler(rest)
	elseif SR.UI:HasPage(command) then
		SR.UI:OpenPage(command)
	else
		SR:Print(L["Unknown command:"], command)
		PrintHelp()
	end
end

SLASH_SILKROAD1 = "/silkroad"
SLASH_SILKROAD2 = "/silk"
SlashCmdList.SILKROAD = HandleSlashCommand

SR:RegisterSlashCommand("help", L["list commands"], PrintHelp)

SR:RegisterSlashCommand("minimap", L["show or hide the minimap button"], function()
	SR:SetSetting("minimap.hide", not SR:GetSetting("minimap.hide"))
end)

SR:RegisterSlashCommand("reset", L["reset the window position and size"], function()
	SR.UI:ResetLayout()
	SR:Print(L["Window position and size reset."])
end)

SR:RegisterSlashCommand("debug", L["toggle debug output"], function()
	local enabled = not SR:GetSetting("debug")
	SR:SetSetting("debug", enabled)
	SR:Print(enabled and L["Debug output enabled."] or L["Debug output disabled."])
end)

SR:RegisterSlashCommand("version", L["print the addon version"], function()
	SR:Print(L["Version"], SR.version)
end)

--[[ A small stand-in for the WoW Forever client, so SilkRoad's code can run
	outside the game (see smoke_test.py). It is not an emulator: it keeps just
	enough state (visibility, scripts, sizes, anchors, text) for the addon's
	code paths to execute, and it is strict where mistakes are likely:

	  * widget methods must exist in the real widget API (when the API lists
	    are supplied), so typos fail instead of silently doing nothing
	  * frame templates must exist and match the frame type
	  * anchors that over-constrain a region (e.g. TOPLEFT + RIGHT) fail
	  * reading an unknown global or writing an unexpected one fails
]]

MOCK = {
	output = {},
	timers = {},
	frames = {},
	sounds = {},
	defined = {},
	widgetMethods = nil, -- set of real widget method names, or nil = permissive
	templates = nil,     -- template name -> frame type, or nil = permissive
	knownAPI = nil,      -- set of real global API names, or nil = permissive
	tocFields = {},
	pendingItems = {},
	loadingItems = {},
	loadedAddons = {},
	modifiedClick = false,
	now = 1800000000, -- time()
	clock = 1000,     -- GetTime()
	replicate = {},   -- auction listings for full scans: { itemID, count, buyoutPrice }
	replicateRequests = 0,
	ahThrottled = false, -- true: ReplicateItems gets no answer
	allowedNilGlobals = {
		SilkRoadDB = true, SilkRoadCharDB = true, -- saved variables on first login
		GetMinimapShape = true, -- defined by minimap addons, checked before use
		Auctionator = true,     -- optional dependency, checked before use
		LibStub = true,         -- LibStub checks for an existing copy before creating one
		AuctionHouseFrame = true, -- exists once Blizzard_AuctionHouseUI has loaded
		LibQuestieDB = true,  -- optional data source (QuestieDB addon)
		QuestieLoader = true, -- optional (Questie addon), for map IDs
		TomTom = true,        -- optional waypoint addon
	},
	allowedNewGlobals = {
		LibStub = true,
		SilkRoad = true, SilkRoadDB = true, SilkRoadCharDB = true,
		SLASH_SILKROAD1 = true, SLASH_SILKROAD2 = true,
		SilkRoad_OnAddonCompartmentClick = true,
		SilkRoad_OnAddonCompartmentEnter = true,
		SilkRoad_OnAddonCompartmentLeave = true,
	},
}
local M = MOCK

local function define(name, value)
	_G[name] = value
	M.defined[#M.defined + 1] = name
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local Widget = {}
M.Widget = Widget

local WidgetMeta = {}
WidgetMeta.__index = function(self, key)
	local method = Widget[key]
	if method then
		return method
	end
	if type(key) == "string" and key:match("^[A-Z]") then
		if M.widgetMethods == nil or M.widgetMethods[key] then
			return function() end
		end
		error(("unknown widget method or missing child '%s' on %s"):format(key, rawget(self, "__type") or "?"), 2)
	end
	return nil
end

local VALID_POINTS = {
	TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
	RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function NewWidget(objectType, name, parent)
	local widget = setmetatable({
		__type = objectType, __name = name, __parent = parent, __children = {},
		__scripts = {}, __shown = true, __points = {}, __width = 0, __height = 0,
		__events = {},
	}, WidgetMeta)
	if parent then
		table.insert(parent.__children, widget)
	end
	table.insert(M.frames, widget)
	if name then
		rawset(_G, name, widget)
	end
	return widget
end
M.NewWidget = NewWidget

local function IsVisible(widget)
	while widget do
		if not widget.__shown then
			return false
		end
		widget = widget.__parent
	end
	return true
end

local function Subtree(widget, out)
	out[#out + 1] = widget
	for _, child in ipairs(widget.__children) do
		Subtree(child, out)
	end
	return out
end

local function SetShownInternal(widget, shown)
	shown = shown and true or false
	if widget.__shown == shown then
		return
	end
	local nodes = Subtree(widget, {})
	local before = {}
	for _, node in ipairs(nodes) do
		before[node] = IsVisible(node)
	end
	widget.__shown = shown
	for _, node in ipairs(nodes) do
		local now = IsVisible(node)
		if now ~= before[node] then
			local script = node.__scripts[now and "OnShow" or "OnHide"]
			if script then
				script(node)
			end
		end
	end
end

function Widget:Show() SetShownInternal(self, true) end
function Widget:Hide() SetShownInternal(self, false) end
function Widget:SetShown(shown) SetShownInternal(self, shown) end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible() return IsVisible(self) end
function Widget:GetParent() return self.__parent end
function Widget:GetName() return self.__name end
function Widget:GetObjectType() return self.__type end

local REGION_TYPES = { Texture = true, FontString = true }
function Widget:IsObjectType(objectType)
	return objectType == self.__type or (objectType == "Frame" and not REGION_TYPES[self.__type])
end

function Widget:SetEnabled(enabled) self.__disabled = not enabled end
function Widget:Enable() self.__disabled = false end
function Widget:Disable() self.__disabled = true end
function Widget:IsEnabled() return not self.__disabled end

function Widget:SetValue(value)
	assert(type(value) == "number", "SetValue: number expected")
	self.__value = value
end
function Widget:GetValue() return self.__value end

function Widget:SetScript(scriptType, handler)
	assert(type(scriptType) == "string", "SetScript: script type must be a string")
	assert(handler == nil or type(handler) == "function", "SetScript: handler must be a function or nil")
	self.__scripts[scriptType] = handler
end

function Widget:GetScript(scriptType)
	return self.__scripts[scriptType]
end

function Widget:HookScript(scriptType, handler)
	assert(type(handler) == "function", "HookScript: handler must be a function")
	local original = self.__scripts[scriptType]
	self.__scripts[scriptType] = function(...)
		if original then
			original(...)
		end
		handler(...)
	end
end

function Widget:RegisterEvent(event)
	self.__events[event] = true
end

function Widget:UnregisterEvent(event)
	self.__events[event] = nil
end

local function FireSizeChanged(widget)
	local script = widget.__scripts.OnSizeChanged
	if script then
		script(widget, widget.__width, widget.__height)
	end
end

function Widget:SetWidth(width)
	assert(type(width) == "number", "SetWidth: number expected")
	assert(width >= 0, "SetWidth: negative width " .. width)
	if width ~= self.__width then
		self.__width = width
		FireSizeChanged(self)
	end
end

function Widget:SetHeight(height)
	assert(type(height) == "number", "SetHeight: number expected")
	assert(height >= 0, "SetHeight: negative height " .. height)
	if height ~= self.__height then
		self.__height = height
		FireSizeChanged(self)
	end
end

function Widget:SetSize(width, height)
	self:SetWidth(width)
	self:SetHeight(height)
end

-- Unsized regions report a plausible laid-out size.
function Widget:GetWidth() return self.__width > 0 and self.__width or 700 end
function Widget:GetHeight() return self.__height > 0 and self.__height or 400 end
function Widget:GetCenter() return 1000, 700 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetFrameLevel() return self.__frameLevel or 1 end
function Widget:SetFrameLevel(level)
	assert(type(level) == "number", "SetFrameLevel: number expected")
	self.__frameLevel = level
end

local VALID_STRATA = {
	BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
	FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true,
}
function Widget:SetFrameStrata(strata)
	assert(VALID_STRATA[strata], "SetFrameStrata: invalid strata " .. tostring(strata))
end

-- Vertical / horizontal role of an anchor point. Mixing a centre anchor with
-- an edge anchor on the same axis over-constrains the region.
local function AxisRoles(point)
	local vertical = point:find("TOP") and "edge" or point:find("BOTTOM") and "edge" or "mid"
	local horizontal = point:find("LEFT") and "edge" or point:find("RIGHT") and "edge" or "mid"
	return vertical, horizontal
end

local function CheckAnchors(widget)
	local count = 0
	local hasVerticalEdge, hasVerticalMid, hasHorizontalEdge, hasHorizontalMid
	for point in pairs(widget.__points) do
		count = count + 1
		local vertical, horizontal = AxisRoles(point)
		if vertical == "edge" then hasVerticalEdge = true else hasVerticalMid = true end
		if horizontal == "edge" then hasHorizontalEdge = true else hasHorizontalMid = true end
	end
	if count < 2 then
		return
	end
	local names = {}
	for point in pairs(widget.__points) do
		names[#names + 1] = point
	end
	table.sort(names)
	if hasVerticalEdge and hasVerticalMid then
		error("conflicting vertical anchors: " .. table.concat(names, " + "), 3)
	end
	if hasHorizontalEdge and hasHorizontalMid then
		error("conflicting horizontal anchors: " .. table.concat(names, " + "), 3)
	end
end

function Widget:SetPoint(point, a, b, c, d)
	assert(VALID_POINTS[point], "SetPoint: invalid point " .. tostring(point))
	local relativeTo, relativePoint, x, y
	if type(a) == "number" then
		assert(type(b) == "number", "SetPoint(point, x, y): y must be a number")
		x, y = a, b
	elseif a == nil then
		x, y = 0, 0
	else
		assert(type(a) == "table" or type(a) == "string", "SetPoint: relative frame expected")
		relativeTo = a
		if type(b) == "number" then
			x, y = b, c or 0
		else
			assert(b == nil or VALID_POINTS[b], "SetPoint: invalid relative point " .. tostring(b))
			relativePoint, x, y = b or point, c or 0, d or 0
		end
	end
	assert(relativeTo ~= self, "SetPoint: region anchored to itself")
	self.__points[point] = { point, relativeTo, relativePoint or point, x, y }
	CheckAnchors(self)
end

function Widget:SetAllPoints(relativeTo)
	self.__points = { TOPLEFT = { "TOPLEFT", relativeTo }, BOTTOMRIGHT = { "BOTTOMRIGHT", relativeTo } }
end

function Widget:ClearAllPoints()
	self.__points = {}
end

function Widget:GetPoint(index)
	local first
	for _, info in pairs(self.__points) do
		first = info
		break
	end
	if not first then
		return nil
	end
	return first[1], first[2], first[3], first[4], first[5]
end

function Widget:CreateTexture(name, layer)
	return NewWidget("Texture", name, self)
end

function Widget:CreateFontString(name, layer, fontObject)
	local fontString = NewWidget("FontString", name, self)
	fontString.__font = fontObject
	return fontString
end

function Widget:SetText(text)
	if text ~= nil then
		text = tostring(text)
	end
	local changed = text ~= self.__text
	self.__text = text
	if changed and self.__type == "EditBox" then
		local script = self.__scripts.OnTextChanged
		if script then
			script(self, false)
		end
	end
end

function Widget:GetText()
	return self.__text
end

local VALID_JUSTIFY_H = { LEFT = true, CENTER = true, RIGHT = true }
function Widget:SetJustifyH(justify)
	assert(VALID_JUSTIFY_H[justify], "SetJustifyH: invalid value " .. tostring(justify))
end

local VALID_JUSTIFY_V = { TOP = true, MIDDLE = true, BOTTOM = true }
function Widget:SetJustifyV(justify)
	assert(VALID_JUSTIFY_V[justify], "SetJustifyV: invalid value " .. tostring(justify))
end

function Widget:SetFontObject(fontObject)
	assert(type(fontObject) == "string" or type(fontObject) == "table", "SetFontObject: font expected")
	self.__font = fontObject
end

function Widget:SetChecked(checked) self.__checked = checked and true or false end
function Widget:GetChecked() return self.__checked or false end
function Widget:HasFocus() return self.__focus or false end
function Widget:SetFocus() self.__focus = true end
function Widget:ClearFocus() self.__focus = false end

function Widget:SetTexture(texture)
	assert(texture == nil or type(texture) == "string" or type(texture) == "number", "SetTexture: path or fileID expected")
	self.__texture = texture
end

function Widget:SetAtlas(atlas, useAtlasSize)
	assert(type(atlas) == "string", "SetAtlas: atlas name expected")
	self.__atlas = atlas
end

function Widget:RegisterForClicks(...)
	local valid = { AnyUp = true, AnyDown = true, LeftButtonUp = true, LeftButtonDown = true,
		RightButtonUp = true, RightButtonDown = true, MiddleButtonUp = true }
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		assert(valid[value], "RegisterForClicks: invalid value " .. tostring(value))
	end
end

-- Simulates a click: runs OnClick the way the client would.
function M.Click(widget, mouseButton)
	if widget.__type == "CheckButton" then
		widget.__checked = not widget.__checked
	end
	local script = widget.__scripts.OnClick
	assert(script, "Click: widget has no OnClick handler")
	script(widget, mouseButton or "LeftButton", false)
end

function M.RunScript(widget, scriptType, ...)
	local script = widget.__scripts[scriptType]
	assert(script, "RunScript: no " .. scriptType .. " handler")
	script(widget, ...)
end

---------------------------------------------------------------------------
-- Templates (only the parts SilkRoad touches)
---------------------------------------------------------------------------

local templateBuilders = {}

templateBuilders.ButtonFrameTemplate = function(frame)
	frame.Inset = NewWidget("Frame", nil, frame)
	frame.TitleContainer = NewWidget("Frame", nil, frame)
	frame.SetTitle = function(self, title)
		assert(type(title) == "string", "SetTitle: string expected")
		self.__title = title
	end
	frame.SetPortraitToAsset = function(self, texture)
		assert(texture ~= nil, "SetPortraitToAsset: texture expected")
	end
end

templateBuilders.UICheckButtonTemplate = function(check)
	check.Text = check:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
end

templateBuilders.SearchBoxTemplate = function(box)
	box.Instructions = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	box.clearButton = NewWidget("Button", nil, box)
end

templateBuilders.BackdropTemplate = function(frame)
	frame.SetBackdrop = function(self, backdrop)
		assert(type(backdrop) == "table", "SetBackdrop: table expected")
	end
	frame.SetBackdropColor = function() end
	frame.SetBackdropBorderColor = function() end
end

templateBuilders.MinimalSliderWithSteppersTemplate = function(holder)
	holder.Slider = NewWidget("Slider", nil, holder)
	holder.__callbacks = {}
	holder.Init = function(self, value, minValue, maxValue, steps, formatters)
		assert(type(value) == "number", "Slider Init: value must be a number")
		assert(minValue < maxValue, "Slider Init: min must be below max")
		assert(steps > 0 and steps == math.floor(steps), "Slider Init: steps must be a positive integer")
		self.__value, self.__min, self.__max = value, minValue, maxValue
		self.__formatters = formatters
		for labelID, formatter in pairs(formatters or {}) do
			assert(type(labelID) == "number", "Slider Init: formatter keys are MinimalSliderWithSteppersMixin.Label values")
			assert(type(formatter(value)) == "string", "Slider Init: formatter must return a string")
		end
	end
	holder.RegisterCallback = function(self, event, func, owner)
		assert(event == MinimalSliderWithSteppersMixin.Event.OnValueChanged, "Slider: unexpected callback event")
		assert(owner ~= nil, "Slider RegisterCallback: owner required")
		table.insert(self.__callbacks, { func = func, owner = owner })
	end
	holder.SetValue = function(self, value)
		assert(type(value) == "number", "Slider SetValue: number expected")
		if value == self.__value then
			return
		end
		self.__value = value
		for labelID, formatter in pairs(self.__formatters or {}) do
			formatter(value)
		end
		for _, callback in ipairs(self.__callbacks) do
			callback.func(callback.owner, value)
		end
	end
end

local function NewMenuDescription()
	local description = { items = {} }
	local function add(kind, text, a, b, data)
		local item = { kind = kind, text = text, a = a, b = b, data = data }
		table.insert(description.items, item)
		return setmetatable(item, { __index = description })
	end
	function description:CreateRadio(text, isSelected, setSelected, data)
		assert(type(text) == "string", "CreateRadio: text expected")
		assert(type(isSelected) == "function" and type(setSelected) == "function", "CreateRadio: callbacks expected")
		isSelected(data)
		return add("radio", text, isSelected, setSelected, data)
	end
	function description:CreateButton(text, callback, data) return add("button", text, callback, nil, data) end
	function description:CreateCheckbox(text, isSelected, setSelected, data) return add("checkbox", text, isSelected, setSelected, data) end
	function description:CreateTitle(text) return add("title", text) end
	function description:CreateDivider() return add("divider") end
	return description
end

templateBuilders.WowStyle1DropdownTemplate = function(dropdown)
	dropdown.SetupMenu = function(self, generator)
		assert(type(generator) == "function", "SetupMenu: generator expected")
		self.__generator = generator
		self:GenerateMenu()
	end
	dropdown.GenerateMenu = function(self)
		local root = NewMenuDescription()
		self.__generator(self, root)
		self.__menu = root
	end
end

-- Picks the n-th entry of a dropdown's menu, as a player would.
function M.PickDropdown(dropdown, index)
	local item = dropdown.__menu.items[index]
	assert(item, "PickDropdown: no item " .. index)
	item.b(item.data)
	dropdown:GenerateMenu()
end

templateBuilders.WowScrollBoxList = function(box)
	box.__pool = {}
	box.__active = {}
	box.SetDataProvider = function(self, provider, retainScroll)
		assert(type(provider) == "table" and provider.__items, "SetDataProvider: data provider expected")
		local view = assert(self.__view, "SetDataProvider: ScrollBox not initialised with a view")
		self.__active = {}
		for index, element in ipairs(provider.__items) do
			local frame = self.__pool[index]
			if not frame then
				frame = NewWidget(view.__frameType, nil, self)
				self.__pool[index] = frame
			end
			view.__initializer(frame, element)
			self.__active[index] = frame
		end
	end
	box.ForEachFrame = function(self, func)
		for _, frame in ipairs(self.__active) do
			func(frame)
		end
	end
end

local function ApplyTemplate(widget, frameType, template)
	if not template then
		return
	end
	for name in template:gmatch("[^,%s]+") do
		if M.templates then
			local templateType = M.templates[name]
			assert(templateType, "CreateFrame: unknown template " .. name)
			-- Frame templates can be inherited by any frame type; others must match.
			assert(templateType == frameType or templateType == "Frame",
				("CreateFrame: template %s is a %s, not a %s"):format(name, templateType, frameType))
		end
		local builder = templateBuilders[name]
		if builder then
			builder(widget)
		end
	end
end

local VALID_FRAME_TYPES = {
	Frame = true, Button = true, CheckButton = true, EditBox = true, Slider = true,
	EventFrame = true, DropdownButton = true, ScrollFrame = true, StatusBar = true,
	GameTooltip = true,
}

define("CreateFrame", function(frameType, name, parent, template)
	assert(VALID_FRAME_TYPES[frameType], "CreateFrame: unsupported frame type " .. tostring(frameType))
	assert(name == nil or type(name) == "string", "CreateFrame: name must be a string or nil")
	local frame = NewWidget(frameType, name, parent)
	ApplyTemplate(frame, frameType, template)
	return frame
end)

-- Fires a game event on every frame that registered for it.
function M.FireEvent(event, ...)
	for _, frame in ipairs(M.frames) do
		if frame.__events[event] and frame.__scripts.OnEvent then
			frame.__scripts.OnEvent(frame, event, ...)
		end
	end
end

-- Timers fire in order of their due time. RunTimers lets "a few seconds" of
-- game time pass without moving the clock: everything due within
-- SHORT_WAIT runs (debounces, frame-by-frame batches, short delays), while
-- long timers such as timeouts only fire once M.Advance moves the clock.
local SHORT_WAIT = 5
local timerSequence = 0

function M.Schedule(delay, callback)
	timerSequence = timerSequence + 1
	table.insert(M.timers, { due = M.clock + delay, sequence = timerSequence, callback = callback })
end

function M.RunTimers()
	local horizon = M.clock + SHORT_WAIT
	for _ = 1, 10000 do
		local nextIndex, nextTimer
		for index, timer in ipairs(M.timers) do
			if timer.due <= horizon and (not nextTimer or timer.due < nextTimer.due
				or (timer.due == nextTimer.due and timer.sequence < nextTimer.sequence)) then
				nextIndex, nextTimer = index, timer
			end
		end
		if not nextTimer then
			return
		end
		table.remove(M.timers, nextIndex)
		nextTimer.callback()
	end
	error("RunTimers: timers keep scheduling more timers (endless loop?)")
end

---------------------------------------------------------------------------
-- Global frames and UI tables
---------------------------------------------------------------------------

define("UIParent", NewWidget("Frame", "UIParent"))
define("Minimap", NewWidget("Frame", "Minimap", UIParent))
Minimap:SetSize(140, 140)
define("SettingsPanel", NewWidget("Frame", "SettingsPanel", UIParent))
SettingsPanel:Hide()

define("GameTooltip", NewWidget("GameTooltip", "GameTooltip", UIParent))
GameTooltip:Hide()
GameTooltip.SetItemByID = function(self, itemID)
	assert(type(itemID) == "number", "SetItemByID: itemID expected")
end
define("GameTooltip_Hide", function() GameTooltip:Hide() end)

define("UISpecialFrames", {})
define("SlashCmdList", {})
define("UNKNOWN", "Unknown")
define("SOUNDKIT", {
	IG_MAINMENU_OPTION = 852,
	IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
	IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
	IG_CHARACTER_INFO_OPEN = 839,
	IG_CHARACTER_INFO_CLOSE = 840,
})

define("MinimalSliderWithSteppersMixin", {
	Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 },
	Event = { OnValueChanged = "OnValueChanged", OnInteractStart = "OnInteractStart", OnInteractEnd = "OnInteractEnd" },
})
define("ScrollBoxConstants", { RetainScrollPosition = true })
define("ScrollUtil", {
	InitScrollBoxListWithScrollBar = function(scrollBox, scrollBar, view)
		assert(scrollBox.SetDataProvider and scrollBar and view.__initializer, "InitScrollBoxListWithScrollBar: bad arguments")
		scrollBox.__view = view
	end,
})
define("CreateScrollBoxListLinearView", function()
	local view = {}
	function view:SetElementExtent(extent)
		assert(type(extent) == "number" and extent > 0, "SetElementExtent: positive number expected")
	end
	function view:SetElementInitializer(frameTypeOrTemplate, initializer)
		assert(VALID_FRAME_TYPES[frameTypeOrTemplate] or (M.templates and M.templates[frameTypeOrTemplate]),
			"SetElementInitializer: unknown frame type or template " .. tostring(frameTypeOrTemplate))
		self.__frameType = VALID_FRAME_TYPES[frameTypeOrTemplate] and frameTypeOrTemplate or "Frame"
		self.__initializer = initializer
	end
	return view
end)
define("CreateDataProvider", function(items)
	return { __items = items or {} }
end)

define("Settings", {
	RegisterCanvasLayoutCategory = function(frame, name)
		assert(type(frame) == "table" and type(name) == "string", "RegisterCanvasLayoutCategory: frame and name expected")
		M.settingsCategory = { name = name, frame = frame, GetID = function() return 1001 end }
		return M.settingsCategory
	end,
	RegisterAddOnCategory = function(category)
		assert(category == M.settingsCategory, "RegisterAddOnCategory: unknown category")
		M.settingsRegistered = true
	end,
	OpenToCategory = function(categoryID)
		M.settingsOpened = categoryID
	end,
})

define("ChatFrameUtil", {
	InsertLink = function(text)
		return false
	end,
})

---------------------------------------------------------------------------
-- Global functions
---------------------------------------------------------------------------

define("print", function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	table.insert(M.output, table.concat(parts, " "))
end)
-- A controllable clock: M.Advance(seconds) moves both time() and GetTime().
define("time", function() return M.now end)
define("GetTime", function() return M.clock end)
function M.Advance(seconds)
	M.now = M.now + seconds
	M.clock = M.clock + seconds
	M.RunTimers()
end

define("BreakUpLargeNumbers", function(value)
	local text = tostring(math.floor(value))
	local formatted
	repeat
		text, formatted = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until formatted == 0
	return text
end)
define("tinsert", table.insert)
define("strmatch", string.match)
define("strtrim", function(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end)

define("Mixin", function(object, ...)
	for i = 1, select("#", ...) do
		for key, value in pairs((select(i, ...))) do
			object[key] = value
		end
	end
	return object
end)

define("hooksecurefunc", function(a, b, c)
	local tbl, name, hook
	if type(a) == "string" then
		tbl, name, hook = _G, a, b
	else
		tbl, name, hook = a, b, c
	end
	local original = tbl[name]
	assert(type(original) == "function", "hooksecurefunc: no function " .. tostring(name))
	tbl[name] = function(...)
		local results = { original(...) }
		hook(...)
		return unpack(results)
	end
end)

define("WrapTextInColorCode", function(text, hex)
	assert(type(hex) == "string" and #hex == 8, "WrapTextInColorCode: 8-digit hex colour expected")
	return "|c" .. hex .. text .. "|r"
end)

define("GetMoneyString", function(copper, separateThousands)
	assert(type(copper) == "number" and copper >= 0 and copper == math.floor(copper),
		"GetMoneyString: non-negative whole copper expected, got " .. tostring(copper))
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end)

define("PlaySound", function(soundKitID)
	assert(type(soundKitID) == "number", "PlaySound: sound kit ID expected")
	table.insert(M.sounds, soundKitID)
end)

define("GetRealmName", function() return "Test Realm" end)
define("GetCursorPosition", function() return 1100, 800 end)
define("IsModifiedClick", function() return M.modifiedClick end)
define("HandleModifiedItemClick", function(link)
	assert(type(link) == "string", "HandleModifiedItemClick: link expected")
	M.lastModifiedLink = link
	return true
end)
define("HideUIPanel", function(frame) frame:Hide() end)

-- Professions: indices for prof1, prof2, archaeology, fishing, cooking.
M.professions = {
	[1] = { "Tailoring", 136249, 75, 150, 0, 0, 197 },
	[2] = { "Enchanting", 136244, 40, 75, 0, 0, 333 },
	[5] = { "Cooking", 133971, 1, 75, 0, 0, 185 },
}
define("GetProfessions", function()
	return M.professions[1] and 1, M.professions[2] and 2, nil, nil, M.professions[5] and 5
end)
define("GetProfessionInfo", function(index)
	local info = assert(M.professions[index], "GetProfessionInfo: invalid index")
	return unpack(info)
end)

define("C_AddOns", {
	GetAddOnMetadata = function(addon, field)
		assert(addon == "SilkRoad", "GetAddOnMetadata: unexpected addon " .. tostring(addon))
		return M.tocFields[field]
	end,
	IsAddOnLoaded = function(addon)
		assert(type(addon) == "string", "IsAddOnLoaded: addon name expected")
		local loaded = M.loadedAddons[addon] or false
		return loaded, loaded
	end,
})

---------------------------------------------------------------------------
-- Auction house
---------------------------------------------------------------------------

-- Constants from the client, read by LibAHTab.
define("WOW_PROJECT_MAINLINE", 1)
define("WOW_PROJECT_CAMELOT", 21)
define("WOW_PROJECT_ID", WOW_PROJECT_CAMELOT)

define("PanelTemplates_TabResize", function(tab, padding, absoluteSize, minWidth)
	assert(type(tab) == "table", "PanelTemplates_TabResize: tab expected")
end)
define("PanelTemplates_SelectTab", function(tab)
	tab.__selected = true
end)
define("PanelTemplates_DeselectTab", function(tab)
	tab.__selected = false
end)

-- Full scans: ReplicateItems answers on a later frame unless throttled.
define("C_AuctionHouse", {
	-- Like the real client, the result event fires more than once per
	-- request (again as item data for the listings arrives).
	ReplicateItems = function()
		M.replicateRequests = M.replicateRequests + 1
		if not M.ahThrottled then
			for _, delay in ipairs({ 0, 0.5, 1.5 }) do
				M.Schedule(delay, function()
					M.FireEvent("REPLICATE_ITEM_LIST_UPDATE")
				end)
			end
		end
	end,
	GetNumReplicateItems = function()
		return #M.replicate
	end,
	GetReplicateItemInfo = function(index)
		assert(type(index) == "number" and index >= 0 and index < #M.replicate,
			"GetReplicateItemInfo: 0-based index out of range: " .. tostring(index))
		local listing = M.replicate[index + 1]
		local item = M.items[listing[1]]
		return item and item.name, item and item.icon, listing[2], 1, true, 10, "PLAYER", 0, 0,
			listing[3], 0, nil, nil, "Seller", "Seller-Realm", 0, listing[1], item ~= nil
	end,
})

-- Simulates Blizzard_AuctionHouseUI loading the first time an auctioneer is visited.
function M.LoadAuctionHouseUI()
	local frame = NewWidget("Frame", "AuctionHouseFrame", UIParent)
	frame:Hide()
	frame:SetSize(800, 538)
	frame.Tabs = {}
	for i = 1, 3 do
		frame.Tabs[i] = CreateFrame("Button", nil, frame, "AuctionHouseFrameDisplayModeTabTemplate")
	end
	frame.SetDisplayMode = function(self, displayMode)
		assert(type(displayMode) == "table", "SetDisplayMode: display mode table expected")
		self.displayMode = displayMode
	end
	frame.SetTitle = function(self, title)
		self.__title = title
	end
	M.loadedAddons.Blizzard_AuctionHouseUI = true
	M.FireEvent("ADDON_LOADED", "Blizzard_AuctionHouseUI")
end

function M.OpenAuctionHouse()
	AuctionHouseFrame:Show()
	AuctionHouseFrame:SetDisplayMode({ "CategoriesList", "SearchBar", "BrowseResultsFrame" })
	M.FireEvent("AUCTION_HOUSE_SHOW")
end

function M.CloseAuctionHouse()
	AuctionHouseFrame:Hide()
	M.FireEvent("AUCTION_HOUSE_CLOSED")
end

define("C_Timer", {
	After = function(delay, callback)
		assert(type(delay) == "number" and type(callback) == "function", "C_Timer.After: delay and callback expected")
		M.Schedule(delay, callback)
	end,
})

-- Item data. Items in M.pendingItems behave like uncached items: they return
-- nil until requested, then arrive with GET_ITEM_INFO_RECEIVED.
M.items = {
	[2589] = { name = "Linen Cloth", quality = 1, icon = 132889, sellPrice = 13 },
	[2996] = { name = "Bolt of Linen Cloth", quality = 1, icon = 132889, sellPrice = 25 },
	[2320] = { name = "Coarse Thread", quality = 1, icon = 132912, sellPrice = 2 },
	[6948] = { name = "Hearthstone", quality = 1, icon = 134414, sellPrice = 0 },
	[4306] = { name = "Silk Cloth", quality = 1, icon = 132905, sellPrice = 38 },
}

local function ResolveItem(item)
	if type(item) == "number" then
		return item
	end
	assert(type(item) == "string", "item ID, link or name expected")
	local id = item:match("item:(%d+)")
	if id then
		return tonumber(id)
	end
	for itemID, data in pairs(M.items) do
		if data.name == item and not M.pendingItems[itemID] then
			return itemID
		end
	end
end

local function ItemLink(itemID)
	return ("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(itemID, M.items[itemID].name)
end

define("C_Item", {
	GetItemInfo = function(item)
		local itemID = ResolveItem(item)
		local data = itemID and M.items[itemID]
		if not data or M.pendingItems[itemID] then
			return nil
		end
		return data.name, ItemLink(itemID), data.quality, 10, 1, "Tradeskill", "Cloth", 200, "",
			data.icon, data.sellPrice, 7, 5, 0, 0, nil, true
	end,
	GetItemInfoInstant = function(item)
		local itemID = ResolveItem(item)
		if itemID and M.items[itemID] then
			return itemID, "Tradeskill", "Cloth", "", M.items[itemID].icon, 7, 5
		end
	end,
	RequestLoadItemDataByID = function(itemID)
		assert(type(itemID) == "number", "RequestLoadItemDataByID: itemID expected")
		-- The data arrives later, together with the event, as in the client.
		if M.pendingItems[itemID] and not M.loadingItems[itemID] then
			M.loadingItems[itemID] = true
			M.Schedule(0, function()
				M.pendingItems[itemID] = nil
				M.loadingItems[itemID] = nil
				M.FireEvent("GET_ITEM_INFO_RECEIVED", itemID, true)
			end)
		end
	end,
	GetItemIconByID = function(itemID)
		return M.items[itemID] and M.items[itemID].icon or 134400
	end,
	GetItemNameByID = function(itemID)
		return M.items[itemID] and not M.pendingItems[itemID] and M.items[itemID].name or nil
	end,
	GetItemQualityByID = function(itemID)
		return M.items[itemID] and M.items[itemID].quality or nil
	end,
	GetItemQualityColor = function(quality)
		assert(type(quality) == "number", "GetItemQualityColor: quality expected")
		return 1, 1, 1, "ffffffff"
	end,
	DoesItemExistByID = function(itemID)
		assert(type(itemID) == "number", "DoesItemExistByID: itemID expected")
		return M.items[itemID] ~= nil
	end,
})

---------------------------------------------------------------------------
-- Game version, professions window, merchants, maps
---------------------------------------------------------------------------

define("GetBuildInfo", function()
	return "1.60.1", "70938", "Nov 1 2026", 16001
end)

define("UnitFactionGroup", function(unit)
	return "Horde", "Horde"
end)

-- The open profession window: M.tradeSkill = { professionID, name, recipes = { [recipeID] = learned } }
M.tradeSkill = nil
M.schematics = {} -- [recipeID] = schematic table for recipes missing from the generated data
define("C_TradeSkillUI", {
	IsTradeSkillReady = function() return M.tradeSkill ~= nil end,
	IsTradeSkillLinked = function() return false end,
	IsTradeSkillGuild = function() return false end,
	IsNPCCrafting = function() return false end,
	-- Like Forever: the child profession identifies the window (its parent is
	-- the profession); the base info carries no profession ID.
	GetChildProfessionInfo = function()
		local open = M.tradeSkill
		if not open then
			return { professionID = 0 }
		end
		return { professionID = open.childID or 2830, professionName = "Classic " .. open.name,
			parentProfessionID = open.professionID, parentProfessionName = open.name }
	end,
	GetBaseProfessionInfo = function()
		return { professionID = 0 }
	end,
	GetAllRecipeIDs = function()
		local ids = {}
		for recipeID in pairs(M.tradeSkill and M.tradeSkill.recipes or {}) do
			ids[#ids + 1] = recipeID
		end
		return ids
	end,
	GetRecipeInfo = function(recipeID)
		local learned = M.tradeSkill and M.tradeSkill.recipes[recipeID]
		if learned == nil then return nil end
		return { recipeID = recipeID, learned = learned }
	end,
	GetRecipeSchematic = function(recipeID, isRecraft)
		assert(isRecraft == false, "GetRecipeSchematic: isRecraft expected")
		return M.schematics[recipeID]
	end,
})

-- The open merchant: M.merchant = { { itemID, price, stackCount, hasExtendedCost }, ... }
M.merchant = {}
define("GetMerchantNumItems", function() return #M.merchant end)
define("GetMerchantItemID", function(index) return M.merchant[index] and M.merchant[index][1] end)
define("C_MerchantFrame", {
	GetItemInfo = function(index)
		local entry = M.merchant[index]
		return entry and { price = entry[2], stackCount = entry[3] or 1, hasExtendedCost = entry[4] or false } or nil
	end,
})

M.areas = { [1637] = "Orgrimmar", [17] = "The Barrens", [209] = "Shadowfang Keep" }
M.waypoints = {}
define("C_Map", {
	GetAreaInfo = function(areaID) return M.areas[areaID] end,
	CanSetUserWaypointOnMap = function(uiMapID) return type(uiMapID) == "number" end,
	SetUserWaypoint = function(point)
		assert(type(point) == "table" and point.uiMapID, "SetUserWaypoint: UiMapPoint expected")
		table.insert(M.waypoints, point)
	end,
})
define("C_SuperTrack", { SetSuperTrackedUserWaypoint = function(enabled) M.superTracked = enabled end })
define("UiMapPoint", {
	CreateFromCoordinates = function(uiMapID, x, y)
		assert(x >= 0 and x <= 1 and y >= 0 and y <= 1, "UiMapPoint: coordinates must be 0..1")
		return { uiMapID = uiMapID, x = x, y = y }
	end,
})
define("ButtonFrameTemplate_HidePortrait", function(frame)
	assert(frame.Inset, "ButtonFrameTemplate_HidePortrait: ButtonFrameTemplate frame expected")
end)

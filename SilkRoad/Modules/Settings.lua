--[[ SilkRoad - Modules/Settings.lua
	SilkRoad's settings page, pinned to the bottom of the sidebar, split into
	tabs by purpose:
	  General  minimap button, window, the open/close key binding
	  Prices   auction house cut, preferred price source, automatic scans
	  Data     wiping market data, resetting settings
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local Page = SR.UI:RegisterPage({
	id = "settings",
	order = 1000,
	placement = "bottom",
	title = L["Settings"],
	description = L.SETTINGS_DESC,
	icon = "Interface\\Icons\\INV_Misc_Gear_01",
	-- The controls update themselves; refreshing on every setting change
	-- would fight with a slider while it is being dragged.
	autoRefresh = false,
})

local SECTION_WIDTH = 560
local TABS = {
	{ id = "general", label = L["General"] },
	{ id = "prices", label = L["Prices"] },
	{ id = "data", label = L["Data"] },
}

local function Section(parent, title, anchor, offsetY)
	local header = Widgets.CreateHeader(parent, title)
	if anchor then
		header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY or -24)
	else
		header:SetPoint("TOPLEFT")
	end
	header:SetWidth(SECTION_WIDTH)
	return header
end

local function Note(parent, text, anchor)
	local note = Widgets.CreateLabel(parent, text, "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
	note:SetWidth(SECTION_WIDTH)
	note:SetSpacing(2)
	return note
end

function Page:OnCreate(frame)
	self.controls = {}
	self.tabs = {}

	self.TabBar = Widgets.CreateTabBar(frame, TABS, function(id)
		self:SelectTab(id)
	end)
	self.TabBar:SetPoint("TOPLEFT")
	self.TabBar:SetPoint("TOPRIGHT")

	for _, tab in ipairs(TABS) do
		local content = CreateFrame("Frame", nil, frame)
		content:SetPoint("TOPLEFT", self.TabBar, "BOTTOMLEFT", 0, -14)
		content:SetPoint("BOTTOMRIGHT")
		content:Hide()
		self.tabs[tab.id] = content
	end

	self:BuildGeneral(self.tabs.general)
	self:BuildPrices(self.tabs.prices)
	self:BuildData(self.tabs.data)
	self:SelectTab(SR.DB.settings.settingsTab or "general")
end

function Page:Track(control)
	self.controls[#self.controls + 1] = control
	return control
end

function Page:SelectTab(id)
	if not self.tabs[id] then
		id = "general"
	end
	SR.DB.settings.settingsTab = id
	for tabID, content in pairs(self.tabs) do
		content:SetShown(tabID == id)
	end
	self.TabBar:Select(id)
	self.currentTab = id
	self:Refresh()
end

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------

function Page:BuildGeneral(parent)
	local general = Section(parent, L["General"])

	local minimap = self:Track(Widgets.CreateCheckbox(parent, L["Show minimap button"],
		L["The addon compartment menu by the minimap always lists SilkRoad, even with the button hidden."],
		function()
			return not SR:GetSetting("minimap.hide")
		end,
		function(checked)
			SR:SetSetting("minimap.hide", not checked)
		end))
	minimap:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -8)

	local tooltipLabel = Widgets.CreateLabel(parent, L["Prices in item tooltips"], "GameFontHighlight")
	tooltipLabel:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 4, -8)
	local tooltipMode = self:Track(Widgets.CreateDropdown(parent, 220, {
		{ value = "off", label = L["Off"] },
		{ value = "single", label = L["Single item"] },
		{ value = "stack", label = L["Whole stack"] },
		{ value = "both", label = L["Single and stack"] },
	}, function()
		return SR:GetSetting("tooltipMode")
	end, function(value)
		SR:SetSetting("tooltipMode", value)
	end))
	tooltipMode:SetPoint("LEFT", tooltipLabel, "RIGHT", 12, 0)
	Widgets.AttachTooltip(tooltipMode, L["Prices in item tooltips"], L.TOOLTIP_MODE_TOOLTIP)
	local tooltipNote = Note(parent, L.TOOLTIP_MODE_NOTE, tooltipLabel)
	tooltipNote:SetPoint("TOPLEFT", tooltipLabel, "BOTTOMLEFT", 0, -12)

	local recipesLabel = Widgets.CreateLabel(parent, L["Recipes in item tooltips"], "GameFontHighlight")
	recipesLabel:SetPoint("TOPLEFT", tooltipNote, "BOTTOMLEFT", 0, -16)
	local tooltipRecipes = self:Track(Widgets.CreateDropdown(parent, 220, {
		{ value = "off", label = L["Off"] },
		{ value = "favorites", label = L["Favorites only"] },
		{ value = "learned", label = L["Learned and favorites"] },
		{ value = "all", label = L["All recipes"] },
	}, function()
		return SR:GetSetting("tooltipRecipes")
	end, function(value)
		SR:SetSetting("tooltipRecipes", value)
	end))
	tooltipRecipes:SetPoint("LEFT", recipesLabel, "RIGHT", 12, 0)
	Widgets.AttachTooltip(tooltipRecipes, L["Recipes in item tooltips"], L.TOOLTIP_RECIPES_TOOLTIP)

	local professionPrices = self:Track(Widgets.CreateCheckbox(parent, L["Prices in the professions window"],
		L.PROFESSION_PRICES_TOOLTIP,
		function()
			return SR:GetSetting("professionPrices")
		end,
		function(checked)
			SR:SetSetting("professionPrices", checked)
		end))
	professionPrices:SetPoint("TOPLEFT", recipesLabel, "BOTTOMLEFT", -6, -14)

	local scale = self:Track(Widgets.CreateSlider(parent, L["Window scale"], 0.7, 1.5, 0.05,
		function()
			return SR:GetSetting("window.scale")
		end,
		function(value)
			SR:SetSetting("window.scale", Util.Round(value, 2))
		end,
		function(value)
			return ("%d%%"):format(Util.Round(value * 100))
		end))
	scale:SetPoint("TOPLEFT", professionPrices, "BOTTOMLEFT", 6, -12)

	local reset = Widgets.CreateButton(parent, L["Reset window position"], 180, function()
		SR.UI:ResetLayout()
		self:Refresh()
	end)
	reset:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -8)

	-- Key binding
	local binding = Section(parent, L["Key binding"], reset, -24)
	local bindingLabel = Widgets.CreateLabel(parent, L["Open / close SilkRoad"], "GameFontHighlight")
	bindingLabel:SetPoint("TOPLEFT", binding, "BOTTOMLEFT", 0, -12)

	local keyButton = Widgets.CreateButton(parent, "", 160)
	keyButton:SetPoint("LEFT", bindingLabel, "RIGHT", 16, 0)
	keyButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	keyButton:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			self:ClearKey()
		else
			self:StartKeyCapture()
		end
	end)
	keyButton:SetScript("OnKeyDown", function(_, key)
		self:OnCapturedKey(key)
	end)
	-- Setting an OnKeyDown script turns keyboard input on; the button must
	-- only take keys while it waits for one, or Escape (and every other key)
	-- stops reaching the game whenever the Settings page is open.
	keyButton:EnableKeyboard(false)
	keyButton:HookScript("OnHide", function()
		if self.capturingKey then
			self:StopKeyCapture() -- page or window closed while waiting for a key
		end
	end)
	Widgets.AttachTooltip(keyButton, L["Open / close SilkRoad"], L.KEY_BINDING_TOOLTIP)
	self.KeyButton = keyButton

	local clearKey = Widgets.CreateButton(parent, L["Clear"], 80, function()
		self:ClearKey()
	end)
	clearKey:SetPoint("LEFT", keyButton, "RIGHT", 6, 0)

	local bindingNote = Note(parent, L.KEY_BINDING_NOTE, bindingLabel)
	bindingNote:SetPoint("TOPLEFT", bindingLabel, "BOTTOMLEFT", 0, -14)
end

function Page:UpdateKeyButton()
	if self.capturingKey then
		self.KeyButton:SetText(L["Press a key..."])
	else
		self.KeyButton:SetText(SR.Bindings:GetKeyText())
	end
end

function Page:StartKeyCapture()
	self.capturingKey = true
	self.KeyButton:EnableKeyboard(true) -- keys stop at the button until one is pressed
	self:UpdateKeyButton()
end

function Page:StopKeyCapture()
	self.capturingKey = false
	self.KeyButton:EnableKeyboard(false)
	self:UpdateKeyButton()
end

function Page:OnCapturedKey(key)
	if not self.capturingKey then
		return
	end
	if key == "ESCAPE" then
		self:StopKeyCapture()
		return
	end
	local combo = SR.Bindings:ComboFor(key)
	if not combo then
		return -- a modifier on its own: keep waiting for the actual key
	end
	local ok, detail = SR.Bindings:SetKey(combo)
	self:StopKeyCapture()
	if not ok then
		SR:Print(detail)
	elseif detail then
		SR:Print(L["%s now opens SilkRoad (it was bound to %s)."]:format(GetBindingText(combo), detail))
	else
		SR:Print(L["%s now opens SilkRoad."]:format(GetBindingText(combo)))
	end
end

function Page:ClearKey()
	local ok, problem = SR.Bindings:ClearKeys()
	if not ok then
		SR:Print(problem)
	end
	self:StopKeyCapture()
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

function Page:BuildPrices(parent)
	local pricing = Section(parent, L["Pricing"])

	local cut = self:Track(Widgets.CreateSlider(parent, L["Auction house cut"], 0, 15, 1,
		function()
			return SR:GetSetting("auctionCutPercent")
		end,
		function(value)
			SR:SetSetting("auctionCutPercent", Util.Round(value))
		end,
		function(value)
			return ("%d%%"):format(Util.Round(value))
		end))
	cut:SetPoint("TOPLEFT", pricing, "BOTTOMLEFT", 2, -10)

	local sourceLabel = Widgets.CreateLabel(parent, L["Preferred auction price source"], "GameFontHighlight")
	sourceLabel:SetPoint("TOPLEFT", cut, "BOTTOMLEFT", 0, -10)

	local source = self:Track(Widgets.CreateDropdown(parent, 220, function()
		local options = { { value = "auto", label = L["Automatic (first with data)"] } }
		for _, provider in ipairs(SR.Prices:GetProviders()) do
			options[#options + 1] = { value = provider.id, label = provider.label }
		end
		return options
	end, function()
		return SR:GetSetting("priceSource")
	end, function(value)
		SR:SetSetting("priceSource", value)
	end))
	source:SetPoint("TOPLEFT", sourceLabel, "BOTTOMLEFT", 0, -6)

	local sourceHelp = Note(parent, L["If the preferred source has no price for an item, the other sources are tried in order."], source)

	local auctionHouse = Section(parent, L["Auction house"], sourceHelp, -24)
	local autoScan = self:Track(Widgets.CreateCheckbox(parent, L["Scan automatically when the auction house opens"], L.AUTO_SCAN_TOOLTIP,
		function()
			return SR:GetSetting("autoScan")
		end,
		function(checked)
			SR:SetSetting("autoScan", checked)
		end))
	autoScan:SetPoint("TOPLEFT", auctionHouse, "BOTTOMLEFT", -2, -8)
	local autoScanHelp = Note(parent, L.AH_SCAN_NOTE, autoScan)
	autoScanHelp:SetPoint("TOPLEFT", autoScan, "BOTTOMLEFT", 2, -4)
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

function Page:BuildData(parent)
	-- Market data
	local market = Section(parent, L["Market data"])
	local marketText = Widgets.CreateLabel(parent, L.WIPE_MARKET_DESC, "GameFontHighlight")
	marketText:SetPoint("TOPLEFT", market, "BOTTOMLEFT", 0, -8)
	marketText:SetWidth(SECTION_WIDTH)
	marketText:SetSpacing(2)
	self.MarketSummary = Note(parent, "", marketText)
	local function Wipe(confirmText, wipe, doneText)
		Widgets.Confirm(confirmText, function()
			wipe()
			SR.Sources:ResetCache()
			SR:Print(doneText)
			self:Refresh()
		end)
	end
	local wipeAuction = Widgets.CreateButton(parent, L["Wipe auction prices"], 176, function()
		Wipe(L.WIPE_AUCTION_CONFIRM, function() SR.DB:WipeAuctionData() end, L["Auction prices were wiped."])
	end)
	wipeAuction:SetPoint("TOPLEFT", self.MarketSummary, "BOTTOMLEFT", 0, -10)
	Widgets.AttachTooltip(wipeAuction, L["Wipe auction prices"], L.WIPE_AUCTION_DESC)
	self.WipeAuctionButton = wipeAuction

	local wipeMerchant = Widgets.CreateButton(parent, L["Wipe merchant prices"], 176, function()
		Wipe(L.WIPE_MERCHANT_CONFIRM, function() SR.DB:WipeMerchantData() end, L["Merchant prices were wiped."])
	end)
	wipeMerchant:SetPoint("LEFT", wipeAuction, "RIGHT", 8, 0)
	Widgets.AttachTooltip(wipeMerchant, L["Wipe merchant prices"], L.WIPE_MERCHANT_DESC)
	self.WipeMerchantButton = wipeMerchant

	local wipeMarket = Widgets.CreateButton(parent, L["Wipe all market data"], 176, function()
		Wipe(L.WIPE_MARKET_CONFIRM, function() SR.DB:WipeMarketData() end, L["Market data was wiped."])
	end)
	wipeMarket:SetPoint("LEFT", wipeMerchant, "RIGHT", 8, 0)
	self.WipeMarketButton = wipeMarket

	-- Settings
	local settings = Section(parent, L["Settings"], wipeAuction, -24)
	local settingsText = Widgets.CreateLabel(parent, L.RESET_SETTINGS_DESC, "GameFontHighlight")
	settingsText:SetPoint("TOPLEFT", settings, "BOTTOMLEFT", 0, -8)
	settingsText:SetWidth(SECTION_WIDTH)
	local resetSettings = Widgets.CreateButton(parent, L["Reset settings"], 180, function()
		Widgets.Confirm(L.RESET_SETTINGS_CONFIRM, function()
			SR.DB:ResetSettings()
			SR.UI:ResetLayout()
			SR:Print(L["Settings were reset."])
			self:SelectTab("data")
		end)
	end)
	resetSettings:SetPoint("TOPLEFT", settingsText, "BOTTOMLEFT", 0, -10)
	self.ResetSettingsButton = resetSettings
end

function Page:UpdateDataSummary()
	local summary = SR.DB:GetDataSummary()
	self.MarketSummary:SetText(L["%s auction prices on %d auction house(s), %s merchant prices (items sold by vendors)."]:format(
		Util.FormatNumber(summary.auctionPrices), summary.realms, Util.FormatNumber(summary.vendorPrices)))
end

function Page:Refresh()
	if not self.controls then
		return
	end
	for _, control in ipairs(self.controls) do
		control:Refresh()
	end
	self:UpdateKeyButton()
	self:UpdateDataSummary()
end

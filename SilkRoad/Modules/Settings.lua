--[[ SilkRoad - Modules/Settings.lua
	SilkRoad's settings page, pinned to the bottom of the sidebar, split into
	tabs by purpose:
	  General  minimap button, window, the open/close key binding, about
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

	local tooltips = self:Track(Widgets.CreateCheckbox(parent, L["Prices in item tooltips"], L.TOOLTIP_PRICES_TOOLTIP,
		function()
			return SR:GetSetting("tooltipPrices")
		end,
		function(checked)
			SR:SetSetting("tooltipPrices", checked)
		end))
	tooltips:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 0, -2)

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
	scale:SetPoint("TOPLEFT", tooltips, "BOTTOMLEFT", 4, -10)

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
	Widgets.AttachTooltip(keyButton, L["Open / close SilkRoad"], L.KEY_BINDING_TOOLTIP)
	self.KeyButton = keyButton

	local clearKey = Widgets.CreateButton(parent, L["Clear"], 80, function()
		self:ClearKey()
	end)
	clearKey:SetPoint("LEFT", keyButton, "RIGHT", 6, 0)

	local bindingNote = Note(parent, L.KEY_BINDING_NOTE, bindingLabel)
	bindingNote:SetPoint("TOPLEFT", bindingLabel, "BOTTOMLEFT", 0, -14)

	-- About
	local about = Section(parent, L["About"], bindingNote, -24)
	local aboutText = Widgets.CreateLabel(parent, "", "GameFontHighlight")
	aboutText:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -8)
	aboutText:SetSpacing(3)
	aboutText:SetText(table.concat({
		L["%s version %s"]:format(SR.title, SR.version),
		L["Type |cffffd100/silkroad help|r in chat for every command."],
	}, "\n"))
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
	self.KeyButton:EnableKeyboard(true)
	self.KeyButton:SetPropagateKeyboardInput(false)
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
	local wipeMarket = Widgets.CreateButton(parent, L["Wipe market data"], 180, function()
		Widgets.Confirm(L.WIPE_MARKET_CONFIRM, function()
			SR.DB:WipeMarketData()
			SR.Sources:ResetCache()
			SR:Print(L["Market data was wiped."])
			self:Refresh()
		end)
	end)
	wipeMarket:SetPoint("TOPLEFT", self.MarketSummary, "BOTTOMLEFT", 0, -10)
	self.WipeMarketButton = wipeMarket

	-- Settings
	local settings = Section(parent, L["Settings"], wipeMarket, -24)
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
	self.MarketSummary:SetText(L["%s auction prices on %d realm(s), %s merchant prices."]:format(
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

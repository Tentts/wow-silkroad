--[[ SilkRoad - Modules/Settings.lua
	SilkRoad's settings page, pinned to the bottom of the sidebar.
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

function Page:OnCreate(frame)
	self.controls = {}
	local function track(control)
		self.controls[#self.controls + 1] = control
		return control
	end

	-- General
	local general = Widgets.CreateHeader(frame, L["General"])
	general:SetPoint("TOPLEFT")
	general:SetWidth(SECTION_WIDTH)

	local minimap = track(Widgets.CreateCheckbox(frame, L["Show minimap button"],
		L["The addon compartment menu by the minimap always lists SilkRoad, even with the button hidden."],
		function()
			return not SR:GetSetting("minimap.hide")
		end,
		function(checked)
			SR:SetSetting("minimap.hide", not checked)
		end))
	minimap:SetPoint("TOPLEFT", general, "BOTTOMLEFT", -2, -8)

	local scale = track(Widgets.CreateSlider(frame, L["Window scale"], 0.7, 1.5, 0.05,
		function()
			return SR:GetSetting("window.scale")
		end,
		function(value)
			SR:SetSetting("window.scale", Util.Round(value, 2))
		end,
		function(value)
			return ("%d%%"):format(Util.Round(value * 100))
		end))
	scale:SetPoint("TOPLEFT", minimap, "BOTTOMLEFT", 4, -10)

	local reset = Widgets.CreateButton(frame, L["Reset window position"], 180, function()
		SR.UI:ResetLayout()
		self:Refresh()
	end)
	reset:SetPoint("TOPLEFT", scale, "BOTTOMLEFT", 0, -8)

	-- Pricing
	local pricing = Widgets.CreateHeader(frame, L["Pricing"])
	pricing:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", -2, -24)
	pricing:SetWidth(SECTION_WIDTH)

	local cut = track(Widgets.CreateSlider(frame, L["Auction house cut"], 0, 15, 1,
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

	local sourceLabel = Widgets.CreateLabel(frame, L["Preferred auction price source"], "GameFontHighlight")
	sourceLabel:SetPoint("TOPLEFT", cut, "BOTTOMLEFT", 0, -10)

	local source = track(Widgets.CreateDropdown(frame, 220, function()
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

	local sourceHelp = Widgets.CreateLabel(frame, L["If the preferred source has no price for an item, the other sources are tried in order."], "GameFontDisableSmall")
	sourceHelp:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -6)

	-- About
	local about = Widgets.CreateHeader(frame, L["About"])
	about:SetPoint("TOPLEFT", sourceHelp, "BOTTOMLEFT", 0, -24)
	about:SetWidth(SECTION_WIDTH)

	local aboutText = Widgets.CreateLabel(frame, "", "GameFontHighlight")
	aboutText:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -8)
	aboutText:SetSpacing(3)
	aboutText:SetText(table.concat({
		L["%s version %s"]:format(SR.title, SR.version),
		L["Type |cffffd100/silkroad help|r in chat for every command."],
	}, "\n"))
end

function Page:Refresh()
	for _, control in ipairs(self.controls) do
		control:Refresh()
	end
end

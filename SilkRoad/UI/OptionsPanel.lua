--[[ SilkRoad - UI/OptionsPanel.lua
	An entry under Options > AddOns in Blizzard's settings window. The real
	settings live on SilkRoad's own Settings page; this panel points there.
]]
local _, SR = ...
local L = SR.L
local Widgets = SR.Widgets

local OptionsPanel = SR:NewComponent("OptionsPanel")

local function CloseBlizzardSettings()
	if SettingsPanel and SettingsPanel:IsShown() then
		HideUIPanel(SettingsPanel)
	end
end

function OptionsPanel:OnEnable()
	local panel = CreateFrame("Frame")

	local icon = panel:CreateTexture(nil, "ARTWORK")
	icon:SetSize(40, 40)
	icon:SetPoint("TOPLEFT", 16, -16)
	icon:SetTexture(SR.icon)

	local title = Widgets.CreateLabel(panel, SR.title, "GameFontNormalHuge")
	title:SetPoint("LEFT", icon, "RIGHT", 12, 6)

	local version = Widgets.CreateLabel(panel, L["Version"] .. " " .. SR.version, "GameFontDisableSmall")
	version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

	local description = Widgets.CreateLabel(panel, L.TAGLINE .. ". " .. L["Settings are on SilkRoad's own Settings page."], "GameFontHighlight")
	description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -16)
	description:SetWidth(560)

	local openButton = Widgets.CreateButton(panel, L["Open SilkRoad"], 160, function()
		CloseBlizzardSettings()
		SR.UI:Show()
	end)
	openButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

	local settingsButton = Widgets.CreateButton(panel, L["Open settings page"], 160, function()
		CloseBlizzardSettings()
		SR.UI:OpenPage("settings")
	end)
	settingsButton:SetPoint("LEFT", openButton, "RIGHT", 10, 0)

	local category = Settings.RegisterCanvasLayoutCategory(panel, SR.title)
	Settings.RegisterAddOnCategory(category)
	self.category = category
end

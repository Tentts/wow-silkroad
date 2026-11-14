--[[ SilkRoad - UI/AuctionHouseTab.lua
	A "SilkRoad" tab in Blizzard's auction house window: scan status, a
	manual scan button, the automatic-scan toggle and shortcuts into
	SilkRoad. Deliberately small; new auction house helpers get their own
	card here.

	The tab is created with LibAHTab (Libs/LibAHTab), which adds tabs without
	tainting the auction house. Adding them with Blizzard's PanelTemplates
	functions taints the player's bags. Addons that use LibAHTab (Auctionator
	does) share one tab row.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local AuctionHouseTab = SR:NewComponent("AuctionHouseTab")

local TAB_ID = "SilkRoad"
local AUCTION_HOUSE_ADDON = "Blizzard_AuctionHouseUI"
local CARD_HEIGHT = 250
local SCAN_CARD_WIDTH = 430
local UPDATE_INTERVAL = 0.5

function AuctionHouseTab:OnEnable()
	-- Blizzard's auction house UI loads the first time an auctioneer is opened.
	if C_AddOns.IsAddOnLoaded(AUCTION_HOUSE_ADDON) then
		self:CreateTab()
	else
		local function OnAddonLoaded(_, name)
			if name == AUCTION_HOUSE_ADDON then
				SR:UnregisterEvent("ADDON_LOADED", OnAddonLoaded)
				self:CreateTab()
			end
		end
		SR:RegisterEvent("ADDON_LOADED", OnAddonLoaded)
	end

	SR:RegisterCallback("SCAN_STATUS", function()
		self:Update()
	end)
	SR:RegisterCallback("PRICES_UPDATED", function()
		self:Update()
	end)
	SR:RegisterCallback("SETTING_CHANGED", function(_, path)
		if path == "autoScan" then
			self:Update()
		end
	end)
end

function AuctionHouseTab:CreateTab()
	local LibAHTab = LibStub and LibStub("LibAHTab-1-0", true)
	if self.panel or not AuctionHouseFrame or not LibAHTab or LibAHTab:DoesIDExist(TAB_ID) then
		return
	end

	local panel = CreateFrame("Frame", "SilkRoadAuctionHousePanel", AuctionHouseFrame)
	panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 12, -64)
	panel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -12, 32)
	self.panel = panel

	self:CreateScanCard(panel)
	self:CreateInfoCard(panel)

	panel:SetScript("OnShow", function()
		self:Update()
	end)
	-- Keeps the cooldown countdown ticking while the tab is open.
	local elapsedSinceUpdate = 0
	panel:SetScript("OnUpdate", function(_, elapsed)
		elapsedSinceUpdate = elapsedSinceUpdate + elapsed
		if elapsedSinceUpdate >= UPDATE_INTERVAL then
			elapsedSinceUpdate = 0
			self:Update()
		end
	end)

	LibAHTab:CreateTab(TAB_ID, panel, SR.title, SR.title)
end

function AuctionHouseTab:CreateScanCard(panel)
	local card = Widgets.CreatePanel(panel, 0.35)
	card:SetPoint("TOPLEFT")
	card:SetSize(SCAN_CARD_WIDTH, CARD_HEIGHT)

	local header = Widgets.CreateHeader(card, L["Auction scan"])
	header:SetPoint("TOPLEFT", 12, -12)
	header:SetPoint("TOPRIGHT", -12, -12)

	panel.LastScan = Widgets.CreateLabel(card, "", "GameFontHighlight")
	panel.LastScan:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)

	panel.ScanDetail = Widgets.CreateLabel(card, "", "GameFontDisableSmall")
	panel.ScanDetail:SetPoint("TOPLEFT", panel.LastScan, "BOTTOMLEFT", 0, -4)

	panel.ScanButton = Widgets.CreateButton(card, L["Scan now"], 140, function()
		SR.Scanner:StartScan(false)
	end)
	panel.ScanButton:SetPoint("TOPLEFT", panel.ScanDetail, "BOTTOMLEFT", 0, -14)

	panel.Cooldown = Widgets.CreateLabel(card, "", "GameFontHighlightSmall")
	panel.Cooldown:SetPoint("LEFT", panel.ScanButton, "RIGHT", 12, 0)

	local progress = CreateFrame("StatusBar", nil, card)
	progress:SetSize(SCAN_CARD_WIDTH - 24, 14)
	progress:SetPoint("TOPLEFT", panel.ScanButton, "BOTTOMLEFT", 0, -12)
	progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	progress:SetStatusBarColor(1, 0.82, 0)
	progress:SetMinMaxValues(0, 1)
	local background = progress:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.5)
	progress.Text = Widgets.CreateLabel(progress, "", "GameFontHighlightSmall", "CENTER")
	progress.Text:SetPoint("CENTER")
	progress:Hide()
	panel.Progress = progress

	panel.AutoScan = Widgets.CreateCheckbox(card, L["Scan automatically when the auction house opens"], L.AUTO_SCAN_TOOLTIP,
		function()
			return SR:GetSetting("autoScan")
		end,
		function(checked)
			SR:SetSetting("autoScan", checked)
		end)
	panel.AutoScan:SetPoint("TOPLEFT", panel.ScanButton, "BOTTOMLEFT", -2, -38)

	local note = Widgets.CreateLabel(card, L.AH_SCAN_NOTE, "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", panel.AutoScan, "BOTTOMLEFT", 2, -8)
	note:SetWidth(SCAN_CARD_WIDTH - 26)
	note:SetSpacing(2)

	panel.ScanCard = card
end

function AuctionHouseTab:CreateInfoCard(panel)
	local card = Widgets.CreatePanel(panel, 0.35)
	card:SetPoint("TOPLEFT", panel.ScanCard, "TOPRIGHT", 12, 0)
	card:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
	card:SetHeight(CARD_HEIGHT)

	local header = Widgets.CreateHeader(card, SR.title)
	header:SetPoint("TOPLEFT", 12, -12)
	header:SetPoint("TOPRIGHT", -12, -12)

	local about = Widgets.CreateLabel(card, L.AH_ABOUT, "GameFontHighlightSmall")
	about:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
	about:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -10)
	about:SetSpacing(2)

	local shortcuts = {
		{ label = L["Open SilkRoad"], page = nil },
		{ label = L["Recipes"], page = "recipes" },
		{ label = L["Vendor Flips"], page = "flips" },
		{ label = L["Price Database"], page = "prices" },
	}
	local previous
	for _, shortcut in ipairs(shortcuts) do
		local button = Widgets.CreateButton(card, shortcut.label, 160, function()
			if shortcut.page then
				SR.UI:OpenPage(shortcut.page)
			else
				SR.UI:Show()
			end
		end)
		if previous then
			button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
		else
			button:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -16)
		end
		previous = button
	end
end

function AuctionHouseTab:Update()
	local panel = self.panel
	if not panel or not panel:IsVisible() then
		return
	end
	local scanner = SR.Scanner
	local market = SR.DB:GetMarket()
	local stats = market.lastScanStats

	panel.LastScan:SetText(L["Last scan: %s"]:format(Util.TimeAgo(market.lastScan)))
	if stats then
		panel.ScanDetail:SetText(L["%s items from %s auctions on %s"]:format(
			Util.FormatNumber(stats.items), Util.FormatNumber(stats.listings), SR.DB:GetMarketKey()))
	else
		panel.ScanDetail:SetText(L["No scans on %s yet."]:format(SR.DB:GetMarketKey()))
	end

	local state = scanner.state
	panel.Progress:SetShown(state ~= "idle")
	if state == "waiting" then
		panel.Progress:SetValue(0)
		panel.Progress.Text:SetText(L["Waiting for the auction house..."])
	elseif state == "processing" then
		panel.Progress:SetValue(scanner.progress)
		panel.Progress.Text:SetText(L["Reading auctions... %d%%"]:format(math.floor(scanner.progress * 100)))
	end

	local remaining = scanner:GetCooldownRemaining()
	panel.ScanButton:SetEnabled(state == "idle" and remaining == 0)
	if state ~= "idle" then
		panel.Cooldown:SetText(L["Scanning..."])
	elseif remaining > 0 then
		panel.Cooldown:SetText(L["Next scan in %s"]:format(Util.FormatDuration(remaining)))
	else
		panel.Cooldown:SetText("|cff55ff55" .. L["Ready to scan"] .. "|r")
	end

	panel.AutoScan:Refresh()
end

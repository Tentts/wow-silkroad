--[[ SilkRoad - UI/MainFrame.lua
	The main window: a sidebar of pages ("menus") on the left, the selected
	page on the right, the page title above it and a status line below.

	Pages register themselves from Modules/*.lua:

	local Page = SR.UI:RegisterPage({
		id = "recipes",              -- also usable as "/silkroad recipes"
		order = 20,                  -- position in the sidebar
		title = "Recipes",
		description = "...",         -- shown under the title
		icon = "Interface\\Icons\\...",
		placement = "bottom",        -- optional: pin to the bottom of the sidebar
		autoRefresh = true,          -- refresh when prices/settings/item data change (default)
	})
	function Page:OnCreate(frame) end  -- build widgets, once, the first time the page opens
	function Page:Refresh() end        -- update contents; runs every time the page is shown

	Page.frame is the page's content frame once it has been created.
]]
local _, SR = ...
local L = SR.L
local Widgets = SR.Widgets

local UI = SR:NewComponent("UI")

local FRAME_NAME = "SilkRoadMainFrame"
local SIDEBAR_WIDTH = 176
local NAV_BUTTON_HEIGHT = 34
local NAV_BUTTON_GAP = 2
local MIN_WIDTH, MIN_HEIGHT = 1040, 560
local MAX_WIDTH, MAX_HEIGHT = 1800, 1200
local CONTENT_PADDING = 10

local pages = {}
local pageList = {}

function UI:RegisterPage(page)
	assert(type(page.id) == "string" and page.title, "SilkRoad: pages need an id and a title")
	assert(not pages[page.id], "SilkRoad: duplicate page id " .. page.id)
	page.order = page.order or (#pageList + 1) * 10
	if page.autoRefresh == nil then
		page.autoRefresh = true
	end
	pages[page.id] = page
	pageList[#pageList + 1] = page
	table.sort(pageList, function(a, b)
		return a.order < b.order
	end)
	return page
end

function UI:HasPage(id)
	return pages[id] ~= nil
end

function UI:GetPages()
	return pageList
end

function UI:OnInitialize()
	local refresh = SR.Util.Debounce(0.2, function()
		self:RefreshCurrentPage()
	end)
	SR:RegisterCallback("SETTING_CHANGED", function(_, path, value)
		if path == "window.scale" and self.frame then
			self.frame:SetScale(value)
		end
		self:UpdateStatus()
		refresh()
	end)
	SR:RegisterCallback("PRICES_UPDATED", function()
		self:UpdateStatus()
		refresh()
	end)
	SR:RegisterCallback("RECIPES_UPDATED", refresh)
	SR:RegisterCallback("ITEM_INFO_RECEIVED", function()
		if self:IsShown() then
			refresh()
		end
	end)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function UI:IsShown()
	return self.frame ~= nil and self.frame:IsShown()
end

function UI:Show()
	self:OpenPage(self.currentPageID or SR.DB.settings.window.lastPage)
end

function UI:Hide()
	if self.frame then
		self.frame:Hide()
	end
end

function UI:Toggle()
	if self:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function UI:OpenPage(id)
	local frame = self:GetFrame()
	self:SelectPage(id)
	frame:Show()
end

function UI:RefreshCurrentPage()
	local page = self.currentPageID and pages[self.currentPageID]
	if page and page.frame and page.autoRefresh and page.Refresh and self:IsShown() then
		page:Refresh()
	end
end

function UI:ResetLayout()
	SR.DB:ResetWindowLayout()
	if self.frame then
		self:RestoreGeometry()
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function UI:GetFrame()
	if not self.frame then
		self:CreateMainFrame()
	end
	return self.frame
end

function UI:CreateMainFrame()
	local frame = CreateFrame("Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
	self.frame = frame
	frame:Hide()
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(f)
		f:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		self:SaveGeometry()
	end)
	-- Hooked rather than set, so the template's own handlers keep running.
	frame:HookScript("OnShow", function()
		Widgets.PlaySoundKit("IG_CHARACTER_INFO_OPEN")
		self:UpdateStatus()
	end)
	frame:HookScript("OnHide", function()
		Widgets.PlaySoundKit("IG_CHARACTER_INFO_CLOSE")
	end)

	frame:SetTitle(SR.title)
	frame:SetPortraitToAsset(SR.icon)

	-- Close with Escape, like Blizzard's own panels.
	tinsert(UISpecialFrames, FRAME_NAME)

	self:RestoreGeometry()
	self:CreateHeader()
	self:CreateSidebar()
	self:CreateStatusBar()
	self:CreateResizeGrip()
	self.pageFrames = {}
end

function UI:RestoreGeometry()
	local frame, window = self.frame, SR.DB.settings.window
	frame:SetSize(window.width, window.height)
	frame:SetScale(window.scale or 1)
	frame:ClearAllPoints()
	local point = window.point
	if point then
		frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
	else
		frame:SetPoint("CENTER")
	end
end

function UI:SaveGeometry()
	local frame, window = self.frame, SR.DB.settings.window
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	window.point = { point, relativePoint, x, y }
	window.width = math.floor(frame:GetWidth() + 0.5)
	window.height = math.floor(frame:GetHeight() + 0.5)
end

-- Page title and description, in the band between the title bar and the content.
function UI:CreateHeader()
	local frame = self.frame
	frame.PageTitle = Widgets.CreateLabel(frame, "", "GameFontNormalLarge")
	frame.PageTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_WIDTH + 16, -30)

	frame.PageDescription = Widgets.CreateLabel(frame, "", "GameFontHighlightSmall")
	frame.PageDescription:SetPoint("TOPLEFT", frame.PageTitle, "BOTTOMLEFT", 0, -3)
	frame.PageDescription:SetTextColor(0.75, 0.75, 0.75)
end

function UI:CreateSidebar()
	local frame = self.frame
	local sidebar = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
	sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -60)
	sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 26)
	sidebar:SetWidth(SIDEBAR_WIDTH)
	frame.Sidebar = sidebar

	-- The template's inset becomes the content area, to the right of the sidebar.
	frame.Inset:ClearAllPoints()
	frame.Inset:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 4, 0)
	frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26)

	self.navButtons = {}
	local lastTop, lastBottom
	for _, page in ipairs(pageList) do
		local button = self:CreateNavButton(sidebar, page)
		if page.placement == "bottom" then
			if lastBottom then
				button:SetPoint("BOTTOMLEFT", lastBottom, "TOPLEFT", 0, NAV_BUTTON_GAP)
				button:SetPoint("BOTTOMRIGHT", lastBottom, "TOPRIGHT", 0, NAV_BUTTON_GAP)
			else
				button:SetPoint("BOTTOMLEFT", 6, 6)
				button:SetPoint("BOTTOMRIGHT", -6, 6)
			end
			lastBottom = button
		else
			if lastTop then
				button:SetPoint("TOPLEFT", lastTop, "BOTTOMLEFT", 0, -NAV_BUTTON_GAP)
				button:SetPoint("TOPRIGHT", lastTop, "BOTTOMRIGHT", 0, -NAV_BUTTON_GAP)
			else
				button:SetPoint("TOPLEFT", 6, -6)
				button:SetPoint("TOPRIGHT", -6, -6)
			end
			lastTop = button
		end
		self.navButtons[#self.navButtons + 1] = button
	end
end

function UI:CreateNavButton(parent, page)
	local button = CreateFrame("Button", nil, parent)
	button:SetHeight(NAV_BUTTON_HEIGHT)
	button.pageID = page.id

	button.Selected = button:CreateTexture(nil, "BACKGROUND")
	button.Selected:SetAllPoints()
	button.Selected:SetColorTexture(1, 0.82, 0, 0.14)
	button.Selected:Hide()

	button.Accent = button:CreateTexture(nil, "ARTWORK")
	button.Accent:SetPoint("TOPLEFT")
	button.Accent:SetPoint("BOTTOMLEFT")
	button.Accent:SetWidth(3)
	button.Accent:SetColorTexture(1, 0.82, 0, 0.9)
	button.Accent:Hide()

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.07)

	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetSize(22, 22)
	button.Icon:SetPoint("LEFT", 10, 0)
	button.Icon:SetTexture(page.icon or SR.icon)
	button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	button.Label = Widgets.CreateLabel(button, page.title, "GameFontNormal")
	button.Label:SetPoint("LEFT", button.Icon, "RIGHT", 8, 0)
	button.Label:SetPoint("RIGHT", -6, 0)
	button.Label:SetWordWrap(false)

	button:SetScript("OnClick", function()
		Widgets.PlaySoundKit("IG_MAINMENU_OPTION")
		self:SelectPage(page.id)
	end)

	function button:SetSelected(selected)
		self.Selected:SetShown(selected)
		self.Accent:SetShown(selected)
		self.Label:SetFontObject(selected and "GameFontHighlight" or "GameFontNormal")
	end
	return button
end

function UI:CreateStatusBar()
	local frame = self.frame
	frame.StatusText = Widgets.CreateLabel(frame, "", "GameFontDisableSmall")
	frame.StatusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 8)
	frame.StatusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -120, 8)
	frame.StatusText:SetWordWrap(false)

	frame.VersionText = Widgets.CreateLabel(frame, "v" .. SR.version, "GameFontDisableSmall", "RIGHT")
	frame.VersionText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 8)
end

function UI:CreateResizeGrip()
	local grip = CreateFrame("Button", nil, self.frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -5, 5)
	grip:SetFrameLevel(self.frame:GetFrameLevel() + 600)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		self.frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		self.frame:StopMovingOrSizing()
		self:SaveGeometry()
	end)
end

function UI:UpdateStatus()
	if not self.frame then
		return
	end
	local stats = SR.Prices:GetStats()
	local sources = {}
	for _, provider in ipairs(SR.Prices:GetProviders()) do
		local hasData = provider:IsAvailable() and (provider.id ~= "silkroad" or stats.auctionItems > 0)
		if hasData then
			sources[#sources + 1] = provider.label
		end
	end
	local sourceText = #sources > 0 and table.concat(sources, ", ") or L.NO_AUCTION_SOURCE
	self.frame.StatusText:SetText(L["Realm: %s   |   Auction prices: %s   |   Auction cut: %d%%"]:format(
		stats.marketKey, sourceText, SR:GetSetting("auctionCutPercent")))
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

function UI:GetPageFrame(page)
	local pageFrame = self.pageFrames[page.id]
	if not pageFrame then
		pageFrame = CreateFrame("Frame", nil, self.frame.Inset)
		pageFrame:SetPoint("TOPLEFT", CONTENT_PADDING, -CONTENT_PADDING)
		pageFrame:SetPoint("BOTTOMRIGHT", -CONTENT_PADDING, CONTENT_PADDING)
		pageFrame:Hide()
		self.pageFrames[page.id] = pageFrame
		page.frame = pageFrame
		if page.OnCreate then
			page:OnCreate(pageFrame)
		end
		-- Fires whenever the page becomes visible: page switches and window opens.
		pageFrame:SetScript("OnShow", function()
			if page.Refresh then
				page:Refresh()
			end
		end)
	end
	return pageFrame
end

function UI:SelectPage(id)
	local page = pages[id] or pageList[1]
	local frame = self:GetFrame()

	for pageID, pageFrame in pairs(self.pageFrames) do
		if pageID ~= page.id then
			pageFrame:Hide()
		end
	end

	self.currentPageID = page.id
	SR.DB.settings.window.lastPage = page.id
	frame.PageTitle:SetText(page.title)
	frame.PageDescription:SetText(page.description or "")
	for _, button in ipairs(self.navButtons) do
		button:SetSelected(button.pageID == page.id)
	end

	self:GetPageFrame(page):Show()
end

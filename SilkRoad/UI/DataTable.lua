--[[ SilkRoad - UI/DataTable.lua
	A sortable, filterable, virtualised table built on Blizzard's ScrollBox.
	Only visible rows exist as frames, so it stays fast with thousands of rows.

	local tbl = SR.Widgets.CreateDataTable(parent, {
		columns = {
			{
				key = "name",          -- field read from each row
				title = "Recipe",
				width = 110,           -- fixed width; omit to share the leftover space
				align = "LEFT",        -- LEFT | CENTER | RIGHT
				kind = "text",         -- text | money | profit | percent | item
				sortable = true,       -- default true
				sortDescFirst = false, -- first click sorts high-to-low (good for money)
				format = function(value, row) return "text" end, -- optional override
				onClick = function(row, cellButton) end, -- optional: makes the cell clickable
				tooltip = function(row, tooltip) end,    -- optional: hover text for a clickable cell
			},
		},
		sortKey = "name", sortDesc = false,
		rowHeight = 22,
		emptyIcon = ..., emptyTitle = "...", emptyBody = "...",
		onRowClick = function(row, mouseButton, rowFrame) end,
		onRowEnter = function(rowFrame, row) end,   -- default: item tooltip for row.itemID
		onRefresh = function(tbl, shownCount, totalCount) end,
	})
	tbl:SetRows(rows)        -- array of plain tables
	tbl:SetFilter(function(row) return true end)
	tbl:SetSelected(function(row) return isSelected end) -- highlights rows; call before SetRows

	"item" columns show row.icon and colour the text by row.quality.
	Modified clicks on rows with row.itemID (shift-click to link, ctrl-click to
	preview) behave like they do on any item in the game.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local HEADER_HEIGHT = 22
local DEFAULT_ROW_HEIGHT = 22
local CELL_PADDING = 6
local SCROLLBAR_SPACE = 18
local MIN_FLEX_WIDTH = 80
local SORT_ARROW_SPACE = 12
local QUESTION_MARK_ICON = 134400

local DataTableMixin = {}

function Widgets.CreateDataTable(parent, config)
	local tbl = CreateFrame("Frame", nil, parent)
	Mixin(tbl, DataTableMixin)
	tbl:Init(config)
	return tbl
end

function DataTableMixin:Init(config)
	self.config = config
	self.columns = config.columns
	self.rowHeight = config.rowHeight or DEFAULT_ROW_HEIGHT
	self.sortKey = config.sortKey
	self.sortDesc = config.sortDesc or false
	self.rows = {}
	self.layout = {}

	self:CreateHeader()
	self:CreateList()

	self.Empty = Widgets.CreateEmptyState(self)
	self.Empty:SetPoint("CENTER", self.ScrollBox, "CENTER", 0, 10)
	self.Empty:Hide()

	self:SetScript("OnSizeChanged", self.OnSizeChanged)
	self:UpdateSortArrows()
end

function DataTableMixin:CreateHeader()
	local header = CreateFrame("Frame", nil, self)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT", -SCROLLBAR_SPACE, 0)
	header:SetHeight(HEADER_HEIGHT)
	self.Header = header

	local background = header:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(1, 1, 1, 0.07)

	self.headerButtons = {}
	for index, column in ipairs(self.columns) do
		local button = CreateFrame("Button", nil, header)
		button:SetHeight(HEADER_HEIGHT)
		button.column = column

		button.Text = Widgets.CreateLabel(button, column.title, "GameFontNormalSmall", column.align)
		button.Text:SetWordWrap(false)

		button.Arrow = button:CreateTexture(nil, "OVERLAY")
		button.Arrow:SetAtlas("auctionhouse-ui-sortarrow", true)
		button.Arrow:Hide()

		if column.sortable ~= false then
			local highlight = button:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(1, 1, 1, 0.08)
			button:SetScript("OnClick", function()
				self:OnHeaderClicked(column)
			end)
		else
			button:EnableMouse(false)
		end
		self.headerButtons[index] = button
	end
end

function DataTableMixin:CreateList()
	local scrollBox = CreateFrame("Frame", nil, self, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", self.Header, "BOTTOMLEFT", 0, -2)
	scrollBox:SetPoint("BOTTOMRIGHT", -SCROLLBAR_SPACE, 0)
	self.ScrollBox = scrollBox

	local scrollBar = CreateFrame("EventFrame", nil, self, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
	self.ScrollBar = scrollBar

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(self.rowHeight)
	view:SetElementInitializer("Button", function(rowFrame, row)
		self:InitRow(rowFrame, row)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

function DataTableMixin:ComputeLayout(totalWidth)
	local fixedWidth, flexCount = 0, 0
	for _, column in ipairs(self.columns) do
		if column.width then
			fixedWidth = fixedWidth + column.width
		else
			flexCount = flexCount + 1
		end
	end
	local flexWidth = 0
	if flexCount > 0 then
		flexWidth = math.max(MIN_FLEX_WIDTH, (totalWidth - fixedWidth) / flexCount)
	end

	local x = 0
	for index, column in ipairs(self.columns) do
		local width = column.width or flexWidth
		local slot = self.layout[index] or {}
		slot.x, slot.width = x, width
		self.layout[index] = slot
		x = x + width
	end
end

function DataTableMixin:OnSizeChanged(width)
	self.layoutWidth = width
	self:ComputeLayout(width - SCROLLBAR_SPACE)
	for index, button in ipairs(self.headerButtons) do
		local slot = self.layout[index]
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", self.Header, "TOPLEFT", slot.x, 0)
		button:SetWidth(slot.width)
		self:LayoutHeaderButton(button)
	end
	self.ScrollBox:ForEachFrame(function(rowFrame)
		self:LayoutRow(rowFrame)
	end)
end

function DataTableMixin:LayoutHeaderButton(button)
	button.Text:ClearAllPoints()
	button.Arrow:ClearAllPoints()
	if button.column.align == "RIGHT" then
		-- Keep the arrow on the far side so the title lines up with the values.
		button.Text:SetPoint("LEFT", CELL_PADDING + SORT_ARROW_SPACE, 0)
		button.Text:SetPoint("RIGHT", -CELL_PADDING, 0)
		button.Arrow:SetPoint("LEFT", CELL_PADDING, 0)
	else
		button.Text:SetPoint("LEFT", CELL_PADDING, 0)
		button.Text:SetPoint("RIGHT", -(CELL_PADDING + SORT_ARROW_SPACE), 0)
		button.Arrow:SetPoint("RIGHT", -CELL_PADDING, 0)
	end
end

function DataTableMixin:UpdateSortArrows()
	for _, button in ipairs(self.headerButtons) do
		local active = button.column.key == self.sortKey
		button.Arrow:SetShown(active)
		if active then
			if self.sortDesc then
				button.Arrow:SetTexCoord(0, 1, 0, 1)
			else
				button.Arrow:SetTexCoord(0, 1, 1, 0)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

function DataTableMixin:BuildRow(rowFrame)
	rowFrame.Stripe = rowFrame:CreateTexture(nil, "BACKGROUND")
	rowFrame.Stripe:SetAllPoints()
	rowFrame.Stripe:SetColorTexture(1, 1, 1, 0.03)

	rowFrame.Selected = rowFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
	rowFrame.Selected:SetAllPoints()
	rowFrame.Selected:SetColorTexture(1, 0.82, 0, 0.12)
	rowFrame.Selected:Hide()

	local highlight = rowFrame:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 0.82, 0, 0.1)

	rowFrame.cells = {}
	for index, column in ipairs(self.columns) do
		local cell = {}
		cell.Text = Widgets.CreateLabel(rowFrame, nil, "GameFontHighlightSmall", column.align)
		cell.Text:SetWordWrap(false)
		if column.kind == "item" then
			cell.Icon = rowFrame:CreateTexture(nil, "ARTWORK")
			cell.Icon:SetSize(self.rowHeight - 4, self.rowHeight - 4)
			cell.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		end
		if column.onClick then
			-- A clickable cell: its own button over the cell, with a tooltip.
			local button = CreateFrame("Button", nil, rowFrame)
			local highlight = button:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints()
			highlight:SetColorTexture(0.4, 0.75, 1, 0.15)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			button:SetScript("OnClick", function(_, mouseButton)
				if mouseButton == "RightButton" then
					self:OnRowClicked(rowFrame, mouseButton) -- the row's menu, not the cell's action
				elseif rowFrame.row then
					column.onClick(rowFrame.row, button)
				end
			end)
			button:SetScript("OnEnter", function()
				if rowFrame.row and column.tooltip then
					GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
					column.tooltip(rowFrame.row, GameTooltip)
					GameTooltip:Show()
				end
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)
			cell.Button = button
		end
		rowFrame.cells[index] = cell
	end

	rowFrame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	rowFrame:SetScript("OnClick", function(frame, mouseButton)
		self:OnRowClicked(frame, mouseButton)
	end)
	rowFrame:SetScript("OnEnter", function(frame)
		self:OnRowEnter(frame)
	end)
	rowFrame:SetScript("OnLeave", GameTooltip_Hide)
end

function DataTableMixin:LayoutRow(rowFrame)
	if not rowFrame.cells then
		return
	end
	for index, cell in ipairs(rowFrame.cells) do
		local slot = self.layout[index]
		local left = slot.x + CELL_PADDING
		if cell.Icon then
			cell.Icon:ClearAllPoints()
			cell.Icon:SetPoint("LEFT", rowFrame, "LEFT", left, 0)
			left = left + self.rowHeight
		end
		cell.Text:ClearAllPoints()
		cell.Text:SetPoint("LEFT", rowFrame, "LEFT", left, 0)
		cell.Text:SetWidth(math.max(1, slot.x + slot.width - CELL_PADDING - left))
		if cell.Button then
			cell.Button:ClearAllPoints()
			cell.Button:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", slot.x, 0)
			cell.Button:SetSize(math.max(1, slot.width), self.rowHeight)
		end
	end
end

local function FormatCell(column, value, row)
	if column.format then
		return column.format(value, row)
	end
	local kind = column.kind
	if kind == "money" then
		return Util.FormatMoney(value)
	elseif kind == "profit" then
		return Util.FormatProfit(value)
	elseif kind == "percent" then
		return Util.FormatPercent(value)
	elseif kind == "item" then
		return Util.ColorByQuality(tostring(value or row.name or ""), row.quality)
	end
	return value ~= nil and tostring(value) or ""
end

function DataTableMixin:InitRow(rowFrame, row)
	if not rowFrame.cells then
		self:BuildRow(rowFrame)
	end
	if #self.layout == 0 then
		self:ComputeLayout(self:GetWidth() - SCROLLBAR_SPACE)
	end
	rowFrame.row = row
	rowFrame.Stripe:SetShown(row._index ~= nil and row._index % 2 == 0)
	rowFrame.Selected:SetShown(self.isSelected ~= nil and self.isSelected(row) and true or false)
	self:LayoutRow(rowFrame)

	for index, column in ipairs(self.columns) do
		local cell = rowFrame.cells[index]
		cell.Text:SetText(FormatCell(column, row[column.key], row))
		if cell.Icon then
			cell.Icon:SetTexture(row.icon or QUESTION_MARK_ICON)
		end
	end
end

function DataTableMixin:OnRowClicked(rowFrame, mouseButton)
	local row = rowFrame.row
	if not row then
		return
	end
	if row.itemID and IsModifiedClick() then
		local link = row.link or select(2, C_Item.GetItemInfo(row.itemID))
		if link and HandleModifiedItemClick(link) then
			return
		end
	end
	if self.config.onRowClick then
		self.config.onRowClick(row, mouseButton, rowFrame)
	end
end

function DataTableMixin:OnRowEnter(rowFrame)
	local row = rowFrame.row
	if not row then
		return
	end
	if self.config.onRowEnter then
		self.config.onRowEnter(rowFrame, row)
	elseif row.itemID then
		GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(row.itemID)
		GameTooltip:Show()
	end
end

---------------------------------------------------------------------------
-- Data, sorting and filtering
---------------------------------------------------------------------------

function DataTableMixin:GetColumn(key)
	for _, column in ipairs(self.columns) do
		if column.key == key then
			return column
		end
	end
end

function DataTableMixin:OnHeaderClicked(column)
	if self.sortKey == column.key then
		self.sortDesc = not self.sortDesc
	else
		self.sortKey = column.key
		self.sortDesc = column.sortDescFirst or false
	end
	Widgets.PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
	self:UpdateSortArrows()
	self:Refresh()
end

function DataTableMixin:SetRows(rows)
	self.rows = rows or {}
	self:Refresh(true)
end

function DataTableMixin:SetSelected(predicate)
	self.isSelected = predicate
end

function DataTableMixin:SetFilter(predicate)
	self.filter = predicate
	self:Refresh()
end

-- Missing values always sort to the bottom, whichever direction is active.
local function MakeComparator(key, descending)
	return function(a, b)
		local va, vb = a[key], b[key]
		if va == vb then
			return tostring(a.name or "") < tostring(b.name or "")
		elseif va == nil then
			return false
		elseif vb == nil then
			return true
		end
		if type(va) == "string" and type(vb) == "string" then
			va, vb = va:lower(), vb:lower()
			if va == vb then
				return false
			end
		end
		if descending then
			return va > vb
		end
		return va < vb
	end
end

function DataTableMixin:Refresh(retainScroll)
	-- OnSizeChanged isn't guaranteed before the first refresh; lay out now if needed.
	local width = self:GetWidth()
	if width > 0 and width ~= self.layoutWidth then
		self:OnSizeChanged(width)
	end

	local visible = {}
	for _, row in ipairs(self.rows) do
		if not self.filter or self.filter(row) then
			visible[#visible + 1] = row
		end
	end

	local column = self.sortKey and self:GetColumn(self.sortKey)
	if column then
		table.sort(visible, MakeComparator(column.key, self.sortDesc))
	end
	for index, row in ipairs(visible) do
		row._index = index
	end

	local provider = CreateDataProvider(visible)
	self.ScrollBox:SetDataProvider(provider, retainScroll and ScrollBoxConstants.RetainScrollPosition or nil)

	if #visible == 0 then
		if #self.rows > 0 then
			self.Empty:SetContent(nil, L.NO_MATCHES_TITLE, L.NO_MATCHES_BODY)
		else
			self.Empty:SetContent(self.config.emptyIcon, self.config.emptyTitle, self.config.emptyBody)
		end
	end
	self.Empty:SetShown(#visible == 0)

	if self.config.onRefresh then
		self.config.onRefresh(self, #visible, #self.rows)
	end
end

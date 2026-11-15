--[[ SilkRoad - UI/ItemSuggestions.lua
	A suggestion list under an item edit box: typing "light" lists Light
	Leather, Light Hide... (see Core/ItemSearch.lua). Click a suggestion, or
	pick one with the arrow keys and Enter.

	local suggestions = Widgets.AttachItemSuggestions(editBox, function(itemID) end)
	suggestions:GetPicked()   the item picked, while the box still shows its name
	suggestions:Hide()
]]
local _, SR = ...
local Util = SR.Util
local Widgets = SR.Widgets

local MAX_ROWS = 8
local ROW_HEIGHT = 20

local SuggestionsMixin = {}

function SuggestionsMixin:Init(box, onPick)
	self.box = box
	self.onPick = onPick
	self:SetFrameStrata("DIALOG")
	self:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, -2)
	self:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -2)
	self:EnableMouse(true)
	self:Hide()

	local background = self:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.05, 0.05, 0.95)
	local border = self:CreateTexture(nil, "BORDER")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetColorTexture(0.9, 0.76, 0.36, 0.5)

	self.rows = {}
	for index = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, self)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 2, -2 - (index - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", -2, -2 - (index - 1) * ROW_HEIGHT)
		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
		row.Icon:SetPoint("LEFT", 2, 0)
		row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.Text = Widgets.CreateLabel(row, "", "GameFontHighlightSmall")
		row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
		row.Text:SetPoint("RIGHT", -4, 0)
		row.Text:SetWordWrap(false)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)
		row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
		row.Selected:SetAllPoints()
		row.Selected:SetColorTexture(1, 0.82, 0, 0.15)
		row.Selected:Hide()
		row:SetScript("OnClick", function()
			self:Pick(row.itemID)
		end)
		row:SetScript("OnEnter", function()
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(row.itemID)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		self.rows[index] = row
	end

	box:HookScript("OnTextChanged", function(_, userInput)
		if userInput then
			self.picked = nil -- typing again: whatever was picked no longer applies
			self:Update()
		end
	end)
	box:HookScript("OnEditFocusLost", function()
		if not self:IsMouseOver() then -- a click on a suggestion still has to land
			self:Hide()
		end
	end)
	box:HookScript("OnEscapePressed", function()
		self:Hide()
	end)
	box:SetAltArrowKeyMode(false)
	box:HookScript("OnArrowPressed", function(_, key)
		self:Move(key == "DOWN" and 1 or key == "UP" and -1 or 0)
	end)
	-- Enter picks the highlighted suggestion instead of submitting the text.
	local submit = box:GetScript("OnEnterPressed")
	box:SetScript("OnEnterPressed", function(...)
		if self:IsShown() and self.selected and self.items[self.selected] then
			self:Pick(self.items[self.selected])
		elseif submit then
			submit(...)
		end
	end)
end

function SuggestionsMixin:Update()
	self.items = SR.ItemSearch:Find(self.box:GetText(), MAX_ROWS)
	self.selected = nil
	if #self.items == 0 then
		self:Hide()
		return
	end
	for index, row in ipairs(self.rows) do
		local itemID = self.items[index]
		row.itemID = itemID
		row:SetShown(itemID ~= nil)
		row.Selected:Hide()
		if itemID then
			local display = Util.GetItemDisplay(itemID)
			row.Icon:SetTexture(display.icon or 134400)
			row.Text:SetText(Util.ColorByQuality(display.name, display.quality))
		end
	end
	self:SetHeight(#self.items * ROW_HEIGHT + 4)
	self:Show()
end

-- Arrow keys move the highlight; it wraps around.
function SuggestionsMixin:Move(step)
	if not self:IsShown() or step == 0 or #self.items == 0 then
		return
	end
	self.selected = ((self.selected or (step > 0 and 0 or 1)) - 1 + step) % #self.items + 1
	for index, row in ipairs(self.rows) do
		row.Selected:SetShown(index == self.selected)
	end
end

function SuggestionsMixin:Pick(itemID)
	if not itemID then
		return
	end
	self.picked = itemID
	self:Hide()
	local display = Util.GetItemDisplay(itemID)
	self.box:SetText(display.name or "")
	self.box:SetCursorPosition(#(display.name or ""))
	self.onPick(itemID)
end

function SuggestionsMixin:GetPicked()
	return self.picked
end

function Widgets.AttachItemSuggestions(box, onPick)
	local suggestions = CreateFrame("Frame", nil, box:GetParent())
	Mixin(suggestions, SuggestionsMixin)
	suggestions:Init(box, onPick or function() end)
	return suggestions
end

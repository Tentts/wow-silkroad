--[[ SilkRoad - Modules/BuyLists.lua
	Manages buy lists: create, rename, duplicate and delete them, and set
	which items each one holds and how many. Buying happens in the Buy Lists
	tab of the auction house window; recipes add their reagents from their
	right-click menu.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local Page = SR.UI:RegisterPage({
	id = "buylists",
	order = 30,
	title = L["Buy Lists"],
	description = L.BUYLISTS_DESC,
	icon = "Interface\\Icons\\INV_Misc_Note_01",
})

local LIST_WIDTH = 300
local COLORS = { done = "ff55ff55" }

function Page:SelectedList()
	local settings = SR.DB.settings.buyLists
	local list = SR.BuyLists:GetList(settings.selected)
	if not list then
		list = SR.BuyLists:GetLists()[1]
		settings.selected = list and list.id or nil
	end
	return list
end

function Page:Select(id)
	SR.DB.settings.buyLists.selected = id
	self:Refresh()
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

function Page:NewList()
	Widgets.Prompt(L["Name of the new buy list:"], SR.BuyLists:UniqueName(L["Buy list"]), function(name)
		local list = SR.BuyLists:Create(name)
		self:Select(list.id)
	end)
end

function Page:RenameList(list)
	Widgets.Prompt(L["New name for %s:"]:format(list.name), list.name, function(name)
		SR.BuyLists:Rename(list.id, name)
	end)
end

function Page:DeleteList(list)
	Widgets.Confirm(L["Delete the buy list %s?"]:format(list.name), function()
		SR.BuyLists:Delete(list.id)
	end)
end

function Page:ChangeAmount(list, entry)
	local name = Util.GetItemDisplay(entry.itemID).name
	Widgets.Prompt(L["How many %s? (0 removes it)"]:format(name), entry.quantity, function(text)
		SR.BuyLists:SetQuantity(list.id, entry.itemID, tonumber(text) or entry.quantity)
	end, true)
end

function Page:AddFromInput()
	local list = self:SelectedList()
	local itemID = Util.ParseItemID(self.ItemInput:GetText())
	if not list then
		return
	end
	if not itemID then
		SR:Print(L.LOOKUP_NOT_FOUND)
		return
	end
	local amount = tonumber(self.AmountInput:GetText()) or 1
	SR.BuyLists:AddItem(list.id, itemID, math.max(1, amount))
	self.ItemInput:SetText("")
	self.ItemInput:ClearFocus()
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

function Page:OnCreate(frame)
	-- Left: the lists.
	local listHeader = Widgets.CreateHeader(frame, L["Lists"])
	listHeader:SetPoint("TOPLEFT", 0, 0)
	listHeader:SetWidth(LIST_WIDTH)

	local buttons = {
		{ label = L["New"], run = function() self:NewList() end },
		{ label = L["Rename"], needsList = true, run = function(list) self:RenameList(list) end },
		{ label = L["Copy"], needsList = true, run = function(list) self:Select(SR.BuyLists:Duplicate(list.id).id) end },
		{ label = L["Delete"], needsList = true, run = function(list) self:DeleteList(list) end },
	}
	self.ListButtons = {}
	local buttonWidth = (LIST_WIDTH - 3 * 4) / #buttons
	for index, spec in ipairs(buttons) do
		local button = Widgets.CreateButton(frame, spec.label, buttonWidth, function()
			local list = self:SelectedList()
			if spec.needsList and not list then
				return
			end
			spec.run(list)
		end)
		button:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", (index - 1) * (buttonWidth + 4), -8)
		button.needsList = spec.needsList
		self.ListButtons[index] = button
	end

	self.Lists = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "name", title = L["Name"] },
			{ key = "itemCount", title = L["Items"], width = 46, align = "RIGHT", sortDescFirst = true },
			{ key = "cost", title = L["Left to buy"], width = 96, kind = "money", align = "RIGHT", sortDescFirst = true },
		},
		sortKey = "name",
		emptyIcon = "Interface\\Icons\\INV_Misc_Note_01",
		emptyTitle = L["No buy lists"],
		emptyBody = L.BUYLISTS_EMPTY_BODY,
		onRowClick = function(row, mouseButton, rowFrame)
			self:Select(row.list.id)
			if mouseButton == "RightButton" then
				SR.Game.ShowMenu(rowFrame, row.list.name, {
					{ label = L["Rename"], action = "rename" },
					{ label = L["Copy"], action = "copy" },
					{ label = L["Delete"], action = "delete" },
				}, function(option)
					if option.action == "rename" then
						self:RenameList(row.list)
					elseif option.action == "copy" then
						self:Select(SR.BuyLists:Duplicate(row.list.id).id)
					else
						self:DeleteList(row.list)
					end
				end)
			end
		end,
	})
	self.Lists:SetPoint("TOPLEFT", self.ListButtons[1], "BOTTOMLEFT", 0, -8)
	self.Lists:SetPoint("BOTTOMLEFT")
	self.Lists:SetWidth(LIST_WIDTH)

	-- Right: the selected list's items.
	self.Title = Widgets.CreateHeader(frame, "")
	self.Title:SetPoint("TOPLEFT", listHeader, "TOPRIGHT", 16, 0)
	self.Title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

	local itemLabel = Widgets.CreateLabel(frame, L["Add item"], "GameFontNormal")
	itemLabel:SetPoint("TOPLEFT", self.Title, "BOTTOMLEFT", 0, -12)

	self.ItemInput = Widgets.CreateInput(frame, 240, function()
		self:AddFromInput()
	end)
	self.ItemInput:SetPoint("LEFT", itemLabel, "RIGHT", 12, 0)

	local amountLabel = Widgets.CreateLabel(frame, L["Amount"], "GameFontNormal")
	amountLabel:SetPoint("LEFT", self.ItemInput, "RIGHT", 12, 0)

	self.AmountInput = Widgets.CreateInput(frame, 50, function()
		self:AddFromInput()
	end)
	self.AmountInput:SetNumeric(true)
	self.AmountInput:SetText("1")
	self.AmountInput:SetPoint("LEFT", amountLabel, "RIGHT", 10, 0)

	self.AddButton = Widgets.CreateButton(frame, L["Add"], 80, function()
		self:AddFromInput()
	end)
	self.AddButton:SetPoint("LEFT", self.AmountInput, "RIGHT", 8, 0)
	Widgets.AttachTooltip(self.ItemInput, L["Add item"], L.LOOKUP_HINT)

	-- Shift-clicking an item while the box has focus drops its link in.
	if ChatFrameUtil and ChatFrameUtil.InsertLink then
		hooksecurefunc(ChatFrameUtil, "InsertLink", function(link)
			if link and self.ItemInput:HasFocus() then
				self.ItemInput:SetText(link)
			end
		end)
	end


	self.Items = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "name", title = L["Item"], kind = "item" },
			{ key = "quantity", title = L["Wanted"], width = 64, align = "RIGHT", sortDescFirst = true },
			{ key = "have", title = L["Have"], width = 56, align = "RIGHT", sortDescFirst = true },
			{
				key = "remaining", title = L["Left"], width = 56, align = "RIGHT", sortDescFirst = true,
				format = function(value)
					return value == 0 and Util.ColorText(L["done"], COLORS.done) or tostring(value)
				end,
			},
			{ key = "unitPrice", title = L["Each (AH)"], width = 96, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "cost", title = L["Total"], width = 104, kind = "money", align = "RIGHT", sortDescFirst = true },
		},
		sortKey = "name",
		emptyIcon = "Interface\\Icons\\INV_Misc_Bag_10",
		emptyTitle = L["This list is empty"],
		emptyBody = L.BUYLIST_ITEMS_EMPTY_BODY,
		onRowClick = function(row, mouseButton, rowFrame)
			local list = self:SelectedList()
			if not list then
				return
			end
			if mouseButton == "RightButton" then
				SR.Game.ShowMenu(rowFrame, row.name, {
					{ label = L["Change amount"], action = "amount" },
					{ label = L["Remove"], action = "remove" },
				}, function(option)
					if option.action == "amount" then
						self:ChangeAmount(list, row)
					else
						SR.BuyLists:RemoveItem(list.id, row.itemID)
					end
				end)
			else
				self:ChangeAmount(list, row)
			end
		end,
	})
	self.Items:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", 0, -14)
	self.Items:SetPoint("BOTTOMRIGHT", 0, 20)
	-- Progress of the selected list, under its items.
	self.Summary = Widgets.CreateLabel(frame, "", "GameFontHighlightSmall")
	self.Summary:SetPoint("TOPLEFT", self.Items, "BOTTOMLEFT", 2, -6)

	local bagsChanged = Util.Debounce(1, function()
		if frame:IsVisible() then
			self:Refresh()
		end
	end)
	for _, event in ipairs(SR.Game.events.bagsChanged) do
		SR:RegisterEvent(event, bagsChanged)
	end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function Page:Refresh()
	local selected = self:SelectedList()

	local listRows = {}
	for _, list in ipairs(SR.BuyLists:GetLists()) do
		local _, totals = SR.BuyLists:GetProgress(list)
		local name = list.name
		if totals.items > 0 and totals.done == totals.items then
			name = name .. " " .. Util.ColorText(L["(complete)"], COLORS.done)
		end
		listRows[#listRows + 1] = { list = list, name = name, itemCount = totals.items, cost = totals.cost }
	end
	self.Lists:SetSelected(function(row) return selected ~= nil and row.list.id == selected.id end)
	self.Lists:SetRows(listRows)

	for _, button in ipairs(self.ListButtons) do
		button:SetEnabled(not button.needsList or selected ~= nil)
	end
	self.ItemInput:SetEnabled(selected ~= nil)
	self.AmountInput:SetEnabled(selected ~= nil)
	self.AddButton:SetEnabled(selected ~= nil)

	if not selected then
		self.Title.Text:SetText(L["Buy Lists"])
		self.Summary:SetText("")
		self.Items:SetRows({})
		return
	end
	self.Title.Text:SetText(selected.name)
	local rows, totals = SR.BuyLists:BuildItemRows(selected)
	self.Summary:SetText(SR.BuyLists:DescribeTotals(totals))
	self.Items:SetRows(rows)
end

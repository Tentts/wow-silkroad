--[[ SilkRoad - Modules/Guide.lua
	Levelling guide: the cheapest route from the character's skill to a
	target, worked out by Core/Planner.lua from current prices and recipe
	availability, with the current step highlighted and a shopping list.
	The plan is redone whenever skill, prices, known recipes or bags change.
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local Page = SR.UI:RegisterPage({
	id = "guide",
	order = 25,
	title = L["Leveling Guide"],
	description = L.GUIDE_DESC,
	icon = "Interface\\Icons\\INV_Misc_Book_07",
})

local COLORS = { current = "ff40ff40", done = "ff808080", gap = "ffff4040", link = "ff66bbff", gain = "ff55ff55" }
local SHOPPING_HEIGHT = 160

local AVAILABILITY_LABELS = {
	known = L["Known recipes only"],
	trainer = L["+ Trainer recipes"],
	vendor = L["+ Vendor recipes"],
	auction = L["+ Auction house recipes"],
	drop = L["+ Dropped recipes"],
}
local RESALE_LABELS = {
	none = L["Don't count resale"],
	vendor = L["Sell results to vendors"],
	best = L["Sell results where they earn most"],
}
local SOURCE_TAGS = { vendor = L["Vendor"], auction = L["AH"] }

local function FormatNetCost(cost)
	if cost == nil then
		return "|cff808080--|r"
	elseif cost < 0 then
		return Util.ColorText("+", COLORS.gain) .. Util.FormatMoney(-cost)
	end
	return Util.FormatMoney(cost)
end

local function LearnText(step)
	local learn = step.learn
	if step.gap then
		return Util.ColorText(L["widen availability"], COLORS.gap)
	elseif not learn then
		return L["Known"]
	elseif learn.kind == "trainer" then
		return L["Learn: trainer"]
	elseif learn.kind == "vendor" then
		return L["Buy: %s"]:format(learn.source and learn.source.name or L["vendor"])
	elseif learn.kind == "auction" then
		return L["Buy on AH: %s"]:format(Util.FormatMoney(learn.cost))
	end
	return L["Drop"]
end

local function ShowStepTooltip(rowFrame, row)
	local step = row.step
	GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
	if step.gap then
		GameTooltip:SetText(L["No recipe for these points"], 1, 0.25, 0.25)
		GameTooltip:AddLine(L.GUIDE_GAP_HINT, 1, 0.82, 0, true)
		GameTooltip:Show()
		return
	end
	GameTooltip:SetText(step.recipe.name, 1, 1, 1)
	GameTooltip:AddLine(L["Craft about %d times for skill %d to %d."]:format(step.crafts, step.from, step.to), 1, 0.82, 0)
	for _, intermediate in ipairs(step.intermediates or {}) do
		GameTooltip:AddLine(L["First craft %d x %s (cheaper than buying)."]:format(intermediate.crafts, intermediate.recipe.name),
			0.4, 0.75, 1, true)
	end
	GameTooltip:AddLine(" ")
	for _, reagent in ipairs(step.recipe.reagents) do
		local need = reagent.count * step.crafts
		local have = SR.Game.GetItemCount(reagent.itemID)
		local color = have >= need and "ff55ff55" or "ffffffff"
		GameTooltip:AddDoubleLine(Util.GetItemDisplay(reagent.itemID).name,
			Util.ColorText(("%d / %d"):format(math.min(have, need), need), color), 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Materials"], Util.FormatMoney(step.materialCost), 1, 0.82, 0, 1, 1, 1)
	if step.resale > 0 then
		GameTooltip:AddDoubleLine(L["Selling the results"], "-" .. Util.FormatMoney(step.resale), 1, 0.82, 0, 1, 1, 1)
	end
	if step.unpriced then
		GameTooltip:AddLine(L["Some materials have no known price; the cost is incomplete."], 1, 0.25, 0.25, true)
	end
	GameTooltip:Show()
end

function Page:OnCreate(frame)
	local settings = SR.DB.settings.guide

	self.ProfessionDropdown = Widgets.CreateDropdown(frame, 190, function()
		local options = {}
		for _, profession in ipairs(SR.Recipes:GetProfessions()) do
			local label = profession.learned and ("%s |cff808080(%d)|r"):format(profession.name, profession.rank or 0)
				or (profession.name .. " " .. Util.ColorText(L["(not learned)"], "ff808080"))
			options[#options + 1] = { value = profession.id, label = label }
		end
		return options
	end, function()
		return self.skillLine
	end, function(value)
		self.skillLine = value
		settings.profession = value
		settings.target = nil
		self:Refresh()
	end)
	self.ProfessionDropdown:SetPoint("TOPLEFT", 0, 0)

	local availabilityOptions = {}
	for _, level in ipairs(SR.Planner.AVAILABILITY) do
		availabilityOptions[#availabilityOptions + 1] = { value = level, label = AVAILABILITY_LABELS[level] }
	end
	self.AvailabilityDropdown = Widgets.CreateDropdown(frame, 200, availabilityOptions, function()
		return settings.availability
	end, function(value)
		settings.availability = value
		self:Refresh()
	end)
	self.AvailabilityDropdown:SetPoint("LEFT", self.ProfessionDropdown, "RIGHT", 10, 0)

	local resaleOptions = {}
	for _, mode in ipairs(SR.Planner.RESALE) do
		resaleOptions[#resaleOptions + 1] = { value = mode, label = RESALE_LABELS[mode] }
	end
	self.ResaleDropdown = Widgets.CreateDropdown(frame, 230, resaleOptions, function()
		return settings.resale
	end, function(value)
		settings.resale = value
		self:Refresh()
	end)
	self.ResaleDropdown:SetPoint("LEFT", self.AvailabilityDropdown, "RIGHT", 10, 0)

	-- Second row: skill range and the plan's summary.
	self.SkillLabel = Widgets.CreateLabel(frame, "", "GameFontHighlight")
	self.SkillLabel:SetPoint("TOPLEFT", self.ProfessionDropdown, "BOTTOMLEFT", 2, -12)

	self.TargetInput = Widgets.CreateInput(frame, 44, function(text)
		local value = tonumber(text)
		if value then
			settings.target = math.max(2, math.floor(value))
		end
		self:Refresh()
	end)
	self.TargetInput:SetNumeric(true)
	self.TargetInput:SetMaxLetters(3)
	self.TargetInput:SetPoint("LEFT", self.SkillLabel, "RIGHT", 10, 0)

	self.Summary = Widgets.CreateLabel(frame, "", "GameFontHighlightSmall")
	self.Summary:SetPoint("LEFT", self.TargetInput, "RIGHT", 16, 0)

	self.Status = Widgets.CreateLabel(frame, "", "GameFontHighlightSmall")
	self.Status:SetPoint("TOPLEFT", self.SkillLabel, "BOTTOMLEFT", 0, -10)

	-- Shopping list at the bottom.
	self.Shopping = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "name", title = L["Shopping list"], kind = "item" },
			{ key = "need", title = L["Need"], width = 60, align = "RIGHT", sortDescFirst = true },
			{ key = "have", title = L["Have"], width = 60, align = "RIGHT", sortDescFirst = true },
			{ key = "buy", title = L["Buy"], width = 60, align = "RIGHT", sortDescFirst = true },
			{ key = "unitCost", title = L["Each"], width = 90, kind = "money", align = "RIGHT", sortDescFirst = true },
			{ key = "sourceText", title = L["From"], width = 70, align = "CENTER" },
			{ key = "total", title = L["Total"], width = 100, kind = "money", align = "RIGHT", sortDescFirst = true },
		},
		sortKey = "total",
		sortDesc = true,
		rowHeight = 20,
		emptyTitle = L["Nothing to buy"],
		emptyBody = "",
	})
	self.Shopping:SetPoint("BOTTOMLEFT")
	self.Shopping:SetPoint("BOTTOMRIGHT")
	self.Shopping:SetHeight(SHOPPING_HEIGHT)

	-- The steps.
	self.Steps = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "from", title = L["Skill"], width = 74, format = function(_, row) return row.skillText end },
			{ key = "name", title = L["Craft"], kind = "item", sortable = false, format = function(_, row) return row.nameText end },
			{ key = "crafts", title = L["Crafts"], width = 60, align = "RIGHT", sortable = false },
			{
				key = "learnText", title = L["How to get it"], width = 170, sortable = false,
				onClick = function(row)
					if row.step.recipe and row.step.learn then
						SR.SourcePopup:Show(row.step.recipe)
					end
				end,
				tooltip = function(row, tooltip)
					tooltip:SetText(row.learnText, 1, 1, 1)
					if row.step.learn then
						tooltip:AddLine(L["Click to see where to get this recipe."], 0.4, 0.75, 1)
					end
				end,
			},
			{
				key = "cost", title = L["Cost (net)"], width = 110, align = "RIGHT", sortable = false,
				format = function(value, row)
					if row.step.unpriced then
						return Util.ColorText("?", COLORS.gap)
					end
					return FormatNetCost(value)
				end,
			},
		},
		sortKey = "from",
		emptyTitle = L["No plan"],
		emptyBody = L.GUIDE_EMPTY_BODY,
		onRowEnter = ShowStepTooltip,
	})
	self.Steps:SetPoint("TOPLEFT", self.Status, "BOTTOMLEFT", -2, -8)
	self.Steps:SetPoint("BOTTOMRIGHT", self.Shopping, "TOPRIGHT", 0, 12)

	-- Gathering professions: what to gather at each skill, and where.
	self.GatherSteps = Widgets.CreateDataTable(frame, {
		columns = {
			{ key = "from", title = L["Skill"], width = 74, format = function(_, row) return row.skillText end },
			{ key = "targets", title = L["Gather"], sortable = false },
			{ key = "zones", title = L["Where"], sortable = false },
			{ key = "note", title = L["Note"], width = 230, sortable = false },
		},
		sortKey = "from",
		emptyTitle = L["No plan"],
		emptyBody = L.GUIDE_EMPTY_BODY,
		onRowEnter = function(rowFrame, row)
			GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
			GameTooltip:SetText(row.targets, 1, 1, 1, 1, true)
			GameTooltip:AddLine(row.zones, 1, 0.82, 0, true)
			GameTooltip:AddLine(row.note, 0.8, 0.8, 0.8, true)
			if #row.step.zoneIDs > 0 then
				GameTooltip:AddLine(row.step.nodeID and L["Click to show it on the map, with a waypoint."]
					or L["Click to show it on the map."], 0.4, 0.75, 1, true)
			end
			GameTooltip:Show()
		end,
		onRowClick = function(row, _, rowFrame)
			self:ShowStepOnMap(row.step, rowFrame)
		end,
	})
	self.GatherSteps:SetPoint("TOPLEFT", self.Status, "BOTTOMLEFT", -2, -8)
	self.GatherSteps:SetPoint("BOTTOMRIGHT")
	self.GatherSteps:Hide()

	SR:RegisterCallback("SKILL_CHANGED", function()
		if frame:IsVisible() then
			self:Refresh()
		end
	end)
	local bagsChanged = Util.Debounce(1, function()
		if frame:IsVisible() then
			self:Refresh()
		end
	end)
	for _, event in ipairs(SR.Game.events.bagsChanged) do
		SR:RegisterEvent(event, bagsChanged)
	end
end

function Page:CurrentProfession()
	local professions = SR.Recipes:GetProfessions()
	local wanted = self.skillLine or SR.DB.settings.guide.profession
	local firstLearned
	for _, profession in ipairs(professions) do
		if profession.id == wanted then
			return profession
		end
		firstLearned = firstLearned or (profession.learned and profession)
	end
	return firstLearned or professions[1]
end

function Page:BuildStepRows(plan, skill)
	local currentIndex = skill and SR.Planner.CurrentStep(plan, skill)
	local rows = {}
	for index, step in ipairs(plan.steps) do
		local row = { step = step, from = step.from, crafts = step.crafts or "-", cost = step.cost }
		row.skillText = ("%d - %d"):format(step.from, step.to)
		if step.gap then
			row.name = L["No recipe for these points"]
			row.nameText = Util.ColorText(row.name, COLORS.gap)
		else
			local recipe = step.recipe
			local display = recipe.product and Util.GetItemDisplay(recipe.product)
			row.itemID = recipe.product
			row.icon = display and display.icon or recipe.icon
			row.name = recipe.name
			row.nameText = Util.ColorByQuality(recipe.name, display and display.quality)
		end
		if index == currentIndex then
			row.current = true
			row.skillText = Util.ColorText("> " .. row.skillText, COLORS.current)
			row.nameText = Util.ColorText(row.name, COLORS.current)
		elseif skill and step.to <= skill then
			row.skillText = Util.ColorText(row.skillText, COLORS.done)
			row.nameText = Util.ColorText(row.name, COLORS.done)
		end
		row.learnText = LearnText(step)
		rows[#rows + 1] = row
	end
	return rows, currentIndex
end

function Page:BuildShoppingRows(plan)
	local rows = {}
	for _, entry in ipairs(plan.shopping) do
		local display = Util.GetItemDisplay(entry.itemID)
		rows[#rows + 1] = {
			itemID = entry.itemID, name = display.name, icon = display.icon, quality = display.quality,
			need = entry.need, have = entry.have, buy = entry.buy, unitCost = entry.unitCost,
			total = entry.total, sourceText = SOURCE_TAGS[entry.source] or "-",
		}
	end
	return rows
end

-- One zone: straight to the map. Several: pick one from a small menu.
function Page:ShowStepOnMap(step, owner)
	local zoneIDs = step.zoneIDs or {}
	if #zoneIDs == 1 then
		SR.Gathering:ShowOnMap(step, zoneIDs[1])
	elseif #zoneIDs > 1 then
		local options = {}
		for index, mapID in ipairs(zoneIDs) do
			options[index] = { label = step.zones[index], mapID = mapID }
		end
		SR.Game.ShowMenu(owner, L["Show on the map"], options, function(option)
			SR.Gathering:ShowOnMap(step, option.mapID)
		end)
	end
end

-- Crafting and gathering professions show different controls and tables.
function Page:SetMode(gathering)
	self.AvailabilityDropdown:SetShown(not gathering)
	self.ResaleDropdown:SetShown(not gathering)
	self.Steps:SetShown(not gathering)
	self.Shopping:SetShown(not gathering)
	self.GatherSteps:SetShown(gathering)
end

function Page:RefreshGathering(profession, kind)
	local settings = SR.DB.settings.guide
	local skill = profession.learned and profession.rank or nil
	local from = skill or 1
	local maxSkill = SR.Gathering:MaxSkill()
	local target = settings.target or (profession.learned and profession.maxRank) or maxSkill
	target = math.min(math.max(target, from + 1), math.max(maxSkill, from + 1))

	local plan = SR.Gathering:Plan(kind, from, target)
	self.plan = plan
	local currentIndex
	local rows = {}
	for index, step in ipairs(plan.steps) do
		local isCurrent = skill and skill >= step.from and skill < step.to
		if isCurrent then
			currentIndex = index
		end
		local skillText = ("%d - %d"):format(step.from, step.to)
		local targets = table.concat(step.targets, ", ")
		local zones = #step.zones > 0 and table.concat(step.zones, ", ") or Util.ColorText(L["unknown"], COLORS.done)
		if isCurrent then
			skillText = Util.ColorText("> " .. skillText, COLORS.current)
			targets = Util.ColorText(targets, COLORS.current)
		elseif skill and step.to <= skill then
			skillText = Util.ColorText(skillText, COLORS.done)
			targets = Util.ColorText(targets, COLORS.done)
		end
		rows[#rows + 1] = { step = step, from = step.from, skillText = skillText, targets = targets, zones = zones, note = step.note }
	end
	self.GatherSteps:SetRows(rows)

	self.SkillLabel:SetText(L["Skill %d, plan up to"]:format(from))
	self.TargetInput:SetText(tostring(target))
	if plan.hasNodeData then
		self.Summary:SetText(L["%d steps"]:format(#plan.steps))
	else
		self.Summary:SetText(Util.ColorText(L.GATHER_NO_NODE_DATA, COLORS.gap))
	end
	if not profession.learned then
		self.Status:SetText(Util.ColorText(L["You don't have this profession; the plan starts at skill 1."], COLORS.gap))
	elseif currentIndex then
		self.Status:SetText(L["You're on step %d of %d."]:format(currentIndex, #plan.steps))
	else
		self.Status:SetText(L["You've reached the target."])
	end
	self.ProfessionDropdown:Refresh()
end

function Page:Refresh()
	local profession = self:CurrentProfession()
	if not profession then
		return
	end
	local settings = SR.DB.settings.guide
	self.skillLine = profession.id

	local gatheringKind = SR.Gathering:KindOf(profession.id)
	self:SetMode(gatheringKind ~= nil)
	if gatheringKind then
		self:RefreshGathering(profession, gatheringKind)
		return
	end

	local maxSkill = SR.Planner:MaxSkill(profession.id)
	local skill = profession.learned and profession.rank or nil
	local from = skill or 1
	local target = settings.target or (profession.learned and profession.maxRank) or maxSkill
	target = math.min(math.max(target, from + 1), math.max(maxSkill, from + 1))

	local plan = SR.Planner:Plan(profession.id, {
		from = from, to = target, availability = settings.availability, resale = settings.resale,
	})
	self.plan = plan

	local rows, currentIndex = self:BuildStepRows(plan, skill)
	self.Steps:SetRows(rows)
	self.Shopping:SetRows(self:BuildShoppingRows(plan))

	self.SkillLabel:SetText(L["Skill %d, plan up to"]:format(from))
	self.TargetInput:SetText(tostring(target))
	local craftSteps = 0
	for _, step in ipairs(plan.steps) do
		if not step.gap then
			craftSteps = craftSteps + 1
		end
	end
	local summary = L["%d steps · materials %s · learning %s"]:format(craftSteps,
		FormatNetCost(plan.totalCost), Util.FormatMoney(plan.learningCost))
	if plan.unpriced then
		summary = summary .. " " .. Util.ColorText(L["(some materials have no price)"], COLORS.gap)
	end
	self.Summary:SetText(summary)

	if not profession.learned then
		self.Status:SetText(Util.ColorText(L["You don't have this profession; the plan starts at skill 1."], COLORS.gap))
	elseif plan.gaps > 0 then
		self.Status:SetText(Util.ColorText(L["%d points have no usable recipe with this availability."]:format(plan.gaps), COLORS.gap))
	elseif currentIndex then
		self.Status:SetText(L["You're on step %d of %d."]:format(currentIndex, #plan.steps))
	else
		self.Status:SetText(L["You've reached the target."])
	end

	self.ProfessionDropdown:Refresh()
	self.AvailabilityDropdown:Refresh()
	self.ResaleDropdown:Refresh()
end

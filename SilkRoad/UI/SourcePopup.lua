--[[ SilkRoad - UI/SourcePopup.lua
	The window that opens from a recipe's "Obtained at" cell: every vendor,
	creature, quest or container that gives the recipe, with its zone and
	coordinates. Clicking one sets a waypoint (TomTom when installed,
	otherwise the game's own map pin).
]]
local _, SR = ...
local L = SR.L
local Util = SR.Util
local Widgets = SR.Widgets

local SourcePopup = SR:NewComponent("SourcePopup")

local FRAME_NAME = "SilkRoadSourceFrame"
local KIND_LABELS = {
	vendor = L["Vendor"], drop = L["Drop"], quest = L["Quest"], container = L["Container"],
	trainer = L["Trainer"], auto = L["Profession"], item = L["Recipe item"],
}

local function Location(source)
	if not source.zone then
		return source.kind == "trainer" and L["Any profession trainer"] or ""
	end
	if source.x and source.y then
		return ("%s (%.1f, %.1f)"):format(source.zone, source.x, source.y)
	end
	return source.zone
end

local function ShowSourceTooltip(rowFrame, row)
	local source = row.source
	GameTooltip:SetOwner(rowFrame, "ANCHOR_RIGHT")
	GameTooltip:SetText(source.name or KIND_LABELS[source.kind], 1, 1, 1)
	if source.detail then
		GameTooltip:AddLine("<" .. source.detail .. ">", 0.8, 0.8, 0.8)
	end
	if source.zone then
		GameTooltip:AddLine(Location(source), 1, 0.82, 0)
	end
	if source.hostile then
		GameTooltip:AddLine(L["Belongs to the other faction."], 1, 0.25, 0.25)
	end
	if SR.Sources:CanWaypoint(source) then
		GameTooltip:AddLine(L["Click to set a waypoint."], 0.4, 0.75, 1)
	end
	GameTooltip:Show()
end

function SourcePopup:Create()
	local frame = CreateFrame("Frame", FRAME_NAME, UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(frame)
	frame:SetSize(620, 360)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(f)
		f:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
	end)
	frame:Hide()
	tinsert(UISpecialFrames, FRAME_NAME)

	frame.Info = Widgets.CreateLabel(frame, "", "GameFontHighlight")
	frame.Info:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -32)
	frame.Info:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -32)
	frame.Info:SetSpacing(2)

	frame.Inset:ClearAllPoints()
	frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -72)
	frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 26)

	frame.Table = Widgets.CreateDataTable(frame.Inset, {
		columns = {
			{ key = "kindLabel", title = L["Source"], width = 90 },
			{ key = "name", title = L["Name"] },
			{ key = "location", title = L["Location"], width = 220 },
		},
		emptyTitle = L["No sources known"],
		emptyBody = L.NO_QUESTIE_HINT,
		onRowEnter = ShowSourceTooltip,
		onRowClick = function(row)
			if SR.Sources:CanWaypoint(row.source) then
				SR.Sources:SetWaypoint(row.source)
			end
		end,
	})
	frame.Table:SetPoint("TOPLEFT", 8, -8)
	frame.Table:SetPoint("BOTTOMRIGHT", -8, 8)

	frame.Footer = Widgets.CreateLabel(frame, "", "GameFontDisableSmall")
	frame.Footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 8)
	frame.Footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 8)

	self.frame = frame
	return frame
end

local function InfoText(recipe, sources)
	local lines = {}
	if recipe.recipeItem then
		local item = Util.GetItemDisplay(recipe.recipeItem)
		lines[#lines + 1] = L["Taught by %s"]:format(Util.ColorByQuality(item.name, item.quality))
	elseif sources[1].kind == "auto" then
		lines[#lines + 1] = L.SOURCE_AUTO_HINT
	else
		lines[#lines + 1] = L.SOURCE_TRAINER_HINT
	end
	if recipe.learn then
		lines[#lines + 1] = (recipe.learnExact and L["Requires skill %d."] or L["Requires about skill %d (trainer requirements aren't in the game data)."]):format(recipe.learn)
	end
	return table.concat(lines, "\n")
end

function SourcePopup:Show(recipe)
	local frame = self.frame or self:Create()
	local sources = SR.Sources:GetRecipeSources(recipe)

	frame:SetTitle(recipe.name or "?")
	frame.Info:SetText(InfoText(recipe, sources))

	local rows = {}
	for _, source in ipairs(sources) do
		local name = source.name or KIND_LABELS[source.kind]
		if source.detail then
			name = name .. " |cff999999<" .. source.detail .. ">|r"
		end
		if source.hostile then
			name = Util.ColorText(name, "ffff6060")
		end
		rows[#rows + 1] = {
			source = source, kindLabel = KIND_LABELS[source.kind] or source.kind,
			name = name, location = Location(source),
		}
	end
	frame.Table:SetRows(rows)

	if not SR.Sources:HasQuestie() and recipe.recipeItem then
		frame.Footer:SetText(L.NO_QUESTIE_HINT)
	else
		frame.Footer:SetText(L["Click a source with coordinates to set a waypoint."])
	end

	frame:ClearAllPoints()
	local main = SR.UI.frame
	if main and main:IsShown() then
		frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
	else
		frame:SetPoint("CENTER")
	end
	frame:Show()
end

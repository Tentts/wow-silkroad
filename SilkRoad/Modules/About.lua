--[[ SilkRoad - Modules/About.lua
	The About page, pinned to the very bottom of the sidebar (under
	Settings): version, links to the project and how to report problems or
	suggest ideas. The game can't open web pages, so links are shown in
	boxes that select their text for copying when clicked.
]]
local _, SR = ...
local L = SR.L
local Widgets = SR.Widgets

local Page = SR.UI:RegisterPage({
	id = "about",
	order = 990, -- bottom pages stack upwards in order: this one sits under Settings
	placement = "bottom",
	title = L["About"],
	description = L.ABOUT_DESC,
	icon = "Interface\\Icons\\INV_Misc_Book_11",
	autoRefresh = false,
})

local LINKS = {
	{ label = L["SilkRoad on GitHub"], url = "https://github.com/Tentts/wow-silkroad" },
	{ label = L["SilkRoad on CurseForge"], url = "https://www.curseforge.com/wow/addons/silkroad" },
	{ label = L["Author (Tentts) on GitHub"], url = "https://github.com/Tentts" },
}
local ISSUES_URL = "https://github.com/Tentts/wow-silkroad/issues"

local SECTION_WIDTH = 560
local LABEL_WIDTH = 190
local BOX_WIDTH = 360

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

-- A read-only box holding a URL: clicking it selects the text for Ctrl+C.
local function CreateLinkBox(parent, url)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(BOX_WIDTH, 20)
	box:SetAutoFocus(false)
	box:SetText(url)
	box:SetCursorPosition(0)
	box.url = url
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		self:SetCursorPosition(0)
	end)
	box:SetScript("OnTextChanged", function(self)
		if self:GetText() ~= self.url then -- typing can't change it
			self:SetText(self.url)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	Widgets.AttachTooltip(box, url, L["Click, then press Ctrl+C to copy the link."])
	return box
end

local function CreateLinkRow(parent, label, url, anchor, offsetY)
	local text = Widgets.CreateLabel(parent, label, "GameFontNormal")
	text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
	text:SetWidth(LABEL_WIDTH)
	local box = CreateLinkBox(parent, url)
	box:SetPoint("LEFT", text, "RIGHT", 10, 0)
	return text, box
end

function Page:OnCreate(frame)
	-- Title block
	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetSize(48, 48)
	icon:SetPoint("TOPLEFT", 0, 0)
	icon:SetTexture(SR.icon)

	local name = Widgets.CreateLabel(frame, SR.title, "GameFontNormalHuge")
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)

	self.Version = Widgets.CreateLabel(frame, L["Version %s"]:format(SR.version), "GameFontHighlight")
	self.Version:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)

	local tagline = Widgets.CreateLabel(frame, L.TAGLINE, "GameFontDisable")
	tagline:SetPoint("LEFT", self.Version, "RIGHT", 12, 0)

	-- Links
	local links = Section(frame, L["Links"], icon, -24)
	self.LinkBoxes = {}
	local anchor, offsetY = links, -12
	for _, link in ipairs(LINKS) do
		local label, box = CreateLinkRow(frame, link.label, link.url, anchor, offsetY)
		self.LinkBoxes[#self.LinkBoxes + 1] = box
		anchor, offsetY = label, -14
	end
	local copyHint = Widgets.CreateLabel(frame, L["Click a link, then press Ctrl+C to copy it."], "GameFontDisableSmall")
	copyHint:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)

	-- Feedback
	local feedback = Section(frame, L["Suggestions and problems"], copyHint, -24)
	local feedbackText = Widgets.CreateLabel(frame, L.ABOUT_FEEDBACK, "GameFontHighlight")
	feedbackText:SetPoint("TOPLEFT", feedback, "BOTTOMLEFT", 0, -10)
	feedbackText:SetWidth(SECTION_WIDTH)
	feedbackText:SetSpacing(3)
	local issuesLabel, issuesBox = CreateLinkRow(frame, L["Open an issue"], ISSUES_URL, feedbackText, -12)
	self.IssuesBox = issuesBox

	-- Commands
	local help = Widgets.CreateLabel(frame, L["Type |cffffd100/silkroad help|r in chat for every command."], "GameFontDisable")
	help:SetPoint("TOPLEFT", issuesLabel, "BOTTOMLEFT", 0, -28)
end

function Page:Refresh()
end

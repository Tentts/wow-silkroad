--[[ SilkRoad - UI/Widgets.lua
	Small factories over Blizzard's own templates, so every page looks like
	the rest of the game UI (and picks up UI skins) without repeating setup.
]]
local _, SR = ...
local L = SR.L

local Widgets = {}
SR.Widgets = Widgets

Widgets.GOLD = { 1, 0.82, 0 }

local PANEL_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Buttons\\WHITE8X8",
	edgeSize = 1,
}

local function PlaySoundKit(name)
	if SOUNDKIT and SOUNDKIT[name] then
		PlaySound(SOUNDKIT[name])
	end
end
Widgets.PlaySoundKit = PlaySoundKit

function Widgets.CreateLabel(parent, text, fontObject, justify)
	local label = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontHighlight")
	label:SetJustifyH(justify or "LEFT")
	if text then
		label:SetText(text)
	end
	return label
end

-- Shows a title (and optional wrapped body text) when the frame is hovered.
function Widgets.AttachTooltip(frame, title, body)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		if body then
			GameTooltip:AddLine(body, 1, 0.82, 0, true)
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", GameTooltip_Hide)
end

-- A dark translucent panel with a faint border.
function Widgets.CreatePanel(parent, alpha)
	local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	panel:SetBackdrop(PANEL_BACKDROP)
	panel:SetBackdropColor(0, 0, 0, alpha or 0.3)
	panel:SetBackdropBorderColor(1, 1, 1, 0.08)
	return panel
end

-- Gold section title followed by a thin rule filling the rest of the row.
-- Anchor it with two points (e.g. TOPLEFT and TOPRIGHT) to set its width.
function Widgets.CreateHeader(parent, text)
	local header = CreateFrame("Frame", nil, parent)
	header:SetHeight(18)

	header.Text = Widgets.CreateLabel(header, text, "GameFontNormal")
	header.Text:SetPoint("LEFT")

	header.Rule = header:CreateTexture(nil, "ARTWORK")
	header.Rule:SetColorTexture(1, 0.82, 0, 0.25)
	header.Rule:SetHeight(1)
	header.Rule:SetPoint("LEFT", header.Text, "RIGHT", 8, 0)
	header.Rule:SetPoint("RIGHT")
	return header
end

function Widgets.CreateButton(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 120, 22)
	button:SetText(text)
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	return button
end

-- getter() returns the current state; setter(checked) stores a new one.
function Widgets.CreateCheckbox(parent, label, tooltip, getter, setter)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check.Text:SetFontObject("GameFontHighlight")
	check.Text:SetText(label)
	check:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false
		PlaySoundKit(checked and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		setter(checked)
	end)
	if tooltip then
		Widgets.AttachTooltip(check, label, tooltip)
	end
	function check:Refresh()
		self:SetChecked(getter() and true or false)
	end
	check:Refresh()
	return check
end

-- A labelled slider with stepper arrows. formatter(value) renders the value text.
function Widgets.CreateSlider(parent, label, minValue, maxValue, step, getter, setter, formatter)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(340, 46)

	holder.Label = Widgets.CreateLabel(holder, label, "GameFontHighlight")
	holder.Label:SetPoint("TOPLEFT")

	local slider = CreateFrame("Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("TOPLEFT", holder.Label, "BOTTOMLEFT", 0, -6)
	slider:SetSize(250, 20)
	holder.Slider = slider

	local steps = math.floor((maxValue - minValue) / step + 0.5)
	local formatters = {
		[MinimalSliderWithSteppersMixin.Label.Right] = formatter or tostring,
	}
	slider:Init(getter(), minValue, maxValue, steps, formatters)
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		setter(value)
	end, holder)

	function holder:Refresh()
		self.Slider:SetValue(getter())
	end
	return holder
end

-- options = { { value = ..., label = "..." }, ... }
function Widgets.CreateDropdown(parent, width, options, getter, setter)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width or 180)
	dropdown.options = options
	dropdown:SetupMenu(function(_, rootDescription)
		local list = type(dropdown.options) == "function" and dropdown.options() or dropdown.options
		for _, option in ipairs(list) do
			rootDescription:CreateRadio(option.label, function()
				return getter() == option.value
			end, function()
				setter(option.value)
			end)
		end
	end)
	function dropdown:Refresh()
		self:GenerateMenu()
	end
	return dropdown
end

-- onChanged(text) runs whenever the text changes, including the clear button.
function Widgets.CreateSearchBox(parent, width, onChanged)
	local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	box:SetSize(width or 200, 20)
	box:SetAutoFocus(false)
	box:HookScript("OnTextChanged", function(self)
		onChanged(self:GetText() or "")
	end)
	return box
end

-- A single-line input box. onSubmit(text) runs on Enter.
function Widgets.CreateInput(parent, width, onSubmit)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width or 200, 20)
	box:SetAutoFocus(false)
	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		onSubmit(self:GetText() or "")
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	return box
end

-- Stat tile: small gold caption, big value, grey detail line.
function Widgets.CreateStatCard(parent, title)
	local card = Widgets.CreatePanel(parent, 0.35)
	card:SetHeight(74)

	card.Title = Widgets.CreateLabel(card, title, "GameFontNormalSmall")
	card.Title:SetPoint("TOPLEFT", 12, -10)

	card.Value = Widgets.CreateLabel(card, "--", "GameFontHighlightLarge")
	card.Value:SetPoint("TOPLEFT", card.Title, "BOTTOMLEFT", 0, -6)

	card.Detail = Widgets.CreateLabel(card, "", "GameFontDisableSmall")
	card.Detail:SetPoint("BOTTOMLEFT", 12, 10)
	card.Detail:SetPoint("BOTTOMRIGHT", -10, 10)
	card.Detail:SetWordWrap(false)

	function card:SetData(value, detail)
		self.Value:SetText(value)
		self.Detail:SetText(detail or "")
	end
	return card
end

-- Centered icon + title + explanation, used when a list has nothing to show.
function Widgets.CreateEmptyState(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(440, 140)

	frame.Icon = frame:CreateTexture(nil, "ARTWORK")
	frame.Icon:SetSize(40, 40)
	frame.Icon:SetPoint("TOP")
	frame.Icon:SetDesaturated(true)
	frame.Icon:SetAlpha(0.7)

	frame.Title = Widgets.CreateLabel(frame, "", "GameFontNormalLarge", "CENTER")
	frame.Title:SetPoint("TOP", frame.Icon, "BOTTOM", 0, -10)

	frame.Body = Widgets.CreateLabel(frame, "", "GameFontDisable", "CENTER")
	frame.Body:SetPoint("TOP", frame.Title, "BOTTOM", 0, -8)
	frame.Body:SetWidth(420)
	frame.Body:SetSpacing(2)

	function frame:SetContent(icon, title, body)
		self.Icon:SetTexture(icon or SR.icon)
		self.Title:SetText(title or "")
		self.Body:SetText(body or "")
	end
	frame:SetContent(nil, L["Nothing here yet"], "")
	return frame
end

--[[ SilkRoad - UI/Launcher.lua
	Ways to open the window besides /silkroad: a draggable minimap button and
	an entry in the addon compartment (the menu button by the minimap, hooked
	up through the AddonCompartmentFunc lines in the TOC).
]]
local _, SR = ...
local L = SR.L

local Launcher = SR:NewComponent("Launcher")

local BUTTON_SIZE = 31
local EDGE_OFFSET = 5

local function OnLauncherClick(mouseButton)
	if mouseButton == "RightButton" then
		SR.UI:OpenPage("settings")
	else
		SR.UI:Toggle()
	end
end

local function ShowLauncherTooltip(owner, showDragHint)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:SetText(SR.title, 1, 1, 1)
	GameTooltip:AddLine(L.TAGLINE, 1, 0.82, 0)
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L["Left-click"], L["Open / close"], 0.7, 0.7, 0.7, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Right-click"], L["Settings"], 0.7, 0.7, 0.7, 1, 1, 1)
	if showDragHint then
		GameTooltip:AddDoubleLine(L["Drag"], L["Move this button"], 0.7, 0.7, 0.7, 1, 1, 1)
	end
	GameTooltip:Show()
end

-- Addon compartment callbacks: global names are listed in SilkRoad.toc.
function SilkRoad_OnAddonCompartmentClick(_, mouseButton)
	OnLauncherClick(mouseButton)
end

function SilkRoad_OnAddonCompartmentEnter(_, menuButton)
	ShowLauncherTooltip(menuButton, false)
end

function SilkRoad_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

-- Places the button on the minimap's edge at the saved angle. Works for round
-- minimaps and for square ones from UI addons that define GetMinimapShape.
local function UpdatePosition(button)
	local angle = math.rad(SR:GetSetting("minimap.angle") or 200)
	local x, y = math.cos(angle), math.sin(angle)
	local halfWidth = Minimap:GetWidth() / 2 + EDGE_OFFSET
	local halfHeight = Minimap:GetHeight() / 2 + EDGE_OFFSET
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "ROUND" then
		x, y = x * halfWidth, y * halfHeight
	else
		-- Push the point out to the square's edge, then clamp to it.
		local scale = math.sqrt(2)
		x = math.max(-halfWidth, math.min(x * halfWidth * scale, halfWidth))
		y = math.max(-halfHeight, math.min(y * halfHeight * scale, halfHeight))
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function OnDragUpdate(button)
	local centerX, centerY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cursorX, cursorY = cursorX / scale, cursorY / scale
	local angle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX)) % 360
	SR.DB.settings.minimap.angle = angle
	UpdatePosition(button)
end

function Launcher:CreateMinimapButton()
	local button = CreateFrame("Button", "SilkRoadMinimapButton", Minimap)
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFixedFrameStrata(true)
	button:SetFrameLevel(8)
	button:SetFixedFrameLevel(true)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(24, 24)
	background:SetPoint("CENTER")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexture(SR.icon)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.Icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnClick", function(_, mouseButton)
		OnLauncherClick(mouseButton)
	end)
	button:SetScript("OnEnter", function(self)
		if not self.isDragging then
			ShowLauncherTooltip(self, true)
		end
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnDragStart", function(self)
		self.isDragging = true
		self:LockHighlight()
		GameTooltip:Hide()
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self.isDragging = false
		self:UnlockHighlight()
	end)

	-- UI addons may resize the minimap; stay on its edge when they do.
	Minimap:HookScript("OnSizeChanged", function()
		UpdatePosition(button)
	end)

	self.button = button
end

function Launcher:UpdateMinimapButton()
	if SR:GetSetting("minimap.hide") then
		if self.button then
			self.button:Hide()
		end
		return
	end
	if not self.button then
		self:CreateMinimapButton()
	end
	UpdatePosition(self.button)
	self.button:Show()
end

function Launcher:OnEnable()
	self:UpdateMinimapButton()
	SR:RegisterCallback("SETTING_CHANGED", function(_, path)
		if path == "minimap.hide" then
			self:UpdateMinimapButton()
		end
	end)
end

--[[ SilkRoad - UI/BagGlow.lua
	A pulsing red glow over bag slots for a few seconds, to spot them fast
	(the full-bags helper, Core/BagSpace.lua). Works with Blizzard's bags and
	bag addons whose slot buttons report their bag and slot (Baganator).
	The bags are opened first if none of the slots is on screen.

	SR.BagGlow:Show({ { bag, slot }, ... })
]]
local _, SR = ...

local BagGlow = SR:NewComponent("BagGlow")

local GLOW_SECONDS = 8
local BAG_OPEN_DELAY = 0.2 -- bag frames lay out their buttons a moment after opening

local glows = setmetatable({}, { __mode = "k" }) -- [button] = glow frame, never stored on the button
local hideToken = 0

local function GetGlow(button)
	local glow = glows[button]
	if not glow then
		glow = CreateFrame("Frame", nil, button)
		glow:SetAllPoints()
		glow:SetFrameLevel(button:GetFrameLevel() + 5)
		local texture = glow:CreateTexture(nil, "OVERLAY")
		texture:SetAllPoints()
		texture:SetColorTexture(1, 0.1, 0.1, 0.45)
		texture:SetBlendMode("ADD")
		local pulse = glow:CreateAnimationGroup()
		pulse:SetLooping("BOUNCE")
		local fade = pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.25)
		fade:SetDuration(0.5)
		glow.Pulse = pulse
		glows[button] = glow
	end
	return glow
end

-- { [button] = true } for the glows showing now.
function BagGlow:GetShownButtons()
	local shown = {}
	for button, glow in pairs(glows) do
		if glow:IsShown() then
			shown[button] = true
		end
	end
	return shown
end

function BagGlow:IsAnyShown()
	return next(self:GetShownButtons()) ~= nil
end

function BagGlow:HideAll()
	for _, glow in pairs(glows) do
		glow.Pulse:Stop()
		glow:Hide()
	end
end

-- Glows the slots that are on screen; returns how many.
local function GlowVisible(wanted)
	local count = 0
	SR.Game.ForEachBagButton(function(button, bag, slot)
		if wanted[bag .. ":" .. slot] then
			local glow = GetGlow(button)
			glow:Show()
			glow.Pulse:Play()
			count = count + 1
		end
	end)
	return count
end

function BagGlow:Show(slots)
	self:HideAll()
	local wanted = {}
	for _, item in ipairs(slots) do
		wanted[item.bag .. ":" .. item.slot] = true
	end
	hideToken = hideToken + 1
	local token = hideToken
	local function ScheduleHide()
		C_Timer.After(GLOW_SECONDS, function()
			if token == hideToken then
				self:HideAll()
			end
		end)
	end
	if GlowVisible(wanted) > 0 then
		ScheduleHide()
		return
	end
	SR.Game.OpenBags()
	C_Timer.After(BAG_OPEN_DELAY, function()
		if token == hideToken then
			GlowVisible(wanted)
			ScheduleHide()
		end
	end)
end

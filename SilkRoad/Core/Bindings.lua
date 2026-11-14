--[[ SilkRoad - Core/Bindings.lua
	The "open / close SilkRoad" key binding. Bindings.xml registers the action
	(so it also appears under Options > Keybindings > AddOns); this lets the
	Settings page show, set and clear its key directly.
]]
local _, SR = ...
local L = SR.L

local Bindings = SR:NewComponent("Bindings")

Bindings.ACTION = "SILKROAD_TOGGLE"

-- Names shown in Blizzard's key binding window.
BINDING_HEADER_SILKROAD = SR.title
BINDING_NAME_SILKROAD_TOGGLE = L["Open / close SilkRoad"]

local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	LMETA = true, RMETA = true,
}

function Bindings:GetKeys()
	return { GetBindingKey(self.ACTION) }
end

-- "Ctrl-S", or "Not Bound".
function Bindings:GetKeyText()
	local key = GetBindingKey(self.ACTION)
	return key and GetBindingText(key) or NOT_BOUND
end

-- Key combination for a key press, e.g. "CTRL-SHIFT-S"; nil for modifier
-- keys on their own.
function Bindings:ComboFor(key)
	if not key or MODIFIER_KEYS[key] then
		return nil
	end
	local prefix = ""
	if IsAltKeyDown() then prefix = prefix .. "ALT-" end
	if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
	if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
	return prefix .. key
end

-- Binds the combination to SilkRoad (replacing SilkRoad's previous key).
-- Returns ok, and the action the key was taken from (if any) or an error.
function Bindings:SetKey(combo)
	if InCombatLockdown() then
		return false, L["Key bindings can't be changed in combat."]
	end
	local previous = GetBindingAction(combo)
	for _, key in ipairs(self:GetKeys()) do
		SetBinding(key)
	end
	if not SetBinding(combo, self.ACTION) then
		return false, L["The game refused that key."]
	end
	SaveBindings(GetCurrentBindingSet())
	if previous and previous ~= "" and previous ~= self.ACTION then
		return true, previous
	end
	return true
end

function Bindings:ClearKeys()
	if InCombatLockdown() then
		return false, L["Key bindings can't be changed in combat."]
	end
	for _, key in ipairs(self:GetKeys()) do
		SetBinding(key)
	end
	SaveBindings(GetCurrentBindingSet())
	return true
end

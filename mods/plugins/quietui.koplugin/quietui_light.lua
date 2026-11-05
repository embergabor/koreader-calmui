--[[--
Frontlight, in percent (0..100), for the sheet's sliders and the edge drags.
Writes go straight to the light without touching the screen, so dragging is continuous.
]]

local Device = require("device")
local Screen = Device.screen

local Light = {}

-- The desktop emulator has no frontlight: keep values here so the UI can still be checked.
local preview = not Device:hasFrontlight() and (Device:isDesktop() or Device:isEmulator())
local preview_values = { brightness = 60, warmth = 0 }

local function round(v)
    return math.floor(v + 0.5)
end

function Light.hasBrightness()
    return preview or Device:hasFrontlight()
end

function Light.hasWarmth()
    return preview or Device:hasNaturalLight()
end

function Light.brightness()
    if preview then return preview_values.brightness end
    local powerd = Device:getPowerDevice()
    return round((powerd:frontlightIntensity() - powerd.fl_min) * 100 / (powerd.fl_max - powerd.fl_min))
end

function Light.setBrightness(percent, no_broadcast)
    percent = math.max(0, math.min(100, round(percent)))
    if preview then
        preview_values.brightness = percent
        return
    end
    local powerd = Device:getPowerDevice()
    powerd:setIntensity(round(powerd.fl_min + percent * (powerd.fl_max - powerd.fl_min) / 100), no_broadcast)
end

function Light.warmth()
    if preview then return preview_values.warmth end
    return round(Device:getPowerDevice():frontlightWarmth())
end

function Light.setWarmth(percent)
    percent = math.max(0, math.min(100, round(percent)))
    if preview then
        preview_values.warmth = percent
        return
    end
    Device:getPowerDevice():setWarmth(percent)
end

-- Smallest step the hardware can show, in percent. The Elipsa's warmth has 11 levels.
function Light.warmthStep()
    if preview then return 10 end
    local powerd = Device:getPowerDevice()
    return math.max(1, round(100 / (powerd.fl_warmth_max - powerd.fl_warmth_min)))
end

--- Drag up or down along a screen edge to change the light, as on the stock Kobo reader.
-- A sideways drag falls through, so swiping from the edge still turns the page.
-- actions = { left = "brightness", right = "warmth" }; either may be missing.
function Light.registerEdgeZones(widget, actions, overrides)
    local EDGE = 0.12
    local drag -- { key, base, last_time } of the drag in progress

    local function handler(ges)
        local start = ges.start_pos
        if not start or not ges.relative then return end
        local w = Screen:getWidth()
        local action
        if start.x <= w * EDGE then
            action = actions.left
        elseif start.x >= w * (1 - EDGE) then
            action = actions.right
        end
        if not action then return end
        if math.abs(ges.relative.y) <= math.abs(ges.relative.x) then return end

        local get = action == "warmth" and Light.warmth or Light.brightness
        local key = start.x .. ":" .. start.y
        if not drag or drag.key ~= key then
            drag = { key = key, base = get() }
        end
        local delta = -ges.relative.y * 100 / Screen:getHeight()
        if action == "warmth" then
            local step = Light.warmthStep()
            Light.setWarmth(round((drag.base + delta) / step) * step)
        else
            Light.setBrightness(drag.base + delta, true)
        end
        return true
    end

    widget:registerTouchZones({
        {
            id = "quietui_edge_light",
            ges = "pan",
            rate = Screen.low_pan_rate and 10 or 30,
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            overrides = overrides,
            handler = handler,
        },
    })
end

return Light

--[[--
Applies reading settings. KOReader keeps them per book (copt_ settings in the book's
sidecar); each change here also becomes the default that new books start from.
]]

local Device = require("device")
local Event = require("ui/event")
local FontList = require("fontlist")

local Presets = {
    BOOK_FONT = "book",
    RENDERS = {
        { id = "crisp", label = "Crisp" },
        { id = "smooth", label = "Smooth" },
        { id = "book", label = "Book" },
    },
}

-- antialias: crengine's font.antialiasing.mode (0 = none, 2 = all sizes).
-- hinting: 0 off, 1 native, 2 auto. kerning: 3 best. bump: added on top of the Weight setting.
local RENDER = {
    crisp = { antialias = 0, hinting = 1, kerning = 3, bump = 0 },
    smooth = { antialias = 2, hinting = 2, kerning = 3, bump = 0 },
    book = { antialias = 2, hinting = 0, kerning = 3, bump = 0.5 },
}

local function remember(name, value)
    G_reader_settings:saveSetting("copt_" .. name, value)
end

local function send(ui, ...)
    ui:handleEvent(Event:new(...))
end

function Presets.deviceDefaults(settings)
    return settings.devices[Device.model] or settings.devices.default
end

-- Fonts ---------------------------------------------------------------------

local function installed(family)
    for __, info in pairs(FontList.fontinfo) do
        for __, f in ipairs(info) do
            if f.name == family then return true end
        end
    end
    return false
end

--- Families for the font buttons: the first installed name of each settings entry.
function Presets.fontList(settings)
    local list = {}
    for __, entry in ipairs(settings.fonts) do
        for __, family in ipairs(entry) do
            if installed(family) then
                table.insert(list, family)
                break
            end
        end
    end
    return list
end

function Presets.currentFont(ui)
    if ui.document.configurable.embedded_fonts == 1 then
        return Presets.BOOK_FONT
    end
    return ui.font.font_face
end

function Presets.setFont(ui, family)
    local use_book = family == Presets.BOOK_FONT
    if (ui.document.configurable.embedded_fonts == 1) ~= use_book then
        send(ui, "ToggleEmbeddedFonts", use_book)
        remember("embedded_fonts", use_book and 1 or 0)
    end
    if not use_book then
        send(ui, "SetFont", family)
        G_reader_settings:saveSetting("cre_font", family)
    end
end

function Presets.setFontSize(ui, size)
    send(ui, "SetFontSize", size)
    remember("font_size", size)
end

-- Rendering and weight ------------------------------------------------------

function Presets.currentRender(ui)
    return ui.doc_settings:readSetting("quietui_render")
        or G_reader_settings:readSetting("quietui_render")
        or "smooth"
end

-- The Weight buttons exclude the preset's bump.
function Presets.currentWeight(ui)
    local base = ui.document.configurable.font_base_weight or 0
    return base - RENDER[Presets.currentRender(ui)].bump
end

local function applyWeight(ui, weight, render)
    local value = weight + RENDER[render].bump
    send(ui, "SetFontBaseWeight", value)
    remember("font_base_weight", value)
end

function Presets.setWeight(ui, weight)
    applyWeight(ui, weight, Presets.currentRender(ui))
end

function Presets.applyAntialias(ui, render)
    ui.document._document:setIntProperty("font.antialiasing.mode", RENDER[render].antialias)
end

function Presets.setRender(ui, render)
    local weight = Presets.currentWeight(ui)
    local spec = RENDER[render]
    ui.doc_settings:saveSetting("quietui_render", render)
    G_reader_settings:saveSetting("quietui_render", render)
    Presets.applyAntialias(ui, render)
    send(ui, "SetFontHinting", spec.hinting)
    send(ui, "SetFontKerning", spec.kerning)
    remember("font_hinting", spec.hinting)
    remember("font_kerning", spec.kerning)
    applyWeight(ui, weight, render)
end

--- First run on a device: start from its default preset.
function Presets.seedDevice(settings)
    if G_reader_settings:has("quietui_render") then return end
    local render = Presets.deviceDefaults(settings).render
    local spec = RENDER[render]
    G_reader_settings:saveSetting("quietui_render", render)
    remember("font_hinting", spec.hinting)
    remember("font_kerning", spec.kerning)
    remember("font_base_weight", spec.bump)
end

-- Page ----------------------------------------------------------------------

function Presets.setLineSpacing(ui, percent)
    send(ui, "SetLineSpace", percent)
    remember("line_spacing", percent)
end

-- Either argument may be nil to keep the current value.
function Presets.setMargins(ui, side, tb)
    local typeset = ui.typeset
    local current = typeset.unscaled_margins
    side = side or current[1]
    tb = tb or current[2]
    typeset.unscaled_margins = { side, tb, side, tb }
    local h = { side, side }
    send(ui, "ConfigChange", "h_page_margins", h)
    send(ui, "ConfigChange", "t_page_margin", tb)
    send(ui, "ConfigChange", "b_page_margin", tb)
    remember("h_page_margins", h)
    remember("t_page_margin", tb)
    remember("b_page_margin", tb)
    send(ui, "SetPageMargins", typeset.unscaled_margins)
end

function Presets.isLeftAligned(ui)
    return ui.styletweak:isTweakEnabled("text_align_most_left")
        or ui.styletweak:isTweakEnabled("text_align_all_left")
end

function Presets.setAlignment(ui, left)
    -- Not onToggleStyleTweak(): it can't find these nested tweaks' conflicts, and would leave both on.
    local styletweak = ui.styletweak
    local tweak = left and "text_align_most_left" or "text_align_most_justify"
    styletweak:resolveConflictsBeforeEnabling(tweak, {
        "text_align_most_left", "text_align_all_left", "text_align_most_justify", "text_align_all_justify",
    })
    styletweak.doc_tweaks[tweak] = true
    styletweak:updateCssText(true)
    local global = G_reader_settings:readSetting("style_tweaks", {})
    global.text_align_most_left = left or nil
    global.text_align_most_justify = (not left) or nil
end

return Presets

-- Sizes KOReader's stock screens by physical size instead of screen width.
-- Stock uses shortSide / 600, so on the Elipsa's 10.3" screen every popup, keyboard and icon comes
-- out far too large. This uses the screen's density, so they match Calm UI's own screens.
-- Runs before anything measures itself. Book text and margins keep their old sizes
-- (see 2-quietui-book-scale.lua).
local fb = require("ffi/framebuffer")

local path = os.getenv("QUIETUI_SETTINGS") or "plugins/quietui.koplugin/settings.lua"
local ok, settings = pcall(dofile, path)
local ui_scale = ok and type(settings) == "table" and settings.ui_scale or 1

local UNITS_PER_DPI = 0.0049 * ui_scale

local stock = fb.scaleBySize

function fb:scaleBySize(px)
    if self.dpi_override then
        return stock(self, px)
    end
    local by_width = math.min(self:getWidth(), self:getHeight()) / 600
    return math.ceil(px * math.min(by_width, self:getDPI() * UNITS_PER_DPI))
end

-- Sizes KOReader's stock screens by physical size instead of screen width.
-- Stock uses shortSide / 600, so on the Elipsa's 10.3" screen every popup, keyboard and icon comes
-- out far larger than on a smaller Kobo. This caps it at the density of a Libra 2, which is left as is.
-- Runs before anything measures itself. Book text and margins keep their old sizes (see main.lua).
local fb = require("ffi/framebuffer")

local LIBRA2_UNITS_PER_DPI = (1264 / 600) / 300

local stock = fb.scaleBySize

function fb:scaleBySize(px)
    if self.dpi_override then
        return stock(self, px)
    end
    local by_width = math.min(self:getWidth(), self:getHeight()) / 600
    return math.ceil(px * math.min(by_width, self:getDPI() * LIBRA2_UNITS_PER_DPI))
end

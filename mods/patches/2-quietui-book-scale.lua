-- Companion to 1-quietui-scale.lua: that patch makes the stock UI smaller, but the book must not
-- change with it. Font sizes and margins keep meaning what they always did, at shortSide / 600.
-- A late patch, because documents cache their methods when they are created.
local CreDocument = require("document/credocument")
local Device = require("device")
local Event = require("ui/event")
local ReaderTypeset = require("apps/reader/modules/readertypeset")

local function bookScale(px)
    local Screen = Device.screen
    return math.ceil(px * math.min(Screen:getWidth(), Screen:getHeight()) / 600)
end

local setFontSize = CreDocument.setFontSize
function CreDocument:setFontSize(scaled)
    if not scaled then return end
    -- Both callers in ReaderFont pass ceil(size * unit), so size is within (scaled - 1, scaled] / unit.
    -- Whole sizes are the only ones the sheet offers, and at most one fits in that range.
    local unit = Device.screen:scaleBySize(100000) / 100000
    local size = math.floor(scaled / unit)
    if size <= (scaled - 1) / unit then
        size = scaled / unit -- a fractional size from before Calm UI
    end
    return setFontSize(self, bookScale(size))
end

function ReaderTypeset:onSetPageMargins(margins, when_applied_callback)
    local bottom = bookScale(margins[4])
    if not self.view.footer.reclaim_height then
        bottom = bottom + self.view.footer:getHeight()
    end
    self.ui.document:setPageMargins(bookScale(margins[1]), bookScale(margins[2]), bookScale(margins[3]), bottom)
    self.ui:handleEvent(Event:new("UpdatePos"))
    if when_applied_callback then when_applied_callback() end
    return true
end

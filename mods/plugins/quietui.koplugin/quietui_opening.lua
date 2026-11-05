--[[--
Shown while a book opens, in place of KOReader's "Opening file '/path/to/it'" message.
A card with the book's title, author and a loading bar; it closes itself once the reader takes over.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Library = require("quietui_library")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local time = require("ui/time")
local Screen = Device.screen
local _ = require("gettext")

local D = UI.D

-- Where the card's bar is while a book loads. UIManager doesn't run during that time, so the bar
-- is drawn straight on the screen, as stock draws its own.
local bar = nil
local next_update = 0
local UPDATE_SECONDS = 0.25

local function paintBar(bb, percent)
    local h = bar.h
    bb:paintRect(bar.x, bar.y, bar.w, h, UI.WHITE)
    bb:paintBorder(bar.x, bar.y, bar.w, h, D(UI.style.border), UI.BLACK, math.floor(h / 2))
    local filled = math.floor(bar.w * percent)
    if filled > 0 then
        bb:paintRoundedRect(bar.x, bar.y, filled, h, UI.BLACK, math.floor(h / 2))
    end
end

local Opening = InputContainer:extend{
    file = nil,
}

function Opening:init()
    self.dimen = Screen:getSize()
    local title, author = Library.identify(self.file)
    local inner_w = D(480) - 2 * D(UI.style.border) - 2 * D(28)
    local content = VerticalGroup:new{
        align = "left",
        UI.label(_("Opening")),
        VerticalSpan:new{ width = D(10) },
        TextBoxWidget:new{
            text = title,
            face = UI.serif(24, 700),
            width = inner_w,
            height = author and D(100) or nil,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
    }
    if author then
        table.insert(content, VerticalSpan:new{ width = D(6) })
        table.insert(content, UI.pinned(UI.text(author, UI.sans(16), nil, inner_w), D(22)))
    end
    table.insert(content, VerticalSpan:new{ width = D(18) })
    table.insert(content, UI.canvas(inner_w, D(6), function(bb, x, y)
        bar = { x = x, y = y, w = inner_w, h = D(6) }
        paintBar(bb, 0)
    end))
    self.frame = FrameContainer:new{
        padding = D(28),
        bordersize = D(UI.style.border),
        radius = D(12),
        background = UI.WHITE,
        content,
    }
    self[1] = CenterContainer:new{ dimen = self.dimen, self.frame }
end

function Opening:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    -- Runs as soon as the UI is free again, which is once the book has loaded.
    UIManager:scheduleIn(0, function() UIManager:close(self) end)
    return true
end

function Opening.showProgress(percent)
    if not bar or not percent then return end
    local now = time.now()
    if now < next_update then return end
    next_update = now + time.s(UPDATE_SECONDS)
    paintBar(Screen.bb, math.max(0, math.min(1, percent)))
    Screen:refreshFast(bar.x, bar.y, bar.w, bar.h)
end

-- The book is open: later layout work has no card to report to.
function Opening.finish()
    bar = nil
    next_update = 0
end

return Opening

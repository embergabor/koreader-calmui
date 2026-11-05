--[[--
Shown while a book opens, in place of KOReader's "Opening file '/path/to/it'" message.
A card with the book's title and author; it closes itself once the reader takes over.
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
local Screen = Device.screen
local _ = require("gettext")

local D = UI.D

local Opening = InputContainer:extend{
    file = nil,
}

function Opening:init()
    self.dimen = Screen:getSize()
    local title, author = Library.identify(self.file)
    local inner_w = D(480) - 2 * D(2) - 2 * D(28)
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
    self.frame = FrameContainer:new{
        padding = D(28),
        bordersize = D(2),
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

return Opening

--[[--
A question in the same style as the rest of the UI: a card with a title, an optional
explanation and a row of buttons. Tap outside it to close, unless it's marked as not dismissable.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local D = UI.D

local Dialog = InputContainer:extend{
    title = nil,
    text = nil,
    buttons = nil, -- { { text = str, callback = fn, selected = bool }, ... }
    modal = true,
    dismissable = true,
}

function Dialog:init()
    self.dimen = Screen:getSize()
    if self.dismissable then
        self.ges_events = {
            TapClose = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h } } },
        }
    end
    local inner_w = D(480) - 2 * D(UI.style.border) - 2 * D(28)
    local content = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{ text = self.title, face = UI.serif(22, 700), width = inner_w },
    }
    if self.text then
        table.insert(content, VerticalSpan:new{ width = D(8) })
        table.insert(content, TextBoxWidget:new{ text = self.text, face = UI.sans(16), width = inner_w })
    end
    table.insert(content, VerticalSpan:new{ width = D(22) })
    local row = {}
    for __, button in ipairs(self.buttons) do
        table.insert(row, {
            text = button.text,
            selected = button.selected,
            callback = function()
                UIManager:close(self)
                if button.callback then button.callback() end
            end,
        })
    end
    table.insert(content, UI.group({ row }, inner_w, UI.H(44)))
    self.frame = FrameContainer:new{
        padding = D(28),
        bordersize = D(UI.style.border),
        radius = D(12),
        background = UI.WHITE,
        content,
    }
    self[1] = CenterContainer:new{ dimen = self.dimen, self.frame }
end

function Dialog:onTapClose(__, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        UIManager:close(self)
    end
    return true
end

function Dialog:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen end)
end

function Dialog:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

return Dialog

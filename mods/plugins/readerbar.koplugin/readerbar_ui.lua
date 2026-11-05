--[[--
Small building blocks for the reader bar: option boxes, pill tabs,
toggle switches, dots and a slider. Sizes are given in "design pixels"
(the mockup was drawn ~570px wide) and converted with UI.D().
scaleBySize() is min(screen w, h) / 600, so 1.05 maps a 570px-wide design
onto the full screen width on any device.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

local UI = {
    BLACK = BLACK,
    WHITE = WHITE,
    GRAY = Blitbuffer.COLOR_DARK_GRAY,
    LIGHT = Blitbuffer.COLOR_LIGHT_GRAY,
}

-- Design pixel -> device pixel.
function UI.D(px)
    return math.max(1, math.floor(Screen:scaleBySize(px * 1.05) + 0.5))
end
local D = UI.D

local function face(file, px)
    return Font:getFace(file, math.floor(px * 1.05 + 0.5))
end

UI.faces = {
    title    = face("NotoSans-BoldItalic.ttf", 13),
    subtitle = face("NotoSans-Italic.ttf", 10),
    label    = face("NotoSans-BoldItalic.ttf", 11),
    small    = face("NotoSans-BoldItalic.ttf", 9.5),
    meta     = face("NotoSans-Italic.ttf", 10.5),
    section  = face("NotoSans-Bold.ttf", 9),
    value    = face("NotoSans-BoldItalic.ttf", 16),
    link     = face("NotoSans-BoldItalic.ttf", 11.5),
    glyph    = face("NotoSans-Regular.ttf", 22),
}
UI.face = face

UI.BORDER = D(1.4)
UI.RADIUS = D(6)

function UI.text(str, f, color, max_width)
    return TextWidget:new{ text = str, face = f, fgcolor = color or BLACK, max_width = max_width }
end

-- Section heading: small, bold, uppercase, grey.
function UI.section(str)
    return UI.text(str:upper(), UI.faces.section, UI.GRAY)
end

function UI.icon(name, size, inverted)
    return IconWidget:new{ icon = name, width = size, height = size, invert = inverted }
end

-- Anything tappable.
local Tappable = InputContainer:extend{
    callback = nil,
}

function Tappable:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ w = size.w, h = size.h }
    if self.callback then
        self.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        }
    end
end

function Tappable:onTap()
    self.callback()
    return true
end

function UI.tappable(widget, callback)
    return Tappable:new{ callback = callback, widget }
end

--- Bordered box, black when selected. `content` is fn(fg_color, selected) -> widget.
function UI.box(args)
    local selected = args.selected
    local border = UI.BORDER
    local frame = FrameContainer:new{
        width = args.w,
        height = args.h,
        padding = 0,
        margin = 0,
        bordersize = border,
        color = BLACK,
        background = selected and BLACK or WHITE,
        radius = args.radius or UI.RADIUS,
        CenterContainer:new{
            dimen = Geom:new{ w = args.w - 2 * border, h = args.h - 2 * border },
            args.content(selected and WHITE or BLACK, selected),
        },
    }
    return UI.tappable(frame, args.callback)
end

--- Icon/glyph above a small label.
function UI.stacked(top, label, fg)
    return VerticalGroup:new{
        align = "center",
        top,
        VerticalSpan:new{ width = D(3) },
        UI.text(label, UI.faces.small, fg),
    }
end

--- Row of equally wide boxes; choices = { {label=..., top=fn(fg, sel), selected=bool, callback=fn}, ... }
function UI.choiceRow(choices, total_w, h, gap)
    gap = gap or D(8)
    local n = #choices
    local w = math.floor((total_w - gap * (n - 1)) / n)
    local row = HorizontalGroup:new{}
    for i, c in ipairs(choices) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        table.insert(row, UI.box{
            w = w, h = h,
            selected = c.selected,
            callback = c.callback,
            content = function(fg, sel)
                if c.top then
                    return UI.stacked(c.top(fg, sel), c.label, fg)
                end
                return UI.text(c.label, UI.faces.label, fg)
            end,
        })
    end
    return row
end

--- Two-or-more segment pill (e.g. Text | Page).
function UI.segmented(labels, selected_idx, seg_w, h, on_select)
    local border = UI.BORDER
    local row = HorizontalGroup:new{}
    for i, label in ipairs(labels) do
        local sel = i == selected_idx
        table.insert(row, UI.tappable(FrameContainer:new{
            width = seg_w,
            height = h - 2 * border,
            padding = 0,
            bordersize = 0,
            background = sel and BLACK or WHITE,
            radius = UI.RADIUS - border,
            CenterContainer:new{
                dimen = Geom:new{ w = seg_w, h = h - 2 * border },
                UI.text(label, UI.faces.label, sel and WHITE or BLACK),
            },
        }, function() on_select(i) end))
    end
    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        radius = UI.RADIUS,
        background = WHITE,
        row,
    }
end

--- Round close button.
function UI.closeButton(callback)
    local s = D(40)
    return UI.tappable(FrameContainer:new{
        width = s, height = s,
        padding = 0,
        bordersize = UI.BORDER,
        radius = math.floor(s / 2),
        background = WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = s - 2 * UI.BORDER, h = s - 2 * UI.BORDER },
            UI.icon("close", D(18)),
        },
    }, callback)
end

-- FrameContainer:getSize() measures its child and ignores width/height,
-- so solid shapes get an empty child of the exact inner size.
local function dot(size, filled, border)
    border = border or math.max(1, D(1))
    local inner = size - 2 * border
    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        radius = math.floor(size / 2),
        background = filled and BLACK or WHITE,
        Widget:new{ dimen = Geom:new{ w = inner, h = inner } },
    }
end

function UI.dots(n, pos)
    local row = HorizontalGroup:new{ align = "center" }
    for i = 1, n do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = D(9) }) end
        table.insert(row, dot(D(8), i <= pos))
    end
    return row
end

--- Toggle switch.
function UI.toggle(on, callback)
    local w, h = D(58), D(30)
    local border = UI.BORDER
    local knob_size = h - 2 * border - 2 * D(3)
    local knob = on and dot(knob_size, false, 0) or dot(knob_size, true)
    local inner = Geom:new{ w = w - 2 * border, h = h - 2 * border }
    local pad = HorizontalSpan:new{ width = D(3) }
    local track = FrameContainer:new{
        width = w, height = h,
        padding = 0,
        bordersize = border,
        radius = math.floor(h / 2),
        background = on and BLACK or WHITE,
        on and RightContainer:new{ dimen = inner, HorizontalGroup:new{ knob, pad } }
            or LeftContainer:new{ dimen = inner, HorizontalGroup:new{ pad, knob } },
    }
    return UI.tappable(track, callback)
end

--- Little drawings used inside choice boxes.
function UI.linesIcon(gap, fg)
    local w, t = D(17), math.max(1, D(1.4))
    local g = VerticalGroup:new{}
    for i = 1, 3 do
        if i > 1 then table.insert(g, VerticalSpan:new{ width = gap }) end
        table.insert(g, LineWidget:new{ dimen = Geom:new{ w = w, h = t }, background = fg })
    end
    return g
end

--- A page with text lines; `side` and `tb` are the drawn margins.
function UI.pageIcon(side, tb, fg, selected)
    local w, h = D(19), D(24)
    local t = math.max(1, D(1.2))
    local gap = D(2.5)
    local room = h - 2 * t - 2 * tb
    local count = math.max(1, math.floor((room + gap) / (t + gap)))
    local lines = VerticalGroup:new{}
    for i = 1, count do
        if i > 1 then table.insert(lines, VerticalSpan:new{ width = gap }) end
        table.insert(lines, LineWidget:new{ dimen = Geom:new{ w = w - 2 * t - 2 * side, h = t }, background = fg })
    end
    return FrameContainer:new{
        width = w, height = h,
        padding = 0,
        bordersize = t,
        color = fg,
        background = selected and BLACK or WHITE,
        radius = D(1.5),
        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * t, h = h - 2 * t }, lines },
    }
end

function UI.hline(w, color, thickness)
    return LineWidget:new{ dimen = Geom:new{ w = w, h = thickness or math.max(1, D(1)) }, background = color or BLACK }
end

--- Horizontal slider with a round knob. value is 0..1.
local Slider = InputContainer:extend{
    width = nil,
    value = 0,
    on_change = nil, -- called with the new value on tap / end of drag
    show_parent = nil,
}

function Slider:init()
    self.knob = D(18)
    self.height = self.knob + D(6)
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local range = function() return self.dimen end
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = range } },
        Pan = { GestureRange:new{ ges = "pan", range = range } },
        PanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
    }
end

function Slider:getSize()
    return self.dimen
end

function Slider:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local r = math.floor(self.knob / 2)
    local x0, x1 = x + r, x + self.width - r
    local th = math.max(2, D(2))
    local cy = y + math.floor(self.height / 2)
    local kx = x0 + math.floor((x1 - x0) * self.value + 0.5)
    bb:paintRect(x0, cy - math.floor(th / 2), x1 - x0, th, UI.LIGHT)
    bb:paintRect(x0, cy - math.floor(th / 2), kx - x0, th, BLACK)
    bb:paintRoundedRect(kx - r, cy - r, self.knob, self.knob, WHITE, r)
    bb:paintBorder(kx - r, cy - r, self.knob, self.knob, math.max(1, D(1.6)), BLACK, r)
end

function Slider:valueAt(pos)
    local r = self.knob / 2
    local v = (pos.x - self.dimen.x - r) / (self.width - 2 * r)
    return math.max(0, math.min(1, v))
end

function Slider:repaint()
    UIManager:setDirty(self.show_parent, function() return "fast", self.dimen end)
end

function Slider:onTap(_, ges)
    self.value = self:valueAt(ges.pos)
    self:repaint()
    if self.on_change then self.on_change(self.value) end
    return true
end

function Slider:onPan(_, ges)
    self.value = self:valueAt(ges.pos)
    self:repaint()
    return true
end

function Slider:onPanRelease(_, ges)
    if self.on_change then self.on_change(self.value) end
    return true
end

UI.Slider = Slider

return UI

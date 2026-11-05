--[[--
Widgets shared by the library and the Aa sheet. Sizes are in board pixels, which are a
physical size: D() maps them by the screen's density, so the UI is the same size on any
device and bigger screens simply show more. settings.lua's ui_scale multiplies everything.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE

local UI = { BLACK = BLACK, WHITE = WHITE }

-- How heavy the controls are, in board pixels (1 board pixel is 2 device pixels on the Elipsa).
-- border: outline, rule: lines between cells (0 for none), height: multiplies control heights.
local STYLES = {
    current = { border = 2, rule = 2, radius = 12, height = 1, track = 12, knob = 30, knob_border = 3, dot = 12, stroke = 2 },
    thin = { border = 1, rule = 1, radius = 12, height = 1, track = 8, knob = 26, knob_border = 2, dot = 10, stroke = 1.5 },
    slim = { border = 1, rule = 1, radius = 8, height = 0.82, track = 8, knob = 24, knob_border = 2, dot = 10, stroke = 1.5 },
    open = { border = 1, rule = 0, radius = 8, height = 0.82, track = 8, knob = 24, knob_border = 2, dot = 10, stroke = 1.5 },
    hairline = { border = 0.5, rule = 0.5, radius = 8, height = 1, track = 6, knob = 24, knob_border = 1, dot = 10, stroke = 1 },
}
UI.style = STYLES.current

function UI.setStyle(name)
    UI.style = STYLES[name] or STYLES.current
end

-- Device pixels per board pixel at 1 DPI. About 1.34 on the Elipsa (227 DPI), 1.77 on a Libra 2.
local PIXELS_PER_DPI = 1.34 / 227
UI.scale = 1

function UI.setScale(scale)
    UI.scale = scale or 1
end

local function pixelsPerBoard()
    return Screen:getDPI() * PIXELS_PER_DPI * UI.scale
end

function UI.D(px)
    return math.max(1, math.floor(px * pixelsPerBoard() + 0.5))
end
local D = UI.D

-- The screen's size in board pixels.
function UI.boardW()
    return Screen:getWidth() / pixelsPerBoard()
end

function UI.boardH()
    return Screen:getHeight() / pixelsPerBoard()
end

-- Height of a control, following the style.
-- Never below what a finger can hit: about 6.5 mm.
function UI.H(px)
    return math.max(D(px * UI.style.height), math.floor(Screen:getDPI() * 6.5 / 25.4 + 0.5))
end

-- Font:getFace() scales by scaleBySize(), so divide that back out.
function UI.face(file, px, fallback)
    local size = px * pixelsPerBoard() / (Screen:scaleBySize(1000) / 1000)
    return Font:getFace(file, size) or Font:getFace(fallback or "NotoSans-Regular.ttf", size)
end

local SANS = { [400] = "SourceSans3-Regular.ttf", [600] = "SourceSans3-Semibold.ttf", [700] = "SourceSans3-Bold.ttf" }
local SERIF = { [400] = "SourceSerif4-Regular.ttf", [700] = "SourceSerif4-Bold.ttf", italic = "SourceSerif4-It.ttf" }

function UI.sans(px, weight)
    return UI.face(SANS[weight or 400], px, weight and weight >= 600 and "NotoSans-Bold.ttf" or "NotoSans-Regular.ttf")
end

function UI.serif(px, weight)
    return UI.face(SERIF[weight or 400], px, weight == 700 and "NotoSerif-Bold.ttf" or "NotoSerif-Regular.ttf")
end

function UI.text(str, face, color, max_width)
    return TextWidget:new{ text = str, face = face, fgcolor = color or BLACK, max_width = max_width }
end

-- A font's own line height is taller than the design's: pin a widget to a fixed box height.
function UI.pinned(widget, h, w)
    local LeftContainer = require("ui/widget/container/leftcontainer")
    return LeftContainer:new{ dimen = Geom:new{ w = w or widget:getSize().w, h = h }, widget }
end

-- Section label: small, bold, uppercase.
function UI.label(str)
    return UI.pinned(UI.text(str:upper(), UI.sans(15, 700)), D(20))
end

--- Anything drawn directly. paint(bb, x, y) draws within w x h.
local Canvas = Widget:extend{ w = 0, h = 0, paint = nil }

function Canvas:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

function Canvas:paintTo(bb, x, y)
    self.paint(bb, x, y)
end

function UI.canvas(w, h, paint)
    return Canvas:new{ w = w, h = h, paint = paint }
end

--- Anything tappable.
local Tappable = InputContainer:extend{ callback = nil }

function Tappable:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ w = size.w, h = size.h }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Tappable:onTap()
    if self.callback then self.callback() end
    return true
end

function UI.tappable(widget, callback)
    return Tappable:new{ callback = callback, widget }
end

-- Clears the part of a square corner outside its rounded border.
local function maskCorners(bb, x, y, w, h, r)
    for i = 0, r - 1 do
        local off = r - i - 0.5
        local dx = math.ceil(r - math.sqrt(r * r - off * off))
        if dx > 0 then
            bb:paintRect(x, y + i, dx, 1, WHITE)
            bb:paintRect(x + w - dx, y + i, dx, 1, WHITE)
            bb:paintRect(x, y + h - 1 - i, dx, 1, WHITE)
            bb:paintRect(x + w - dx, y + h - 1 - i, dx, 1, WHITE)
        end
    end
end

--- The design's control group: cells joined by 2px rules inside one rounded border,
-- with the selected cell inverted. Every button in the UI is one of these.
--
-- rows = { { cell, cell, ... }, ... }
-- cell = { text = str, face = face, span = 1, selected = bool, callback = fn,
--          content = function(fg, selected) return widget end }
local Group = InputContainer:extend{
    rows = nil,
    width = nil,
    cell_height = nil,
}

function Group:init()
    self.border = D(UI.style.border)
    self.gap = UI.style.rule > 0 and D(UI.style.rule) or 0
    self.radius = D(UI.style.radius)
    local inner_w = self.width - 2 * self.border
    local y = self.border
    for r, row in ipairs(self.rows) do
        local total = 0
        for __, cell in ipairs(row) do total = total + (cell.span or 1) end
        local room = inner_w - (#row - 1) * self.gap
        local x = self.border
        local used = 0
        for i, cell in ipairs(row) do
            local w = i == #row and room - used or math.floor(room * (cell.span or 1) / total)
            used = used + w
            cell.x, cell.y, cell.w, cell.h = x, y, w, self.cell_height
            local fg = cell.selected and WHITE or BLACK
            if cell.content then
                cell.widget = cell.content(fg, cell.selected)
            elseif cell.text then
                cell.widget = UI.text(cell.text, cell.face or UI.sans(17, 700), fg, w - D(8))
            end
            x = x + w + self.gap
        end
        y = y + self.cell_height + (r < #self.rows and self.gap or 0)
    end
    self.dimen = Geom:new{ w = self.width, h = y + self.border }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function Group:getSize()
    return Geom:new{ w = self.dimen.w, h = self.dimen.h }
end

function Group:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local w, h = self.dimen.w, self.dimen.h
    bb:paintRect(x, y, w, h, WHITE)
    for r, row in ipairs(self.rows) do
        for i, cell in ipairs(row) do
            if cell.selected then
                bb:paintRect(x + cell.x, y + cell.y, cell.w, cell.h, BLACK)
            end
            if i < #row and self.gap > 0 then
                bb:paintRect(x + cell.x + cell.w, y + cell.y, self.gap, cell.h, BLACK)
            end
        end
        if r < #self.rows and self.gap > 0 then
            local cell = row[1]
            bb:paintRect(x + self.border, y + cell.y + cell.h, w - 2 * self.border, self.gap, BLACK)
        end
    end
    maskCorners(bb, x, y, w, h, self.radius)
    bb:paintBorder(x, y, w, h, self.border, BLACK, self.radius)
    for __, row in ipairs(self.rows) do
        for __, cell in ipairs(row) do
            if cell.widget then
                local size = cell.widget:getSize()
                cell.widget:paintTo(bb,
                    x + cell.x + math.floor((cell.w - size.w) / 2),
                    y + cell.y + math.floor((cell.h - size.h) / 2))
            end
        end
    end
end

function Group:onTap(__, ges)
    local px, py = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    for __, row in ipairs(self.rows) do
        for __, cell in ipairs(row) do
            if px >= cell.x and px < cell.x + cell.w + self.gap
                and py >= cell.y and py < cell.y + cell.h + self.gap then
                if cell.callback then cell.callback() end
                return true
            end
        end
    end
    return true
end

function UI.group(rows, width, cell_height)
    return Group:new{ rows = rows, width = width, cell_height = cell_height }
end

--- One button, as wide as its content plus padding. Takes the same fields as a cell.
function UI.button(cell, height, pad)
    local content = cell.content and cell.content(BLACK)
        or UI.text(cell.text, cell.face or UI.sans(17, 700))
    local width = content:getSize().w + 2 * D(pad or 18) + 2 * D(UI.style.border)
    return UI.group({ { cell } }, width, height or UI.H(44))
end

--- One row of options, exactly one selected. Without a width, cells are as wide as
-- the longest label plus padding.
function UI.choices(options, selected_id, width, cell_height, on_pick)
    if not width then
        local widest = 0
        for __, opt in ipairs(options) do
            if opt.label then
                widest = math.max(widest, UI.text(opt.label, opt.face or UI.sans(17, 700)):getSize().w)
            end
        end
        width = #options * (widest + 2 * D(16)) + (#options - 1) * D(UI.style.rule) + 2 * D(UI.style.border)
    end
    local row = {}
    for __, opt in ipairs(options) do
        table.insert(row, {
            text = opt.label,
            face = opt.face,
            span = opt.span,
            selected = opt.id == selected_id,
            content = opt.content,
            callback = function() on_pick(opt) end,
        })
    end
    return UI.group({ row }, width, cell_height)
end

--- Slider in 10% steps: track, black fill, round knob.
local Slider = InputContainer:extend{
    width = nil,
    height = nil,
    value = 0, -- 0..1
    steps = 10,
    on_change = nil, -- on tap and at the end of a drag
    on_drag = nil, -- during a drag
    show_parent = nil,
}

function Slider:init()
    self.height = self.height or D(56)
    self.inset = D(14)
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local range = function() return self.dimen end
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = range } },
        Pan = { GestureRange:new{ ges = "pan", range = range } },
        PanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
    }
end

function Slider:getSize()
    return Geom:new{ w = self.dimen.w, h = self.dimen.h }
end

function Slider:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    local x0 = x + self.inset
    local track_w = self.width - 2 * self.inset
    local track_h, knob = D(UI.style.track), D(UI.style.knob)
    local cy = y + math.floor(self.height / 2)
    local kx = x0 + math.floor(track_w * self.value + 0.5)
    local top = cy - math.floor(track_h / 2)
    local r = math.floor(track_h / 2)
    bb:paintBorder(x0, top, track_w, track_h, D(UI.style.border), BLACK, r)
    if kx > x0 then
        bb:paintRoundedRect(x0, top, kx - x0, track_h, BLACK, r)
    end
    local kr = math.floor(knob / 2)
    bb:paintRoundedRect(kx - kr, cy - kr, knob, knob, WHITE, kr)
    bb:paintBorder(kx - kr, cy - kr, knob, knob, D(UI.style.knob_border), BLACK, kr)
end

function Slider:valueAt(pos)
    local v = (pos.x - self.dimen.x - self.inset) / (self.width - 2 * self.inset)
    v = math.max(0, math.min(1, v))
    return math.floor(v * self.steps + 0.5) / self.steps
end

function Slider:repaint()
    UIManager:setDirty(self.show_parent, function() return "fast", self.dimen end)
end

function Slider:onTap(__, ges)
    self.value = self:valueAt(ges.pos)
    if self.on_change then self.on_change(self.value) end
    return true
end

function Slider:onPan(__, ges)
    self.value = self:valueAt(ges.pos)
    if self.on_drag then self.on_drag(self.value) end
    self:repaint()
    return true
end

function Slider:onPanRelease()
    if self.on_change then self.on_change(self.value) end
    return true
end

UI.Slider = Slider

-- Icons, drawn from the design's SVG coordinates -----------------------------

local function icon(w, h, draw)
    local pw, pxh = D(w), D(h)
    local t = D(UI.style.stroke)
    return UI.canvas(pw, pxh, function(bb, x, y)
        draw(function(lx, ly, lw) -- horizontal line
            bb:paintRect(x + D(lx), y + D(ly) - math.floor(t / 2), D(lw), t, UI.icon_fg or BLACK)
        end, function(rx, ry, rw, rh, radius) -- outlined rect
            bb:paintBorder(x + D(rx), y + D(ry), D(rw), D(rh), t, UI.icon_fg or BLACK, radius and D(radius) or 0)
        end)
    end)
end

local function colored(widget, fg)
    local paint = widget.paint
    widget.paint = function(bb, x, y)
        UI.icon_fg = fg
        paint(bb, x, y)
        UI.icon_fg = nil
    end
    return widget
end

function UI.iconGrid(fg)
    return colored(icon(24, 24, function(_line, rect)
        rect(3, 3, 8, 8)
        rect(13, 3, 8, 8)
        rect(3, 13, 8, 8)
        rect(13, 13, 8, 8)
    end), fg)
end

function UI.iconList(fg)
    return colored(icon(24, 24, function(line)
        line(4, 6, 16)
        line(4, 12, 16)
        line(4, 18, 16)
    end), fg)
end

function UI.iconSpacing(y1, y3, fg)
    return colored(icon(28, 22, function(line)
        line(4, y1, 20)
        line(4, 11, 20)
        line(4, y3, 20)
    end), fg)
end

function UI.iconAlign(l1, l2, l3, l4, fg)
    return colored(icon(26, 22, function(line)
        line(3, 3, l1 - 3)
        line(3, 8.3, l2 - 3)
        line(3, 13.6, l3 - 3)
        line(3, 19, l4 - 3)
    end), fg)
end

-- Page outline with three lines: y positions show top & bottom margins, x side margins.
function UI.iconPage(x1, x2, y1, y2, y3, fg)
    return colored(icon(22, 26, function(line, rect)
        rect(1, 1, 20, 24, 2)
        line(x1, y1, x2 - x1)
        line(x1, y2, x2 - x1)
        line(x1, y3, x2 - x1)
    end), fg)
end

-- Label under an icon, as in the Page tab's options.
function UI.iconLabel(widget, label, fg)
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    return VerticalGroup:new{
        align = "center",
        widget,
        VerticalSpan:new{ width = D(4) },
        UI.text(label, UI.sans(14, 700), fg),
    }
end

function UI.dots(count, filled)
    local d, gap = D(UI.style.dot), D(8)
    return UI.canvas(count * d + (count - 1) * gap, d, function(bb, x, y)
        for i = 1, count do
            local dx = x + (i - 1) * (d + gap)
            if i <= filled then
                bb:paintRoundedRect(dx, y, d, d, BLACK, math.floor(d / 2))
            else
                bb:paintBorder(dx, y, d, d, D(UI.style.border), BLACK, math.floor(d / 2))
            end
        end
    end)
end

return UI

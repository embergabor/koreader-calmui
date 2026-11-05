--[[--
The Aa sheet: one tap on the page opens it, and the page between its two panels
is the live preview.

Top strip: Library, title, Contents, page number; Light and Warm sliders.
Bottom panel: Text tab (size, font, weight, rendering) and
Page tab (line spacing, alignment, margins, full refresh).
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FontList = require("fontlist")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Light = require("quietui_light")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Presets = require("quietui_presets")
local TextWidget = require("ui/widget/textwidget")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local D = UI.D

local SIZES = { 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 26 }

local SPACINGS = {
    { id = 90, label = _("Tight"), y1 = 7, y3 = 15 },
    { id = 100, label = _("Normal"), y1 = 5, y3 = 17 },
    { id = 115, label = _("Relaxed"), y1 = 3, y3 = 19 },
    { id = 130, label = _("Loose"), y1 = 1.5, y3 = 20.5 },
}

local ALIGNS = {
    { id = "left", label = _("Left"), l = { 21, 15, 23, 12 } },
    { id = "justify", label = _("Justified"), l = { 23, 23, 23, 14 } },
}

-- Margins are the design's board pixels; KOReader scales its values by shortSide / 600.
local function margin(px)
    return math.floor(px * 600 / 702 + 0.5)
end

local TB_MARGINS = {
    { id = margin(16), label = _("Narrow"), y1 = 6, y3 = 20 },
    { id = margin(40), label = _("Normal"), y1 = 8, y3 = 18 },
    { id = margin(80), label = _("Wide"), y1 = 10, y3 = 16 },
}

local LR_MARGINS = {
    { id = margin(28), label = _("Narrow"), x1 = 5, x2 = 17 },
    { id = margin(56), label = _("Normal"), x1 = 7, x2 = 15 },
    { id = margin(104), label = _("Wide"), x1 = 9, x2 = 13 },
}

local REFRESHES = {
    { id = 1, label = _("Every page") },
    { id = 6, label = _("Every 6") },
    { id = 12, label = _("Every 12") },
    { id = -1, label = _("Chapters") },
}

local LIGHT_ROW_H = 48

local function closest(list, value)
    local best, best_d = list[1], math.huge
    for __, item in ipairs(list) do
        local d = math.abs(item.id - (value or 0))
        if d < best_d then best, best_d = item, d end
    end
    return best
end

local function fontPath(family, bold)
    for path, info in pairs(FontList.fontinfo) do
        for __, f in ipairs(info) do
            if f.name == family and not f.italic and (bold and f.bold or (not bold and not f.bold)) then
                return path
            end
        end
    end
end

local Sheet = InputContainer:extend{
    ui = nil,
    settings = nil,
    tab = "text",
    peeking = false,
}

function Sheet:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.content_w = self.dimen.w - 2 * D(32)
    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
    end
    self.ges_events = {
        TapPage = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    self:update()
end

-- Top strip -----------------------------------------------------------------

function Sheet:currentPage()
    return self.ui:getCurrentPage(), self.ui.document:getPageCount()
end

function Sheet:buildTopRow()
    local page, total = self:currentPage()
    local library = UI.button({
        content = function()
            return HorizontalGroup:new{
                align = "center",
                IconWidget:new{ icon = "chevron.left", width = D(20), height = D(20) },
                HorizontalSpan:new{ width = D(2) },
                UI.text(_("Library"), UI.sans(17, 700)),
            }
        end,
        callback = function() self:closeBook() end,
    }, UI.H(44), 14)
    local contents = UI.button({
        text = _("Contents"),
        callback = function()
            self:closeThen(function()
                UIManager:show(require("quietui_contents"):new{ ui = self.ui }, "ui")
            end)
        end,
    })
    local page_button = UI.button({
        text = T("%1 / %2", page, total),
        face = UI.sans(15, 700),
        callback = function()
            self:closeThen(function() self:showJumpDialog() end)
        end,
    })

    local right = HorizontalGroup:new{
        align = "center", contents, HorizontalSpan:new{ width = D(8) }, page_button,
    }
    local title_w = self.dimen.w - D(16) - D(24) - library:getSize().w - right:getSize().w - D(24)
    local props = self.ui.doc_props or {}
    return HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = D(16) },
        library,
        CenterContainer:new{
            dimen = Geom:new{ w = title_w + D(24), h = library:getSize().h },
            UI.text(props.display_title or props.title or "", UI.serif(18, 700), nil, title_w),
        },
        right,
        HorizontalSpan:new{ width = D(24) },
    }
end

-- One light control: label, minus, slider, plus, value. Percent values throughout.
function Sheet:lightRow(label, percent, step, slider_steps, set)
    local row_h = UI.H(LIGHT_ROW_H)
    local label_w, button_w, value_w, gap = D(52), D(48), D(52), D(8)
    local function change(value)
        set(math.max(0, math.min(100, value)))
        self:refreshStrip()
    end
    local function button(text, delta)
        return UI.group({ {
            { text = text, face = UI.sans(24, 600), callback = function() change(percent + delta) end },
        } }, button_w, UI.H(36))
    end
    local value_box = Geom:new{ w = value_w, h = row_h }
    return HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = D(24) },
        LeftContainer:new{ dimen = Geom:new{ w = label_w, h = row_h }, UI.label(label) },
        button("−", -step),
        UI.Slider:new{
            width = self.dimen.w - 2 * D(24) - label_w - 2 * button_w - value_w - gap,
            height = row_h,
            value = percent / 100,
            steps = slider_steps,
            show_parent = self,
            on_drag = function(v) set(v * 100) end,
            on_change = function(v) change(v * 100) end,
        },
        button("+", step),
        HorizontalSpan:new{ width = gap },
        RightContainer:new{
            dimen = value_box,
            UI.text(string.format("%d%%", percent), UI.sans(16, 700)),
        },
    }
end

function Sheet:buildStrip()
    local w = self.dimen.w
    local rows = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = D(14) },
        self:buildTopRow(),
        VerticalSpan:new{ width = D(12) },
        LineWidget:new{ dimen = Geom:new{ w = w, h = D(1) }, background = UI.BLACK },
        VerticalSpan:new{ width = D(10) },
    }
    if Light.hasBrightness() then
        table.insert(rows, self:lightRow(_("Light"), Light.brightness(), 1, 100, function(v)
            Light.setBrightness(v)
        end))
    end
    if Light.hasBrightness() and Light.hasWarmth() then
        table.insert(rows, VerticalSpan:new{ width = D(10) })
    end
    if Light.hasWarmth() then
        local step = Light.warmthStep()
        table.insert(rows, self:lightRow(_("Warm"), Light.warmth(), step, math.floor(100 / step), function(v)
            Light.setWarmth(v)
        end))
    end
    table.insert(rows, VerticalSpan:new{ width = D(10) })
    table.insert(rows, LineWidget:new{ dimen = Geom:new{ w = w, h = D(2) }, background = UI.BLACK })
    return FrameContainer:new{
        width = w,
        padding = 0,
        bordersize = 0,
        background = UI.WHITE,
        rows,
    }
end

-- Light changes don't touch the page, so only the strip needs a refresh.
function Sheet:refreshStrip()
    self.strip = self:buildStrip()
    self[1][1] = self.strip
    local size = self.strip:getSize()
    UIManager:setDirty(self, function()
        return "ui", Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    end)
end

-- Bottom panel --------------------------------------------------------------

local function labelled(title, widget)
    return VerticalGroup:new{
        align = "left",
        UI.label(title),
        VerticalSpan:new{ width = D(8) },
        widget,
    }
end

function Sheet:buildSize()
    local size = self.ui.document.configurable.font_size or 20
    local index = 1
    local best = math.huge
    for i, s in ipairs(SIZES) do
        if math.abs(s - size) < best then index, best = i, math.abs(s - size) end
    end
    local function step(delta)
        local next_index = math.max(1, math.min(#SIZES, index + delta))
        Presets.setFontSize(self.ui, SIZES[next_index])
        self:refresh()
    end
    local label = (tostring(math.floor(size * 10 + 0.5) / 10):gsub("%.0$", ""))
    return UI.group({ {
        { text = "−", face = UI.sans(28, 600), span = 96, callback = function() step(-1) end },
        {
            span = 446,
            content = function()
                return HorizontalGroup:new{
                    align = "center",
                    UI.text(label, UI.sans(24, 700)),
                    HorizontalSpan:new{ width = D(18) },
                    UI.dots(#SIZES, index),
                }
            end,
        },
        { text = "+", face = UI.sans(28, 600), span = 96, callback = function() step(1) end },
    } }, self.content_w, UI.H(52))
end

function Sheet:buildFonts()
    local current = Presets.currentFont(self.ui)
    local options = {}
    for __, family in ipairs(Presets.fontList(self.settings)) do
        local path = fontPath(family)
        table.insert(options, {
            text = family,
            face = path and UI.face(path, 19) or UI.serif(19),
            selected = family == current,
            callback = function()
                Presets.setFont(self.ui, family)
                self:refresh()
            end,
        })
    end
    local per_row = math.max(4, math.floor(self.content_w / D(150)))
    local rows = { {} }
    for __, option in ipairs(options) do
        if #rows[#rows] == per_row then table.insert(rows, {}) end
        table.insert(rows[#rows], option)
    end
    if #rows[#rows] == per_row then table.insert(rows, {}) end
    table.insert(rows[#rows], {
        text = _("Book’s own"),
        face = UI.sans(17, 700),
        span = per_row - #rows[#rows], -- fills the rest of the row
        selected = current == Presets.BOOK_FONT,
        callback = function()
            Presets.setFont(self.ui, Presets.BOOK_FONT)
            self:refresh()
        end,
    })
    return UI.group(rows, self.content_w, UI.H(46))
end

function Sheet:buildTextBody()
    local col_gap = D(24)
    local col_w = math.floor((self.content_w - col_gap) / 2)
    local weight_family = fontPath(Presets.currentFont(self.ui)) and Presets.currentFont(self.ui) or "Source Serif 4"
    local regular = fontPath(weight_family) or "SourceSerif4-Regular.ttf"
    local bold = fontPath(weight_family, true) or regular
    local weights = {
        { id = 0, label = _("Regular"), face = UI.face(regular, 16) },
        {
            id = 0.5, content = function(fg)
                return TextWidget:new{ text = _("Medium"), face = UI.face(regular, 16), bold = true, fgcolor = fg }
            end,
        },
        { id = 1, label = _("Bold"), face = UI.face(bold, 16) },
    }
    local current_weight = closest(weights, Presets.currentWeight(self.ui)).id
    return VerticalGroup:new{
        align = "left",
        labelled(_("Size"), self:buildSize()),
        VerticalSpan:new{ width = D(18) },
        labelled(_("Font"), self:buildFonts()),
        VerticalSpan:new{ width = D(18) },
        HorizontalGroup:new{
            align = "top",
            labelled(_("Weight"), UI.choices(weights, current_weight, col_w, UI.H(48), function(opt)
                Presets.setWeight(self.ui, opt.id)
                self:refresh()
            end)),
            HorizontalSpan:new{ width = col_gap },
            labelled(_("Rendering"), UI.choices(Presets.RENDERS, Presets.currentRender(self.ui), col_w, UI.H(48),
                function(opt)
                    Presets.setRender(self.ui, opt.id)
                    self:refresh()
                end)),
        },
    }
end

function Sheet:buildPageBody()
    local configurable = self.ui.document.configurable
    local col_gap = D(24)
    local col_w = math.floor((self.content_w - col_gap) / 2)
    local spacing_w = math.floor((self.content_w - col_gap) * 3 / 5)
    local align_w = self.content_w - col_gap - spacing_w

    local spacings = {}
    for __, sp in ipairs(SPACINGS) do
        table.insert(spacings, {
            id = sp.id,
            content = function(fg)
                return UI.iconLabel(UI.iconSpacing(sp.y1, sp.y3, fg), sp.label, fg)
            end,
        })
    end
    local aligns = {}
    for __, al in ipairs(ALIGNS) do
        table.insert(aligns, {
            id = al.id,
            content = function(fg)
                return UI.iconLabel(UI.iconAlign(al.l[1], al.l[2], al.l[3], al.l[4], fg), al.label, fg)
            end,
        })
    end
    local tbs = {}
    for __, m in ipairs(TB_MARGINS) do
        table.insert(tbs, {
            id = m.id,
            content = function(fg)
                return UI.iconLabel(UI.iconPage(6, 16, m.y1, 13, m.y3, fg), m.label, fg)
            end,
        })
    end
    local lrs = {}
    for __, m in ipairs(LR_MARGINS) do
        table.insert(lrs, {
            id = m.id,
            content = function(fg)
                return UI.iconLabel(UI.iconPage(m.x1, m.x2, 8, 13, 18, fg), m.label, fg)
            end,
        })
    end
    local h_margin = configurable.h_page_margins and configurable.h_page_margins[1] or LR_MARGINS[2].id
    return VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "top",
            labelled(_("Line spacing"), UI.choices(spacings, closest(SPACINGS, configurable.line_spacing).id,
                spacing_w, UI.H(72), function(opt)
                    Presets.setLineSpacing(self.ui, opt.id)
                    self:refresh()
                end)),
            HorizontalSpan:new{ width = col_gap },
            labelled(_("Alignment"), UI.choices(aligns, Presets.isLeftAligned(self.ui) and "left" or "justify",
                align_w, UI.H(72), function(opt)
                    Presets.setAlignment(self.ui, opt.id == "left")
                    self:refresh()
                end)),
        },
        VerticalSpan:new{ width = D(16) },
        HorizontalGroup:new{
            align = "top",
            labelled(_("Top & bottom margins"), UI.choices(tbs, closest(TB_MARGINS, configurable.t_page_margin).id,
                col_w, UI.H(72), function(opt)
                    Presets.setMargins(self.ui, nil, opt.id)
                    self:peek()
                end)),
            HorizontalSpan:new{ width = col_gap },
            labelled(_("Left & right margins"), UI.choices(lrs, closest(LR_MARGINS, h_margin).id,
                col_w, UI.H(72), function(opt)
                    Presets.setMargins(self.ui, opt.id, nil)
                    self:refresh()
                end)),
        },
        VerticalSpan:new{ width = D(16) },
        labelled(_("Full refresh"), UI.choices(REFRESHES, UIManager.FULL_REFRESH_COUNT, self.content_w, UI.H(48),
            function(opt)
                UIManager:setRefreshRate(opt.id, opt.id)
                self:refresh()
            end)),
    }
end

-- Both tabs share one height, so the page doesn't jump when switching.
function Sheet:panelHeight()
    if not self.panel_h then
        local tallest = math.max(self:buildTextBody():getSize().h, self:buildPageBody():getSize().h)
        self.panel_h = D(2) + D(18) + UI.H(44) + 2 * D(UI.style.border) + D(18) + tallest + D(22)
    end
    return self.panel_h
end

function Sheet:buildPanel()
    local tabs = UI.group({ {
        { text = _("Text"), selected = self.tab == "text", callback = function() self:setTab("text") end },
        { text = _("Page"), selected = self.tab == "page", callback = function() self:setTab("page") end },
    } }, D(246), UI.H(44))
    local done = UI.button({ text = _("Done"), callback = function() self:onClose() end })
    local bar = Geom:new{ w = self.content_w, h = done:getSize().h }
    local body = self.tab == "text" and self:buildTextBody() or self:buildPageBody()
    return FrameContainer:new{
        width = self.dimen.w,
        padding = 0,
        bordersize = 0,
        background = UI.WHITE,
        VerticalGroup:new{
            align = "left",
            LineWidget:new{ dimen = Geom:new{ w = self.dimen.w, h = D(2) }, background = UI.BLACK },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = D(32) },
                OverlapGroup:new{
                    dimen = Geom:new{ w = self.content_w, h = self:panelHeight() - D(2) },
                    VerticalGroup:new{
                        align = "left",
                        VerticalSpan:new{ width = D(18) },
                        OverlapGroup:new{
                            dimen = bar,
                            LeftContainer:new{ dimen = bar, tabs },
                            RightContainer:new{ dimen = bar, done },
                        },
                        VerticalSpan:new{ width = D(18) },
                        body,
                    },
                },
            },
        },
    }
end

-- State ---------------------------------------------------------------------

function Sheet:update()
    self.strip = self:buildStrip()
    self.panel = self:buildPanel()
    self[1] = OverlapGroup:new{
        dimen = self.dimen:copy(),
        self.strip,
        VerticalGroup:new{
            VerticalSpan:new{ width = self.dimen.h - self:panelHeight() },
            self.panel,
        },
    }
end

function Sheet:paintTo(bb, x, y)
    if self.peeking then return end
    InputContainer.paintTo(self, bb, x, y)
end

function Sheet:refresh()
    self:update()
    UIManager:setDirty(self, "ui")
end

function Sheet:setTab(tab)
    self.tab = tab
    self:refresh()
end

-- Hides the sheet for a moment, so the page's top and bottom edges can be seen.
function Sheet:peek()
    self:update()
    self.peeking = true
    UIManager:setDirty(self.ui, "ui")
    self.peek_end = function() self:endPeek() end
    UIManager:scheduleIn(self.settings.peek_seconds or 1.5, self.peek_end)
end

function Sheet:endPeek()
    if not self.peeking then return end
    self.peeking = false
    UIManager:unschedule(self.peek_end)
    self:update()
    UIManager:setDirty(self, "ui")
end

function Sheet:inPanels(pos)
    local panels = { self.strip, self.panel }
    for __, panel in ipairs(panels) do
        local d = panel.dimen
        if d and pos.x >= d.x and pos.x < d.x + d.w and pos.y >= d.y and pos.y < d.y + d.h then
            return true
        end
    end
    return false
end

function Sheet:onTapPage(__, ges)
    if self.peeking then
        self:endPeek()
        return true
    end
    if self:inPanels(ges.pos) then return true end
    return self:onClose()
end

-- While peeking the sheet isn't drawn, so nothing inside it may react.
function Sheet:handleEvent(event)
    if self.peeking and event.handler == "onGesture" then
        local ges = event.args and event.args[1]
        if ges and ges.ges == "tap" then self:endPeek() end
        return true
    end
    return InputContainer.handleEvent(self, event)
end

function Sheet:onClose()
    if self.peek_end then UIManager:unschedule(self.peek_end) end
    UIManager:close(self, "ui")
    return true
end

function Sheet:closeThen(callback)
    self:onClose()
    UIManager:nextTick(callback)
end

function Sheet:closeBook()
    self:closeThen(function()
        local file = self.ui.document.file
        self.ui:onClose()
        self.ui:showFileManager(file)
    end)
end

function Sheet:showJumpDialog()
    local InputDialog = require("ui/widget/inputdialog")
    local page, total = self:currentPage()
    local ui = self.ui
    local dialog
    dialog = InputDialog:new{
        title = _("Go to page"),
        input_type = "number",
        input_hint = T("%1 / %2", page, total),
        buttons = { {
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Go"),
                is_enter_default = true,
                callback = function()
                    local target = tonumber(dialog:getInputText())
                    UIManager:close(dialog)
                    if target then
                        ui:handleEvent(Event:new("GotoPage", math.max(1, math.min(total, target))))
                    end
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return Sheet

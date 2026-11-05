--[[--
Reader overlay shown when tapping the middle of the page.

    bars  : top bar (Library, title, search, bookmark) + bottom bar
            (chapter, progress slider, Contents / Text & page / Light / Notes / More)
    text  : Aa sheet, Text tab (typeface, size, line spacing, weight)
    page  : Aa sheet, Page tab (margins, alignment, status bar, hyphenation, book styles)
    light : brightness, warmth, night mode

Everything advanced stays in KOReader's own menus, reachable through
"More" and "All settings".
]]

local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FontList = require("fontlist")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UI = require("readerbar_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local N_ = _.ngettext

local D = UI.D

-- Typeface cards, serif only: the preferred three first, then installed fallbacks.
local CARD_FONTS = {
    { "Bitter", "Bitter" },
    { "Rakuten Serif", "Rakuten Serif" },
    { "Literata", "Literata" },
    { "STIX Two Text", "STIX Two" },
    { "Noto Serif", "Noto Serif" },
    { "FreeSerif", "FreeSerif" },
}

local LINE_SPACING = {
    { label = _("Tight"), value = 90, gap = 2 },
    { label = _("Normal"), value = 100, gap = 3.5 },
    { label = _("Loose"), value = 115, gap = 5 },
}

local WEIGHT = {
    { label = _("Regular"), value = 0 },
    { label = _("Medium"), value = 0.5 },
    { label = _("Bold"), value = 1 },
}

-- Unscaled margins, same units as KOReader's own margin presets; icon = drawn margin in design px.
local SIDE_MARGINS = {
    { label = _("Narrow"), value = 5, icon = 1 },
    { label = _("Normal"), value = 15, icon = 2.5 },
    { label = _("Wide"), value = 35, icon = 4 },
}
local TB_MARGINS = {
    { label = _("Narrow"), value = 5, icon = 1 },
    { label = _("Normal"), value = 15, icon = 3 },
    { label = _("Wide"), value = 30, icon = 5 },
}

local SIZE_MIN, SIZE_MAX = 12, 44

local function closestIndex(list, value)
    local best, best_d = 1, math.huge
    for i, item in ipairs(list) do
        local d = math.abs(item.value - (value or 0))
        if d < best_d then best, best_d = i, d end
    end
    return best
end

local function fontPath(name)
    for path, info in pairs(FontList.fontinfo) do
        local f = info[1]
        if f and f.name == name and not f.bold and not f.italic then
            return path
        end
    end
end

local function fontFaces()
    return require("document/credocument"):engineInit().getFontFaces()
end

local Overlay = InputContainer:extend{
    ui = nil,
    mode = "bars",
}

function Overlay:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.side = D(22)
    self.inner_w = self.dimen.w - 2 * self.side
    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
    end
    self.ges_events.TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } }
    self.ges_events.SwipeOutside = { GestureRange:new{ ges = "swipe", range = self.dimen } }
    self:update()
end

-- Layout helpers ------------------------------------------------------------

function Overlay:padded(widget)
    return HorizontalGroup:new{ HorizontalSpan:new{ width = self.side }, widget }
end

function Overlay:spread(h, left, right, center)
    local dimen = Geom:new{ w = self.inner_w, h = h }
    local group = OverlapGroup:new{ dimen = dimen }
    if left then table.insert(group, LeftContainer:new{ dimen = dimen, left }) end
    if center then table.insert(group, CenterContainer:new{ dimen = dimen, center }) end
    if right then table.insert(group, RightContainer:new{ dimen = dimen, right }) end
    return group
end

function Overlay:panel(content)
    return FrameContainer:new{
        width = self.dimen.w,
        padding = 0,
        bordersize = 0,
        background = UI.WHITE,
        content,
    }
end

function Overlay:link(text, callback, underline)
    local label = UI.text(text, UI.faces.link)
    local widget = label
    if underline then
        widget = VerticalGroup:new{
            align = "left",
            label,
            UI.hline(label:getSize().w, UI.BLACK, math.max(1, D(0.8))),
        }
    end
    return UI.tappable(widget, callback)
end

-- Bars ----------------------------------------------------------------------

function Overlay:buildTopBar()
    local props = self.ui.doc_props or {}
    local title = props.display_title or props.title or ""
    local author = props.authors and props.authors:gsub("\n.*", "") or ""
    local bar_h = D(38)
    local icon = D(19)

    local library = UI.tappable(HorizontalGroup:new{
        align = "center",
        UI.icon("chevron.left", D(14)),
        HorizontalSpan:new{ width = D(3) },
        UI.text(_("Library"), UI.faces.label),
    }, function() self:closeBook() end)

    local bookmarked = self.ui.bookmark:isPageBookmarked(self.ui.bookmark:getCurrentPageNumber())
    local actions = HorizontalGroup:new{
        align = "center",
        UI.tappable(UI.icon("appbar.search", icon), function() self:closeThen(function()
            self.ui.search:onShowFulltextSearchInput()
        end) end),
        HorizontalSpan:new{ width = D(16) },
        UI.tappable(UI.icon("bookmark", icon, bookmarked), function()
            self.ui.bookmark:onToggleBookmark()
            self:refresh()
        end),
    }

    local heading = VerticalGroup:new{
        align = "center",
        UI.text(title, UI.faces.title, nil, math.floor(self.inner_w * 0.55)),
        UI.text(author, UI.faces.subtitle, nil, math.floor(self.inner_w * 0.55)),
    }

    return self:panel(VerticalGroup:new{
        VerticalSpan:new{ width = D(10) },
        self:padded(self:spread(bar_h, library, actions, heading)),
        VerticalSpan:new{ width = D(8) },
        UI.hline(self.dimen.w, UI.BLACK, D(1.4)),
    })
end

function Overlay:pageInfo()
    local page = self.ui:getCurrentPage()
    local total = self.ui.document:getPageCount()
    local chapter = self.ui.toc:getTocTitleByPage(page)
    if not chapter or chapter == "" then
        chapter = (self.ui.doc_props or {}).display_title or ""
    end
    local left = self.ui.toc:getChapterPagesLeft(page) or (total - page)
    return page, total, chapter, left
end

function Overlay:buildBottomBar()
    local page, total, chapter, left = self:pageInfo()
    local meta = T(N_("p. %1 of %2 · %3 page left in chapter", "p. %1 of %2 · %3 pages left in chapter", left),
        page, total, left)
    local meta_widget = UI.text(meta, UI.faces.meta)
    local chapter_widget = UI.text(chapter, UI.faces.label, nil,
        self.inner_w - meta_widget:getSize().w - D(12))

    local slider = UI.Slider:new{
        width = self.inner_w,
        value = total > 1 and (page - 1) / (total - 1) or 0,
        show_parent = self,
        on_change = function(v)
            self.ui:handleEvent(Event:new("GotoPage", math.floor(v * (total - 1) + 0.5) + 1))
            self:refresh()
        end,
    }

    local tab_w = math.floor(self.inner_w / 5)
    local tab_h = D(54)
    local function tab(top, label, callback)
        return UI.tappable(CenterContainer:new{
            dimen = Geom:new{ w = tab_w, h = tab_h },
            UI.stacked(top, label, UI.BLACK),
        }, callback)
    end
    local glyph = function(str, file, px)
        return TextWidget:new{ text = str, face = UI.face(file or "NotoSerif-Bold.ttf", px or 15) }
    end
    -- Font Awesome glyphs from the bundled nerdfont (reached via font fallback)
    local symbol = function(codepoint) return glyph(codepoint, "NotoSans-Regular.ttf", 16) end
    local tabs = HorizontalGroup:new{
        tab(symbol("\u{F0CA}"), _("Contents"), function()
            self:closeThen(function() self.ui.toc:onShowToc() end)
        end),
        tab(glyph("Aa"), _("Text & page"), function() self:setMode("text") end),
        tab(symbol("\u{F185}"), _("Light"), function() self:setMode("light") end),
        tab(symbol("\u{F097}"), _("Notes"), function()
            self:closeThen(function() self.ui.bookmark:onShowBookmark() end)
        end),
        tab(glyph("•••", "NotoSans-Bold.ttf"), _("More"), function()
            self:closeThen(function() self.ui.menu:onShowMenu() end)
        end),
    }

    return self:panel(VerticalGroup:new{
        UI.hline(self.dimen.w, UI.BLACK, D(1.4)),
        VerticalSpan:new{ width = D(12) },
        self:padded(self:spread(D(18), chapter_widget, meta_widget)),
        VerticalSpan:new{ width = D(6) },
        self:padded(slider),
        VerticalSpan:new{ width = D(6) },
        self:padded(tabs),
        VerticalSpan:new{ width = D(10) },
    })
end

-- Sheets --------------------------------------------------------------------

function Overlay:buildSheet(header, body, footer_left, footer_right)
    return self:panel(VerticalGroup:new{
        UI.hline(self.dimen.w, UI.BLACK, D(1.4)),
        VerticalSpan:new{ width = D(16) },
        self:padded(self:spread(D(40), header, UI.closeButton(function() self:onClose() end))),
        VerticalSpan:new{ width = D(16) },
        self:padded(body),
        VerticalSpan:new{ width = D(16) },
        self:padded(UI.hline(self.inner_w, UI.LIGHT)),
        VerticalSpan:new{ width = D(12) },
        self:padded(self:spread(D(20), footer_left, footer_right)),
        VerticalSpan:new{ width = D(16) },
    })
end

function Overlay:aaHeader()
    return UI.segmented({ _("Text"), _("Page") }, self.mode == "text" and 1 or 2, D(100), D(40), function(i)
        self:setMode(i == 1 and "text" or "page")
    end)
end

function Overlay:aaFooter()
    local reset = self:link(_("Reset to defaults"), function()
        if self.mode == "text" then self:resetText() else self:resetPage() end
    end, true)
    local all = self:link(_("All settings ›"), function()
        self:closeThen(function() self.ui.config:onShowConfigMenu() end)
    end)
    return reset, all
end

function Overlay:cardFonts()
    local available = {}
    for __, name in ipairs(fontFaces()) do available[name] = true end
    local current = self.ui.font.font_face
    local cards, has_current = {}, false
    for __, f in ipairs(CARD_FONTS) do
        if available[f[1]] and #cards < 5 then
            table.insert(cards, { name = f[1], label = f[2] })
            has_current = has_current or f[1] == current
        end
    end
    if current and not has_current then
        cards[math.min(#cards + 1, 5)] = { name = current, label = current }
    end
    return cards, current
end

function Overlay:buildTextBody()
    local w = self.inner_w
    local cards, current = self:cardFonts()
    local choices = {}
    for __, card in ipairs(cards) do
        local path = fontPath(card.name)
        table.insert(choices, {
            label = card.label,
            selected = card.name == current,
            top = function(fg)
                return TextWidget:new{
                    text = "Aa",
                    face = path and UI.face(path, 20) or UI.faces.glyph,
                    fgcolor = fg,
                }
            end,
            callback = function() self:setFont(card.name) end,
        })
    end

    local configurable = self.ui.document.configurable
    local size = configurable.font_size or 22
    local pos = math.floor((size - SIZE_MIN) / (SIZE_MAX - SIZE_MIN) * 8 + 0.5) + 1
    local size_box = function(face_px, delta)
        return UI.box{
            w = D(64), h = D(44),
            content = function(fg)
                return TextWidget:new{ text = "A", face = UI.face("NotoSerif-Bold.ttf", face_px), fgcolor = fg }
            end,
            callback = function() self:setFontSize(size + delta) end,
        }
    end
    local size_value = VerticalGroup:new{
        align = "center",
        UI.text((tostring(math.floor(size * 10 + 0.5) / 10):gsub("%.0$", "")), UI.faces.value),
        VerticalSpan:new{ width = D(4) },
        UI.dots(9, math.max(1, math.min(9, pos))),
    }

    local col_gap = D(18)
    local col_w = math.floor((w - col_gap) / 2)
    local spacing_idx = closestIndex(LINE_SPACING, configurable.line_spacing)
    local spacing = {}
    for i, s in ipairs(LINE_SPACING) do
        table.insert(spacing, {
            label = s.label,
            selected = i == spacing_idx,
            top = function(fg) return UI.linesIcon(D(s.gap), fg) end,
            callback = function() self:apply("SetLineSpace", s.value) end,
        })
    end
    local weight_idx = closestIndex(WEIGHT, configurable.font_base_weight)
    local weights = {}
    for i, wt in ipairs(WEIGHT) do
        table.insert(weights, {
            label = wt.label,
            selected = i == weight_idx,
            top = function(fg)
                return TextWidget:new{
                    text = "Aa",
                    face = UI.face(i == 3 and "NotoSerif-Bold.ttf" or "NotoSerif-Regular.ttf", 13),
                    bold = i == 2,
                    fgcolor = fg,
                }
            end,
            callback = function() self:apply("SetFontBaseWeight", wt.value) end,
        })
    end

    return VerticalGroup:new{
        align = "left",
        self:spread(D(16), UI.section(_("Typeface")), self:link(_("All fonts ›"), function() self:showAllFonts() end)),
        VerticalSpan:new{ width = D(8) },
        UI.choiceRow(choices, w, D(70)),
        VerticalSpan:new{ width = D(16) },
        UI.section(_("Size")),
        VerticalSpan:new{ width = D(8) },
        self:spread(D(46), size_box(9, -1), size_box(15, 1), size_value),
        VerticalSpan:new{ width = D(16) },
        HorizontalGroup:new{
            align = "top",
            VerticalGroup:new{
                align = "left",
                UI.section(_("Line spacing")),
                VerticalSpan:new{ width = D(8) },
                UI.choiceRow(spacing, col_w, D(50)),
            },
            HorizontalSpan:new{ width = col_gap },
            VerticalGroup:new{
                align = "left",
                UI.section(_("Weight")),
                VerticalSpan:new{ width = D(8) },
                UI.choiceRow(weights, col_w, D(50)),
            },
        },
    }
end

function Overlay:alignmentIsLeft()
    local st = self.ui.styletweak
    return st:isTweakEnabled("text_align_most_left") or st:isTweakEnabled("text_align_all_left")
end

function Overlay:statusBarIndex()
    local footer = self.ui.view.footer
    if footer.mode == 0 then return 1 end
    return footer.settings.all_at_once and 3 or 2
end

function Overlay:buildPageBody()
    local w = self.inner_w
    local configurable = self.ui.document.configurable
    local col_gap = D(18)
    local col_w = math.floor((w - col_gap) / 2)

    local side_idx = closestIndex(SIDE_MARGINS,
        configurable.h_page_margins and configurable.h_page_margins[1] or 15)
    local tb_idx = closestIndex(TB_MARGINS, configurable.t_page_margin or 15)
    local side_margins, tb_margins = {}, {}
    for i, m in ipairs(SIDE_MARGINS) do
        table.insert(side_margins, {
            label = m.label,
            selected = i == side_idx,
            top = function(fg, sel) return UI.pageIcon(D(m.icon), D(2), fg, sel) end,
            callback = function() self:setMargins(m.value, nil) end,
        })
    end
    for i, m in ipairs(TB_MARGINS) do
        table.insert(tb_margins, {
            label = m.label,
            selected = i == tb_idx,
            top = function(fg, sel) return UI.pageIcon(D(1.5), D(m.icon), fg, sel) end,
            callback = function() self:setMargins(nil, m.value) end,
        })
    end

    local left = self:alignmentIsLeft()
    local alignment = {
        {
            label = _("Justified"),
            selected = not left,
            top = function(fg, sel) return UI.icon("align.justify", D(20), sel) end,
            callback = function() self:setAlignment(false) end,
        },
        {
            label = _("Left"),
            selected = left,
            top = function(fg, sel) return UI.icon("align.left", D(20), sel) end,
            callback = function() self:setAlignment(true) end,
        },
    }

    local status_idx = self:statusBarIndex()
    local status = {}
    for i, label in ipairs({ _("Hidden"), _("Page no."), _("Full") }) do
        table.insert(status, {
            label = label,
            selected = i == status_idx,
            callback = function() self:setStatusBar(i) end,
        })
    end

    local function toggleRow(title, subtitle, on, callback)
        return self:spread(D(36),
            VerticalGroup:new{
                align = "left",
                UI.text(title, UI.faces.label),
                UI.text(subtitle, UI.faces.subtitle, UI.GRAY),
            },
            UI.toggle(on, callback))
    end

    local book_styles = configurable.embedded_css ~= 0 and configurable.embedded_fonts ~= 0

    local function column(title, choices, h)
        return VerticalGroup:new{
            align = "left",
            UI.section(title),
            VerticalSpan:new{ width = D(8) },
            UI.choiceRow(choices, col_w, h),
        }
    end

    return VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "top",
            column(_("Side margins"), side_margins, D(56)),
            HorizontalSpan:new{ width = col_gap },
            column(_("Top & bottom"), tb_margins, D(56)),
        },
        VerticalSpan:new{ width = D(16) },
        HorizontalGroup:new{
            align = "top",
            column(_("Alignment"), alignment, D(56)),
            HorizontalSpan:new{ width = col_gap },
            column(_("Status bar"), status, D(56)),
        },
        VerticalSpan:new{ width = D(18) },
        toggleRow(_("Hyphenation"), _("Break long words at line ends"),
            self.ui.typography.hyphenation, function() self:toggleHyphenation() end),
        VerticalSpan:new{ width = D(12) },
        toggleRow(_("Book’s own fonts & styles"), _("Use the publisher’s typography instead of yours"),
            book_styles, function() self:setBookStyles(not book_styles) end),
    }
end

function Overlay:buildLightBody()
    local w = self.inner_w
    local powerd = Device:getPowerDevice()
    local body = VerticalGroup:new{ align = "left" }
    -- The desktop emulator has no frontlight: still draw the sliders so the layout can be checked.
    local preview = not Device:hasFrontlight() and (Device:isDesktop() or Device:isEmulator())

    local function sliderRow(title, value, value_text, ends, on_change)
        table.insert(body, self:spread(D(16), UI.section(title), UI.text(value_text, UI.faces.label)))
        table.insert(body, VerticalSpan:new{ width = D(6) })
        table.insert(body, UI.Slider:new{
            width = w,
            value = value,
            show_parent = self,
            on_change = function(v) on_change(v); self:refresh() end,
        })
        if ends then
            table.insert(body, self:spread(D(14),
                UI.text(ends[1], UI.faces.subtitle, UI.GRAY), UI.text(ends[2], UI.faces.subtitle, UI.GRAY)))
        end
        table.insert(body, VerticalSpan:new{ width = D(18) })
    end

    if Device:hasFrontlight() or preview then
        local min, max = powerd.fl_min, powerd.fl_max
        local v = preview and 0.6 or (powerd:frontlightIntensity() - min) / (max - min)
        sliderRow(_("Brightness"), v, string.format("%d%%", math.floor(v * 100 + 0.5)), nil, function(nv)
            powerd:setIntensity(math.floor(min + nv * (max - min) + 0.5))
        end)
    end
    if Device:hasNaturalLight() or preview then
        local v = preview and 0.25 or powerd:frontlightWarmth() / 100
        sliderRow(_("Color"), v, string.format("%d%%", math.floor(v * 100 + 0.5)), { _("Cool"), _("Warm") }, function(nv)
            powerd:setWarmth(math.floor(nv * 100 + 0.5))
        end)
    end
    return body
end

-- Build & state -------------------------------------------------------------

function Overlay:update()
    self.top, self.bottom = nil, nil
    if self.mode == "bars" then
        self.top = self:buildTopBar()
        self.bottom = self:buildBottomBar()
    elseif self.mode == "light" then
        self.bottom = self:buildSheet(UI.text(_("Light"), UI.faces.value), self:buildLightBody(), nil,
            self:link(_("All settings ›"), function()
                self:closeThen(function() Device:showLightDialog() end)
            end))
    else
        local body = self.mode == "text" and self:buildTextBody() or self:buildPageBody()
        self.bottom = self:buildSheet(self:aaHeader(), body, self:aaFooter())
    end
    local layer = OverlapGroup:new{
        dimen = self.dimen:copy(),
        BottomContainer:new{ dimen = self.dimen:copy(), self.bottom },
    }
    if self.top then table.insert(layer, self.top) end
    self[1] = layer
end

function Overlay:refresh()
    self:update()
    UIManager:setDirty(self, "ui")
end

function Overlay:setMode(mode)
    self.mode = mode
    self:update()
    -- the page behind needs repainting where the previous panels were
    UIManager:setDirty(self.ui, "ui")
    UIManager:setDirty(self, "ui")
end

function Overlay:inPanel(pos)
    for __, panel in ipairs({ self.top, self.bottom }) do
        local d = panel and panel.dimen
        if d and pos.x >= d.x and pos.x < d.x + d.w and pos.y >= d.y and pos.y < d.y + d.h then
            return true
        end
    end
    return false
end

function Overlay:onTapOutside(__, ges)
    if self:inPanel(ges.pos) then return true end
    return self:onClose()
end

function Overlay:onSwipeOutside(__, ges)
    if self:inPanel(ges.pos) then return true end
    return self:onClose()
end

function Overlay:onClose()
    UIManager:close(self, "ui")
    return true
end

function Overlay:closeThen(callback)
    self:onClose()
    UIManager:nextTick(callback)
end

function Overlay:closeBook()
    self:closeThen(function()
        local file = self.ui.document.file
        self.ui:onClose()
        self.ui:showFileManager(file)
    end)
end

-- Settings ------------------------------------------------------------------

function Overlay:apply(event, arg)
    self.ui:handleEvent(Event:new(event, arg))
    self:refresh()
end

function Overlay:setFont(face)
    self:apply("SetFont", face)
end

function Overlay:setFontSize(size)
    self:apply("SetFontSize", math.max(SIZE_MIN - 4, math.min(SIZE_MAX + 16, size)))
end

-- Either argument may be nil to keep the current value.
function Overlay:setMargins(side, tb, no_refresh)
    local typeset = self.ui.typeset
    local m = typeset.unscaled_margins
    side = side or m[1]
    tb = tb or m[2]
    typeset.unscaled_margins = { side, tb, side, tb }
    self.ui:handleEvent(Event:new("ConfigChange", "h_page_margins", { side, side }))
    self.ui:handleEvent(Event:new("ConfigChange", "t_page_margin", tb))
    self.ui:handleEvent(Event:new("ConfigChange", "b_page_margin", tb))
    self.ui:handleEvent(Event:new("SetPageMargins", typeset.unscaled_margins))
    if not no_refresh then self:refresh() end
end

function Overlay:setAlignment(left, no_refresh)
    local st = self.ui.styletweak
    if left == nil then -- back to the book's own alignment
        st:onToggleStyleTweak({ "text_align_most_left", false }, nil, true)
        st:onToggleStyleTweak({ "text_align_most_justify", false }, nil, true)
    else
        st:onToggleStyleTweak({ left and "text_align_most_left" or "text_align_most_justify", true }, nil, true)
    end
    if not no_refresh then self:refresh() end
end

function Overlay:setStatusBar(idx)
    local footer = self.ui.view.footer
    local mode = 0
    if idx == 2 then
        footer.settings.all_at_once = false
        footer.settings.page_progress = true
        footer.settings.disable_progress_bar = true
        mode = footer.mode_list.page_progress
    elseif idx == 3 then
        footer.settings.all_at_once = true
        footer.settings.disable_progress_bar = false
        mode = footer.mode_list.page_progress
    end
    G_reader_settings:saveSetting("reader_footer_mode", mode)
    footer:updateFooterTextGenerator()
    footer:applyFooterMode(mode)
    footer:refreshFooter(true, true)
    self:refresh()
end

function Overlay:toggleHyphenation(value)
    local typography = self.ui.typography
    if value == nil then value = not typography.hyphenation end
    typography.hyphenation = value
    self.ui.document:setTextHyphenation(value)
    self.ui:handleEvent(Event:new("UpdatePos"))
    self:refresh()
end

function Overlay:setBookStyles(on, no_refresh)
    self.ui:handleEvent(Event:new("ToggleEmbeddedStyleSheet", on))
    self.ui:handleEvent(Event:new("ToggleEmbeddedFonts", on))
    if not no_refresh then self:refresh() end
end

function Overlay:resetText()
    local G = G_reader_settings
    self.ui:handleEvent(Event:new("SetFont", G:readSetting("cre_font") or "Noto Serif"))
    self.ui:handleEvent(Event:new("SetFontSize", G:readSetting("copt_font_size")
        or G_defaults:readSetting("DCREREADER_CONFIG_DEFAULT_FONT_SIZE")))
    self.ui:handleEvent(Event:new("SetLineSpace", G:readSetting("copt_line_spacing") or 100))
    self.ui:handleEvent(Event:new("SetFontBaseWeight", G:readSetting("copt_font_base_weight") or 0))
    self:refresh()
end

function Overlay:resetPage()
    self:setMargins(SIDE_MARGINS[2].value, TB_MARGINS[2].value, true)
    self:setAlignment(nil, true)
    self:setBookStyles(true, true)
    self:toggleHyphenation(G_reader_settings:nilOrTrue("hyphenation"))
end

function Overlay:showAllFonts()
    local Menu = require("ui/widget/menu")
    local current = self.ui.font.font_face
    local menu
    local items = {}
    for __, face in ipairs(fontFaces()) do
        table.insert(items, {
            text = face == current and ("✓  " .. face) or face,
            bold = face == current,
            callback = function()
                UIManager:close(menu)
                self:setFont(face)
            end,
        })
    end
    menu = Menu:new{
        title = _("All fonts"),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
    }
    UIManager:show(menu)
end

return Overlay

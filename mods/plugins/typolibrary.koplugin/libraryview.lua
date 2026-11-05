--[[--
Full-screen, cover-less library list: authors as small-caps headings,
series as italic sub-headings, one line per book with its reading state.
]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LibraryScan = require("libraryscan")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")
local N_ = _.ngettext

local faces = {
    heading = Font:getFace("NotoSerif-Bold.ttf", 30),
    count   = Font:getFace("smallinfofont", 15),
    author  = Font:getFace("smallinfofontbold", 14),
    series  = Font:getFace("NotoSerif-Italic.ttf", 16),
    index   = Font:getFace("NotoSerif-Regular.ttf", 15),
    title   = Font:getFace("NotoSerif-Regular.ttf", 19),
    status  = Font:getFace("smallinfofont", 14),
    page    = Font:getFace("smallinfofont", 15),
}

local scale = function(n) return Screen:scaleBySize(n) end

local ROW_HEIGHT = {
    author = scale(46),
    series = scale(30),
    book   = scale(40),
}
local SIDE_MARGIN = scale(26)
local AUTHOR_INDENT = scale(14)
local INDEX_WIDTH = scale(26)
local BAR_WIDTH = scale(64)
local GAP = scale(14)

-- One tappable line.
local Row = InputContainer:extend{
    callback = nil,
    hold_callback = nil,
}

function Row:init()
    local range = function() return self.dimen end
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = range } },
        Hold = { GestureRange:new{ ges = "hold", range = range } },
    }
end

function Row:onTap()
    if self.callback then self.callback() end
    return true
end

function Row:onHold()
    if self.hold_callback then self.hold_callback() end
    return true
end

local LibraryView = InputContainer:extend{
    ui = nil,
    covers_fullscreen = true,
    page = 1,
}

function LibraryView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.content_width = self.dimen.w - 2 * SIDE_MARGIN

    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
        self.key_events.NextPage = { { Input.group.PgFwd } }
        self.key_events.PrevPage = { { Input.group.PgBack } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }
        self.ges_events.Pan = { GestureRange:new{ ges = "pan", range = self.dimen } } -- mousewheel
    end

    self:reload()
end

function LibraryView:reload()
    local authors, count = LibraryScan.load(self.ui and self.ui.coverbrowser)
    self.book_count = count
    self.rows = {}
    for __, author in ipairs(authors) do
        table.insert(self.rows, { kind = "author", author = author })
        for __, book in ipairs(author.books) do
            table.insert(self.rows, { kind = "book", book = book, author = author })
        end
        for __, series in ipairs(author.series) do
            table.insert(self.rows, { kind = "series", series = series, author = author })
            for __, book in ipairs(series.books) do
                table.insert(self.rows, { kind = "book", book = book, author = author, series = series })
            end
        end
    end

    self.header = self:buildHeader()
    self.footer_height = scale(56)
    self:paginate(self.dimen.h - self.header:getSize().h - self.footer_height)
    self.page = self:findPage(G_reader_settings:readSetting("lastfile")) or self.page
    self.page = math.max(1, math.min(self.page, #self.pages))
    self:buildPage()
end

-- Splits rows into pages without leaving a heading at the bottom of a page,
-- and repeats the author/series heading at the top of a continued page.
function LibraryView:paginate(available)
    self.pages = {}
    local page, used = {}, 0
    local function push(row)
        table.insert(page, row)
        used = used + ROW_HEIGHT[row.kind]
    end
    for i, row in ipairs(self.rows) do
        local need = ROW_HEIGHT[row.kind]
        local j = i
        while self.rows[j] and self.rows[j].kind ~= "book" do -- keep headings with their first book
            j = j + 1
            if self.rows[j] then need = need + ROW_HEIGHT[self.rows[j].kind] end
        end
        if #page > 0 and used + need > available then
            table.insert(self.pages, page)
            page, used = {}, 0
            if row.kind ~= "author" then
                push{ kind = "author", author = row.author, continued = true }
                if row.kind == "book" and row.series then
                    push{ kind = "series", series = row.series, author = row.author, continued = true }
                end
            end
        end
        push(row)
    end
    if #page > 0 or #self.pages == 0 then
        table.insert(self.pages, page)
    end
end

-- Page holding the given book, so returning from a book lands next to it.
function LibraryView:findPage(file)
    if not file then return end
    for page_no, page in ipairs(self.pages) do
        for __, row in ipairs(page) do
            if row.book and row.book.file == file then
                return page_no
            end
        end
    end
end

function LibraryView:buildHeader()
    local title = TextWidget:new{ text = _("Library"), face = faces.heading }
    local close = IconButton:new{
        icon = "appbar.filebrowser",
        width = scale(36),
        height = scale(36),
        padding = scale(4),
        callback = function() self:onClose() end,
        show_parent = self,
    }
    local count = TextWidget:new{
        text = T(N_("1 book", "%1 books", self.book_count), self.book_count),
        face = faces.count,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local bar_height = math.max(title:getSize().h, close:getSize().h)
    local dimen = Geom:new{ w = self.content_width, h = bar_height }
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = scale(22) },
        OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{ dimen = dimen, title },
            RightContainer:new{
                dimen = dimen,
                HorizontalGroup:new{
                    align = "center",
                    count,
                    HorizontalSpan:new{ width = GAP },
                    close,
                },
            },
        },
        VerticalSpan:new{ width = scale(10) },
        LineWidget:new{ dimen = Geom:new{ w = self.content_width, h = Size.line.thick } },
    }
end

function LibraryView:buildStatus(book)
    local text, color
    if book.status == "complete" then
        text = "✓ " .. _("read")
    elseif book.status == "abandoned" then
        text = _("on hold")
        color = Blitbuffer.COLOR_DARK_GRAY
    elseif book.status == "new" then
        text = _("new")
        color = Blitbuffer.COLOR_DARK_GRAY
    elseif book.percent then
        local pct = TextWidget:new{
            text = string.format("%d%%", math.floor(book.percent * 100 + 0.5)),
            face = faces.status,
        }
        local pct_width = TextWidget:new{ text = "100%", face = faces.status }:getSize().w
        return HorizontalGroup:new{
            align = "center",
            ProgressWidget:new{
                width = BAR_WIDTH,
                height = scale(8),
                percentage = book.percent,
                margin_h = 0,
                margin_v = 0,
                radius = 0,
                bordersize = Size.border.thin,
                fillcolor = Blitbuffer.COLOR_BLACK,
            },
            HorizontalSpan:new{ width = scale(8) },
            RightContainer:new{
                dimen = Geom:new{ w = pct_width, h = pct:getSize().h },
                pct,
            },
        }
    else
        text = _("reading")
    end
    return TextWidget:new{ text = text, face = faces.status, fgcolor = color }
end

function LibraryView:buildRow(row)
    local w = self.content_width
    local h = ROW_HEIGHT[row.kind]
    if row.kind == "author" then
        local label = row.author.name:upper()
        if row.continued then label = label .. "  ·  " .. _("continued") end
        local text = TextWidget:new{ text = label, face = faces.author, max_width = w }
        local text_h = text:getSize().h
        local rule = Size.line.thin
        return VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = h - text_h - scale(4) - rule },
            LeftContainer:new{ dimen = Geom:new{ w = w, h = text_h }, text },
            VerticalSpan:new{ width = scale(4) },
            LineWidget:new{ dimen = Geom:new{ w = w, h = rule }, background = Blitbuffer.COLOR_LIGHT_GRAY },
        }
    elseif row.kind == "series" then
        return LeftContainer:new{
            dimen = Geom:new{ w = w, h = h },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = AUTHOR_INDENT },
                TextWidget:new{
                    text = row.series.name,
                    face = faces.series,
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    max_width = w - AUTHOR_INDENT,
                },
            },
        }
    end

    local book = row.book
    local status = self:buildStatus(book)
    local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = AUTHOR_INDENT } }
    local used = AUTHOR_INDENT
    if row.series then
        local index = TextWidget:new{
            text = book.series_index and tostring(book.series_index) or "",
            face = faces.index,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
        table.insert(left, HorizontalSpan:new{ width = AUTHOR_INDENT })
        table.insert(left, LeftContainer:new{ dimen = Geom:new{ w = INDEX_WIDTH, h = index:getSize().h }, index })
        used = used + AUTHOR_INDENT + INDEX_WIDTH
    end
    table.insert(left, TextWidget:new{
        text = book.title,
        face = faces.title,
        max_width = w - used - status:getSize().w - GAP,
    })
    local dimen = Geom:new{ w = w, h = h }
    return Row:new{
        dimen = Geom:new{ w = w, h = h },
        callback = function() self:openBook(book.file) end,
        hold_callback = function() self:showBookInfo(book.file) end,
        OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{ dimen = dimen, left },
            RightContainer:new{ dimen = dimen, status },
        },
    }
end

function LibraryView:buildFooter()
    local page_count = #self.pages
    local chevron = function(icon, enabled, callback)
        return Button:new{
            icon = icon,
            icon_width = scale(34),
            icon_height = scale(34),
            bordersize = 0,
            enabled = enabled,
            callback = callback,
            show_parent = self,
        }
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = self.dimen.w, h = self.footer_height },
        HorizontalGroup:new{
            align = "center",
            chevron("chevron.left", self.page > 1, function() self:onPrevPage() end),
            HorizontalSpan:new{ width = scale(24) },
            TextWidget:new{
                text = T(_("%1 / %2"), self.page, page_count),
                face = faces.page,
            },
            HorizontalSpan:new{ width = scale(24) },
            chevron("chevron.right", self.page < page_count, function() self:onNextPage() end),
        },
    }
end

function LibraryView:buildPage()
    local list = VerticalGroup:new{ align = "left" }
    for __, row in ipairs(self.pages[self.page]) do
        table.insert(list, self:buildRow(row))
    end
    if #self.rows == 0 then
        table.insert(list, VerticalSpan:new{ width = scale(40) })
        table.insert(list, TextWidget:new{
            text = _("No books in the home folder."),
            face = faces.title,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        })
    end

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        OverlapGroup:new{
            dimen = self.dimen:copy(),
            HorizontalGroup:new{
                HorizontalSpan:new{ width = SIDE_MARGIN },
                VerticalGroup:new{ align = "left", self.header, list },
            },
            BottomContainer:new{ dimen = self.dimen:copy(), self:buildFooter() },
        },
    }
end

function LibraryView:goToPage(page)
    page = math.max(1, math.min(page, #self.pages))
    if page == self.page then return end
    self.page = page
    self:buildPage()
    UIManager:setDirty(self, "ui")
end

function LibraryView:onNextPage()
    self:goToPage(self.page + 1)
    return true
end

function LibraryView:onPrevPage()
    self:goToPage(self.page - 1)
    return true
end

function LibraryView:onSwipe(__, ges)
    if ges.direction == "west" then
        return self:onNextPage()
    elseif ges.direction == "east" then
        return self:onPrevPage()
    elseif ges.direction == "north" or ges.direction == "south" then
        return true
    end
    UIManager:setDirty(nil, "full") -- diagonal swipe: clean up ghosting
    return false
end

function LibraryView:onPan(__, ges)
    if ges.mousewheel_direction then
        if ges.direction == "north" then
            self:onNextPage()
        elseif ges.direction == "south" then
            self:onPrevPage()
        end
    end
    return true
end

function LibraryView:openBook(file)
    filemanagerutil.openFile(self.ui, file, function() UIManager:close(self) end, true)
end

function LibraryView:showBookInfo(file)
    if self.ui and self.ui.bookinfo then
        self.ui.bookinfo:show(file)
    end
end

function LibraryView:onClose()
    UIManager:close(self, "flashui")
    return true
end

return LibraryView

--[[--
The library screen. It replaces the file manager's content rather than sitting on
top of it, so the file browser is never drawn.

Header: sort (Recent / Title / Author) and view (Grid / List). Swipe to change page.
]]

local Blitbuffer = require("ffi/blitbuffer")
local has_covers, BookInfoManager = pcall(require, "bookinfomanager") -- Cover Browser may be turned off
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FontList = require("fontlist")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Library = require("quietui_library")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local D = UI.D

local SORTS = {
    { id = "recent", label = _("Recent") },
    { id = "title", label = _("Title") },
    { id = "author", label = _("Author") },
}

-- Board pixels, from the design.
local HEADER_H, FOOTER_H = 76, 56
local SIDE = 32
local GRID_COLS, GRID_COL_GAP, GRID_ROW_GAP, GRID_PAD = 4, 20, 22, 24
local COVER_H, TILE_TEXT_H, TILE_GAP = 196, 36, 8
local LIST_PAD, LIST_ROW_H = 8, 66
local AUTHOR_H, SERIES_H = 44, 30

local LibraryView = InputContainer:extend{
    ui = nil,
    settings = nil,
    run_action = nil, -- called with the settings.gestures action for a corner long-press
    page = 1,
}

function LibraryView:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.sort = G_reader_settings:readSetting("quietui_sort", "recent")
    self.view = G_reader_settings:readSetting("quietui_view", "grid")
    self.cover_w = math.floor((D(702 - 2 * SIDE) - (GRID_COLS - 1) * D(GRID_COL_GAP)) / GRID_COLS)
    self.cover_specs = { max_cover_w = self.cover_w, max_cover_h = D(COVER_H) }
    self.covers = {}

    local corner = Geom:new{ x = 0, y = 0, w = math.floor(self.dimen.w * 0.15), h = math.floor(self.dimen.h * 0.1) }
    self.ges_events = {
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        HoldCorner = { GestureRange:new{ ges = "hold", range = corner } },
        Pan = { GestureRange:new{ ges = "pan", range = self.dimen } }, -- mousewheel
    }
    self.books = Library.load(self.settings)
    self:paginate()
    self.page = self:findPage(G_reader_settings:readSetting("lastfile")) or 1
    self:buildPage()
end

-- Splitting into pages ------------------------------------------------------

function LibraryView:bookRows(books)
    if self.view == "list" then
        local rows = {}
        for __, book in ipairs(books) do
            table.insert(rows, { kind = "list", h = LIST_ROW_H, books = { book } })
        end
        return rows
    end
    local rows, current = {}, nil
    for __, book in ipairs(books) do
        if not current or #current.books == GRID_COLS then
            current = { kind = "grid", h = COVER_H + TILE_GAP + TILE_TEXT_H, books = {} }
            table.insert(rows, current)
        end
        table.insert(current.books, book)
    end
    return rows
end

function LibraryView:flatRows()
    if self.sort ~= "author" then
        return self:bookRows(Library.sorted(self.books, self.sort))
    end
    local rows = {}
    for __, author in ipairs(Library.byAuthor(self.books)) do
        table.insert(rows, { kind = "author", h = AUTHOR_H, name = author.name })
        for __, row in ipairs(self:bookRows(author.books)) do
            row.author = author.name
            table.insert(rows, row)
        end
        for __, series in ipairs(author.series) do
            table.insert(rows, { kind = "series", h = SERIES_H, name = series.name, author = author.name })
            for __, row in ipairs(self:bookRows(series.books)) do
                row.author, row.series = author.name, series.name
                table.insert(rows, row)
            end
        end
    end
    return rows
end

-- Keeps a heading with its first row, and repeats headings on a continued page.
function LibraryView:paginate()
    local pad = self.view == "grid" and GRID_PAD or LIST_PAD
    local available = 936 - HEADER_H - FOOTER_H - pad
    local gap = self.view == "grid" and GRID_ROW_GAP or 0
    local rows = self:flatRows()
    self.pages = {}
    local page, used = {}, 0
    local function push(row)
        table.insert(page, row)
        used = used + row.h + ((row.kind == "grid" or row.kind == "list") and gap or 0)
    end
    for i, row in ipairs(rows) do
        local need = row.h
        local j = i
        while rows[j] and (rows[j].kind == "author" or rows[j].kind == "series") do
            j = j + 1
            if rows[j] then need = need + rows[j].h end
        end
        if #page > 0 and used + need > available then
            table.insert(self.pages, page)
            page, used = {}, 0
            if row.kind ~= "author" and row.author then
                push{ kind = "author", h = AUTHOR_H, name = row.author, continued = true }
                if row.kind ~= "series" and row.series then
                    push{ kind = "series", h = SERIES_H, name = row.series, continued = true }
                end
            end
        end
        push(row)
    end
    if #page > 0 or #self.pages == 0 then
        table.insert(self.pages, page)
    end
end

function LibraryView:findPage(file)
    if not file then return end
    for page_no, page in ipairs(self.pages) do
        for __, row in ipairs(page) do
            for __, book in ipairs(row.books or {}) do
                if book.file == file then return page_no end
            end
        end
    end
end

-- Covers --------------------------------------------------------------------

local function fontPath(family)
    for path, info in pairs(FontList.fontinfo) do
        local f = info[1]
        if f and f.name == family and not f.bold and not f.italic then return path end
    end
end

-- A stable, varied look for books without a cover image.
function LibraryView:drawnStyle(book)
    local hash = 0
    for i = 1, #book.title do hash = (hash * 31 + book.title:byte(i)) % 9973 end
    local families = {}
    for __, entry in ipairs(self.settings.fonts) do
        for __, family in ipairs(entry) do
            local path = fontPath(family)
            if path then
                table.insert(families, path)
                break
            end
        end
    end
    return families[hash % math.max(#families, 1) + 1] or "SourceSerif4-Regular.ttf", hash % 4 == 1
end

function LibraryView:drawnCover(book, w, h)
    local path, inverted = self:drawnStyle(book)
    local fg = inverted and UI.WHITE or UI.BLACK
    local bg = inverted and UI.BLACK or UI.WHITE
    local dimen = Geom:new{ w = w, h = h }
    local inner_w = w - 2 * D(2) - 2 * D(12)
    local inner_h = h - 2 * D(2) - D(14) - D(12)
    local top = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = book.title,
            face = UI.face(path, 18),
            width = inner_w,
            height = inner_h - D(40),
            height_overflow_show_ellipsis = true,
            fgcolor = fg,
            bgcolor = bg,
        },
        VerticalSpan:new{ width = D(10) },
        LineWidget:new{ dimen = Geom:new{ w = D(24), h = D(2) }, background = fg },
    }
    local author = UI.text(book.author:upper(), UI.sans(11, 700), fg, inner_w)
    return FrameContainer:new{
        padding = 0,
        bordersize = D(UI.style.border),
        radius = D(3),
        background = bg,
        OverlapGroup:new{
            dimen = Geom:new{ w = dimen.w - 2 * D(2), h = dimen.h - 2 * D(2) },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = D(12) },
                VerticalGroup:new{ align = "left", VerticalSpan:new{ width = D(14) }, top },
            },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = D(12) },
                VerticalGroup:new{
                    align = "left",
                    VerticalSpan:new{ width = dimen.h - 2 * D(2) - D(12) - author:getSize().h },
                    author,
                },
            },
        },
    }
end

function LibraryView:drawnThumb(book, w, h)
    local path, inverted = self:drawnStyle(book)
    return FrameContainer:new{
        padding = 0,
        bordersize = D(UI.style.border),
        radius = D(2),
        background = inverted and UI.BLACK or UI.WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * D(2), h = h - 2 * D(2) },
            UI.text(book.title_key:sub(1, 1):upper(), UI.face(path, 15), inverted and UI.WHITE or UI.BLACK),
        },
    }
end

-- Returns the cached cover image, or nil and queues the book for extraction.
function LibraryView:coverImage(book, w, h)
    if not has_covers then return end
    local info = BookInfoManager:getBookInfo(book.file, true)
    if not info or info.cover_fetched ~= "Y"
        or (info.has_cover and BookInfoManager.isCachedCoverInvalid(info, self.cover_specs)) then
        if info and info.cover_bb then info.cover_bb:free() end
        table.insert(self.to_extract, { filepath = book.file, cover_specs = self.cover_specs })
        return
    end
    if not info.has_cover or info.ignore_cover or not info.cover_bb then
        if info.cover_bb then info.cover_bb:free() end
        return
    end
    local __, __, scale = BookInfoManager.getCachedCoverSize(info.cover_w, info.cover_h, w, h)
    -- ImageWidget owns cover_bb from here (image_disposable defaults to true)
    local image = ImageWidget:new{ image = info.cover_bb, scale_factor = scale }
    image:_render()
    table.insert(self.covers, image)
    return image
end

function LibraryView:coverWidget(book, w, h, thumb)
    local image = self:coverImage(book, w - 2 * D(2), h - 2 * D(2))
    if image then
        self.has_images = true
        return FrameContainer:new{ padding = 0, bordersize = D(UI.style.border), radius = D(thumb and 2 or 3), image }
    end
    return thumb and self:drawnThumb(book, w, h) or self:drawnCover(book, w, h)
end

function LibraryView:freeCovers()
    for __, image in ipairs(self.covers) do image:free() end
    self.covers = {}
end

-- Extraction runs in a subprocess; repaint once it is done.
function LibraryView:extractCovers()
    if #self.to_extract == 0 then return end
    local files = self.to_extract
    UIManager:nextTick(function() BookInfoManager:extractInBackground(files) end)
    if self.extract_poll then UIManager:unschedule(self.extract_poll) end
    self.extract_poll = function()
        if BookInfoManager:isExtractingInBackground() then
            UIManager:scheduleIn(1, self.extract_poll)
        else
            self.extract_poll = nil
            self:showPage()
        end
    end
    UIManager:scheduleIn(1, self.extract_poll)
end

-- Rows ----------------------------------------------------------------------

function LibraryView:open(book)
    filemanagerutil.openFile(self.ui, book.file, nil, true)
end

function LibraryView:gridRow(row)
    local group = HorizontalGroup:new{ align = "top" }
    for i, book in ipairs(row.books) do
        if i > 1 then table.insert(group, HorizontalSpan:new{ width = D(GRID_COL_GAP) }) end
        local w = self.cover_w
        table.insert(group, UI.tappable(VerticalGroup:new{
            align = "left",
            UI.pinned(self:coverWidget(book, w, D(COVER_H)), D(COVER_H), w),
            VerticalSpan:new{ width = D(TILE_GAP) },
            UI.pinned(UI.text(book.title, UI.sans(15, 700), nil, w), D(19), w),
            UI.pinned(UI.text(book.progress, UI.sans(14)), D(17), w),
        }, function() self:open(book) end))
    end
    return group
end

function LibraryView:listRow(row)
    local book = row.books[1]
    local w, h = D(702 - 2 * SIDE), D(LIST_ROW_H)
    local progress = UI.text(book.progress, UI.sans(15, 600))
    local text_w = w - D(40) - D(16) - progress:getSize().w - D(16)
    local dimen = Geom:new{ w = w, h = h - D(1) }
    return UI.tappable(VerticalGroup:new{
        OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{
                dimen = dimen,
                HorizontalGroup:new{
                    align = "center",
                    self:coverWidget(book, D(40), D(54), true),
                    HorizontalSpan:new{ width = D(16) },
                    VerticalGroup:new{
                        align = "left",
                        UI.pinned(UI.text(book.title, UI.sans(18, 700), nil, text_w), D(23)),
                        UI.pinned(UI.text(book.author, UI.sans(15), nil, text_w), D(19)),
                    },
                },
            },
            RightContainer:new{ dimen = dimen, progress },
        },
        LineWidget:new{ dimen = Geom:new{ w = w, h = D(1) }, background = UI.BLACK },
    }, function() self:open(book) end)
end

function LibraryView:heading(row)
    local w = D(702 - 2 * SIDE)
    if row.kind == "author" then
        local label = row.name:upper()
        if row.continued then label = label .. "  ·  " .. _("continued") end
        local text = UI.text(label, UI.sans(13, 700), nil, w)
        local rule = D(1)
        return VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = D(AUTHOR_H) - text:getSize().h - D(4) - rule },
            text,
            VerticalSpan:new{ width = D(4) },
            LineWidget:new{ dimen = Geom:new{ w = w, h = rule }, background = UI.BLACK },
        }
    end
    return LeftContainer:new{
        dimen = Geom:new{ w = w, h = D(SERIES_H) },
        UI.text(row.name, UI.face("SourceSerif4-It.ttf", 16), nil, w),
    }
end

-- Page ----------------------------------------------------------------------

function LibraryView:buildHeader()
    local sort = UI.choices(SORTS, self.sort, D(216), UI.H(44), function(opt)
        self.sort = opt.id
        G_reader_settings:saveSetting("quietui_sort", opt.id)
        self:rebuild()
    end)
    local view = UI.choices({
        { id = "grid", content = function(fg) return UI.iconGrid(fg) end },
        { id = "list", content = function(fg) return UI.iconList(fg) end },
    }, self.view, D(96), UI.H(44), function(opt)
        self.view = opt.id
        G_reader_settings:saveSetting("quietui_view", opt.id)
        self:rebuild()
    end)
    local cog = UI.group({ {
        {
            content = function()
                return IconWidget:new{ icon = "appbar.settings", width = D(26), height = D(26) }
            end,
            callback = function()
                UIManager:show(require("quietui_settings"):new{ settings = self.settings }, "ui")
            end,
        },
    } }, D(48), UI.H(44))
    local back = UI.group({ {
        {
            content = function()
                return HorizontalGroup:new{
                    align = "center",
                    IconWidget:new{ icon = "chevron.left", width = D(20), height = D(20) },
                    HorizontalSpan:new{ width = D(2) },
                    UI.text(_("Back to Kobo"), UI.sans(16, 700)),
                }
            end,
            callback = function() self.run_action("exit") end,
        },
    } }, D(140), UI.H(40))
    local dimen = Geom:new{ w = self.dimen.w - D(16) - D(24), h = D(HEADER_H) - D(2) }
    return VerticalGroup:new{
        HorizontalGroup:new{
            HorizontalSpan:new{ width = D(16) },
            OverlapGroup:new{
                dimen = dimen,
                LeftContainer:new{
                    dimen = dimen,
                    HorizontalGroup:new{
                        align = "center",
                        back,
                        HorizontalSpan:new{ width = D(14) },
                        UI.text(_("Library"), UI.serif(28, 700)),
                    },
                },
                RightContainer:new{
                    dimen = dimen,
                    HorizontalGroup:new{
                        align = "center",
                        sort,
                        HorizontalSpan:new{ width = D(8) },
                        view,
                        HorizontalSpan:new{ width = D(8) },
                        cog,
                    },
                },
            },
        },
        LineWidget:new{ dimen = Geom:new{ w = self.dimen.w, h = D(2) }, background = UI.BLACK },
    }
end

function LibraryView:buildPage()
    self:freeCovers()
    self.to_extract = {}
    self.has_images = false
    local grid = self.view == "grid"
    local body = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = D(grid and GRID_PAD or LIST_PAD) } }
    for i, row in ipairs(self.pages[self.page]) do
        if row.kind == "grid" then
            table.insert(body, self:gridRow(row))
            local next_row = self.pages[self.page][i + 1]
            if next_row then table.insert(body, VerticalSpan:new{ width = D(GRID_ROW_GAP) }) end
        elseif row.kind == "list" then
            table.insert(body, self:listRow(row))
        else
            table.insert(body, self:heading(row))
        end
    end
    if #self.books == 0 then
        table.insert(body, VerticalSpan:new{ width = D(40) })
        table.insert(body, UI.text(_("No books in the home folder."), UI.sans(18)))
    end
    local footer_dimen = Geom:new{ w = self.dimen.w, h = D(FOOTER_H) }
    local footer = CenterContainer:new{
        dimen = footer_dimen,
        UI.text(T("%1 / %2", self.page, #self.pages), UI.sans(15)),
    }
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = self.dimen:copy(),
            VerticalGroup:new{
                align = "left",
                self:buildHeader(),
                HorizontalGroup:new{ HorizontalSpan:new{ width = D(SIDE) }, body },
            },
            VerticalGroup:new{
                VerticalSpan:new{ width = self.dimen.h - D(FOOTER_H) },
                footer,
            },
        },
    }
    self:extractCovers()
end

function LibraryView:showPage()
    self:buildPage()
    local dithered = self.has_images
    UIManager:setDirty(self.ui, function() return "ui", self.dimen, dithered end)
end

function LibraryView:rebuild()
    self:paginate()
    self.page = 1
    self:showPage()
end

function LibraryView:goToPage(page)
    page = math.max(1, math.min(page, #self.pages))
    if page == self.page then return end
    self.page = page
    self:showPage()
end

-- Gestures ------------------------------------------------------------------

function LibraryView:onSwipe(__, ges)
    if ges.direction == "west" then
        self:goToPage(self.page + 1)
    elseif ges.direction == "east" then
        self:goToPage(self.page - 1)
    end
    return true
end

-- Finger drags fall through to the edge-light zones on the file manager.
function LibraryView:onPan(__, ges)
    if ges.mousewheel_direction then
        self:goToPage(self.page + (ges.direction == "north" and 1 or -1))
        return true
    end
end

function LibraryView:onHoldCorner()
    local action = self.settings.gestures.hold_top_left
    if action and action ~= "none" then self.run_action(action) end
    return true
end

function LibraryView:onCloseWidget()
    if self.extract_poll then
        UIManager:unschedule(self.extract_poll)
        self.extract_poll = nil
    end
    self:freeCovers()
end

return LibraryView

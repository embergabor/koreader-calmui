--[[--
Long-press a book in the library: a small card with its details, Mark finished and Delete.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Dialog = require("quietui_dialog")
local DocSettings = require("docsettings")
local BookList = require("ui/widget/booklist")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local D = UI.D

local COVER_W, COVER_H = 130, 178

local BookCard = InputContainer:extend{
    book = nil,
    library = nil,
    modal = true,
}

function BookCard:details()
    local book = self.book
    local lines = {}
    if book.series then
        local series = book.series
        if book.series_index then series = T(_("%1, book %2"), series, book.series_index) end
        table.insert(lines, series)
    end
    local format = book.file:match("%.([^.]+)$")
    local size = lfs.attributes(book.file, "size")
    table.insert(lines, (format and format:upper() or "") .. (size and "  ·  " .. util.getFriendlySize(size) or ""))
    if BookList.hasBookBeenOpened(book.file) then
        local pages = DocSettings:open(book.file):readSetting("doc_pages")
        if pages then table.insert(lines, T(_("%1 pages"), pages)) end
    end
    table.insert(lines, book.progress)
    if book.last_read then
        table.insert(lines, T(_("Last read %1"), os.date("%Y-%m-%d", book.last_read)))
    end
    return table.concat(lines, "\n")
end

function BookCard:init()
    self.dimen = Screen:getSize()
    self.ges_events = {
        TapClose = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h } } },
    }
    local book = self.book
    local card_w = math.min(D(620), self.dimen.w - 2 * D(24))
    local inner_w = card_w - 2 * D(UI.style.border) - 2 * D(28)
    local text_w = inner_w - D(COVER_W) - D(20)
    local finished = book.status == "complete"
    local text = VerticalGroup:new{
        align = "left",
        TextBoxWidget:new{
            text = book.title,
            face = UI.serif(22, 700),
            width = text_w,
            height = D(84),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
        VerticalSpan:new{ width = D(4) },
        UI.pinned(UI.text(book.author, UI.sans(16), nil, text_w), D(22)),
        VerticalSpan:new{ width = D(10) },
        TextBoxWidget:new{ text = self:details(), face = UI.sans(15), width = text_w },
    }
    self.frame = FrameContainer:new{
        padding = D(28),
        bordersize = D(UI.style.border),
        radius = D(12),
        background = UI.WHITE,
        VerticalGroup:new{
            align = "left",
            HorizontalGroup:new{
                align = "top",
                self.library:coverWidget(book, D(COVER_W), D(COVER_H)),
                HorizontalSpan:new{ width = D(20) },
                text,
            },
            VerticalSpan:new{ width = D(22) },
            UI.group({ {
                {
                    text = finished and _("Mark as reading") or _("Mark finished"),
                    callback = function() self:setStatus(finished and "reading" or "complete") end,
                },
                { text = _("Delete"), callback = function() self:confirmDelete() end },
            } }, inner_w, UI.H(44)),
        },
    }
    self.dithered = self.library.has_images
    self[1] = CenterContainer:new{ dimen = self.dimen, self.frame }
end

function BookCard:setStatus(status)
    local file = self.book.file
    local doc_settings = DocSettings:open(file)
    local summary = doc_settings:readSetting("summary") or {}
    summary.status = status
    filemanagerutil.saveSummary(doc_settings, summary)
    BookList.resetBookInfoCache(file)
    self:closeAndReload()
end

function BookCard:confirmDelete()
    UIManager:close(self)
    local book, library = self.book, self.library
    UIManager:show(Dialog:new{
        title = _("Delete this book?"),
        text = T(_("“%1” will be removed from your Kobo. This can’t be undone."), book.title),
        buttons = {
            { text = _("Cancel") },
            {
                text = _("Delete"),
                selected = true,
                callback = function()
                    if library.ui:deleteFile(book.file, true) then
                        local ok, BookInfoManager = pcall(require, "bookinfomanager")
                        if ok then BookInfoManager:deleteBookInfo(book.file) end
                        library:reload()
                    end
                end,
            },
        },
    })
end

function BookCard:closeAndReload()
    UIManager:close(self)
    self.library:reload()
end

function BookCard:onTapClose(__, ges)
    if ges.pos:notIntersectWith(self.frame.dimen) then
        UIManager:close(self)
    end
    return true
end

function BookCard:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen, self.dithered end)
end

function BookCard:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen, self.dithered end)
    return true
end

return BookCard

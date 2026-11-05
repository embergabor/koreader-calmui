--[[--
Contents: one flat list of chapters, indented by level. Nothing collapses and there
are no options. It replaces KOReader's table of contents screen. Tap a chapter to go
there, swipe to change page, Done to go back to the book.
]]

local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local D = UI.D

-- Board pixels, matching the library.
local HEADER_H, FOOTER_H, SIDE, PAD, ROW_H, INDENT = 76, 56, 32, 8, 56, 24
local PER_PAGE = math.floor((936 - HEADER_H - FOOTER_H - PAD) / ROW_H)

local Contents = InputContainer:extend{
    ui = nil,
    covers_fullscreen = true,
    page = 1,
}

function Contents:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
    end
    self.ges_events = {
        Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        Pan = { GestureRange:new{ ges = "pan", range = self.dimen } }, -- mousewheel
    }

    local toc = self.ui.toc
    toc:fillToc()
    self.entries = toc.toc or {}
    self.min_depth = math.huge
    for __, entry in ipairs(self.entries) do
        self.min_depth = math.min(self.min_depth, entry.depth or 1)
    end
    self.current = toc:getTocIndexByPage(self.ui:getCurrentPage())
    self.page_count = math.max(1, math.ceil(#self.entries / PER_PAGE))
    self.page = self.current and math.ceil(self.current / PER_PAGE) or 1
    self:buildPage()
end

function Contents:buildHeader()
    local done = UI.group({ { { text = _("Done"), callback = function() self:onClose() end } } }, D(96), D(44))
    local dimen = Geom:new{ w = self.dimen.w - D(SIDE) - D(24), h = D(HEADER_H) - D(2) }
    return VerticalGroup:new{
        HorizontalGroup:new{
            HorizontalSpan:new{ width = D(SIDE) },
            OverlapGroup:new{
                dimen = dimen,
                LeftContainer:new{ dimen = dimen, UI.text(_("Contents"), UI.serif(28, 700)) },
                RightContainer:new{ dimen = dimen, done },
            },
        },
        LineWidget:new{ dimen = Geom:new{ w = self.dimen.w, h = D(2) }, background = UI.BLACK },
    }
end

function Contents:buildRow(index, entry)
    local w = self.dimen.w - 2 * D(SIDE)
    local dimen = Geom:new{ w = w, h = D(ROW_H) - D(1) }
    local is_current = index == self.current
    local indent = D(INDENT) * ((entry.depth or 1) - self.min_depth)
    local page = UI.text(tostring(entry.page or ""), UI.sans(15, 600))
    local title = self.ui.toc:cleanUpTocTitle(entry.title or "", true)
    return UI.tappable(VerticalGroup:new{
        OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{
                dimen = dimen,
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = indent },
                    UI.text(title, UI.sans(18, is_current and 700 or 400), nil, w - indent - page:getSize().w - D(16)),
                },
            },
            RightContainer:new{ dimen = dimen, page },
        },
        LineWidget:new{ dimen = Geom:new{ w = w, h = D(1) }, background = UI.BLACK },
    }, function() self:goTo(entry) end)
end

function Contents:buildPage()
    local body = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = D(PAD) } }
    local first = (self.page - 1) * PER_PAGE + 1
    for i = first, math.min(first + PER_PAGE - 1, #self.entries) do
        table.insert(body, self:buildRow(i, self.entries[i]))
    end
    if #self.entries == 0 then
        table.insert(body, VerticalSpan:new{ width = D(40) })
        table.insert(body, UI.text(_("This book has no chapters listed."), UI.sans(18)))
    end
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        bordersize = 0,
        background = UI.WHITE,
        OverlapGroup:new{
            dimen = self.dimen:copy(),
            VerticalGroup:new{
                align = "left",
                self:buildHeader(),
                HorizontalGroup:new{ HorizontalSpan:new{ width = D(SIDE) }, body },
            },
            VerticalGroup:new{
                VerticalSpan:new{ width = self.dimen.h - D(FOOTER_H) },
                CenterContainer:new{
                    dimen = Geom:new{ w = self.dimen.w, h = D(FOOTER_H) },
                    UI.text(T("%1 / %2", self.page, self.page_count), UI.sans(15)),
                },
            },
        },
    }
end

function Contents:goToPage(page)
    page = math.max(1, math.min(page, self.page_count))
    if page == self.page then return end
    self.page = page
    self:buildPage()
    UIManager:setDirty(self, "ui")
end

function Contents:goTo(entry)
    self:onClose()
    self.ui.link:addCurrentLocationToStack()
    if entry.xpointer then
        self.ui:handleEvent(Event:new("GotoXPointer", entry.xpointer, entry.xpointer))
    else
        self.ui:handleEvent(Event:new("GotoPage", entry.page))
    end
end

function Contents:onSwipe(__, ges)
    if ges.direction == "west" then
        self:goToPage(self.page + 1)
    elseif ges.direction == "east" then
        self:goToPage(self.page - 1)
    end
    return true
end

function Contents:onPan(__, ges)
    if ges.mousewheel_direction then
        self:goToPage(self.page + (ges.direction == "north" and 1 or -1))
    end
    return true
end

function Contents:onClose()
    UIManager:close(self, "ui")
    return true
end

return Contents

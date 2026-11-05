--[[--
Reading statistics, from the cogwheel: time and pages today, this week, this month and overall,
and the last seven days as bars. Reads the database KOReader's statistics plugin keeps.
]]

local DataStorage = require("datastorage")
local Device = require("device")
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
local SQ3 = require("lua-ljsqlite3/init")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local D = UI.D

local Stats = InputContainer:extend{
    modal = true,
    on_close = nil,
}

local DB = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

-- A page read twice counts once, as in the plugin's own screens.
local PERIOD_SQL = [[
    SELECT count(*), sum(seconds), count(DISTINCT id_book)
    FROM (SELECT id_book, page, sum(duration) AS seconds FROM page_stat
          WHERE start_time >= %d GROUP BY id_book, page);
]]

local function dayStart(offset)
    local t = os.date("*t")
    t.hour, t.min, t.sec = 0, 0, 0
    t.day = t.day + (offset or 0)
    return os.time(t)
end

local function weekStart()
    local weekday = (os.date("*t").wday + 5) % 7 -- days since Monday
    return dayStart(-weekday)
end

local function monthStart()
    local t = os.date("*t")
    t.day, t.hour, t.min, t.sec = 1, 0, 0, 0
    return os.time(t)
end

local function period(conn, since)
    local pages, seconds, books = conn:rowexec(string.format(PERIOD_SQL, since))
    return tonumber(pages) or 0, tonumber(seconds) or 0, tonumber(books) or 0
end

function Stats.duration(seconds)
    local minutes = math.floor(seconds / 60 + 0.5)
    if minutes < 60 then return T(_("%1 min"), minutes) end
    return T(_("%1 h %2 min"), math.floor(minutes / 60), minutes % 60)
end

--- { { label, pages, seconds, books }, ... } and the last seven days as { { letter, seconds }, ... }.
-- Empty if nothing has been recorded yet.
function Stats.read()
    if lfs.attributes(DB, "mode") ~= "file" then return {}, {} end
    local conn = SQ3.open(DB)
    local ok, periods, days = pcall(function()
        local list = {}
        for __, row in ipairs{
            { _("Today"), dayStart() },
            { _("This week"), weekStart() },
            { _("This month"), monthStart() },
            { _("All time"), 0 },
        } do
            local pages, seconds, books = period(conn, row[2])
            table.insert(list, { label = row[1], pages = pages, seconds = seconds, books = books })
        end
        local bars = {}
        for offset = -6, 0 do
            local from, to = dayStart(offset), dayStart(offset + 1)
            local seconds = conn:rowexec(string.format(
                "SELECT sum(duration) FROM page_stat WHERE start_time >= %d AND start_time < %d;", from, to))
            table.insert(bars, { letter = os.date("%a", from):sub(1, 1), seconds = tonumber(seconds) or 0 })
        end
        return list, bars
    end)
    conn:close()
    if not ok then return {}, {} end
    return periods, days
end

function Stats:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.content_w = self.dimen.w - 2 * D(32)
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    self:update()
end

function Stats:row(entry)
    local dimen = Geom:new{ w = self.content_w, h = D(40) }
    local detail = T(_("%1  ·  %2 pages"), Stats.duration(entry.seconds), entry.pages)
    return VerticalGroup:new{
        align = "left",
        OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{ dimen = dimen, UI.text(entry.label, UI.sans(18, 700)) },
            RightContainer:new{ dimen = dimen, UI.text(detail, UI.sans(17)) },
        },
        LineWidget:new{ dimen = Geom:new{ w = self.content_w, h = D(UI.style.rule) }, background = UI.BLACK },
    }
end

function Stats:bars(days)
    local chart_h, label_h, gap = D(110), D(24), D(16)
    local bar_w = math.floor((self.content_w - 6 * gap) / 7)
    local longest = 1
    for __, day in ipairs(days) do longest = math.max(longest, day.seconds) end
    local group = HorizontalGroup:new{ align = "bottom" }
    for i, day in ipairs(days) do
        if i > 1 then table.insert(group, HorizontalSpan:new{ width = gap }) end
        local h = day.seconds > 0 and math.max(D(2), math.floor(chart_h * day.seconds / longest)) or D(UI.style.rule)
        table.insert(group, VerticalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = bar_w },
            LineWidget:new{ dimen = Geom:new{ w = D(36), h = h }, background = UI.BLACK },
            UI.pinned(UI.text(day.letter, UI.sans(14, 700)), label_h),
        })
    end
    return group
end

function Stats:update()
    local periods, days = Stats.read()
    local done = UI.button({ text = _("Back"), callback = function() self:onClose() end })
    local bar = Geom:new{ w = self.content_w, h = D(48) }
    local body = VerticalGroup:new{ align = "left" }
    if #periods == 0 or periods[4].seconds == 0 then
        table.insert(body, UI.text(_("Nothing recorded yet. Open a book to start."), UI.sans(18)))
    else
        for __, entry in ipairs(periods) do table.insert(body, self:row(entry)) end
        table.insert(body, VerticalSpan:new{ width = D(24) })
        table.insert(body, UI.label(_("Last 7 days")))
        table.insert(body, VerticalSpan:new{ width = D(10) })
        table.insert(body, self:bars(days))
    end
    self.panel = FrameContainer:new{
        width = self.dimen.w,
        padding = 0,
        bordersize = 0,
        background = UI.WHITE,
        VerticalGroup:new{
            align = "left",
            LineWidget:new{ dimen = Geom:new{ w = self.dimen.w, h = D(2) }, background = UI.BLACK },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = D(32) },
                VerticalGroup:new{
                    align = "left",
                    VerticalSpan:new{ width = D(18) },
                    OverlapGroup:new{
                        dimen = bar,
                        LeftContainer:new{ dimen = bar, UI.text(_("Reading statistics"), UI.serif(24, 700)) },
                        RightContainer:new{ dimen = bar, done },
                    },
                    VerticalSpan:new{ width = D(14) },
                    body,
                    VerticalSpan:new{ width = D(24) },
                },
            },
        },
    }
    self[1] = VerticalGroup:new{
        VerticalSpan:new{ width = self.dimen.h - self.panel:getSize().h },
        self.panel,
    }
end

function Stats:onTapOutside(__, ges)
    if ges.pos.y >= self.dimen.h - self.panel:getSize().h then return true end
    return self:onClose()
end

function Stats:onClose()
    UIManager:close(self, "ui")
    if self.on_close then self.on_close() end
    return true
end

return Stats

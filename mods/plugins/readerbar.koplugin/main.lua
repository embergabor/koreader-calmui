--[[--
Reader bar: replaces KOReader's top menu and bottom config panel with
one overlay (top bar + bottom bar with Text & page / Light sheets).
The original menus stay reachable from "More" and "All settings".

@module koplugin.ReaderBar
--]]--

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ReaderBar = WidgetContainer:extend{
    name = "readerbar",
    is_doc_only = true,
}

function ReaderBar:init()
    self.ui.menu:registerToMainMenu(self)
    -- Only reflowable books (EPUB & co.) for now; PDFs keep the stock menus.
    if not self.ui.rolling or G_reader_settings:isFalse("readerbar_enabled") then return end

    local show = function() return self:showOverlay() end
    -- Tapping or swiping the top/bottom edge, or tapping the middle, all open the overlay.
    self.ui.menu.onTapShowMenu = show
    self.ui.menu.onSwipeShowMenu = function(_, ges)
        if ges.direction == "south" then return show() end
    end
    self.ui.config.onTapShowConfigMenu = show
    self.ui.config.onSwipeShowConfigMenu = function(_, ges)
        if ges.direction == "north" then return show() end
    end
    self.ui:registerTouchZones({
        {
            id = "readerbar_center_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0.3, ratio_y = 0.3, ratio_w = 0.4, ratio_h = 0.4 },
            overrides = { "tap_forward", "tap_backward" },
            handler = show,
        },
    })
end

function ReaderBar:showOverlay()
    local Overlay = require("readerbar_overlay")
    UIManager:show(Overlay:new{ ui = self.ui }, "ui")
    return true
end

function ReaderBar:addToMainMenu(menu_items)
    menu_items.readerbar = {
        text = _("Simple reader bar"),
        sorting_hint = "more_tools",
        checked_func = function() return G_reader_settings:nilOrTrue("readerbar_enabled") end,
        callback = function()
            G_reader_settings:flipNilOrTrue("readerbar_enabled")
            UIManager:show(require("ui/widget/infomessage"):new{
                text = _("This takes effect the next time you open a book."),
            })
        end,
    }
end

return ReaderBar

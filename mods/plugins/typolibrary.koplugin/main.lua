--[[--
Library list: a typographic home screen for the file manager.

@module koplugin.TypoLibrary
--]]--

local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local TypoLibrary = WidgetContainer:extend{
    name = "typolibrary",
    is_doc_only = false,
}

function TypoLibrary:onDispatcherRegisterActions()
    Dispatcher:registerAction("typolibrary_show", {
        category = "none", event = "ShowTypoLibrary", title = _("Library list"), general = true,
    })
end

function TypoLibrary:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    -- A new file manager is created at startup and whenever a book is closed,
    -- so showing the list here makes it the home screen.
    if not self.ui.document and G_reader_settings:nilOrTrue("typolibrary_as_home") then
        UIManager:nextTick(function() self:onShowTypoLibrary() end)
    end
end

function TypoLibrary:addToMainMenu(menu_items)
    menu_items.typolibrary = {
        text = _("Library list"),
        -- filemanager_settings only exists in the file manager's menu
        sorting_hint = self.ui.document and "more_tools" or "filemanager_settings",
        sub_item_table = {
            {
                text = _("Show library list"),
                callback = function() self:onShowTypoLibrary() end,
            },
            {
                text = _("Use as home screen"),
                checked_func = function() return G_reader_settings:nilOrTrue("typolibrary_as_home") end,
                callback = function() G_reader_settings:flipNilOrTrue("typolibrary_as_home") end,
            },
        },
    }
end

function TypoLibrary:onShowTypoLibrary()
    local LibraryView = require("libraryview")
    UIManager:show(LibraryView:new{ ui = self.ui }, "flashui")
    return true
end

return TypoLibrary

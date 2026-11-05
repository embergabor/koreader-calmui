--[[--
Quiet UI: KOReader reduced to two screens.

Library: replaces the file manager's content (see setupLayout below).
Reader: one tap opens the Aa sheet, swipes turn pages, nothing else on screen.
Stock menus are only reachable with a long-press in the top-left corner.
PDFs and other fixed-layout documents keep the stock reader controls.

@module koplugin.QuietUI
--]]--

local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."

local function loadSettings()
    local ok, settings = pcall(dofile, plugin_dir .. "/settings.lua")
    if not ok or type(settings) ~= "table" then
        logger.warn("QuietUI: could not read settings.lua:", settings)
        return { devices = { default = { render = "smooth" } }, gestures = {}, fonts = {}, keep_plugins = {} }
    end
    return settings
end

local settings = loadSettings()

local QuietUI = WidgetContainer:extend{
    name = "quietui",
    is_doc_only = false,
}

local defaults_applied = false

-- Stock behaviour we rely on. Reapplied at every start, so this file stays the source of truth.
local function applyDefaults()
    if defaults_applied then return end
    defaults_applied = true
    local G = G_reader_settings
    local Presets = require("quietui_presets")

    G:saveSetting("start_with", "filemanager")
    G:makeTrue("page_turns_disable_tap")
    G:saveSetting("default_highlight_action", "dictionary")
    G:saveSetting("notification_sources_to_show_mask", 0)
    G:saveSetting("hyphenation", settings.hyphenation == true)
    if not G:has("copt_embedded_fonts") then
        G:saveSetting("copt_embedded_fonts", 0)
    end
    Presets.seedDevice(settings)

    -- Portrait only
    G:makeTrue("input_ignore_gsensor")
    if Device:hasGSensor() then Device:toggleGSensor(false) end

    -- Unused stock plugins are never loaded (takes effect from the next start).
    local disabled = {}
    local keep = settings.keep_plugins or {}
    local ok, iter, dir_obj = pcall(lfs.dir, "plugins")
    if ok then
        for entry in iter, dir_obj do
            local name = entry:match("^(.+)%.koplugin$")
            if name and name ~= "quietui" and not keep[name] then
                disabled[name] = true
            end
        end
    end
    G:saveSetting("plugins_disabled", disabled)

    -- Reading position sync is silent: forward without asking, never backward.
    -- Logging in is done once from the stock menu.
    if keep.kosync then
        local LuaSettings = require("luasettings")
        local DataStorage = require("datastorage")
        local kosync = LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua")
        local sync = kosync:readSetting("settings") or {}
        if sync.userkey then
            sync.auto_sync = true
            sync.sync_forward = 2 -- SYNC_STRATEGY.SILENT
            sync.sync_backward = 3 -- SYNC_STRATEGY.DISABLE
            kosync:saveSetting("settings", sync)
            kosync:flush()
            G:saveSetting("wifi_enable_action", "turn_on")
            G:saveSetting("wifi_disable_action", "turn_off")
        end
    end

    G:saveSetting("reader_footer_mode", 1)
end

function QuietUI:init()
    applyDefaults()
    if self.ui.document then
        self:initReader()
    else
        self:initLibrary()
    end
end

function QuietUI:runAction(action)
    if action == "menu" then
        UIManager:nextTick(function() self.ui.menu:onShowMenu() end)
    elseif action == "exit" then
        UIManager:nextTick(function()
            self.ui:onClose()
            UIManager:quit()
        end)
    end
end

-- Library -------------------------------------------------------------------

function QuietUI:initLibrary()
    local fm = self.ui
    local noop = function() end
    fm.menu.onTapShowMenu = noop
    fm.menu.onSwipeShowMenu = noop

    -- The file manager builds its layout after loading plugins. Keep its file chooser,
    -- which the rest of KOReader talks to, but never put it on screen.
    local setupLayout = fm.setupLayout
    fm.setupLayout = function(this)
        setupLayout(this)
        local LibraryView = require("quietui_libraryview")
        this[1] = LibraryView:new{
            ui = this,
            settings = settings,
            run_action = function(action) self:runAction(action) end,
        }
    end
end

-- Reader --------------------------------------------------------------------

function QuietUI:initReader()
    self.is_active = self.ui.rolling ~= nil
    if not self.is_active then return end

    local noop = function() end
    self.ui.menu.onTapShowMenu = noop
    self.ui.menu.onSwipeShowMenu = noop
    self.ui.config.onTapShowConfigMenu = noop
    self.ui.config.onSwipeShowConfigMenu = noop

    -- Read by ReaderTypography right after plugins are loaded.
    self.ui.doc_settings:saveSetting("hyphenation", settings.hyphenation == true)

    -- Footer: only "1 / 412", centred.
    local footer = self.ui.view.footer
    footer.settings.all_at_once = false
    footer.settings.page_progress = true
    footer.settings.disable_progress_bar = true
    footer.settings.align = "center"
    footer:updateFooterTextGenerator()
    footer:applyFooterMode(1)
    footer:updateFooterContainer()
    footer:resetLayout(true)

    self:registerZones()
end

function QuietUI:registerZones()
    self.ui:registerTouchZones({
        {
            id = "quietui_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            overrides = {
                "tap_link",
                "readerhighlight_tap",
                "tap_top_left_corner",
                "tap_top_right_corner",
                "tap_left_bottom_corner",
                "tap_right_bottom_corner",
                "readerfooter_tap",
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
                "readermenu_ext_tap",
                "readermenu_tap",
                "tap_forward",
                "tap_backward",
            },
            handler = function(ges) return self:onReaderTap(ges) end,
        },
        {
            id = "quietui_hold_corner",
            ges = "hold",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 0.15, ratio_h = 0.1 },
            overrides = { "readerhighlight_hold", "readerfooter_hold" },
            handler = function()
                self:runAction(settings.gestures.hold_top_left)
                return true
            end,
        },
    })
end

function QuietUI:onReaderTap(ges)
    -- Links and footnotes come first; an empty tap_link result means there was none here.
    if self.ui.link:onTap(nil, ges) then return true end
    if settings.gestures.tap == "sheet" then
        local Sheet = require("quietui_sheet")
        UIManager:show(Sheet:new{ ui = self.ui, settings = settings }, "ui")
    end
    return true
end

-- Other modules register their zones again on these events, which drops our overrides.
function QuietUI:onReaderReady()
    if self.is_active then self:registerZones() end
end

function QuietUI:onSetDimensions()
    if self.is_active then self:registerZones() end
end

-- After the document is loaded and before it is rendered.
function QuietUI:onPreRenderDocument()
    if not self.is_active then return end
    local Presets = require("quietui_presets")
    Presets.applyAntialias(self.ui, Presets.currentRender(self.ui))
end

return QuietUI

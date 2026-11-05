--[[--
Quiet UI: KOReader reduced to two screens.

Library: replaces the file manager's content (see setupLayout below).
Reader: one tap opens the Aa sheet, swipes turn pages, nothing else on screen.
Stock menus are only reachable with a long-press in the top-left corner.
PDFs and other fixed-layout documents keep the stock reader controls.

@module koplugin.QuietUI
--]]--

local Device = require("device")
local Event = require("ui/event")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

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

-- The dictionary popup keeps only its definition and a Close button (see dict_button_config).
-- Its title and word rows build these icons directly, so they are taken out once built.
local DICT_ICONS_REMOVED = { ["appbar.menu"] = true, edit = true, close = true }

local function removeIcons(node)
    for i = #node, 1, -1 do
        local child = node[i]
        if type(child) == "table" then
            if DICT_ICONS_REMOVED[child.icon] then
                table.remove(node, i)
            else
                removeIcons(child)
            end
        end
    end
end

local DictQuickLookup = require("ui/widget/dictquicklookup")
local dict_init = DictQuickLookup.init
function DictQuickLookup:init()
    dict_init(self)
    removeIcons(self)
end

-- Same as stock, except for the card shown while the book loads. A seamless reload after a settings
-- change stays stock: its invisible message keeps a widget on screen, or KOReader would quit.
local stockShowReaderCoroutine = ReaderUI.showReaderCoroutine
function ReaderUI:showReaderCoroutine(file, provider, seamless)
    if seamless then
        return stockShowReaderCoroutine(self, file, provider, seamless)
    end
    UIManager:show(require("quietui_opening"):new{ file = file })
    -- doShowReader might block for a long time, so force repaint here
    UIManager:forceRePaint()
    UIManager:nextTick(function()
        local co = coroutine.create(function()
            self:doShowReader(file, provider, seamless)
        end)
        local ok, err = coroutine.resume(co)
        if err ~= nil or ok == false then
            io.stderr:write("[!] doShowReader coroutine crashed:\n")
            io.stderr:write(debug.traceback(co, err, 1))
            -- Restore input if we crashed before ReaderUI has restored it
            Device:setIgnoreInput(false)
            Device.input:inhibitInputUntil(0.2)
            UIManager:show(require("ui/widget/infomessage"):new{
                text = _("No reader engine for this file or invalid file."),
            })
            self:showFileManager(file)
        end
    end)
end

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
    G:saveSetting("dict_button_config", { layout = { { "close" } }, order = { "close" }, row_count = { 1 } })
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

    if keep.kosync then
        require("quietui_sync").reapply()
    end

    G:saveSetting("reader_footer_mode", 1)
    -- Footer band as in the design: 56 board pixels, in KOReader's units (shortSide / 600),
    -- with the page number centred in it. ReaderFooter reads these when a book opens.
    local footer = G:readSetting("footer", require("apps/reader/modules/readerfooter").default_settings)
    footer.container_height = math.floor(56 * 600 / 702 + 0.5)
    footer.container_bottom_padding = 0
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
        -- Same as the stock Exit menu entry; on Kobo this returns to the home screen.
        UIManager:broadcastEvent(Event:new("Exit"))
    end
end

function QuietUI:edgeActions()
    local gestures = settings.gestures
    return { left = gestures.edge_left, right = gestures.edge_right }
end

-- Library -------------------------------------------------------------------

function QuietUI:initLibrary()
    local fm = self.ui
    local noop = function() end
    fm.menu.onTapShowMenu = noop
    fm.menu.onSwipeShowMenu = noop
    require("quietui_light").registerEdgeZones(fm, self:edgeActions())

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
    require("quietui_light").registerEdgeZones(self.ui, self:edgeActions(), { "rolling_pan" })
    local action = settings.gestures.hold_top_left
    if action and action ~= "none" then
        self.ui:registerTouchZones({
            {
                id = "quietui_hold_corner",
                ges = "hold",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 0.15, ratio_h = 0.1 },
                overrides = { "readerhighlight_hold", "readerfooter_hold" },
                handler = function()
                    self:runAction(action)
                    return true
                end,
            },
        })
    end
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

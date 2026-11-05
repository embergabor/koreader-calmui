--[[--
Quiet UI: KOReader reduced to two screens.

Library: replaces the file manager's content (see setupLayout below).
Reader: one tap opens the sheet, swipes turn pages, nothing else on screen.
Books and fixed-layout documents such as PDFs share the sheet, each with its own options.
Stock popups keep their logic and take this UI's look (see quietui_popups.lua).

@module koplugin.QuietUI
--]]--

local Device = require("device")
local Event = require("ui/event")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
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
require("quietui_ui").setScale(settings.ui_scale)
require("quietui_ui").setStyle(settings.button_style)
require("quietui_popups").apply()

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

-- The USB question, in our style. The rest is stock.
local MassStorage = require("ui/elements/mass_storage")
local massStorageStart = MassStorage.start
function MassStorage:start(with_confirmation)
    local ask = with_confirmation
    if ask == nil then ask = self:requireConfirmation() end
    if not (ask and Device:canToggleMassStorage() and self:isEnabled()) then
        return massStorageStart(self, with_confirmation)
    end
    self.usbms_widget = require("quietui_dialog"):new{
        title = _("Connect to computer?"),
        text = _("You can't read while your Kobo is connected."),
        buttons = {
            { text = _("Not now"), callback = function() self.usbms_widget = nil end },
            {
                text = _("Connect"),
                selected = true,
                callback = function()
                    self.usbms_widget = nil
                    massStorageStart(self, false)
                end,
            },
        },
    }
    UIManager:show(self.usbms_widget)
end

-- A book's embedded cover can be tiny (some are 300 x 450). Blown up to fill the screen, its pixels and
-- JPEG noise show: stop at a limit and leave the rest white. Takes ownership of image.
local function limitCoverUpscale(image)
    local Blitbuffer = require("ffi/blitbuffer")
    local RenderImage = require("ui/renderimage")
    local limit = settings.sleep_cover_max_upscale or 2.5
    local screen_w, screen_h = Device.screen:getWidth(), Device.screen:getHeight()
    local image_w, image_h = image:getWidth(), image:getHeight()
    if math.min(screen_w / image_w, screen_h / image_h) <= limit then return image end
    local w, h = math.floor(image_w * limit), math.floor(image_h * limit)
    local scaled = RenderImage:scaleBlitBuffer(image, w, h, true)
    -- The sleep screen fits whatever it's given to the screen, so give it a whole screen.
    local page = Blitbuffer.new(screen_w, screen_h, scaled:getType())
    page:fill(Blitbuffer.COLOR_WHITE)
    page:blitFrom(scaled, math.floor((screen_w - w) / 2), math.floor((screen_h - h) / 2), 0, 0, w, h)
    scaled:free()
    return page
end

-- Sleep shows the book's cover (see applyDefaults); dither it, so its gradients don't band on the
-- screen's 16 grays.
-- A book without a cover would fall back to KOReader's logo: leave the page on screen instead.
local Screensaver = require("ui/screensaver")
local screensaverSetup = Screensaver.setup
function Screensaver:setup(event, event_message)
    screensaverSetup(self, event, event_message)
    if self.screensaver_type == "random_image" and not G_reader_settings:has("screensaver_dir") then
        self.screensaver_type = "disable"
        self.image_file = nil
        self.show_message = false
    end
    if self.image then
        self.image = limitCoverUpscale(self.image)
    end
end

local ScreenSaverWidget = require("ui/widget/screensaverwidget")
function ScreenSaverWidget:onShow()
    UIManager:setDirty(self, function() return "full", self[1].dimen, true end)
    return true
end

-- KOReader's top-left status icons say that a book is being re-laid out in the background after a
-- settings change, or that a long-press has been held for a while. Nothing depends on seeing them.
local ReaderFlipping = require("apps/reader/modules/readerflipping")
function ReaderFlipping:paintTo() end
function ReaderFlipping:getRefreshRegion()
    return require("ui/geometry"):new{ x = 0, y = 0, w = 1, h = 1 }
end

-- The loading bar lives in the opening card rather than at the top left of the screen.
local ReaderRolling = require("apps/reader/modules/readerrolling")
function ReaderRolling:showEngineProgress(percent)
    require("quietui_opening").showProgress(percent)
end

-- A word without an entry just says so, instead of offering other ways to search.
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
function ReaderDictionary:showNoResultsDialog(word, __, __, __, __, __, lookupCancelled)
    self:dismissLookupInfo()
    lookupCancelled()
    UIManager:show(require("ui/widget/infomessage"):new{
        text = require("ffi/util").template(_("“%1” not found"), word),
        timeout = 2,
    })
    return true
end

local ReaderStatus = require("apps/reader/modules/readerstatus")
local stockEndOfBook = ReaderStatus.onEndOfBook
function ReaderStatus:onEndOfBook()
    if (G_reader_settings:readSetting("end_document_action") or "pop-up") ~= "pop-up" then
        return stockEndOfBook(self)
    end
    local top = UIManager:getTopmostVisibleWidget() or {}
    if top.name == "end_document" then return end
    local function toLibrary()
        UIManager:nextTick(function() self:openFileBrowser() end)
    end
    UIManager:show(require("quietui_dialog"):new{
        name = "end_document",
        title = _("End of book"),
        buttons = {
            { text = _("Go to beginning"), callback = function() self.ui.gotopage:onGoToBeginning() end },
            { text = _("Library"), callback = toLibrary },
            {
                text = _("Mark finished"),
                selected = true,
                callback = function()
                    self:markBook(true)
                    toLibrary()
                end,
            },
        },
    })
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
            require("quietui_opening").finish()
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

    if (settings.keep_plugins or {}).kosync then
        require("quietui_sync").reapply()
    end

    -- Sleep: the current book's cover, whole and undistorted, with no "Sleeping" box.
    G:saveSetting("screensaver_type", "cover")
    G:makeFalse("screensaver_show_message")
    G:makeFalse("screensaver_stretch_images")
    G:saveSetting("screensaver_img_background", "white")

    G:saveSetting("reader_footer_mode", 1)
    -- Footer as in the design: a 56 board pixel band with 15 pixel text, in the units ReaderFooter
    -- scales by. It reads these when a book opens.
    local UI = require("quietui_ui")
    local unit = Device.screen:scaleBySize(1000) / 1000
    local footer = G:readSetting("footer", require("apps/reader/modules/readerfooter").default_settings)
    footer.container_height = math.floor(UI.D(56) / unit + 0.5)
    footer.container_bottom_padding = 0
    footer.text_font_size = math.floor(UI.D(15) / unit + 0.5)
end

function QuietUI:init()
    -- A USB install waits here. Connecting from KOReader restarts it without unpacking, so do that now.
    if lfs.attributes("ota/update.tar.xz", "mode") == "file" then
        UIManager:nextTick(function() UIManager:restartKOReader() end)
    end
    applyDefaults()
    require("quietui_remote").install()
    if self.ui.document then
        self:initReader()
    else
        self:initLibrary()
    end
end

function QuietUI:onSuspend()
    require("quietui_remote").stop()
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
    local noop = function() end
    self.ui.menu.onTapShowMenu = noop
    self.ui.menu.onSwipeShowMenu = noop
    self.ui.config.onTapShowConfigMenu = noop
    self.ui.config.onSwipeShowConfigMenu = noop

    if self.ui.rolling then
        -- Read by ReaderTypography right after plugins are loaded.
        self.ui.doc_settings:saveSetting("hyphenation", settings.hyphenation == true)
    else
        -- One page at a time, as swipes turn pages. Read by ReaderView when the document's settings load.
        self.ui.doc_settings:saveSetting("kopt_page_scroll", 0)
    end

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
    require("quietui_light").registerEdgeZones(self.ui, self:edgeActions(), { self.ui.rolling and "rolling_pan" or "paging_pan" })
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
    require("quietui_opening").finish()
    if self.ui.document then self:registerZones() end
end

function QuietUI:onSetDimensions()
    if self.ui.document then self:registerZones() end
end

-- After the document is loaded and before it is rendered.
function QuietUI:onPreRenderDocument()
    if not self.ui.rolling then return end
    local Presets = require("quietui_presets")
    Presets.applyAntialias(self.ui, Presets.currentRender(self.ui))
end

return QuietUI

--[[--
The library's cogwheel: a small sheet with Wi-Fi, updates over Wi-Fi, sleep timing, reading statistics,
calibre wireless and the KOReader sync account. Tap outside it or Done to close.
]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local OverlapGroup = require("ui/widget/overlapgroup")
local Remote = require("quietui_remote")
local RightContainer = require("ui/widget/container/rightcontainer")
local Sync = require("quietui_sync")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Input = Device.input
local Screen = Device.screen
local T = require("ffi/util").template
local _ = require("gettext")

local D = UI.D

local SLEEP_MINUTES = {
    { id = 5, label = _("5 min") },
    { id = 15, label = _("15 min") },
    { id = 30, label = _("30 min") },
    { id = 60, label = _("1 hour") },
    { id = -1, label = _("Never") },
}

local ROW_H = 52

local Settings = InputContainer:extend{
    settings = nil,
    library = nil,
    ui = nil,
}

function Settings:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.content_w = self.dimen.w - 2 * D(32)
    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
    end
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    self:update()
    self:watchCalibre()
end

-- One setting: a label, a line or two about it on the left, its controls on the right.
function Settings:row(label, status, detail, control)
    local room = self.content_w - control:getSize().w - D(16)
    local dimen = Geom:new{ w = self.content_w, h = D(ROW_H) }
    local text = VerticalGroup:new{
        align = "left",
        UI.pinned(UI.text(status, UI.sans(18, 700), nil, room), D(25)),
    }
    if detail then
        table.insert(text, UI.pinned(UI.text(detail, UI.sans(15), nil, room), D(21)))
    end
    return VerticalGroup:new{
        align = "left",
        UI.label(label),
        VerticalSpan:new{ width = D(6) },
        OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{ dimen = dimen, text },
            RightContainer:new{ dimen = dimen, control },
        },
    }
end

function Settings:buildWifi()
    local NetworkMgr = require("ui/network/manager")
    local on = NetworkMgr:isWifiOn()
    local status, detail
    if on and NetworkMgr:isConnected() then
        local network = NetworkMgr:getCurrentNetwork()
        status = T(_("Connected to %1"), network and network.ssid or _("Wi-Fi"))
    elseif on then
        status = _("On, not connected")
    else
        status = _("Off")
    end
    local after = function() self:refresh() end
    local controls = HorizontalGroup:new{ align = "center" }
    if on then
        table.insert(controls, UI.button({
            text = _("Networks"),
            callback = function()
                NetworkMgr.wifi_toggle_long_press = true
                NetworkMgr:reconnectOrShowNetworkMenu(after, true)
            end,
        }))
        table.insert(controls, HorizontalSpan:new{ width = D(8) })
    end
    table.insert(controls, UI.choices({
        { id = false, label = _("Off") },
        { id = true, label = _("On") },
    }, on, nil, UI.H(44), function(opt)
        if opt.id == on then return end
        if opt.id then
            NetworkMgr:toggleWifiOn(after, false, true)
        else
            Remote.stop()
            NetworkMgr:toggleWifiOff(after, true)
        end
        self:refresh()
    end))
    return self:row(_("Wi-Fi"), status, detail, controls)
end

-- Off until wanted: lets deploy-to-kobo.sh --wifi install a new version.
function Settings:buildUpdates()
    if not Remote.available() then return end
    local on = Remote.isRunning()
    local status = _("Off")
    local detail = _("Turn on to install a new version from the computer.")
    if on then
        local address = Remote.address()
        status = _("On")
        detail = address and T(_("Address %1"), address) or _("Waiting for Wi-Fi")
    end
    local choices = UI.choices({
        { id = false, label = _("Off") },
        { id = true, label = _("On") },
    }, on, nil, UI.H(44), function(opt)
        if opt.id == Remote.isRunning() then return end
        if opt.id then
            self:turnUpdatesOn()
        else
            Remote.stop()
        end
        self:refresh()
    end)
    return self:row(_("Updates over Wi-Fi"), status, detail, choices)
end

function Settings:turnUpdatesOn()
    local NetworkMgr = require("ui/network/manager")
    local ready = function()
        if not Remote.start() then
            UIManager:show(InfoMessage:new{ text = _("Couldn't turn on updates."), timeout = 2 })
        end
        self:refresh()
    end
    if NetworkMgr:isConnected() then
        ready()
    else
        NetworkMgr:beforeWifiAction(ready)
    end
end

function Settings:buildSleep()
    local seconds = G_reader_settings:readSetting("auto_suspend_timeout_seconds", 15 * 60)
    local current = seconds > 0 and math.floor(seconds / 60) or -1
    local status = current > 0 and T(_("After %1 min without use"), current) or _("Only with the power button")
    local choices = UI.choices(SLEEP_MINUTES, current, nil, UI.H(44), function(opt)
        local value = opt.id > 0 and opt.id * 60 or -1
        G_reader_settings:saveSetting("auto_suspend_timeout_seconds", value)
        local autosuspend = self.ui and self.ui.autosuspend
        if autosuspend then
            autosuspend.auto_suspend_timeout_seconds = value
            autosuspend:_unschedule()
            autosuspend:_start()
        end
        self:refresh()
    end)
    return self:row(_("Sleep"), status, nil, choices)
end

function Settings:buildStats()
    local Stats = require("quietui_stats")
    local periods = Stats.read()
    local today = periods[1]
    local week = periods[2]
    local status = today and T(_("%1 today"), Stats.duration(today.seconds)) or _("Nothing recorded yet")
    local detail = week and T(_("%1 this week"), Stats.duration(week.seconds)) or nil
    local button = UI.button({
        text = _("Open"),
        callback = function()
            local settings, library, ui = self.settings, self.library, self.ui
            self:onClose()
            UIManager:show(Stats:new{
                on_close = function()
                    UIManager:show(Settings:new{ settings = settings, library = library, ui = ui }, "ui")
                end,
            }, "ui")
        end,
    })
    return self:row(_("Reading statistics"), status, detail, button)
end

-- Calibre's plugin runs in its own coroutine: follow the connection while this sheet is open,
-- and show books as they arrive.
function Settings:calibreClient()
    if not (self.ui and self.ui.calibre) then return end
    return require("wireless")
end

function Settings:watchCalibre()
    local client = self:calibreClient()
    if not client then return end
    local CalibreMetadata = require("metadata")
    if not CalibreMetadata.quietui_watched then
        CalibreMetadata.quietui_watched = true
        local saveBookList = CalibreMetadata.saveBookList
        CalibreMetadata.saveBookList = function(...)
            saveBookList(...)
            local library = require("apps/filemanager/filemanager").instance
            if library and library[1] and library[1].reload then library[1]:reload() end
        end
    end
    self.calibre_connected = client.calibre_socket ~= nil
    self.calibre_watch = function()
        local connected = client.calibre_socket ~= nil
        if connected ~= self.calibre_connected then
            self.calibre_connected = connected
            self:refresh()
        end
        UIManager:scheduleIn(1, self.calibre_watch)
    end
    UIManager:scheduleIn(1, self.calibre_watch)
end

function Settings:connectCalibre(client)
    -- Stock asks for a folder first. Calibre's books get one of their own in the home folder.
    local home = require("apps/filemanager/filemanagerutil").getHomeFolder()
    local lfs = require("libs/libkoreader-lfs")
    local inbox = G_reader_settings:readSetting("inbox_dir")
    if home and not (inbox and lfs.attributes(inbox, "mode") == "directory") then
        inbox = home .. "/" .. require("quietui_library").INBOX
        if lfs.attributes(inbox, "mode") ~= "directory" then lfs.mkdir(inbox) end
        G_reader_settings:saveSetting("inbox_dir", inbox)
    end
    client:connect()
end

function Settings:buildCalibre()
    local client = self:calibreClient()
    if not client then return end
    local connected = client.calibre_socket ~= nil
    local status = connected and _("Connected") or _("Not connected")
    local detail = connected and _("Send books from calibre now.")
        or _("In calibre, start the wireless device connection first.")
    local button = UI.button({
        text = connected and _("Disconnect") or _("Connect"),
        callback = function()
            if client.calibre_socket then
                client:disconnect()
                if self.library then self.library:reload() end
            else
                self:connectCalibre(client)
            end
            self:refresh()
        end,
    })
    return self:row(_("Calibre wireless"), status, detail, button)
end

function Settings:buildSync()
    local username = Sync.username()
    local status, detail
    if username then
        status = T(_("Logged in as %1"), username)
        detail = _("Your reading position syncs automatically.")
    else
        status = _("Not logged in")
        detail = _("Log in to keep your reading position across devices.")
    end
    local button = UI.button({
        text = username and _("Log out") or _("Log in"),
        callback = function()
            if username then
                Sync.logout()
                self:refresh()
            else
                self:showLogin()
            end
        end,
    })
    return self:row(_("KOReader sync"), status, detail, button)
end

function Settings:buildSections()
    local sections = VerticalGroup:new{ align = "left" }
    for __, section in ipairs{
        self:buildWifi(),
        self:buildUpdates() or false,
        self:buildSleep(),
        self:buildStats(),
        self:buildCalibre() or false,
        self:buildSync(),
    } do
        if section then
            table.insert(sections, VerticalSpan:new{ width = D(16) })
            table.insert(sections, section)
            table.insert(sections, VerticalSpan:new{ width = D(16) })
            table.insert(sections, LineWidget:new{
                dimen = Geom:new{ w = self.content_w, h = D(UI.style.rule) },
                background = UI.BLACK,
            })
        end
    end
    table.remove(sections) -- no rule under the last one
    table.insert(sections, VerticalSpan:new{ width = D(8) })
    return sections
end

function Settings:update()
    local done = UI.button({ text = _("Done"), callback = function() self:onClose() end })
    local bar = Geom:new{ w = self.content_w, h = D(48) }
    local panel = FrameContainer:new{
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
                        LeftContainer:new{ dimen = bar, UI.text(_("Settings"), UI.serif(24, 700)) },
                        RightContainer:new{ dimen = bar, done },
                    },
                    self:buildSections(),
                },
            },
        },
    }
    self.panel = panel
    self[1] = VerticalGroup:new{
        VerticalSpan:new{ width = self.dimen.h - panel:getSize().h },
        panel,
    }
end

function Settings:refresh()
    self:update()
    UIManager:setDirty(self, "ui")
end

function Settings:showLogin()
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:willRerunWhenOnline(function() self:showLogin() end) then
        return
    end
    local dialog
    local function submit(action, working)
        local username, password = unpack(dialog:getFields())
        username = username:match("^%s*(.-)%s*$")
        if username == "" or password == "" then
            UIManager:show(InfoMessage:new{ text = _("Enter a username and a password."), timeout = 2 })
            return
        end
        UIManager:close(dialog)
        local message = InfoMessage:new{ text = working }
        UIManager:show(message)
        UIManager:forceRePaint()
        UIManager:scheduleIn(0.1, function()
            local ok, err = Sync.signIn(action, username, password, self.settings.sync_server)
            UIManager:close(message)
            if not ok then
                UIManager:show(InfoMessage:new{ text = err })
            end
            self:refresh()
        end)
    end
    dialog = MultiInputDialog:new{
        title = _("KOReader sync"),
        fields = {
            { hint = _("Username") },
            { hint = _("Password"), text_type = "password" },
        },
        buttons = { {
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Register"),
                callback = function() submit("register", _("Registering…")) end,
            },
            {
                text = _("Log in"),
                is_enter_default = true,
                callback = function() submit("authorize", _("Logging in…")) end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Settings:onTapOutside(__, ges)
    local d = self.panel.dimen
    if d and ges.pos.y >= d.y then return true end
    return self:onClose()
end

-- Sleep turns updates off, and Wi-Fi may have changed.
function Settings:onResume()
    self:refresh()
end

function Settings:onCloseWidget()
    if self.calibre_watch then UIManager:unschedule(self.calibre_watch) end
end

function Settings:onClose()
    UIManager:close(self, "ui")
    return true
end

return Settings

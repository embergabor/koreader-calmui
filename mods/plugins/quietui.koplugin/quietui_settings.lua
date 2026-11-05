--[[--
The library's cogwheel: a small sheet. For now it only holds the KOReader sync account.
Tap outside it or Done to close.
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

local Settings = InputContainer:extend{
    settings = nil,
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
    local button = UI.group({ {
        {
            text = username and _("Log out") or _("Log in"),
            callback = function()
                if username then
                    Sync.logout()
                    self:refresh()
                else
                    self:showLogin()
                end
            end,
        },
    } }, D(112), UI.H(44))
    local dimen = Geom:new{ w = self.content_w, h = D(52) }
    return VerticalGroup:new{
        align = "left",
        UI.label(_("KOReader sync")),
        VerticalSpan:new{ width = D(8) },
        OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{
                dimen = dimen,
                VerticalGroup:new{
                    align = "left",
                    UI.pinned(UI.text(status, UI.sans(18, 700), nil, self.content_w - D(128)), D(25)),
                    UI.pinned(UI.text(detail, UI.sans(15), nil, self.content_w - D(128)), D(21)),
                },
            },
            RightContainer:new{ dimen = dimen, button },
        },
    }
end

function Settings:update()
    local done = UI.group({ { { text = _("Done"), callback = function() self:onClose() end } } }, D(96), UI.H(44))
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
                    VerticalSpan:new{ width = D(18) },
                    self:buildSync(),
                    VerticalSpan:new{ width = D(24) },
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

function Settings:onClose()
    UIManager:close(self, "ui")
    return true
end

return Settings

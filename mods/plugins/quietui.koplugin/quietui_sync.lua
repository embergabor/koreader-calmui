--[[--
KOReader sync account, from the library. The sync plugin itself only runs inside a book,
so this writes its settings file directly; it picks them up when the next book opens.
Only the hash of the password is stored, as KOReader's own login does.
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local md5 = require("ffi/sha2").md5

local Sync = {}

-- From the sync plugin
local SILENT, DISABLE, CHECKSUM_BINARY = 2, 3, 0

local function open()
    return LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua")
end

local function client(server)
    local KOSyncClient = require("KOSyncClient")
    return KOSyncClient:new{
        custom_url = server,
        service_spec = "plugins/kosync.koplugin/api.json",
    }
end

function Sync.username()
    local sync = open():readSetting("settings")
    return sync and sync.userkey and sync.username or nil
end

-- Silent: jump forward without asking, never backward. Wi-Fi turns on by itself when needed.
local function applyBehaviour(sync)
    sync.auto_sync = true
    sync.sync_forward = SILENT
    sync.sync_backward = DISABLE
    sync.checksum_method = sync.checksum_method or CHECKSUM_BINARY
    G_reader_settings:saveSetting("wifi_enable_action", "turn_on")
    G_reader_settings:saveSetting("wifi_disable_action", "turn_off")
end

--- Keeps a logged-in account's behaviour as above at every start.
function Sync.reapply()
    local settings = open()
    local sync = settings:readSetting("settings")
    if sync and sync.userkey then
        applyBehaviour(sync)
        settings:saveSetting("settings", sync)
        settings:flush()
    end
end

--- action is "authorize" (log in) or "register". Returns true, or false and a message.
function Sync.signIn(action, username, password, server)
    local userkey = md5(password)
    local c = client(server)
    local ok, status, body = pcall(c[action], c, username, userkey)
    if not ok then
        return false, tostring(status)
    end
    if not status then
        return false, body and body.message or "Unknown server error"
    end
    local settings = open()
    local sync = settings:readSetting("settings") or {}
    sync.custom_server = server
    sync.username = username
    sync.userkey = userkey
    applyBehaviour(sync)
    settings:saveSetting("settings", sync)
    settings:flush()
    return true
end

function Sync.logout()
    local settings = open()
    local sync = settings:readSetting("settings") or {}
    sync.userkey = nil
    settings:saveSetting("settings", sync)
    settings:flush()
    pcall(function() require("KOSyncQueue"):clear() end)
end

return Sync

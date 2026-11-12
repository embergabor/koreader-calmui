--[[--
Updates over Wi-Fi: runs KOReader's own SSH server (dropbear) so deploy-to-kobo.sh --wifi can
install a new version. Key login only (settings/SSH/authorized_keys), off until turned on in
the cogwheel, and off again when the device sleeps or leaves KOReader.

The server outlives a restart of KOReader, so several updates can follow each other.
]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

local PID_FILE = "/tmp/dropbear_koreader.pid"
local RESTART_FLAG = "/tmp/quietui-restart"

local Remote = { PORT = 2222 }

local standby_held = false
local restarting = false

local function readPid()
    local f = io.open(PID_FILE, "r")
    if not f then return nil end
    local pid = tonumber(f:read("*l"))
    f:close()
    return pid
end

-- Only on devices set up for it: the USB install from the source folder adds the computer's key.
function Remote.available()
    return lfs.attributes("dropbear", "mode") == "file"
        and (lfs.attributes("settings/SSH/authorized_keys", "size") or 0) > 0
end

function Remote.isRunning()
    local pid = readPid()
    return pid ~= nil and lfs.attributes("/proc/" .. pid, "mode") == "directory"
end

-- This device's address on the Wi-Fi network, or nil.
function Remote.address()
    local ok, interfaces = pcall(function()
        return require("ffi/netinfo"):new():retrieve()
    end)
    if not ok or not interfaces then return nil end
    for __, interface in ipairs(interfaces) do
        if interface.ipv4 and interface.name ~= "lo" and not interface.ipv4:match("^127%.") then
            return interface.ipv4
        end
    end
end

local function watch()
    if not Remote.isRunning() then
        Remote.watching = false
        return
    end
    if lfs.attributes(RESTART_FLAG, "mode") then
        os.remove(RESTART_FLAG)
        restarting = true
        UIManager:restartKOReader()
        return
    end
    UIManager:scheduleIn(1, watch)
end

-- While the server runs: stay out of low power between touches and listen for an update's restart.
local function hold()
    if not standby_held then
        standby_held = true
        UIManager:preventStandby()
    end
    if not Remote.watching then
        Remote.watching = true
        UIManager:scheduleIn(1, watch)
    end
end

function Remote.start()
    if Remote.isRunning() then return true end
    os.remove(RESTART_FLAG)
    -- Kobo's init scripts don't set up pseudoterminals. Same as the stock SSH plugin.
    os.execute("[ -d /dev/pts ] || { mkdir -p /dev/pts; mount -t devpts devpts /dev/pts; }")
    local ok = os.execute(string.format("./dropbear -E -R -s -p %d -P %s", Remote.PORT, PID_FILE)) == 0
    if ok then hold() end
    return ok
end

function Remote.stop()
    local pid = readPid()
    if pid then
        -- With its sessions, so nothing stays connected.
        os.execute(string.format("pkill -TERM -P %d 2>/dev/null; kill -TERM %d 2>/dev/null", pid, pid))
        os.remove(PID_FILE)
    end
    UIManager:unschedule(watch)
    Remote.watching = false
    if standby_held then
        standby_held = false
        UIManager:allowStandby()
    end
end

-- Once per start of KOReader: pick up a server left running by the last start, and stop it for
-- good when leaving KOReader, except for an update's restart.
function Remote.install()
    if Remote.installed then return end
    Remote.installed = true
    if Remote.isRunning() then hold() end
    local exit = Device.exit
    Device.exit = function(device, ...)
        if not restarting then Remote.stop() end
        return exit(device, ...)
    end
end

return Remote

-- Emulator only (never deployed): runs emulator/home/test-cmd.lua when it appears, to drive
-- real gesture events without the mouse. Coordinates are board pixels (702 x 936).
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local time = require("ui/time")
local DataStorage = require("datastorage")

local cmd = DataStorage:getDataDir() .. "/test-cmd.lua"
local out = DataStorage:getDataDir() .. "/test-out.txt"
local scale = Device.screen:getWidth() / 702
if os.getenv("EMULATE_MODEL") then Device.model = os.getenv("EMULATE_MODEL") end

local function gesture(name, bx, by, extra)
    local ges = {
        ges = name,
        pos = Geom:new{ x = bx * scale, y = by * scale, w = 0, h = 0 },
        time = time.now(),
    }
    for k, v in pairs(extra or {}) do ges[k] = v end
    UIManager:sendEvent(Event:new("Gesture", ges))
end

_G.T = {
    tap = function(x, y) gesture("tap", x, y) end,
    hold = function(x, y) gesture("hold", x, y) end,
    swipe = function(dir) gesture("swipe", 351, 500, { direction = dir, distance = 400, multiswipe_directions = dir }) end,
    log = function(...)
        local f = io.open(out, "a")
        f:write(table.concat({ ... }, " "), "\n")
        f:close()
    end,
    top = function()
        local top = UIManager._window_stack[#UIManager._window_stack]
        return top and top.widget
    end,
}

local function poll()
    local f = io.open(cmd, "r")
    if f then
        f:close()
        local chunk, err = loadfile(cmd)
        os.remove(cmd)
        if chunk then
            local ok, run_err = pcall(chunk)
            if not ok then T.log("ERROR", tostring(run_err)) end
        else
            T.log("ERROR", tostring(err))
        end
    end
    UIManager:scheduleIn(0.3, poll)
end
UIManager:scheduleIn(1, poll)

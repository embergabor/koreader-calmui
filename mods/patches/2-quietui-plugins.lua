-- Only the stock plugins Quiet UI uses are ever loaded (settings.lua's keep_plugins).
-- Runs before KOReader loads its plugins, so a change takes effect at this very start.
local lfs = require("libs/libkoreader-lfs")

local path = os.getenv("QUIETUI_SETTINGS") or "plugins/quietui.koplugin/settings.lua"
local ok, settings = pcall(dofile, path)
local keep = ok and type(settings) == "table" and settings.keep_plugins
if not keep then return end

local disabled = {}
local listed, iter, dir_obj = pcall(lfs.dir, "plugins")
if listed then
    for entry in iter, dir_obj do
        local name = entry:match("^(.+)%.koplugin$")
        if name and name ~= "quietui" and not keep[name] then
            disabled[name] = true
        end
    end
end
G_reader_settings:saveSetting("plugins_disabled", disabled)

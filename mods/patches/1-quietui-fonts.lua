-- Adds the font_folders from Quiet UI's settings.lua to KOReader's font search, before fonts load.
-- On Kobo this list comes from EXT_FONT_DIR, set in koreader.sh. Other platforms ignore it.
local ok, settings = pcall(dofile, "plugins/quietui.koplugin/settings.lua")
if not ok or type(settings) ~= "table" or not settings.font_folders or #settings.font_folders == 0 then
    return
end

local ffi = require("ffi")
require("ffi/posix_h")

local folders = { os.getenv("EXT_FONT_DIR") }
for _, folder in ipairs(settings.font_folders) do
    table.insert(folders, folder)
end
ffi.C.setenv("EXT_FONT_DIR", table.concat(folders, ";"), 1)

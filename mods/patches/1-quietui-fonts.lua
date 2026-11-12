-- Adds the font_folders from Calm UI's settings.lua to KOReader's font search, before fonts load.
-- On Kobo this list comes from EXT_FONT_DIR, set in koreader.sh. Other platforms ignore it.
-- With font_report on, also writes what it finds to quietui-fonts.txt in the KOReader folder.
local ok, settings = pcall(dofile, "plugins/quietui.koplugin/settings.lua")
if not ok or type(settings) ~= "table" then
    return
end

local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
require("ffi/posix_h")

local FONT_MAGIC = {
    ["\0\1\0\0"] = "truetype",
    ["true"] = "truetype",
    ["OTTO"] = "opentype",
    ["ttcf"] = "collection",
    ["wOFF"] = "woff",
    ["wOF2"] = "woff2",
}

local function isDir(path)
    return lfs.attributes(path, "mode") == "directory"
end

local function reportFonts()
    local report = io.open("quietui-fonts.txt", "w")
    if not report then return end
    local function walk(dir, depth, only_matching)
        local dir_ok, iter, dir_obj = pcall(lfs.dir, dir)
        if not dir_ok then
            report:write("  cannot read ", dir, "\n")
            return
        end
        for name in iter, dir_obj do
            if name ~= "." and name ~= ".." then
                local path = dir .. "/" .. name
                local mode = lfs.attributes(path, "mode")
                if mode == "directory" then
                    if depth > 0 then walk(path, depth - 1, only_matching) end
                elseif not only_matching or name:lower():find("%.[ot]t[fc]$") then
                    local kind = "unknown"
                    local f = io.open(path, "rb")
                    if f then
                        kind = FONT_MAGIC[f:read(4) or ""] or "not a plain font"
                        f:close()
                    else
                        kind = "unreadable"
                    end
                    report:write("  ", path, "  ", tostring(lfs.attributes(path, "size")), " bytes  ", kind, "\n")
                end
            end
        end
    end
    report:write("Configured font folders:\n")
    for __, folder in ipairs(settings.font_folders or {}) do
        report:write(" ", folder, isDir(folder) and "" or "  (does not exist)", "\n")
        if isDir(folder) then walk(folder, 2, false) end
    end
    report:write("Font files elsewhere on the system:\n")
    for __, root in ipairs({ "/usr/local", "/usr/share", "/usr/lib", "/opt", "/etc", "/mnt/onboard/.kobo" }) do
        if isDir(root) then walk(root, 6, true) end
    end
    report:close()
end

if settings.font_report then
    pcall(reportFonts)
end

local folders = { os.getenv("EXT_FONT_DIR") }
for __, folder in ipairs(settings.font_folders or {}) do
    if isDir(folder) then
        table.insert(folders, folder)
    end
end
if #folders > 0 then
    ffi.C.setenv("EXT_FONT_DIR", table.concat(folders, ";"), 1)
end

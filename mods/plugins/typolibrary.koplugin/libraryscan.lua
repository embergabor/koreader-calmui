--[[--
Scans the home folder and groups books the way calibre lays them out on a Kobo:

    Author/Title.kepub.epub
    Author/Series/Series-01 - Title.kepub.epub

Everything is derived from paths, so no document has to be opened.
Files outside an author folder fall back to the cover browser's metadata cache.
]]

local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")

local Library = {}

local UNSORTED = "Unsorted"

local function stripExtension(name)
    return name:gsub("%.kepub%.epub$", ""):gsub("%.[^.]+$", "")
end

-- Undo calibre's filename mangling: "Odyssey, The" -> "The Odyssey",
-- "Harry Potter_ The..." -> "Harry Potter: The...", "It_s" -> "It’s".
function Library.prettifyTitle(title)
    title = title:gsub("_ ", ": "):gsub("_", "’")
    local rest, article = title:match("^(.-), (%a%a?%a?)$")
    if rest and (article == "The" or article == "A" or article == "An") then
        title = article .. " " .. rest
    end
    return title
end

-- Sort key that ignores a leading article, case-insensitive.
local function sortKey(str)
    return BookList.removeLeadingArticle(str, "en"):lower()
end

local function scan(dir, depth, found)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return end
    for name in iter, dir_obj do
        if name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
            local path = dir .. "/" .. name
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                if depth < 3 then
                    scan(path, depth + 1, found)
                end
            elseif mode == "file" and DocumentRegistry:hasProvider(path) then
                table.insert(found, path)
            end
        end
    end
end

local function describe(file, home, coverbrowser)
    local rel = file:sub(#home + 2)
    local parts = {}
    for part in rel:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    local book = {
        file = file,
        title = Library.prettifyTitle(stripExtension(parts[#parts])),
    }
    if #parts >= 2 then
        book.author = parts[1]
    end
    if #parts >= 3 then
        local series = parts[#parts - 1]
        book.series = series
        local stem = stripExtension(parts[#parts])
        local idx, title = stem:match("%-(%d+) %- (.+)$")
        if idx and stem:sub(1, #series) == series then
            book.series_index = tonumber(idx)
            book.title = Library.prettifyTitle(title)
        end
    end
    if not book.author and coverbrowser then
        local props = coverbrowser.getDocProps(file)
        if props then
            book.author = props.authors and props.authors:gsub("\n.*", "")
            book.title = props.title or book.title
        end
    end
    book.author = book.author or UNSORTED

    local info = BookList.getBookInfo(file)
    book.status = info.been_opened and info.status or "new"
    book.percent = info.percent_finished
    return book
end

--- Returns a list of authors, each { name, books = {...}, series = { {name, books}, ... } }.
function Library.load(coverbrowser)
    local home = ffiUtil.realpath(require("apps/filemanager/filemanagerutil").getHomeFolder())
    local files = {}
    if home then
        scan(home, 1, files)
    end

    local by_author = {}
    local authors = {}
    for _, file in ipairs(files) do
        local book = describe(file, home, coverbrowser)
        local author = by_author[book.author]
        if not author then
            author = { name = book.author, books = {}, series = {}, series_by_name = {} }
            by_author[book.author] = author
            table.insert(authors, author)
        end
        if book.series then
            local series = author.series_by_name[book.series]
            if not series then
                series = { name = book.series, books = {} }
                author.series_by_name[book.series] = series
                table.insert(author.series, series)
            end
            table.insert(series.books, book)
        else
            table.insert(author.books, book)
        end
    end

    local function byTitle(a, b) return sortKey(a.title) < sortKey(b.title) end
    local function byIndex(a, b)
        if a.series_index and b.series_index and a.series_index ~= b.series_index then
            return a.series_index < b.series_index
        end
        return byTitle(a, b)
    end
    table.sort(authors, function(a, b)
        if (a.name == UNSORTED) ~= (b.name == UNSORTED) then
            return b.name == UNSORTED
        end
        return a.name:lower() < b.name:lower()
    end)
    for _, author in ipairs(authors) do
        author.series_by_name = nil
        table.sort(author.books, byTitle)
        table.sort(author.series, function(a, b) return sortKey(a.name) < sortKey(b.name) end)
        for _, series in ipairs(author.series) do
            table.sort(series.books, byIndex)
        end
    end
    return authors, #files
end

return Library

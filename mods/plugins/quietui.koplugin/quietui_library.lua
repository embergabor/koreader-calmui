--[[--
Finds the books in the home folder. Everything comes from paths, as calibre lays
books out on a Kobo, so no document has to be opened:

    Author/Title.kepub.epub
    Author/Series/Series-01 - Title.kepub.epub
]]

local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local ReadHistory = require("readhistory")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")

local Library = {}

local UNSORTED = "Unsorted"
local NAME_PARTICLES = { le = true, la = true, de = true, du = true, van = true, von = true, der = true }

local function stripExtension(name)
    return (name:gsub("%.kepub%.epub$", ""):gsub("%.[^.]+$", ""))
end

-- Undo calibre's filename mangling: "Odyssey, The" -> "The Odyssey",
-- "Harry Potter_ The..." -> "Harry Potter: The...", "It_s" -> "It’s".
local function prettifyTitle(title)
    title = title:gsub("_ ", ": "):gsub("_", "’")
    local rest, article = title:match("^(.-), (%a%a?%a?)$")
    if rest and (article == "The" or article == "A" or article == "An") then
        title = article .. " " .. rest
    end
    return title
end

local function titleKey(str)
    return BookList.removeLeadingArticle(str, "en"):lower()
end

-- "Arthur Conan Doyle" -> "doyle", "John Le Carre" -> "le carre",
-- "Stanislaw Lem, Joanna Kilmartin" -> "lem"
local function authorKey(name)
    local first = name:gsub("%s*[,&].*$", "")
    local words = {}
    for word in first:gmatch("%S+") do table.insert(words, word) end
    local n = #words
    if n == 0 then return name:lower() end
    if n >= 3 and NAME_PARTICLES[words[n - 1]:lower()] then
        return (words[n - 1] .. " " .. words[n]):lower()
    end
    return words[n]:lower()
end

local function scan(dir, depth, exclude, found)
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok then return end
    for name in iter, dir_obj do
        if name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
            local path = dir .. "/" .. name
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" then
                if depth < 3 and not (depth == 1 and exclude[name]) then
                    scan(path, depth + 1, exclude, found)
                end
            elseif mode == "file" and DocumentRegistry:hasProvider(path) then
                table.insert(found, path)
            end
        end
    end
end

local function progressText(status, percent)
    if status == "new" then return "New" end
    if status == "complete" then return "Finished" end
    if status == "abandoned" then return "On hold" end
    return string.format("%d%%", math.floor((percent or 0) * 100 + 0.5))
end

local function describe(file, home)
    local parts = {}
    for part in file:sub(#home + 2):gmatch("[^/]+") do
        table.insert(parts, part)
    end
    local stem = stripExtension(parts[#parts])
    local book = {
        file = file,
        title = prettifyTitle(stem),
        author = #parts >= 2 and parts[1] or UNSORTED,
    }
    if #parts >= 3 then
        local series = parts[#parts - 1]
        book.series = series
        local idx, title = stem:match("%-(%d+) %- (.+)$")
        if idx and stem:sub(1, #series) == series then
            book.series_index = tonumber(idx)
            book.title = prettifyTitle(title)
        end
    end
    book.title_key = titleKey(book.title)
    book.author_key = authorKey(book.author)

    local info = BookList.getBookInfo(file)
    local status = info.been_opened and info.status or "new"
    book.status = status
    book.progress = progressText(status, info.percent_finished)
    return book
end

function Library.load(settings)
    local home = ffiUtil.realpath(filemanagerutil.getHomeFolder())
    local files = {}
    if home then
        scan(home, 1, settings.exclude_folders or {}, files)
    end
    local recent = {}
    for i, entry in ipairs(ReadHistory.hist) do
        recent[entry.file] = i
    end
    local books = {}
    for __, file in ipairs(files) do
        local book = describe(file, home)
        book.recent = recent[file] or math.huge
        table.insert(books, book)
    end
    return books
end

local function byTitle(a, b)
    return a.title_key < b.title_key
end

local function byRecent(a, b)
    if a.recent ~= b.recent then return a.recent < b.recent end
    return byTitle(a, b)
end

--- Books in reading order for a flat sort ("recent" or "title").
function Library.sorted(books, sort)
    local list = {}
    for i, book in ipairs(books) do list[i] = book end
    table.sort(list, sort == "title" and byTitle or byRecent)
    return list
end

--- Authors in order, each { name, books = {...}, series = { { name, books = {...} }, ... } }.
function Library.byAuthor(books)
    local authors, by_name = {}, {}
    for __, book in ipairs(books) do
        local author = by_name[book.author]
        if not author then
            author = { name = book.author, key = book.author_key, books = {}, series = {}, series_by_name = {} }
            by_name[book.author] = author
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
    table.sort(authors, function(a, b)
        if (a.name == UNSORTED) ~= (b.name == UNSORTED) then return b.name == UNSORTED end
        if a.key ~= b.key then return a.key < b.key end
        return a.name < b.name
    end)
    for __, author in ipairs(authors) do
        author.series_by_name = nil
        table.sort(author.books, byTitle)
        table.sort(author.series, function(a, b) return titleKey(a.name) < titleKey(b.name) end)
        for __, series in ipairs(author.series) do
            table.sort(series.books, function(a, b)
                if a.series_index and b.series_index and a.series_index ~= b.series_index then
                    return a.series_index < b.series_index
                end
                return byTitle(a, b)
            end)
        end
    end
    return authors
end

return Library

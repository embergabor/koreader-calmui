-- Quiet UI: rare options. There is deliberately no screen for these on the device.
-- Edit this file over USB and restart KOReader.
return {
    -- Per device model. render ("crisp", "smooth" or "book") is a default, used until it's changed
    -- on the device. Other settings from this file can go here too, such as library_columns, and
    -- replace the general one on that device. Not ui_scale or font_folders, which are read earlier.
    devices = {
        Kobo_condor = { render = "smooth" }, -- Elipsa 2E
        Kobo_io     = { render = "book" },   -- Libra 2
        default     = { render = "smooth" },
    },

    -- What the reader gestures do.
    -- tap: "sheet" or "none"
    -- hold_top_left: "none", "exit" (back to the Kobo home screen) or "menu" (stock KOReader menus).
    --   The stock menus can't otherwise be reached. Turn "menu" on for one-off jobs such as logging
    --   in to sync, then back to "none".
    -- edge_left, edge_right: dragging up or down along that edge changes "brightness" or "warmth".
    gestures = {
        tap = "sheet",
        hold_top_left = "none",
        edge_left = "brightness",
        edge_right = "warmth",
    },

    -- Font buttons in the Aa sheet, in order: family name, then a replacement used when the
    -- family isn't installed. "Book's own" is always added after these.
    fonts = {
        { "Bitter" },
        { "Literata" },
        { "IBM Plex Serif" }, -- shown once installed; takes the place Rakuten Serif would have had
        { "Source Serif 4" },
        { "Spectral" },
        { "Crimson Pro" },
    },

    -- Extra font folders on the device, read at startup by patches/1-quietui-fonts.lua.
    -- /mnt/onboard/fonts is always included. Folders that don't exist are skipped.
    -- Kobo's built-in fonts (/usr/local/Qt-5.2.1-arm/lib/fonts) are obfuscated, so they can't be used.
    font_folders = {},

    -- Write quietui-fonts.txt to the KOReader folder at each start, listing what the patch found.
    font_report = false,

    -- Top-level folders of the home folder that are not books.
    exclude_folders = {
        ["Exported Annotations"] = true,
        ["Exported Notebooks"] = true,
        ["My Notebooks"] = true,
        ["fonts"] = true,
    },

    -- Stock plugins that stay on. Every other stock plugin is never loaded.
    keep_plugins = {
        coverbrowser = true, -- real covers in the library
        autosuspend = true,  -- sleep after being idle
        autostandby = true,  -- low power between page turns
        kosync = true,       -- reading position sync
        statistics = true,   -- reading time, shown from the cogwheel
        calibre = true,      -- calibre wireless, from the cogwheel
    },

    -- Overall size of every screen, stock ones included. 1 is the design's size; book text isn't affected.
    -- Keep it at 0.9 or above.
    ui_scale = 1,

    -- Books per row in the library's grid. On a smaller screen the covers shrink a little if that
    -- makes room for one more row.
    library_columns = 4,

    -- How heavy buttons and outlines are: "current", "thin", "slim", "open" or "hairline".
    button_style = "hairline",

    hyphenation = false,

    -- The sleep screen enlarges a book's cover at most this many times. Small embedded covers stay
    -- a little smaller with white around them, as their pixels show when enlarged further.
    sleep_cover_max_upscale = 2.5,

    -- KOReader sync server. Leave out for KOReader's public one.
    -- sync_server = "https://example.com",

    -- How long the sheet hides after a top or bottom margin tap, so the change can be seen.
    peek_seconds = 1.5,
}

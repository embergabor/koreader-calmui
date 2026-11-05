-- Quiet UI: rare options. There is deliberately no screen for these on the device.
-- Edit this file over USB and restart KOReader.
return {
    -- Defaults per device model, used until a setting has been changed on the device.
    -- render: "crisp", "smooth" or "book"
    devices = {
        Kobo_condor = { render = "smooth" }, -- Elipsa 2E
        Kobo_io     = { render = "book" },   -- Libra 2
        default     = { render = "smooth" },
    },

    -- What the reader gestures do.
    -- tap: "sheet" or "none"
    -- hold_top_left: "menu" (stock KOReader menus), "exit" (back to the Kobo home screen) or "none"
    gestures = {
        tap = "sheet",
        hold_top_left = "menu",
    },

    -- Font buttons in the Aa sheet, in order: family name, then a replacement used when the
    -- family isn't installed. "Book's own" is always added after these.
    fonts = {
        { "Bitter" },
        { "Literata" },
        { "Rakuten Serif", "IBM Plex Serif" },
        { "Source Serif 4" },
        { "Spectral" },
        { "Crimson Pro" },
    },

    -- Extra font folders on the device, read at startup by patches/1-quietui-fonts.lua.
    -- /mnt/onboard/fonts is always included. Example: { "/usr/local/Kobo/fonts" }
    font_folders = {},

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
    },

    hyphenation = false,

    -- How long the sheet hides after a top or bottom margin tap, so the change can be seen.
    peek_seconds = 1.5,
}

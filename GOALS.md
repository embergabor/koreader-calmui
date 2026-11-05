# KOReader UI: goals and design

Updated 2026-11-05. These replace the earlier direction (tap-centre bars, Light sheet, More menu).
Where the decisions below differ from the goals or design further down, the decisions win.

## Decisions (2026-11-05)

1. No long-press corner (changed after device testing). "Back to Kobo" at the top left of the Library
   exits KOReader. Stock menus aren't reachable from the UI; settings.lua can bring the corner back.
2. One tap anywhere opens the Aa sheet, except on links and footnotes. Swipes turn pages; no tap zones.
3. Kept beyond the design: Contents (our own flat list, nothing collapses), jump to page, long-press
   a word for the dictionary (popup has only the definition and Close).
   Not kept: highlights and notes, search in book.
4. After a top or bottom margin tap, the sheet hides for about 1.5 seconds so the change can be seen.
5. Grid shows real covers, with a drawn cover when a book has none (uses Cover Browser).
6. Author sort shows author headings and series sub-headings. Recent and Title stay flat.
7. Fonts: Bitter, Literata, Source Serif 4, Spectral, Crimson Pro, plus Book's own (see 8). Rakuten
   Serif is on the device but obfuscated, so unusable. IBM Plex Serif shows if installed.
8. Hyphenation is always off. There is no toggle for book fonts: "Book's own" is one of the font
   choices and uses the book's embedded fonts. Publisher styles stay on.
9. New books start from the last settings used, then keep their own per book.
10. Elipsa first, Libra 2 afterwards. Libra 2 page-turn buttons keep turning pages.

Sync: a cogwheel in the Library header opens a small Settings sheet with the sync login. After that
it runs silently (forward without asking, never backward).

After device testing: the opening popup is a card with title and author; the reader's page number sits
in a 56px band; sizes go 12 to 26; dragging up or down the left edge changes brightness live, and the
right edge warmth; Light and Warm have plus and minus buttons, on two rows in the top strip.

Scaling: KOReader sizes its UI by screen width, far too large on the Elipsa. patches/1-quietui-scale.lua
caps it at a Libra 2's physical density (Elipsa: 0.68x; Libra 2 unchanged), for every stock screen.
patches/2-quietui-book-scale.lua keeps book text and margins exactly as they were. The USB storage
screen is a separate program: mods/usbms has it with a smaller font and no logo, program unchanged.

Dictionary: English-English Wiktionary (one language, from KOReader's own catalogue).

Interface font: Source Sans 3, with Noto Sans as the fallback.

Assumed unless changed: Full refresh stays on the Page tab; the library opens at launch; portrait
locked on both devices; Book preset adds +0.5 weight on top of Weight; no Wi-Fi screen, KOReader
updates over USB; only the plugins needed for covers, sleep and sync stay on; mods/ goes into git before
the rewrite.

## Goals (as given)

Goal: KOReader on Kobo Elipsa 2E (also Libra 2), stock Kobo FW,
launched via NickelMenu. Keep the crengine rendering, replace the UI.
Plugin + user patches, no full fork.

Principle: REMOVE, don't hide or overlay. Zen/SimpleUI are the
anti-pattern (renamed nested menus, nav bars, home screens).

Scope:
- Two screens only: library + reader. No home screen, no navbar,
  no widgets.
- No ▸ submenus anywhere on the device UI.
- Reader: centre tap opens the custom Aa sheet (Text / Page tabs) and
  REPLACES the bottom ReaderConfig panel. Direct controls with live
  preview: font (with real previews), size steps, line spacing, weight,
  margins (separate top/bottom), alignment, rendering preset
  (Crisp / Smooth / Book), frontlight.
- Library: one screen; sort/view toggle in the header, no settings page.
- Rare options go in a settings.lua config file, not the UI
  (per-device defaults, gesture map, font folder).
- Escape hatch: long-press in a corner exits koreader back to stock home screen

Removal mechanics:
1. reader/filemanager_menu_order.lua: strict KOMenu:disabled list,
   or patch ReaderMenu:setUpdateItemTable to drop whole tabs.
2. Turn off unused plugins in Plugin management (never loaded).
3. Patch the gesture that opens ReaderConfig so it opens the Aa sheet.

Rendering presets (per device):
- Crisp: mono + hinting
- Smooth: KOReader default (Elipsa default)
- Book: AA, hinting off, slight weight bump, best kerning
  (Libra 2 default)

## Design

Source: https://claude.ai/artifact/1PZXvJefKVGe8wMHGYGhxv (version 1793862494-bd12).
Boards are 702x936, half the Elipsa's 1404x1872.

Library
- Header: "Library", sort Recent / Title / Author, view Grid / List.
- Grid: 4 columns, 3 rows. Cover, title, then 3% / New / Finished.
- List: 66px rows with thumbnail, title, author, progress.

Reader
- No chrome, only a centred "1 / 412" at the bottom.
- Swipe left/right turns the page; there are no tap zones.
- One tap anywhere opens the Aa sheet and Library button. Tap the page or Done to close.

Aa sheet
- Top strip: Library button, title, page number; Light and Warm sliders in 10% steps.
- Bottom panel (420px high): Text / Page tabs and Done.
- Text tab: Size (minus, value with 9 dots, plus). Font: Bitter, Source Serif 4, IBM Plex Serif,
  Spectral, Zilla Slab, Crimson Pro, each in its own face. Weight: Regular / Medium / Bold.
  Rendering: Crisp / Smooth / Book.
- Page tab: Line spacing Tight / Normal / Relaxed / Loose. Alignment Left / Justified.
  Top & bottom margins and Left & right margins, each Narrow / Normal / Wide.
  Full refresh: Every page / Every 6 / Every 12 / Chapters.

Notes on the canvas
- Elipsa, portrait only, right-hand grip. Stylus = finger. No night mode.
- Stock KOReader menus: long-press top-left corner (not designed).

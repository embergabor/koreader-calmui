-- Opens each stock screen still reachable in Calm UI, one per step, to compare scaling.
local UM = require("ui/uimanager")
local Screen = require("device").screen
local u = require("apps/reader/readerui").instance
local step = _G.AUDIT_STEP or 1
if _G.AUDIT_W then UM:close(_G.AUDIT_W); _G.AUDIT_W = nil end
local w
if step == 1 then
    w = require("ui/widget/confirmbox"):new{ text = "Share storage via USB?", ok_text = "Share" }
elseif step == 2 then
    w = require("ui/widget/infomessage"):new{ text = "Could not connect to Wi-Fi network." }
elseif step == 3 then
    w = require("ui/widget/buttondialog"):new{ title = "You've reached the end of the document.\nWhat would you like to do?",
        title_align = "center", buttons = { { { text = "Book status" }, { text = "Go to beginning" } }, { { text = "Close" }, { text = "Mark as finished" } } } }
elseif step == 4 then
    local d = require("ui/widget/inputdialog"):new{ title = "Go to page", input_type = "number", input_hint = "1 / 412",
        buttons = { { { text = "Cancel" }, { text = "Go" } } } }
    w = d; UM:show(d); d:onShowKeyboard(); _G.AUDIT_W = d; _G.AUDIT_STEP = step + 1
    T.log("step", step, "scale", Screen:scaleBySize(1000)); return
elseif step == 5 then
    u.dictionary:onLookupWord("time"); _G.AUDIT_STEP = step + 1; T.log("step", step); return
end
if w then UM:show(w); _G.AUDIT_W = w end
_G.AUDIT_STEP = step + 1
T.log("step", step, "scale", Screen:scaleBySize(1000))

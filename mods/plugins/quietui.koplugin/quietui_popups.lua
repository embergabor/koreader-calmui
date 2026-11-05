--[[--
Every stock popup in this UI's look. Their logic stays KOReader's: the messages, questions and
buttons come from wherever they always did. Only what's drawn changes.

Two layers: a theme for anything built from stock parts (fonts, sizes, hairlines), and our own
layout for the simple message and question boxes, which are a text and some buttons.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Size = require("ui/size")
local UI = require("quietui_ui")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local D = UI.D

local Popups = {}

local CARD_W, CARD_PADDING = 480, 28
local LONG_TEXT = 280 -- characters; longer messages get a wider card

local function cardFrame(content)
    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = D(12),
        bordersize = D(UI.style.border),
        padding = D(CARD_PADDING),
        content,
    }
end

local function innerWidth(text)
    local card = #(text or "") > LONG_TEXT and D(640) or D(CARD_W)
    card = math.min(card, Screen:getWidth() - 2 * D(24))
    return card - 2 * D(UI.style.border) - 2 * D(CARD_PADDING)
end

-- "First sentence.\n\nThe rest." reads as a title and an explanation.
local function questionContent(text, width)
    text = (text or ""):gsub("%s+$", "")
    local title, rest = text:match("^([^\n]+)\n\n(.+)$")
    local group = VerticalGroup:new{ align = "left" }
    if title and #title <= 70 then
        table.insert(group, TextBoxWidget:new{ text = title, face = UI.serif(22, 700), width = width })
        table.insert(group, VerticalSpan:new{ width = D(8) })
        table.insert(group, TextBoxWidget:new{ text = rest, face = UI.sans(16), width = width })
    else
        table.insert(group, TextBoxWidget:new{ text = text, face = UI.serif(20, 700), width = width })
    end
    return group
end

-- The theme -----------------------------------------------------------------

local function applyFonts()
    local SANS, SANS_BOLD = "SourceSans3-Regular.ttf", "SourceSans3-Bold.ttf"
    local SERIF_BOLD = "SourceSerif4-Bold.ttf"
    local fonts = {
        cfont = { SANS, 17 }, ffont = { SANS, 16 }, smallffont = { SANS, 14 }, largeffont = { SANS, 19 },
        tfont = { SERIF_BOLD, 24 }, smalltfont = { SERIF_BOLD, 22 }, x_smalltfont = { SERIF_BOLD, 20 },
        rifont = { SANS, 15 }, pgfont = { SANS, 15 }, hfont = { SANS, 15 },
        infofont = { SANS, 17 }, smallinfofont = { SANS, 16 }, smallinfofontbold = { SANS_BOLD, 16 },
        x_smallinfofont = { SANS, 15 }, xx_smallinfofont = { SANS, 14 },
    }
    for name, font in pairs(fonts) do
        Font.fontmap[name] = font[1]
        Font.sizemap[name] = UI.fontUnits(font[2])
    end
end

local function applySizes()
    local border = D(UI.style.border)
    Size.border.window = border
    Size.border.button = border
    Size.border.inputtext = border
    Size.border.thick = border
    Size.radius.window = D(12)
    Size.radius.button = D(UI.style.radius)
    Size.line.medium = D(UI.style.rule)
    Size.line.thick = D(UI.style.rule)
    FrameContainer.bordersize = border
end

-- Stock buttons in our type, with black hairlines between them.
local function applyButtons()
    local Button = require("ui/widget/button")
    local ButtonTable = require("ui/widget/buttontable")
    local LineWidget = require("ui/widget/linewidget")
    Button.text_font_face = "SourceSans3-Bold.ttf"
    Button.text_font_size = UI.fontUnits(17)
    Button.text_font_bold = false
    ButtonTable.sep_width = D(UI.style.rule)

    local function blacken(node)
        for __, child in ipairs(node) do
            if type(child) == "table" then
                local mt = getmetatable(child)
                if mt and mt.__index == LineWidget then
                    child.background = Blitbuffer.COLOR_BLACK
                else
                    blacken(child)
                end
            end
        end
    end
    local init = ButtonTable.init
    function ButtonTable:init()
        init(self)
        blacken(self)
    end
end

-- Some classes read their fonts when they're first loaded, before this runs.
local function applyLoadedFaces()
    local face = function(name) return Font:getFace(name) end
    local TitleBar = require("ui/widget/titlebar")
    TitleBar.title_face_fullscreen = face("smalltfont")
    TitleBar.title_face_not_fullscreen = face("x_smalltfont")
    TitleBar.subtitle_face = face("xx_smallinfofont")
    TitleBar.info_text_face = face("x_smallinfofont")
    TitleBar.title_h_padding = D(20)
    local ButtonDialog = require("ui/widget/buttondialog")
    ButtonDialog.title_face = face("x_smalltfont")
    ButtonDialog.info_face = face("infofont")
end

-- Our own layouts -----------------------------------------------------------

local function tapAnywhere()
    return { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } } }
end

local function applyInfoMessage()
    local InfoMessage = require("ui/widget/infomessage")
    function InfoMessage:init()
        if self.dismissable then
            if Device:hasKeys() then
                self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
            end
            self.ges_events.TapClose = tapAnywhere()
        end
        local width = innerWidth(self.text)
        local face = self.face or UI.sans(17)
        -- A short message gets a card that fits it.
        if not self.text:find("\n", 1, true) then
            local measure = UI.text(self.text, face)
            width = math.min(width, measure:getSize().w + 1)
            measure:free()
        end
        local text = TextBoxWidget:new{
            text = self.text, face = face, width = width, alignment = self.alignment,
            lang = self.lang, para_direction_rtl = self.para_direction_rtl, auto_para_direction = self.auto_para_direction,
        }
        local limit = self.height or math.floor(Screen:getHeight() * 0.8)
        if self.height or text:getSize().h > limit then
            text:free()
            text = ScrollTextWidget:new{
                text = self.text, face = face, width = width, height = limit, alignment = self.alignment,
                dialog = self, lang = self.lang, para_direction_rtl = self.para_direction_rtl,
                auto_para_direction = self.auto_para_direction,
            }
        end
        self.movable = MovableContainer:new{ cardFrame(text), unmovable = true }
        self[1] = CenterContainer:new{ dimen = Screen:getSize(), self.movable }
        if self.show_delay then
            self.invisible = true
        end
    end
end

local function applyConfirmBox()
    local ConfirmBox = require("ui/widget/confirmbox")
    function ConfirmBox:init()
        if self.dismissable then
            self.ges_events.TapClose = tapAnywhere()
            if Device:hasKeys() then
                self.key_events.Close = { { Device.input.group.Back } }
            end
        end
        local width = innerWidth(self.text)
        self.text_widget_width = width
        self.text_group = questionContent(self.text, width)
        if self._added_widgets then
            table.insert(self.text_group, VerticalSpan:new{ width = D(12) })
            for __, widget in ipairs(self._added_widgets) do
                table.insert(self.text_group, widget)
            end
        end
        local main = { {
            text = self.cancel_text,
            callback = function()
                self.cancel_callback()
                UIManager:close(self)
            end,
        } }
        if not self.no_ok_button then
            table.insert(main, {
                text = self.ok_text,
                selected = true,
                callback = function()
                    self.ok_callback()
                    if not self.keep_dialog_open then UIManager:close(self) end
                end,
            })
        end
        local rows = { main }
        for i, stock_row in ipairs(self.other_buttons or {}) do
            local row = {}
            for __, button in ipairs(stock_row) do
                table.insert(row, {
                    text = button.text,
                    callback = function()
                        if button.callback then button.callback() end
                        if not self.keep_dialog_open then UIManager:close(self) end
                    end,
                })
            end
            table.insert(rows, self.other_buttons_first and i or i + 1, row)
        end
        self.movable = MovableContainer:new{
            cardFrame(VerticalGroup:new{
                align = "left",
                self.text_group,
                VerticalSpan:new{ width = D(22) },
                UI.group(rows, width, UI.H(44)),
            }),
            unmovable = true,
        }
        self[1] = CenterContainer:new{ dimen = Screen:getSize(), self.movable }
    end
    -- Stock takes added widgets back out one by one from the end, which still works here.
end

local function applyMultiConfirmBox()
    local MultiConfirmBox = require("ui/widget/multiconfirmbox")
    function MultiConfirmBox:init()
        if self.dismissable then
            self.ges_events.TapClose = tapAnywhere()
            if Device:hasKeys() then
                self.key_events.Close = { { Device.input.group.Back } }
            end
        end
        local width = innerWidth(self.text)
        local function choice(text, text_func, callback, selected)
            return {
                text = text_func and text_func() or text,
                selected = selected,
                callback = function()
                    callback()
                    UIManager:close(self)
                end,
            }
        end
        self[1] = CenterContainer:new{
            dimen = Screen:getSize(),
            MovableContainer:new{
                cardFrame(VerticalGroup:new{
                    align = "left",
                    questionContent(self.text, width),
                    VerticalSpan:new{ width = D(22) },
                    UI.group({ {
                        choice(self.cancel_text, nil, self.cancel_callback),
                        choice(self.choice1_text, self.choice1_text_func, self.choice1_callback),
                        choice(self.choice2_text, self.choice2_text_func, self.choice2_callback, true),
                    } }, width, UI.H(44)),
                }),
                unmovable = true,
            },
        }
    end
end

-- The Wi-Fi list is stock, without its alternating gray rows, and only as tall as it needs to be.
local function applyNetworkList()
    local NetworkSetting = require("ui/widget/networksetting")
    local init = NetworkSetting.init
    local row_h = UI.H(48)
    for i = 1, 60 do
        local name, value = debug.getupvalue(init, i)
        if not name then break end
        if name == "NetworkItem" then value.height = row_h end
    end
    function NetworkSetting:init()
        self.height = math.min(math.floor(Screen:getHeight() * 0.75), row_h * #self.network_list + D(8))
        init(self)
        self.popup.radius = D(12)
        local list = self.popup[1][2]
        for __, item in ipairs(list.items or {}) do
            item.background = Blitbuffer.COLOR_WHITE
            if item[1] then item[1].background = Blitbuffer.COLOR_WHITE end
        end
    end
end

function Popups.apply()
    applyFonts()
    applySizes()
    applyButtons()
    applyLoadedFaces()
    applyInfoMessage()
    applyConfirmBox()
    applyMultiConfirmBox()
    applyNetworkList()
end

return Popups

-- Run real viewer init with lightweight widget doubles.
local texts, answer_flips, question_flips = {}, 0, 0
local function new(_, spec)
    spec.getSize = function() return {w = 600, h = 60} end
    spec.getHeight = function() return 60 end
    return spec
end
for _, name in ipairs({"ui/bidi", "ui/widget/buttondialog", "ui/widget/buttontable", "ui/widget/container/centercontainer",
    "ui/widget/container/framecontainer", "ui/geometry", "ui/gesturerange", "ui/widget/imagewidget",
    "ui/widget/infomessage", "ui/widget/inputdialog", "ui/widget/container/movablecontainer",
    "ui/widget/notification", "ui/widget/titlebar", "ui/widget/horizontalgroup", "ui/widget/verticalgroup",
    "ui/widget/verticalspan", "ui/rendertext", "ui/widget/container/widgetcontainer"}) do
    package.loaded[name] = {new = new}
end
package.loaded["ui/widget/scrolltextwidget"] = {new = function(_, spec) texts[#texts+1] = spec.text; return new(nil, spec) end}
package.loaded["ui/widget/container/inputcontainer"] = {extend = function(_, spec) return spec end}
package.loaded["ui/size"] = {padding = {large = 10, default = 5}, margin = {small = 2}, radius = {window = 1}}
package.loaded["ffi/blitbuffer"] = {ColorRGB32 = function() return {} end}
package.loaded["ui/font"] = {getFace = function() return {} end}
package.loaded.device = {screen = {getWidth = function() return 800 end, getHeight = function() return 1000 end,
    scaleBySize = function(_, size) return size end}, hasKeys = function() return false end, isTouchDevice = function() return false end}
package.loaded.gettext = function(s) return s end
package.loaded["ui/uimanager"] = {show = function() end}
package.loaded.card_storage = {is_saved = function(card) assert(card.kind == "learn"); return false end}
local Viewer = dofile("AnkiFlashcards.koplugin/card_viewer.lua")
local card = {kind = "learn", question = "QUESTION", answer = "ANSWER", evidence = "QUOTE", explanation = "WHY",
    book_title = "BOOK", book_author = "AUTHOR", chapter = "CHAPTER"}
for _, back in ipairs({false, true}) do
    texts = {}
    local viewer = setmetatable({card = card, show_back = back, on_save = function() end, on_send = function() end,
        on_show_answer = function() answer_flips = answer_flips + 1 end,
        on_show_question = function() question_flips = question_flips + 1 end}, {__index = Viewer})
    viewer:init()
    assert(#viewer.button_table.buttons >= 2 and #viewer.button_table.buttons[1] == 2)
    local flip = viewer.button_table.buttons[2][1]
    assert(flip.id == "flip" and flip.text == (back and "Mostrar pregunta" or "Mostrar respuesta"))
    flip.callback()
    if back then
        viewer.on_show_question = nil
        viewer.update = function(_, _, side) assert(side == false); question_flips = question_flips + 1 end
        flip.callback() -- generic back→front fallback must not call on_show_answer
    end
    assert(#texts == 1)
    if back then
        assert(texts[1]:find("ANSWER", 1, true) and texts[1]:find("QUOTE", 1, true) and texts[1]:find("BOOK", 1, true))
    else
        assert(texts[1]:find("QUESTION", 1, true) and not texts[1]:find("ANSWER", 1, true) and not texts[1]:find("QUOTE", 1, true))
    end
end
assert(answer_flips == 1 and question_flips == 2)
print("PASS: learning viewer shows question only on front; answer/evidence/source on back; Save/Send on both")

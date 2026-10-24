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

local regenerate, dismissed = 0, 0
package.loaded.card_storage.is_saved = function() return false end
for _, back in ipairs({false,true}) do
    local viewer = setmetatable({card={phrase="word"},show_back=back,
        on_regenerate=function() regenerate=regenerate+1 end},{__index=Viewer})
    viewer:init()
    local button=viewer.button_table.buttons[2][3]
    assert(button.id=="regenerate" and button.text=="Regenerar"); button.callback()
end
assert(regenerate==2)
local UI=package.loaded["ui/uimanager"]
UI.setDirty=function() end
UI.close=function(_,widget) widget:onCloseWidget() end
Viewer.new=function(_,spec)
    local viewer=setmetatable(spec,{__index=Viewer}); viewer:init(); return viewer
end
local stream=Viewer:new {card={},generating=true,stream_text="partial",generation_label="Generando tarjeta…",
    on_dismiss=function() dismissed=dismissed+1 end}
assert(#stream.button_table.buttons==1 and #stream.button_table.buttons[1]==1)
assert(stream.button_table.buttons[1][1].text=="Cerrar")
local updated=stream:update()
assert(dismissed==0 and updated.generating and updated.stream_text=="partial")
updated:onClose(); updated:onCloseWidget()
assert(dismissed==1)
print("PASS: Regenerate on both sides, close-only streaming modal, redraw preserves state and real close dismisses exactly once")

local paints, text_updates, scroll_updates = 0, 0, 0
UI.setDirty=function() paints=paints+1 end
local stable=Viewer:new {card={},generating=true,stream_text="",generation_label="Generando tarjeta…"}
stable.scroll_text_w.text_widget={setText=function(_,text)
    text_updates=text_updates+1
    assert(text:find("new content",1,true) or text:find("Reintentando",1,true))
end}
stable.scroll_text_w.updateScrollBar=function() scroll_updates=scroll_updates+1 end
local before=dismissed
stable:update_generation("new content")
assert(text_updates==1 and scroll_updates==1 and paints==1 and not stable._anki_closed and dismissed==before)
stable:update_generation("new content")
assert(text_updates==1 and paints==1, "unchanged visible text must not repaint")
stable:update_generation("", "Reintentando conexión…")
assert(text_updates==2 and scroll_updates==2 and stable.generation_label=="Reintentando conexión…")
stable:onClose()
local after=text_updates
stable:update_generation("late content")
assert(text_updates==after, "dismissed generation must reject late native text updates")
print("PASS: incremental text updates keep one native modal, avoid redundant repaints and ignore late progress")

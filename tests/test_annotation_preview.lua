package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local A = require("annotation_tools")
local queue, shown, dialog, confirm, info, opened, generated = {}, {}, nil, nil, nil, nil, nil
package.loaded.device = {screen = {getWidth = function() return 800 end, getHeight = function() return 1000 end, scaleBySize = function(_, n) return n end}}
package.loaded["ui/size"] = {border = {window = 1}, padding = {button = 5}}
package.loaded["ui/widget/buttondialog"] = {new = function(_, spec) dialog = spec; return spec end}
package.loaded["ui/widget/confirmbox"] = {new = function(_, spec) confirm = spec; return spec end}
package.loaded["ui/widget/infomessage"] = {new = function(_, spec) info = spec.text; return spec end}
package.loaded["ui/widget/textviewer"] = {new = function(_, spec) info = spec.text; return spec end}
package.loaded["ui/uimanager"] = {show = function(_, spec) shown[#shown+1] = spec end, close = function() end,
    scheduleIn = function(_, _, fn) queue[#queue+1] = fn end}
package.loaded["ui/network/manager"] = {runWhenOnline = function(_, fn) fn() end}
local cards = {}
package.loaded.card_storage = {load_cards = function() return cards end}
package.loaded.card_manager = {open_card = function(_, card) opened = card end}
local finish_batch, cancelled = nil, false
package.loaded.annotation_generation = {start = function(_, _, snapshots, kind, done)
    generated = {snapshots = snapshots, kind = kind}; finish_batch = done
    return {cancel = function() cancelled = true end}
end}
local ui = {document = {file = "/book.epub", getProps = function() return {title = "Libro", authors = "Autor"} end},
    annotation = {annotations = {}}}
for i = 1, 9 do ui.annotation.annotations[i] = {text = "Anotación número " .. i, pos0 = "start" .. i, pos1 = "end" .. i, drawer = "lighten"} end
ui.annotation.annotations[3].text = string.rep("Fragmento muy largo áéíóú ", 40)
ui.annotation.annotations[10] = {note = "Una nota personal sin fragmento"}
local first, second = A.capture(ui, ui.annotation.annotations[1]), A.capture(ui, ui.annotation.annotations[2])
cards = {{phrase = "primera", origin_key = first.origin_key}, {kind = "learn", card_id = first.origin_key, phrase = "Pregunta"},
    {phrase = "segunda", origin_key = second.origin_key}}
local Inbox = require("highlight_inbox")
assert(#Inbox.collect(ui) == 10)
Inbox.show(ui, {})
local preview = dialog
assert(#preview.buttons[1] == 3 and preview.buttons[1][3].icon == "check")
assert(preview.buttons[2][3].icon == "plus") -- A Vocab card doesn't count as learning.
assert(preview.title:find("Aprendizaje desde anotaciones", 1, true) and not preview.title:find("Vocab", 1, true))
for i = 1, 6 do
    local row = preview.buttons[i]
    assert(row[1].width == 48 and row[3].width == 52)
    assert(row[1].height == 32 and row[2].height == 32 and row[3].height == 32)
    assert(row[1].font_size == 20 and row[2].font_size == 20)
    assert(row[1].avoid_text_truncation == false and row[2].avoid_text_truncation == false)
    assert(row[1].text == (i == 1 and "☐" or "☑"))
    assert(not row[2].text:find("[V", 1, true) and not row[2].text:find("creada", 1, true))
end
assert(preview.buttons[#preview.buttons][1].text == "Generar seleccionadas (8)")
assert(preview.buttons[#preview.buttons][2].text == "Marcar todas")
preview.buttons[1][3].callback()
assert(opened.kind == "learn" and generated == nil)
preview.buttons[3][2].callback()
assert(info == ui.annotation.annotations[3].text) -- Full text is never lost to truncation.
assert(preview.buttons[#preview.buttons][1].hold_callback == nil)
preview.buttons[#preview.buttons][2].callback()
while #queue > 0 do table.remove(queue, 1)() end
preview = dialog
assert(preview.buttons[#preview.buttons][1].text == "Generar seleccionadas (9)")
preview.buttons[#preview.buttons][2].callback()
while #queue > 0 do table.remove(queue, 1)() end
preview = dialog
assert(preview.buttons[#preview.buttons][1].text == "Generar seleccionadas (0)")
preview.buttons[#preview.buttons][2].callback()
while #queue > 0 do table.remove(queue, 1)() end
preview = dialog
assert(preview.buttons[#preview.buttons][1].text == "Generar seleccionadas (9)")
preview.buttons[#preview.buttons - 1][3].callback()
while #queue > 0 do table.remove(queue, 1)() end
preview = dialog
assert(preview.title:find("2/2", 1, true))
assert(preview.buttons[4][3].enabled == false and preview.buttons[4][1].text == "—")
preview.buttons[4][2].hold_callback()
assert(info:find("nota personal", 1, true))
preview.buttons[#preview.buttons][1].callback()
assert(confirm.text:find("Crear 8 tarjetas de aprendizaje", 1, true) and generated == nil)
assert(not confirm.text:find("Vocab", 1, true) and not confirm.text:find("imágenes", 1, true))
confirm.ok_callback()
assert(generated.kind == "learn" and #generated.snapshots == 9)
dialog.buttons[1][1].callback() -- Cancel progress.
while #queue > 0 do table.remove(queue, 1)() end
assert(cancelled)
finish_batch({generated = 0, existing = 0, invalid = 0, failed = 0, remaining = 9, cancelled = true, cards = {}, errors = {}})
assert(info:find("cancelada", 1, true))
preview = dialog
assert(preview.buttons[#preview.buttons][1].text == "Generar seleccionadas (8)")
preview.buttons[1][3].callback()
assert(confirm.text:find("Crear 1 tarjetas de aprendizaje", 1, true))
print("PASS: learning-only annotations, saved/generate icons, fixed checkbox/text/action cells, pagination and cancellation")

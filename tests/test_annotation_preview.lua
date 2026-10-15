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
ui.annotation.annotations[10] = {note = "Una nota personal sin fragmento"}
local first, second = A.capture(ui, ui.annotation.annotations[1]), A.capture(ui, ui.annotation.annotations[2])
cards = {{phrase = "primera", origin_key = first.origin_key}, {kind = "learn", card_id = first.origin_key, phrase = "Pregunta"},
    {phrase = "segunda", origin_key = second.origin_key}}
local Inbox = require("highlight_inbox")
assert(#Inbox.collect(ui) == 10)
Inbox.show(ui, {})
local preview = dialog
assert(#preview.buttons[1] == 2 and preview.buttons[1][1].width > 400 and preview.buttons[1][2].text == "Ver tarjetas")
assert(preview.buttons[#preview.buttons][1].text == "Generar todas (8)")
assert(preview.buttons[#preview.buttons][2].text == "Desmarcar todas")
preview.buttons[1][2].callback()
assert(dialog.buttons[1][1].text == "Ver Anki Vocab" and dialog.buttons[2][1].text == "Ver Anki Learn")
dialog.buttons[2][1].callback()
assert(opened.kind == "learn" and generated == nil)
preview.buttons[#preview.buttons][2].callback()
while #queue > 0 do table.remove(queue, 1)() end
preview = dialog
assert(preview.buttons[#preview.buttons][1].text == "Generar (0)")
preview.buttons[#preview.buttons][2].callback()
while #queue > 0 do table.remove(queue, 1)() end
preview = dialog
assert(preview.buttons[#preview.buttons][1].text == "Generar todas (8)")
preview.buttons[#preview.buttons - 1][3].callback()
while #queue > 0 do table.remove(queue, 1)() end
preview = dialog
assert(preview.title:find("2/2", 1, true))
assert(preview.buttons[4][2].enabled == false and preview.buttons[4][2].text == "Sin fragmento")
preview.buttons[4][1].hold_callback()
assert(info:find("nota personal", 1, true))
preview.buttons[#preview.buttons][1].callback()
dialog.buttons[1][1].callback() -- Vocab: skips the already-existing second source.
assert(confirm.text:find("Crear 7 tarjetas", 1, true) and generated == nil)
confirm.ok_callback()
assert(generated.kind == "vocab" and #generated.snapshots == 8)
dialog.buttons[1][1].callback() -- Cancel progress.
while #queue > 0 do table.remove(queue, 1)() end
assert(cancelled)
finish_batch({generated = 0, existing = 0, invalid = 0, failed = 0, remaining = 8, cancelled = true, cards = {}, errors = {}})
assert(info:find("cancelada", 1, true))
print("PASS: paged annotation rows, right-side actions, typed status, global selection footer, preview and cancellation")

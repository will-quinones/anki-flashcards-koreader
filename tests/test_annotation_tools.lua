package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
package.loaded.util = {tableDeepCopy = copy}
local A = require("annotation_tools")
local ui = {document = {file = "/book.epub", getProps = function() return {title = "Libro", authors = "Autor"} end},
    annotation = {annotations = {}}}
local previous, writes = {text = "another current selection"}, 0
ui.highlight = {selected_text = previous, saveHighlight = function(self)
    writes = writes + 1
    local annotation = copy(self.selected_text); annotation.drawer = "lighten"
    ui.annotation.annotations[#ui.annotation.annotations+1] = annotation
    return #ui.annotation.annotations
end}
local snapshot = A.capture(ui, {text = "fragmento", pos0 = "start", pos1 = "end"})
assert(A.can_highlight(ui, snapshot) and not A.find_highlight(ui, snapshot))
assert(A.highlight(ui, snapshot))
assert(writes == 1 and ui.highlight.selected_text == previous)
assert(A.highlight(ui, snapshot) and writes == 1)
assert(ui.annotation.annotations[1].text == "fragmento")
local vocab, learn = {phrase = "fragmento"}, {kind = "learn", card_id = snapshot.origin_key, question = "Pregunta"}
A.bind(vocab, snapshot); A.bind(learn, snapshot)
assert(A.find_card(snapshot, "vocab", {learn, vocab}) == vocab)
assert(A.find_card(snapshot, "learn", {vocab, learn}) == learn)
local foreign = {phrase = "fragmento", book_title = "Otro libro", highlight_pos0 = "start", highlight_pos1 = "end"}
assert(not A.find_card(snapshot, "vocab", {foreign}, true))
assert(A.find_card(snapshot, "vocab", {foreign}) == foreign) -- current global vocabulary uniqueness
ui.document.file = "/different.epub"
assert(not A.highlight(ui, snapshot) and writes == 1)
ui.document.file = "/book.pdf"
local pdf = A.capture(ui, {text = "PDF", pos0 = {page = 2, x = 10, y = 20}, pos1 = {page = 2, x = 90, y = 20}, pboxes = {{x = 10}}})
assert(A.highlight(ui, pdf) and writes == 2)
pdf.selection.pos0.x = pdf.selection.pos0.x + 0.000001
assert(A.highlight(ui, pdf) and writes == 2) -- JSON float round-trip does not duplicate PDF highlights
local missing_boxes = A.capture(ui, {text = "PDF", pos0 = {page = 8, x = 10}, pos1 = {page = 8, x = 90}})
assert(not A.can_highlight(ui, missing_boxes))
print("PASS: optional native highlights preserve selections, deduplicate EPUB/PDF and reject the wrong book")

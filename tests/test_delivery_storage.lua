-- luajit tests/test_delivery_storage.lua -- in-memory filesystem, no real notes
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
local blobs, serial = {}, 0
package.loaded.json = {
    encode = function(value) serial = serial + 1; local token = tostring(serial); blobs[token] = copy(value); return token end,
    decode = function(token) return copy(blobs[token]) end,
}
package.loaded.datastorage = {getDataDir = function() return "/fake" end}
local Storage = dofile("AnkiFlashcards.koplugin/card_storage.lua")
local files, failure = {}, false
local real_open, real_rename, real_remove = io.open, os.rename, os.remove
io.open = function(path, mode)
    if mode == "r" then
        if not files[path] then return nil end
        return {read = function() return files[path] end, close = function() return true end}
    end
    if failure then return nil, "disk full" end
    return {write = function(self, data) files[path] = data; return self end, close = function() return true end}
end
os.rename = function(from, to) files[to], files[from] = files[from], nil; return true end
os.remove = function(path) files[path] = nil end
local card = {phrase = "palabra", definition = "Significado", _audio_bytes = "transient"}
assert(Storage.record_sent(card, {note_id = 42, deck = "Spanish", model = "Vocabulary"}))
local cards = Storage.load_cards()
assert(#cards == 1 and cards[1].sent_to_anki and cards[1].anki_note_id == 42)
assert(cards[1]._audio_bytes == nil and cards[1].definition == "Significado")
assert(Storage.record_sent(card, {note_id = 42, deck = "Spanish", model = "Vocabulary"}))
assert(#Storage.load_cards() == 1)
assert(Storage.save_card({phrase = "pendiente", definition = "Otra"}))
assert(Storage.record_sent({phrase = "pendiente"}, {note_id = 43, deck = "Spanish", model = "Vocabulary"}))
cards = Storage.load_cards()
assert(#cards == 2 and cards[2].sent_to_anki and cards[2].definition == "Otra")
failure = true
local pending = {phrase = "fallo"}
local ok, err = Storage.record_sent(pending, {note_id = 44, deck = "Spanish", model = "Vocabulary"})
assert(not ok and err == "disk full" and not pending.sent_to_anki)
assert(#Storage.load_cards() == 2)
failure = false
assert(Storage.import_anki_card({phrase = "importada", definition = "Original", anki_note_id = 100}))
ok, err = Storage.import_anki_card({phrase = "renombrada", definition = "Changed", anki_note_id = 100})
assert(not ok and err == "already_imported")
assert(Storage.find_by_anki_id(100).phrase == "importada")
ok, err = Storage.import_anki_card({phrase = "palabra", anki_note_id = 101})
assert(not ok and err == "phrase_conflict")
failure = true
local incoming = {phrase = "fallo_importacion", anki_note_id = 102}
assert(not Storage.import_anki_card(incoming))
assert(not incoming.sent_to_anki and not Storage.find_by_anki_id(102))
failure = false
local learning = {kind = "learn", card_id = "learn-1234567812345678", phrase = "palabra",
    question = "palabra", answer = "Respuesta", evidence = "Cita", book_title = "Libro"}
assert(Storage.save_card(learning))
assert(Storage.is_saved(learning) and Storage.is_saved("palabra"))
assert(Storage.find_by_phrase("palabra").kind ~= "learn")
assert(Storage.update_card("palabra", {phrase = "palabra", definition = "UPDATED"}))
assert(Storage.find_learning_card(learning.card_id).answer == "Respuesta")
learning.answer = "Respuesta revisada"
assert(Storage.save_learning_card(learning, true))
assert(Storage.record_sent(learning, {note_id = 105, deck = "Libro::Aprendizaje", model = "KOReader Learn"}))
local persisted_learning = Storage.find_learning_card(learning.card_id)
assert(persisted_learning.answer == "Respuesta revisada" and persisted_learning.sent_to_anki)
assert(Storage.find_by_anki_id(42).definition == "UPDATED")
assert(not Storage.save_learning_card(learning, true)) -- sent notes aren't silently overwritten
assert(Storage.import_anki_card({kind = "learn", card_id = "learn-8765432187654321", phrase = "palabra",
    question = "palabra", answer = "Otra idea", anki_note_id = 106}))
io.open, os.rename, os.remove = real_open, real_rename, real_remove
print("PASS: individual sends persist receipts, reconcile saved notes and preserve data on failure")
print("PASS: imports match IDs, preserve phrase conflicts and handle persistence failures")
print("PASS: vocabulary and learning coexist; IDs, edits, receipts and imports stay isolated")

-- luajit tests/test_anki_import.lua; simulated Anki/filesystem, no real data touched.
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local queue, calls, files = {}, {}, {}
local Learn = dofile("AnkiFlashcards.koplugin/learning_card.lua")
local R = require("anki_recovery")
package.loaded.learning_card = Learn
local original = {phrase = "beta", definition = "LOCAL", anki_note_id = 2, image_path = ""}
local local_cards = {[2] = original, [30] = {phrase = "gamma", definition = "KEEP", anki_note_id = 30}}
local lookup_failure = false
package.loaded["ui/uimanager"] = {scheduleIn = function(_, _, callback) queue[#queue+1] = callback end}
package.loaded.datastorage = {getDataDir = function() return "/fake" end}
package.loaded["libs/libkoreader-lfs"] = {
    attributes = function(path) if path == "/fake/.anki_images" then return "directory" end; return files[path] end,
    mkdir = function() return true end,
}
package.loaded.mime = {unb64 = function() return "image-bytes" end}
package.loaded.card_storage = {
    load_cards = function() local cards = {}; for _, card in pairs(local_cards) do cards[#cards+1] = card end; return cards end,
    find_by_anki_id = function(id) return local_cards[id] end,
    find_by_phrase = function(phrase)
        for _, card in pairs(local_cards) do if card.kind ~= "learn" and card.phrase == phrase then return card end end
    end,
    find_learning_card = function(id)
        for _, card in pairs(local_cards) do if card.kind == "learn" and card.card_id == id then return card end end
    end,
    import_anki_card = function(card)
        assert(not local_cards[card.anki_note_id])
        local_cards[card.anki_note_id] = card
        return true
    end,
    attach_import_image = function(id, path) local_cards[id].image_path = path; return true end,
    recovery_patch = function(id, stamp, patch)
        assert(R.stamp(local_cards[id]) == stamp)
        for key, value in pairs(patch) do local_cards[id][key] = value end
        return true
    end,
}
local function note(id, phrase, image)
    return {noteId = id, modelName = "KOReader Vocabulary", cards = {id * 100}, fields = {
        Phrase = {value = phrase}, Definition = {value = "FROM ANKI"},
        ImageFront = {value = image or ""}, Text = {value = "{{c1::" .. phrase .. "}}"},
    }}
end
local notes = {
    [1] = note(1, "alpha", '<img src="safe.png">'),
    [2] = note(2, "beta", '<img src="missing.png">'),
    [3] = note(3, "gamma"), [4] = note(4, ""),
    [5] = note(5, "delta", '<img src="../private.png">'),
}
local learned = {kind = "learn", card_id = "learn-1234567812345678", question = "¿Qué ayuda?", answer = "Preparar el entorno.",
    evidence = "Preparar el entorno facilita empezar.", book_title = "Libro", chapter = "Hábitos"}
notes[6] = {noteId = 6, modelName = Learn.MODEL, cards = {600}, fields = {}}
for key, value in pairs(Learn.fields(learned)) do notes[6].fields[key] = {value = value} end
package.loaded.anki_sync = {source_identity = function() return {profile = "Test", vocabulary_id = 100, learn_id = 200} end,
read = function(_, action, params)
    calls[#calls+1] = action
    if action == "findNotes" then
        assert(params.query == '(note:"KOReader Vocabulary" OR note:"KOReader Learn") tag:KOReader')
        if lookup_failure then return nil, "connection refused" end
        return {1, 2, 3, 4, 5, 6}
    elseif action == "notesInfo" then return {notes[params.notes[1]]}
    elseif action == "cardsInfo" then return {{deckName = "Spanish::Book"}}
    elseif action == "retrieveMediaFile" then
        assert(not params.filename:find("/", 1, true))
        if params.filename == "missing.png" then return false end
        return "encoded"
    else error("Import must be read-only: " .. action) end
end}
local open, rename, remove = io.open, os.rename, os.remove
io.open = function(path) return {write = function(self, bytes) files[path] = bytes; return self end,
    close = function() return true end} end
os.rename = function(from, to) files[to], files[from] = files[from], nil; return true end
os.remove = function(path) files[path] = nil end
local Import = dofile("AnkiFlashcards.koplugin/anki_import.lua")
local config = {url = "http://fake:8765", model = "Vocabulary"}
local function drain()
    while #queue > 0 do table.remove(queue, 1)() end
end
local report
assert(Import.start(config, function(result) report = result end))
assert(not Import.start(config, function() error("Must not start twice") end))
drain()
assert(report.imported == 3 and report.existing == 1 and report.conflicts == 2 and report.failed == 1)
assert(report.image_warnings == 1 and report.processed == 7 and report.missing == 1)
assert(local_cards[6].kind == "learn" and local_cards[6].book_title == "Libro" and local_cards[6].chapter == "Hábitos")
assert(local_cards[1].sent_to_anki and local_cards[1].anki_deck == "Spanish::Book")
assert(files[local_cards[1].image_path] == "image-bytes")
assert(local_cards[1].book_title == "" and not local_cards[1].highlight_pos0)
assert(original.definition == "LOCAL" and local_cards[30].definition == "KEEP")
assert(not local_cards[3] and local_cards[5].image_path == "")
print("PASS: text/images recover with IDs, exact scope, no overwrites and visible conflicts")

assert(Import.start(config, function(result) report = result end))
drain()
assert(report.imported == 0 and report.existing == 4)
print("PASS: repeated recovery is idempotent and retries missing images")
lookup_failure = true
assert(Import.start(config, function(result) report = result end))
drain()
assert(report.failed == 1 and report.errors[1] == "connection refused")
lookup_failure = false
local cancelled_job = assert(Import.start(config, function(result) report = result end))
cancelled_job:cancel()
drain()
assert(report.cancelled and report.processed == 0)
local partial_job
partial_job = assert(Import.start(config, function(result) report = result end,
    function(result) if result.processed == 1 then partial_job:cancel() end end))
drain()
assert(report.cancelled and report.processed == 1)
io.open, os.rename, os.remove = open, rename, remove
print("PASS: network failures, concurrent starts and cancellation preserve completed work")

-- Full recovery/apply flow using real storage with an in-memory filesystem.
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
local files, blobs, serial, queue = {}, {}, 0, {}
local json = {encode = function(value) serial = serial + 1; local token = tostring(serial); blobs[token] = copy(value); return token end,
    decode = function(token) return copy(blobs[token]) end}
package.loaded.json = json
package.loaded.datastorage = {getDataDir = function() return "/fake" end}
package.loaded["ui/uimanager"] = {scheduleIn = function(_, _, callback) queue[#queue+1] = callback end}
package.loaded["libs/libkoreader-lfs"] = {attributes = function(path) return files[path] end, mkdir = function() return true end}
package.loaded.mime = {unb64 = function(value) return value end}
local Storage = require("card_storage")
local R = require("anki_recovery")
local source = {profile = "Will", vocabulary_id = 100, learn_id = 200}
local function note(id, phrase)
    return {noteId = id, modelName = "KOReader Vocabulary", profile = "Will", tags = {"KOReader"}, mod = 1,
        cards = {id * 100}, fields = {Phrase = {value = phrase}, Definition = {value = "Original"}, Text = {value = "{{c1::" .. phrase .. "}}"}}}
end
local notes = {[1] = note(1, "uno"), [2] = note(2, "dos")}
local deck_names = {[100] = "A", [200] = "B"}
local network_failure, swap_on_read = false, false
package.loaded.anki_sync = {
    source_identity = function() return copy(source) end,
    read = function(_, action, params)
        if action == "findNotes" then
            local ids = {}
            for id, remote in pairs(notes) do
                if remote.modelName == "KOReader Vocabulary" and remote.tags[1] == "KOReader" then ids[#ids+1] = id end
            end
            table.sort(ids); return ids
        elseif action == "notesInfo" then
            if network_failure then return nil, "connection failed" end
            if swap_on_read then source.profile = "Other"; swap_on_read = false end
            local value = notes[params.notes[1]]
            return value and {copy(value)} or {{}}
        elseif action == "cardsInfo" then
            local cards = {}; for _, id in ipairs(params.cards) do cards[#cards+1] = {deckName = deck_names[id]} end
            return cards
        elseif action == "retrieveMediaFile" then error("No media expected")
        else error("Recovery must remain read-only: " .. action) end
    end,
}
local real_open, real_rename, real_remove = io.open, os.rename, os.remove
io.open = function(path, mode)
    if mode == "r" or mode == "rb" then
        if not files[path] then return nil end
        return {read = function() return files[path] end, close = function() return true end}
    end
    return {write = function(self, value) files[path] = value; return self end, close = function() return true end}
end
os.rename = function(from, to) files[to], files[from] = files[from], nil; return true end
os.remove = function(path) files[path] = nil; return true end
local Import = require("anki_import")
local cfg = {url = "http://first-ip:8765"}
local function drain() while #queue > 0 do table.remove(queue, 1)() end end
local function scan()
    local report; assert(Import.start(cfg, function(r) report = r end)); drain(); return report
end
local function apply(changes)
    local report; assert(Import.apply_updates(cfg, changes, function(r) report = r end)); drain(); return report
end
local function mutate(id, callback)
    local cards = Storage.load_cards()
    for _, card in ipairs(cards) do if card.anki_note_id == id then callback(card) end end
    files["/fake/anki_flashcards.json"] = json.encode(cards)
end
local report = scan()
assert(report.imported == 2 and report.failed == 0)
assert(scan().imported == 0)
notes[1].cards, deck_names[101] = {100, 101}, "D"
deck_names[100] = "C"
report = scan()
assert(report.moved == 1 and report.changed == 0)
assert(table.concat(Storage.find_by_anki_id(1).anki_decks, ",") == "C,D")
mutate(1, function(card) card.book_title = "Libro local"; card.highlight_pos0 = "xpointer" end)
notes[1].fields.Definition.value, notes[1].mod = "Revisada en Anki", 2
report = scan()
assert(report.changed == 1 and report.conflicts == 0 and #report.changes == 1)
assert(Storage.find_by_anki_id(1).definition == "Original") -- no silent content updates
assert(apply(report.changes).updated == 1)
local updated = Storage.find_by_anki_id(1)
assert(updated.definition == "Revisada en Anki" and updated.book_title == "Libro local" and updated.highlight_pos0 == "xpointer")
assert(scan().changed == 0)
print("PASS: moves/multiple decks reconcile as metadata; remote edits require explicit apply and preserve book provenance")

mutate(1, function(card) card.definition = "Cambio local" end)
notes[1].fields.Definition.value, notes[1].mod = "Otro cambio en Anki", 3
report = scan()
assert(report.conflicts == 1 and report.changes[1].conflict)
mutate(1, function(card) card.definition = "Cambio local posterior" end)
assert(apply(report.changes).updated == 0 and Storage.find_by_anki_id(1).definition == "Cambio local posterior")
report = scan()
notes[1].mod = 4
assert(apply(report.changes).updated == 0)
report = scan()
assert(apply(report.changes).updated == 1) -- explicit per-card resolution of conflict
mutate(1, function(card) card.definition = "Solo en el Kobo" end)
report = scan()
assert(report.local_changed == 1 and #report.changes == 0)
assert(Storage.find_by_anki_id(1).definition == "Solo en el Kobo")
print("PASS: three-way conflicts, local-only edits and stale confirmations never overwrite newer data")

notes[2] = nil
report = scan()
assert(report.missing == 1 and #Storage.load_cards() == 2)
assert(Storage.find_by_anki_id(2).sent_to_anki and Storage.find_by_anki_id(2).anki_sync_state == "missing")
notes[1].tags = {"Other"}
report = scan()
assert(report.out_of_scope == 1 and report.missing == 1)
notes[1].modelName = "Renamed Type"
assert(scan().out_of_scope == 1)
assert(Storage.find_by_anki_id(1).kind ~= "learn")
print("PASS: vanished notes stay local/not requeued; removed tags and renamed types are audited outside the import query")

source.profile = "Other"
report = scan()
assert(report.source_changed and report.imported == 0 and report.missing == 0)
source.profile = "Will"
cfg.url = "http://new-ip:8765"
assert(not scan().source_changed)
source.vocabulary_id = 999
assert(scan().source_changed)
source.vocabulary_id = 100
notes[1].tags, notes[1].modelName = {"KOReader"}, "KOReader Vocabulary"
local before = R.stamp(Storage.find_by_anki_id(1))
swap_on_read = true
assert(scan().source_changed)
assert(R.stamp(Storage.find_by_anki_id(1)) == before)
source.profile = "Will"
network_failure = true
report = scan()
assert(report.failed == 1 and report.missing == 0 and report.incomplete)
network_failure = false
notes[1].fields.Phrase.value, notes[1].mod = "dos", 5
report = scan()
assert(#report.changes == 1 and apply(report.changes).updated == 0)
assert(Storage.find_by_anki_id(1).phrase == "uno")
io.open, os.rename, os.remove = real_open, real_rename, real_remove
print("PASS: profile/type fingerprints, IP changes, mid-scan switches, network failures and phrase collisions are safe")

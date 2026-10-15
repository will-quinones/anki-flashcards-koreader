package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local R = require("anki_recovery")
local source = {profile = "Test", learn_id = 2, vocabulary_id = 1}
local card, note, requests, failure, saves, changed
local function reset()
    card = {kind = "learn", card_id = "local-1", question = "Q", answer = "A", anki_note_id = 42,
        sent_to_anki = true, anki_source = source}
    note = {id = "42", noteType = {id = "2", name = "KOReader Learn"}, fields = {PluginID = "local-1", Question = "Q", Answer = "A"},
        cardIds = {"7", "8"}, modifiedAt = 1}
    requests, failure, saves, changed = {}, nil, 0, 0
end
package.loaded.json = {encode = function(v) return v end, decode = function(v) return v end}
package.loaded.ltn12 = {source = {string = function(v) return v end}, sink = {table = function(v) return v end}}
package.loaded["socket.http"] = {request = function(req)
    local body = req.source
    requests[#requests+1] = body.method
    local result, err
    if failure == body.method then err = {data = {type = "staleSession"}}
    elseif body.method == "collection.get" then result = {profile = source.profile, session = "session-1"}
    elseif body.method == "notes.get" then
        assert(body.params.session == "session-1")
        if failure == "missing" then err = {data = {type = "notFound"}} else result = note end
    elseif body.method == "notes.delete" then
        assert(body.params.session == "session-1" and body.params.ids[1] == "42")
        changed = changed + 1
        result = {items = {{result = {changed = true}}}}
    else error(body.method) end
    req.sink[1] = {result = result, error = err}
    return 1, 200
end}
-- The mock transports table objects instead of JSON strings.
local concat = table.concat
table.concat = function(t, sep, ...)
    if type(t[1]) == "table" then return t[1] end
    return concat(t, sep, ...)
end
package.loaded.anki_sync = {source_identity = function() return source end}
package.loaded.card_storage = {
    load_cards = function() return {card} end,
    recovery_patch = function(id, stamp, patch)
        assert(tostring(id) == "42" and stamp == R.stamp(card))
        saves = saves + 1
        if failure == "disk" then return nil, "disk full" end
        for k, v in pairs(patch) do card[k] = v end
        return true
    end,
}
local Actions = require("anki_note_actions")
local config = {url = "http://localhost:8765"}
reset()
local proof = assert(Actions.prepare_delete(config, card))
assert(changed == 0 and saves == 0 and proof.cards == 2)
assert(Actions.delete_prepared(config, card, proof))
assert(changed == 1 and saves == 2 and card.anki_sync_state == "missing" and card.sent_to_anki and card.anki_note_id == 42)
reset()
proof = assert(Actions.prepare_delete(config, card)); note.fields.Answer = "edited"
assert(not Actions.delete_prepared(config, card, proof) and changed == 0)
reset()
proof = assert(Actions.prepare_delete(config, card)); card.answer = "local edit"
assert(not Actions.delete_prepared(config, card, proof) and changed == 0)
reset()
proof = assert(Actions.prepare_delete(config, card)); failure = "notes.get"
assert(not Actions.delete_prepared(config, card, proof) and changed == 0)
reset()
proof = assert(Actions.prepare_delete(config, card)); failure = "notes.delete"
assert(not Actions.delete_prepared(config, card, proof) and changed == 0 and not card.anki_sync_state)
reset()
proof = assert(Actions.prepare_delete(config, card)); failure = "disk"
assert(not Actions.delete_prepared(config, card, proof) and changed == 0)
reset()
card.anki_source = {profile = "Other", learn_id = 2}
assert(not Actions.prepare_delete(config, card) and changed == 0)
reset()
note.fields.PluginID = "different"
assert(not Actions.prepare_delete(config, card) and changed == 0)
reset()
failure = "missing"
proof = assert(Actions.prepare_delete(config, card))
assert(proof.missing and Actions.delete_prepared(config, card, proof) and changed == 0 and card.anki_sync_state == "missing")
table.concat = concat
-- Live status is read-only toward Anki and repairs only verified receipts.
reset()
local sync = package.loaded.anki_sync
local absent, network, duplicate = false, false, false
sync.read = function(_, method)
    if network then return nil, "offline" end
    if method == "findNotes" then return absent and {} or {42} end
    if method == "notesInfo" then
        if absent then return {{}} end
        local fields = {}; for k,v in pairs(note.fields) do fields[k] = {value = v} end
        local n = {noteId = 42, modelName = "KOReader Learn", fields = fields, cards = {7}}
        return duplicate and {n, n} or {n}
    end
    if method == "cardsInfo" then return {{deckName = "Books::Test"}} end
    error(method)
end
assert(Actions.status(config, card) == "present" and changed == 0)
absent = true
assert(Actions.status(config, card) == "absent" and card.sent_to_anki)
network = true
assert(Actions.status(config, card) == nil)
network, absent = false, false
card.anki_note_id = nil
package.loaded.learning_card = {fields = function() return {Question = "Q", Answer = "A"} end}
package.loaded.card_storage.record_sent = function(c, receipt)
    assert(receipt.deck == "Books::Test" and receipt.source == source)
    c.anki_note_id, c.sent_to_anki = receipt.note_id, true
    return true
end
assert(Actions.status(config, card) == "present" and card.anki_note_id == 42 and changed == 0)
card.anki_note_id, duplicate = nil, true
assert(Actions.status(config, card) == nil and card.anki_note_id == nil)
duplicate = false
note.fields.Answer = "other content"
assert(Actions.status(config, card) == nil and card.anki_note_id == nil)
print("PASS: explicit protected deletion, stale/local/remote/profile guards, disk failures and preserved local copies")
print("PASS: live presence/absence, offline is unknown, exact receipt repair and ambiguous/changed notes rejected")

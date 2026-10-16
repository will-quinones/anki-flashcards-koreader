-- luajit tests/test_send_reconciliation.lua
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local request, response, calls, saved = nil, nil, {}, {}
local scenario, search_count, disk_failure = "existing", 0, false
package.loaded.json = {encode = function(v) request = v; return "request" end,
    decode = function() return response end}
package.loaded.ltn12 = {source = {string = function(s) return s end},
    sink = {table = function(t) return function(s) t[#t+1] = s end end}}
package.loaded.card_storage = {record_sent = function(card, receipt)
    if disk_failure then return false, "disk full" end
    card.sent_to_anki = true
    saved[#saved+1] = receipt
    return true
end}
package.loaded["socket.http"] = {request = function(args)
    calls[#calls+1] = request
    local action = request.action
    if action == "modelNames" then response = {result = {"KOReader Vocabulary"}}
    elseif action == "modelFieldNames" then response = {result = require("note_types").model_params().inOrderFields}
    elseif action == "createDeck" then response = {result = 1}
    elseif action == "findNotes" then
        search_count = search_count + 1
        if scenario == "search_failure" then response = {error = "search unavailable"}
        elseif scenario == "new" or (scenario == "race" and search_count == 1) then response = {result = {}}
        else response = {result = {42}} end
    elseif action == "notesInfo" then
        response = {result = {{noteId = 42, modelName = "KOReader Vocabulary", cards = {84},
            fields = {Phrase = {value = scenario == "similar" and "palabras" or "palabra"}}}}}
    elseif action == "cardsInfo" then
        response = {result = {{deckName = scenario == "child" and "Spanish::Koreader::Child" or "Spanish::Koreader"}}}
    elseif action == "addNote" then
        response = scenario == "race" and {error = "cannot create note because it is a duplicate"} or {result = 99}
    else error("Unexpected action: " .. action) end
    args.sink("response")
    return 1, 200
end}
local Sync = dofile("AnkiFlashcards.koplugin/anki_sync.lua")
local cfg = {url = "http://fake:8765", deck = "Spanish::Koreader", model = "Vocabulary", deck_mode = "configured"}
local function run(kind, expected)
    scenario, search_count, calls, saved = kind, 0, {}, {}
    local card = {phrase = "palabra"}
    local ok, err, receipt = Sync.send_card(cfg, card)
    assert(ok, err)
    assert(receipt.status == expected and card.sent_to_anki and #saved == 1)
    if expected == "existing" then assert(receipt.note_id == 42) else assert(receipt.note_id == 99) end
    return calls
end
local existing_calls = run("existing", "existing")
for _, call in ipairs(existing_calls) do assert(call.action ~= "addNote" and call.action ~= "storeMediaFile") end
run("new", "created")
run("similar", "created") -- similar phrase is not proof of duplicate
run("child", "created") -- deck query includes children; validate exact deck
run("race", "existing") -- lost/racing addNote response reconciles on retry
scenario, search_count = "search_failure", 0
local ok, err = Sync.send_card(cfg, {phrase = "palabra"})
assert(not ok and err == "search unavailable")
scenario, disk_failure, search_count = "existing", true, 0
local card = {phrase = "palabra"}
ok, err = Sync.send_card(cfg, card)
assert(not ok and not card.sent_to_anki and err:find("disk full", 1, true))
print("PASS: existing notes reconcile without re-upload; phrase/model/deck are verified")
print("PASS: duplicate race, search failure and local persistence failure are handled safely")
scenario, disk_failure, search_count, calls = "existing", false, 0, {}
ok, err, receipt = Sync.send_card({url = cfg.url, deck = cfg.deck, model = cfg.model,
    deck_mode = "configured", split_card_types = true}, {phrase = "palabra"})
assert(ok, err)
assert(receipt.status == "existing" and receipt.deck == "Spanish::Koreader")
for _, call in ipairs(calls) do assert(call.action ~= "addNote") end
print("PASS: enabling split decks recognizes vocabulary already in the unsplit parent")
scenario, calls = "child", {}
ok, err, receipt = Sync.send_card({url = cfg.url, deck = cfg.deck, deck_mode = "configured",
    split_card_types = true, vocab_deck_name = "Palabras"}, {phrase = "palabra"})
assert(ok, err)
assert(receipt.status == "existing" and receipt.deck == "Spanish::Koreader::Child")
for _, call in ipairs(calls) do assert(call.action ~= "addNote") end
print("PASS: renaming a typed subdeck recognizes vocabulary already in a sibling subdeck")
for _, kind in ipairs({"existing", "new", "race"}) do
    scenario, search_count, calls, saved = kind, 0, {}, {}
    local pending = {phrase = "palabra"}
    local delivered, err, result = Sync.send_card(cfg, pending, nil, {defer_persistence = true})
    assert(delivered, err)
    assert(result.note_id and #saved == 0 and not pending.sent_to_anki)
end
print("PASS: forked sends return receipts without writing local cards for new, existing or racing notes")

-- luajit tests/test_automatic_note_types.lua; no real collection/network.
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local Types = require("note_types")
local request, reply, created, payload = nil, nil, {}, nil
local models, invalid_schema = {}, false
package.loaded.json = {encode = function(v) request = v; return "body" end, decode = function() return reply end}
package.loaded.ltn12 = {source = {string = function(s) return s end},
    sink = {table = function(t) return function(s) t[#t+1] = s end end}}
package.loaded.card_storage = {record_sent = function() return true end}
package.loaded["socket.http"] = {request = function(args)
    local action = request.action
    if action == "modelNames" then
        local names = {}; for name in pairs(models) do names[#names+1] = name end
        reply = {result = names}
    elseif action == "createModel" then
        local spec = request.params
        assert(spec.modelName == Types.VOCABULARY or spec.modelName == Types.LEARN)
        assert(spec.isCloze == (spec.modelName == Types.VOCABULARY))
        created[#created+1] = spec.modelName
        models[spec.modelName] = spec.inOrderFields
        reply = {result = {id = 1}}
    elseif action == "modelFieldNames" then
        reply = {result = invalid_schema and {"Wrong"} or models[request.params.modelName]}
    elseif action == "createDeck" then reply = {result = 2}
    elseif action == "findNotes" then reply = {result = {}}
    elseif action == "addNote" then payload = request.params.note; reply = {result = 3}
    else error(action) end
    args.sink("result"); return 1, 200
end}
local Sync = require("anki_sync")
local cfg = {url = "http://fake:8765", model = "ignored", anki_model = "ignored", deck = "Lecturas", deck_mode = "book"}
assert(Sync.send_card(cfg, {phrase = "palabra", text = "{{c1::palabra}}", book_title = "Libro"}))
assert(payload.modelName == Types.VOCABULARY and payload.deckName == "Lecturas::Libro")
assert(Sync.send_card(cfg, {kind = "learn", card_id = "learn-1234567812345678", question = "Pregunta", answer = "Respuesta", book_title = "Libro"}))
assert(payload.modelName == Types.LEARN and #created == 2)
assert(Sync.send_card(cfg, {phrase = "otra"}))
assert(#created == 2) -- compatible types are never recreated
cfg.book_parent, cfg.split_card_types = "Estudio::Libros", true
assert(Sync.send_card(cfg, {phrase = "otra", book_title = "Libro"}))
assert(payload.deckName == "Estudio::Libros::Libro::Vocabulario")
cfg.vocab_deck_name, cfg.learn_deck_name = "Palabras", "Ideas"
assert(Sync.send_card(cfg, {phrase = "otra más", book_title = "Libro"}))
assert(payload.deckName == "Estudio::Libros::Libro::Palabras")
assert(Sync.send_card(cfg, {kind = "learn", card_id = "learn-8765432187654321", question = "Otra pregunta", answer = "Otra respuesta", book_title = "Libro"}))
assert(payload.deckName == "Estudio::Libros::Libro::Ideas")
invalid_schema, payload = true, nil
local ok, err = Sync.send_card(cfg, {phrase = "no enviar"})
assert(not ok and err:find("incompatible", 1, true) and payload == nil and #created == 2)
print("PASS: automatic note types and custom Vocab/Learn subdecks route correctly without overwrites")

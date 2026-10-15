-- luajit tests/test_learning_anki.lua -- no real collection/network touched.
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local Learn = dofile("AnkiFlashcards.koplugin/learning_card.lua")
package.loaded.learning_card = Learn
local request, response, calls = nil, nil, {}
local model_exists, existing, conflict, incompatible = false, false, false, false
local saved, search_query, sent_note
package.loaded.json = {encode = function(v) request = v; return "body" end, decode = function() return response end}
package.loaded.ltn12 = {source = {string = function(s) return s end},
    sink = {table = function(t) return function(s) t[#t+1] = s end end}}
package.loaded.card_storage = {record_sent = function(card, receipt) saved = receipt; card.sent_to_anki = true; return true end}
local card = {kind = "learn", card_id = "learn-1234567812345678", question = "¿Qué ayuda?", answer = "Preparar <el entorno>.",
    evidence = "Preparar el entorno facilita empezar.", book_title = "Libro", book_author = "Autor"}
package.loaded["socket.http"] = {request = function(args)
    local action = request.action
    calls[#calls+1] = action
    if action == "getActiveProfile" then response = {result = "Will"}
    elseif action == "modelNamesAndIds" then response = {result = {[Learn.MODEL] = 222, ["KOReader Vocabulary"] = 111}}
    elseif action == "modelNames" then response = {result = model_exists and {Learn.MODEL} or {"Vocabulary"}}
    elseif action == "createModel" then
        assert(request.params.modelName == Learn.MODEL and not request.params.isCloze)
        assert(request.params.inOrderFields[1] == "PluginID")
        model_exists = true; response = {result = {id = 1}}
    elseif action == "modelFieldNames" then response = {result = incompatible and {"Question"} or Learn.FIELDS}
    elseif action == "createDeck" then
        assert(request.params.deck == "Spanish::Libro::Aprendizaje")
        response = {result = 2}
    elseif action == "findNotes" then
        search_query = request.params.query
        response = {result = existing and {99} or {}}
    elseif action == "notesInfo" then
        local fields = Learn.fields(card)
        response = {result = {{noteId = 99, modelName = Learn.MODEL, cards = {999}, fields = {
            PluginID = {value = fields.PluginID}, Question = {value = conflict and "Different question" or fields.Question},
            Answer = {value = fields.Answer},
        }}}}
    elseif action == "cardsInfo" then response = {result = {{deckName = "OldDeck"}}}
    elseif action == "addNote" then
        sent_note = request.params.note
        assert(sent_note.modelName == Learn.MODEL and sent_note.fields.PluginID == card.card_id)
        assert(sent_note.fields.Answer == "Preparar &lt;el entorno&gt;.")
        assert(sent_note.tags[1] == "KOReader" and sent_note.tags[2] == "KOReader::Learn" and #sent_note.tags == 2)
        response = {result = 99}
    else error("Learning must not upload media or generate TTS: " .. action) end
    args.sink("response")
    return 1, 200
end}
local Sync = dofile("AnkiFlashcards.koplugin/anki_sync.lua")
local config = {url = "http://fake:8765", deck = "Spanish::Koreader", split_card_types = true,
    tags = {"KOReader"}, tts_enabled = true, elevenlabs_api_key = "fake"}
local ok, err = Sync.send_card(config, card, config)
assert(ok, err)
assert(saved.model == Learn.MODEL and saved.deck == "Spanish::Libro::Aprendizaje")
assert(calls[1] == "modelNames" and calls[2] == "createModel")
assert(search_query == 'note:"KOReader Learn" "PluginID:learn-1234567812345678"')
local note = {noteId = 99, modelName = Learn.MODEL, fields = {}}
for key, value in pairs(sent_note.fields) do note.fields[key] = {value = value} end
local recovered = assert(Learn.from_note(note))
assert(recovered.kind == "learn" and recovered.answer == card.answer and recovered.book_title == "Libro")
print("PASS: learning model auto-creation, escaped fields, split deck and import round-trip")

existing, calls = true, {}
ok, err = Sync.send_card(config, card, config)
assert(ok, err)
assert(saved.deck == "OldDeck")
for _, action in ipairs(calls) do assert(action ~= "addNote" and action ~= "createModel") end
conflict = true
assert(not Sync.send_card(config, card, config))
incompatible = true
calls = {}
assert(not Sync.send_card(config, card, config))
for _, action in ipairs(calls) do assert(action ~= "addNote" and action ~= "createModel") end
print("PASS: stable ID prevents duplicates across deck changes; conflicts never overwrite notes/models")
card.anki_source = {profile = "Other", vocabulary_id = 111, learn_id = 222}
calls = {}
local ok, reason = Sync.send_card(config, card, config)
assert(not ok and reason:find("otro perfil", 1, true))
for _, action in ipairs(calls) do assert(action == "getActiveProfile" or action == "modelNamesAndIds") end
card.anki_source.profile, incompatible, conflict = "Will", false, false
assert(Sync.send_card(config, card, config))
assert(saved.source.profile == "Will")
print("PASS: linked cards cannot accidentally send to another profile/origin")

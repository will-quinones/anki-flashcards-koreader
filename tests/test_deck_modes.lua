-- Run from repository root: luajit tests/test_deck_modes.lua
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
-- Exercise send_card with fake HTTP/JSON transport, without touching Anki.
local calls, request, reply, fail_create, fail_network, invalid_reply = {}, nil, nil, false, false, false
local auth_error = false
package.loaded.json = {
    encode = function(value) request = value; return "request" end,
    decode = function() return reply end,
}
package.loaded.ltn12 = {
    source = {string = function(body) return body end},
    sink = {table = function(response) return function(chunk) response[#response+1] = chunk end end},
}
local decks = {}
package.loaded.card_storage = {record_sent = function(card, receipt)
    card.sent_to_anki = true
    return true
end}
package.loaded["socket.http"] = {
    request = function(params)
        calls[#calls+1] = request
        if fail_network then return nil, "timeout" end
        if request.action == "modelNames" then reply = {result = {"KOReader Vocabulary"}}
        elseif request.action == "modelFieldNames" then reply = {result = require("note_types").model_params().inOrderFields}
        elseif request.action == "createDeck" then
            local name = request.params.deck
            if fail_create then reply = {error = "permission denied"}
            elseif invalid_reply then reply = {}
            else
                decks[name] = decks[name] or 123
                reply = {result = decks[name]}
            end
        elseif request.action == "findNotes" then
            reply = {result = {}}
        elseif request.action == "version" then
            reply = auth_error and {error = "valid api key must be provided"} or {result = 6}
        else
            assert(request.action == "addNote")
            assert(decks[request.params.note.deckName], "Destination must exist before addNote")
            reply = {result = 456}
        end
        params.sink("response")
        return 1, 200
    end,
}
local sync = dofile("AnkiFlashcards.koplugin/anki_sync.lua")
local function send(mode, title, expected)
    calls = {}
    assert(sync.send_card({url = "http://fake:8765", deck = "Spanish::Koreader",
        model = "Vocabulary", deck_mode = mode}, {phrase = "palabra", book_title = title}))
    assert(#calls == 5)
    assert(calls[3].action == "createDeck" and calls[3].params.deck == expected)
    assert(calls[4].action == "findNotes")
    assert(calls[5].params.note.deckName == expected)
end
send("configured", "Los códigos secretos", "Spanish::Koreader")
send("book", "Los códigos secretos", "Spanish::Los códigos secretos")
send(nil, "Los códigos secretos", "Spanish::Los códigos secretos")
send("book", "  Libro: Parte 2  ", "Spanish::Libro - Parte 2")
send("book", nil, "Spanish::Koreader")
send("book", "", "Spanish::Koreader")
send("book", "   ", "Spanish::Koreader")
send("configured", nil, "Spanish::Koreader")
send("book", "Los códigos secretos", "Spanish::Los códigos secretos") -- existing deck
print("PASS: both deck modes, legacy default, fallback titles, sanitization, existing decks")

fail_create, calls = true, {}
local ok, err = sync.send_card({url = "http://fake:8765"}, {phrase = "word"})
assert(not ok and err:find("permission denied") and #calls == 3)
fail_create, fail_network, calls = false, true, {}
ok, err = sync.send_card({url = "http://fake:8765"}, {phrase = "word"})
assert(not ok and err:find("Cannot reach Anki") and #calls == 1)
fail_network, invalid_reply, calls = false, true, {}
ok, err = sync.send_card({url = "http://fake:8765"}, {phrase = "word"})
assert(not ok and err:find("invalid response") and #calls == 3)
print("PASS: creation/network failures stop before media upload and note creation")
invalid_reply = false
assert(sync.test_connection("http://fake:8765"))
auth_error = true
ok, err = sync.test_connection("http://fake:8765")
assert(not ok and err == "valid api key must be provided")
print("PASS: connection check uses a real action and reports authentication errors")

local dialog, saved
package.loaded.gettext = function(text) return text end
for _, name in ipairs({"ui/widget/buttondialog", "ui/widget/inputdialog", "ui/widget/notification"}) do
    package.loaded[name] = {new = function(_, spec) return spec end}
end
package.loaded["ui/uimanager"] = {
    show = function(_, spec) dialog = spec end,
    close = function() end,
}
package.loaded.anki_sync = sync
package.loaded.card_sync = {}
package.loaded.card_storage = {
    load_anki_settings = function() return saved end,
    save_anki_settings = function(config) saved = config; return true end,
}
local settings = dofile("tests/fixtures/legacy_settings.lua")
local function button(prefix)
    for _, row in ipairs(dialog.buttons) do
        for _, item in ipairs(row) do
            if item.text:sub(1, #prefix) == prefix then return item end
        end
    end
    error("Missing button: " .. prefix)
end
settings.show({anki = {deck = "Spanish::Koreader"}})
button("Anki Connection").callback()
assert(button("Deck organization:").text:find("By book"))
button("Deck organization:").callback()
assert(saved.deck_mode == "configured" and saved.deck == "Spanish::Koreader")
assert(button("Deck organization:").text:find("Configured deck"))
-- Simulate reopening the settings: saved choice wins over file default.
settings.show({anki = {deck_mode = "book", deck = "Spanish::Koreader"}})
button("Anki Connection").callback()
assert(button("Deck organization:").text:find("Configured deck"))
button("Deck organization:").callback()
assert(saved.deck_mode == "book")
print("PASS: settings toggle both modes and persist the choice across reopenings")

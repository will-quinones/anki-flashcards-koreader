-- luajit tests/test_bulk_send.lua
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local messages, menu = {}, nil
local cards = {{phrase = "nueva"}, {phrase = "existente"},
    {phrase = "enviada", sent_to_anki = true}, {phrase = "fallo"},
    {phrase = "borrada", sent_to_anki = false, anki_note_id = 99, anki_sync_state = "missing"}}
package.loaded.gettext = function(s) return s end
for _, name in ipairs({"ui/widget/buttondialog", "ui/widget/confirmbox", "ui/widget/notification", "ui/widget/infomessage"}) do
    package.loaded[name] = {new = function(_, spec) return spec end}
end
package.loaded["ui/widget/menu"] = {new = function(_, spec) menu = spec; return spec end}
package.loaded["ui/uimanager"] = {show = function(_, spec) if spec.text then messages[#messages+1] = spec.text end end}
for _, name in ipairs({"ui/event", "card_generator", "card_viewer", "image_generator", "ui/network/manager", "settings_viewer"}) do
    package.loaded[name] = {}
end
package.loaded.card_storage = {load_cards = function() return cards end,
    load_anki_settings = function() return {anki_model = "KOReader Vocabulary"} end,
    mark_sent = function() error("Only the central send path should persist receipts") end}
package.loaded.anki_sync = {send_card = function(config, card)
    assert(config.url == "http://fake:8765")
    if card.phrase == "fallo" then return nil, "network error" end
    assert(not card.sent_to_anki)
    card.sent_to_anki = true
    return true, nil, {status = card.phrase == "existente" and "existing" or "created"}
end}
package.loaded.anki_import = {}
package.loaded.learning = {}
package.loaded.card_sync = {}
local Manager = dofile("AnkiFlashcards.koplugin/card_manager.lua")
local actions = Manager.menu_items({anki = {url = "http://fake:8765"}})
assert(menu == nil and Manager.show_manage == nil) -- No legacy Manage widget/API.
for _, item in ipairs(actions) do
    assert(not item.text:find("Settings", 1, true))
    assert(not item.text:find("Stats", 1, true))
end
for _, item in ipairs(actions) do
    if item.text == "Enviar todas las pendientes a Anki" then item.callback() end
end
assert(#messages == 1)
assert(messages[1]:find("1 nuevas enviadas", 1, true))
assert(messages[1]:find("1 ya estaban en Anki", 1, true))
assert(messages[1]:find("1 ya marcadas como enviadas", 1, true))
assert(messages[1]:find("1 pendientes por error", 1, true))
assert(messages[1]:find("fallo: network error", 1, true))
assert(messages[1]:find("1 requieren revisión; no reenviadas", 1, true))
assert(not cards[4].sent_to_anki)
print("PASS: bulk send skips sent notes and reports existing/new/failures in one summary")

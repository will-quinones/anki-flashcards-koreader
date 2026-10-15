-- Run from repository root: luajit tests/test_local_ux.lua
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
-- No device, network calls or API keys required.
local plugin_dir = "AnkiFlashcards.koplugin/"
local function stub(name, value) package.loaded[name] = value or {} end
for _, name in ipairs({ "ssl.https", "socket.http", "ltn12", "json", "mime" }) do
    stub(name)
end
stub("datastorage", { getDataDir = function() return "." end })
local images = dofile(plugin_dir .. "image_generator.lua")
local function unexpected() error("Disabled images must not invoke callbacks") end
for _, config in ipairs({ {}, {image_provider = ""}, {image_provider = "none"},
                          {image_provider = false} }) do
    assert(not images.is_enabled(config))
    images.generate_async(config, nil, "word", unexpected, unexpected)
end
images.generate_async(nil, nil, "word", unexpected, unexpected)
assert(images.is_enabled({image_provider = "gemini"}))
local err
images.generate_async({image_provider = "typo"}, "prompt", "word", unexpected,
    function(message) err = message end)
assert(err == "Unknown image provider: typo")
print("PASS: disabled images are silent; unknown configured providers still report errors")

stub("image_generator", images)
stub("configuration", { target_language = "Spanish", image_provider = "none" })
stub("device", {hasClipboard = function() return true end})
stub("gettext", function(text) return text end)
stub("ui/widget/container/inputcontainer", {new = function(_, object) return object end})
for _, name in ipairs({ "ui/widget/infomessage", "ui/widget/notification" }) do
    stub(name, { new = function(_, object) return object end })
end
local status_messages = {}
stub("ui/uimanager", { scheduleIn = function() end, show = function(_, spec)
    if spec.text then status_messages[#status_messages+1] = spec.text end
end })
stub("ui/network/manager", {runWhenOnline = function(_, callback) callback() end})
stub("selection_context", function(_, text) return text end)
stub("card_storage", {load_anki_settings = function() return nil end, load_cards = function() return {} end})
for _, name in ipairs({"card_generator", "card_viewer", "anki_sync", "card_sync",
                       "highlight_inbox", "audio_generator"}) do stub(name) end
local managed, listed = 0, 0
stub("card_manager", {
    menu_items = function() return {{text = "Send", callback = function() managed = managed + 1 end}} end,
    show = function() listed = listed + 1 end,
    show_stats = function() end,
})
stub("settings_viewer", {menu_items = function() return {} end})
stub("settings_state", dofile(plugin_dir .. "settings_state.lua"))
local learning_started = 0
stub("learning", {start = function() learning_started = learning_started + 1 end})
stub("highlight_menu", {install = function() return false end})
local plugin = dofile(plugin_dir .. "main.lua")
local registered = 0
local menu = { registerToMainMenu = function() registered = registered + 1 end }
local function instance(ui)
    return setmetatable({ui = ui}, {__index = plugin})
end
local browser = instance({menu = menu})
browser:init()
local items = {}
browser:addToMainMenu(items)
assert(registered == 1 and items.ankiflashcards.sorting_hint == "tools")
assert(items.ankiflashcards.sub_item_table[1].sub_item_table_func)
local card_items = items.ankiflashcards.sub_item_table[2].sub_item_table_func()
card_items[1].callback()
card_items[2].callback()
assert(managed == 1 and listed == 1)
print("PASS: Tools menu works from file browser without a document")

local buttons, dict_buttons = {}, {}
local highlight_saved, popup_closed = 0, false
local selection = { text = "palabra", pos0 = "start", pos1 = "end" }
local highlight = {
    selected_text = selection,
    addToHighlightDialog = function(_, id, callback) buttons[id] = callback end,
    saveHighlight = function() highlight_saved = highlight_saved + 1 end,
    onClose = function(self) self.selected_text = nil end,
}
local reader = instance({
    menu = menu, highlight = highlight,
    dictionary = {addToDictButtons = function(_, spec) dict_buttons[spec.id] = spec end},
    document = { getProps = function() return {title = "Libro", authors = "Autor"} end },
})
reader:init()
local dict_button = dict_buttons.ankiflashcards_card
assert(buttons.ankiflashcards_4 and dict_button)
assert(buttons.ankiflashcards_4(highlight).text == "Anki Vocab")
assert(buttons.ankiflashcards_5(highlight).text == "Anki Learn")
assert(dict_buttons.ankiflashcards_learn.text == "Anki Learn")
local popup = {highlight = highlight, onClose = function(_, preserve)
    assert(preserve)
    popup_closed = true
end}
assert(dict_button.conditional and dict_button.show_func(popup))
assert(not dict_button.show_func({is_wiki = true, highlight = highlight}))
dict_button.callback(popup)
assert(status_messages[#status_messages] == "Generando tarjeta…")
assert(popup_closed and highlight_saved == 0)
assert(not dict_button.show_func(popup)) -- selection was consumed by card action
highlight.selected_text = selection
buttons.ankiflashcards_4(highlight).callback()
assert(highlight_saved == 0) -- highlighting is now optional in the card preview
dict_buttons.ankiflashcards_learn.callback(popup)
assert(learning_started == 1)
print("PASS: single-word dictionary action preserves selection without forcing a highlight")

-- Older KOReader versions without dictionary extension API still load normally.
local legacy = instance({menu = menu, highlight = highlight, dictionary = {}})
legacy:init()
print("PASS: missing dictionary extension API does not prevent plugin initialization")

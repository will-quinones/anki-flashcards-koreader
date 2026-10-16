-- luajit tests/test_friendly_settings.lua; native menu + simulated storage/UI.
local State = dofile("AnkiFlashcards.koplugin/settings_state.lua")
assert(State.normalize_url(" 192.168.50.213 ") == "http://192.168.50.213:8765")
assert(State.normalize_url("computer.local:9000") == "http://computer.local:9000")
for _, value in ipairs({"", "localhost", "127.0.0.1", "0.0.0.0", "host/path", "http://host:99999"}) do
    assert(not State.normalize_url(value))
end
assert(not State.has_key("YOUR_GEMINI_API_KEY") and not State.has_key("PENDIENTE_KEY"))
local legacy = State.merge({model = "qwen-plus"}, {model = "MyNote"})
assert(legacy.model == "qwen-plus" and legacy.anki_model == "MyNote")
assert(State.persistable(legacy).anki_model == nil)
local modern = State.persistable({model = "qwen-custom", gemini_api_key = "preserve"})
assert(State.merge({}, modern).model == "qwen-custom" and State.merge({}, modern).anki_model == nil)
local empty_model = State.merge({model = ""}, {settings_version = 2, model = "", split_card_types = "false"})
assert(empty_model.model == nil and not empty_model.split_card_types)
assert(State.book_parent({deck = "Spanish::Koreader"}) == "Spanish")
local tags = State.extra_tags({"KOReader", "ideas", "Ideas", "desarrollo personal", "KOReader::Learn"})
assert(#tags == 2 and tags[1] == "ideas" and tags[2] == "desarrollo_personal")

local menu, input, multi, notice, confirm, saved, fail_save = nil, nil, nil, nil, nil, nil, false
package.loaded.gettext = function(s) return s end
package.loaded.settings_state = State
local selected_server, baseline_resets = nil, 0
package.loaded.card_sync = {
    choose_cloud_server = function(_, callback) selected_server = callback end,
    reset_baseline = function() baseline_resets = baseline_resets + 1 end,
    run_sync = function() error("Settings must not start a sync") end,
}
package.loaded.card_storage = {
    load_anki_settings = function() return saved end,
    save_anki_settings = function(cfg) if fail_save then return false, "disk full" end; saved = cfg; return true end,
}
package.loaded.anki_sync = {test_connection = function() return nil, "valid api key must be provided" end}
package.loaded["ui/widget/menu"] = {new = function() error("Use the native menu, not another modal") end}
package.loaded["ui/widget/infomessage"] = {new = function(_, spec) notice = spec.text; return spec end}
package.loaded["ui/widget/confirmbox"] = {new = function(_, spec) confirm = spec; return spec end}
package.loaded["ui/widget/inputdialog"] = {new = function(_, spec)
    input = spec; spec.getInputText = function() return spec.value or spec.input end
    spec.onShowKeyboard = function() end; return spec
end}
package.loaded["ui/widget/multiinputdialog"] = {new = function(_, spec)
    multi = spec
    spec.getFields = function() return spec.values or {spec.fields[1].text, spec.fields[2].text} end
    spec.onShowKeyboard = function() end
    return spec
end}
package.loaded["ui/uimanager"] = {show = function() end, close = function() end,
    scheduleIn = function(_, _, fn) fn() end}
local Settings = dofile("AnkiFlashcards.koplugin/settings_viewer.lua")
local stack, touchmenu = {}, {updateItems = function() end}
local function open(config) stack = {}; menu = Settings.menu_items(config) end
local function back() menu = table.remove(stack); assert(menu) end
local function find(prefix)
    for _, item in ipairs(menu) do
        local text = item.text_func and item.text_func() or item.text
        if text:sub(1, #prefix) == prefix then return item end
    end
    error("Missing native item: " .. prefix)
end
local function click(prefix)
    local item = find(prefix)
    assert(not item.enabled_func or item.enabled_func(), "Disabled item: " .. prefix)
    if item.sub_item_table_func then stack[#stack+1] = menu; menu = item.sub_item_table_func()
    else item.callback(touchmenu) end
end
local config = {text_provider = "gemini", gemini_api_key = "test-secret", model = "qwen-plus",
    anki = {deck = "Spanish::Koreader", model = "KOReader Vocabulary", tags = {"KOReader"}}}
open(config)
assert(#menu == 6)
local function inspect(items)
    for _, item in ipairs(items) do
        local text = item.text_func and item.text_func() or item.text
        assert(not text:find("test-secret", 1, true))
        assert(not text:find("Tipo de nota:", 1, true) and not text:find("Stats", 1, true))
        assert(text ~= "Sincronizar ahora" and text ~= "Enviar todas las pendientes a Anki")
        if item.sub_item_table_func then inspect(item.sub_item_table_func()) end
    end
end
inspect(menu)
assert(not saved) -- browsing/searching the tree is side-effect free
click("Conexión con Anki")
click("Dirección del ordenador:")
input.value = "localhost"; input.buttons[1][2].callback()
assert(not saved and notice:find("no localhost", 1, true))
input.value = "192.168.50.213"; input.buttons[1][2].callback()
assert(saved.url == "http://192.168.50.213:8765" and saved.gemini_api_key == "test-secret")
assert(saved.anki_model == nil and config.anki.model == nil and config.model == "qwen-plus")
click("Comprobar conexión"); assert(notice:find("valid api key", 1, true))
print("PASS: native task groups, no editable note types/operational actions; keys preserved")

open(config); click("Barajas y envío"); click("Organización:"); click("Por libro y tipo")
local before_names = saved
assert(multi.fields[1].text == "Vocabulario" and multi.fields[2].text == "Aprendizaje")
assert(not saved.split_card_types) -- choosing alone does not partially apply settings
multi.buttons[1][1].callback()
assert(saved == before_names)
click("Por libro y tipo")
multi.values = {"", "Ideas"}; multi.buttons[1][2].callback()
assert(saved == before_names and notice:find("vacíos", 1, true))
multi.values = {"Ideas", "ideas"}; multi.buttons[1][2].callback()
assert(saved == before_names and notice:find("distintos", 1, true))
multi.values = {"Palabras::Inglés", "Ideas"}; multi.buttons[1][2].callback()
assert(saved == before_names and notice:find("sin ::", 1, true))
multi.values = {" Palabras ", " Ideas "}; multi.buttons[1][2].callback()
assert(saved.deck_mode == "book" and saved.split_card_types)
assert(saved.vocab_deck_name == "Palabras" and config.anki.learn_deck_name == "Ideas")
back(); click("Deck Padre:")
assert(input.input == "Spanish")
input.value = "Lecturas::Desarrollo"; input.buttons[1][2].callback()
assert(saved.book_parent == "Lecturas::Desarrollo" and config.anki.book_parent == saved.book_parent)
click("Etiquetas adicionales:"); input.value = "KOReader, ideas, desarrollo personal"; input.buttons[1][2].callback()
assert(#saved.tags == 2 and saved.tags[2] == "desarrollo_personal")
click("Enviar pendientes automáticamente"); assert(saved.auto_send_wifi)
click("Organización:"); click("Una sola baraja"); back()
assert(not saved.split_card_types and saved.deck_mode == "configured")
assert(find("Baraja:").text_func():find("Spanish::Koreader", 1, true))
click("Organización:"); click("Por tipo de tarjeta")
assert(multi.fields[1].text == "Palabras" and multi.fields[2].text == "Ideas")
local unchanged = saved
fail_save = true
multi.values = {"Nuevas palabras", "Nuevas ideas"}; multi.buttons[1][2].callback()
assert(saved == unchanged and not saved.split_card_types and saved.vocab_deck_name == "Palabras")
fail_save = false
multi.buttons[1][1].callback()
assert(not saved.split_card_types)
back()
print("PASS: organization naming is atomic/validated, Deck Padre label, retained names and send preferences")

assert(State.merge({}, {}).highlight_on_save == false)
assert(State.merge({}, {highlight_on_generate=true}).highlight_on_save == true)
assert(State.merge({}, {highlight_on_generate=true,highlight_on_save=false}).highlight_on_save == false)
assert(State.merge({}, {highlight_on_generate=true}).highlight_on_generate == nil)
open(config); click("Generación de tarjetas")
local highlight_option = find("Subrayar al guardar tarjeta")
assert(not highlight_option.checked_func())
click("Subrayar al guardar tarjeta")
assert(saved.highlight_on_save == true and config.highlight_on_save == true)
fail_save = true; click("Subrayar al guardar tarjeta"); fail_save = false
assert(highlight_option.checked_func() and saved.highlight_on_save == true)
click("Subrayar al guardar tarjeta")
assert(saved.highlight_on_save == false and config.highlight_on_save == false)
assert(saved.gemini_api_key == "test-secret")
print("PASS: save highlight checkbox migrates the old preference, persists explicit on/off, preserves keys and never applies failed saves")

open(config); click("Generación de tarjetas"); click("Servicio:"); click("OpenRouter"); back()
click("Cuenta y modelo"); click("Clave API:")
assert(input.text_type == "password" and input.title:find("OpenRouter", 1, true))
input.value = "router-secret"; input.buttons[1][2].callback()
assert(saved.openrouter_api_key == "router-secret" and saved.gemini_api_key == "test-secret")
click("Modelo de IA:"); input.value = ""; input.buttons[1][2].callback()
assert(saved.openrouter_model == "anthropic/claude-3-haiku")
click("Clave API:"); input.value = ""; input.buttons[1][2].callback()
assert(confirm and saved.openrouter_api_key == "router-secret")
confirm.ok_callback(); assert(saved.openrouter_api_key == "" and saved.gemini_api_key == "test-secret")
print("PASS: provider/credentials/model together, masked keys and confirmation before deletion")

open(config); click("Extras de vocabulario"); click("Imágenes")
assert(not find("Cuenta y modelo").enabled_func())
click("Servicio:"); click("Google Gemini"); back(); click("Cuenta y modelo"); click("Clave API:")
assert(input.input == "test-secret")
input.buttons[1][1].callback()
open(config); click("Extras de vocabulario"); click("Audio"); click("Añadir pronunciación")
assert(not saved.tts_enabled and notice:find("Cuenta y voz", 1, true))
click("Cuenta y voz"); click("Clave API:"); input.value = "voice-secret"; input.buttons[1][2].callback(); back()
click("Añadir pronunciación"); assert(saved.tts_enabled)
print("PASS: vocabulary-only extras, disabled unused image settings and shared credentials")

open(config); click("Barajas y envío"); click("Baraja:")
local original_deck = saved.deck
fail_save = true; input.value = "ShouldNotSave"; input.buttons[1][2].callback()
assert(saved.deck == original_deck and config.anki.deck == original_deck and notice:find("disk full", 1, true))
print("PASS: failed saves remain visible and never apply unsaved changes")
fail_save = false
open(config); click("Nube entre lectores"); click("Destino:")
assert(selected_server({name = "WebDAV", address = "private-address"}))
assert(saved.sync_server.name == "WebDAV" and not saved.cloud_auto_sync)
click("Sincronizar al abrir"); assert(saved.cloud_auto_sync)
click("Desvincular nube"); confirm.ok_callback()
assert(saved.sync_server == nil and not saved.cloud_auto_sync)
assert(config.sync_server == nil and config.anki.sync_server == nil)
assert(State.merge(config, saved).sync_server == nil and baseline_resets == 2)
assert(saved.gemini_api_key == "test-secret" and saved.elevenlabs_api_key == "voice-secret")
print("PASS: cloud configuration never starts syncing; disconnect really clears state without losing keys")

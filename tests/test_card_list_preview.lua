package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local Preview = require("card_list_preview")
local function fit(text) return text end
local card = {kind = "learn", question = "Pregunta generada", selected_text = "  Cita\ndel   libro áéíóú ",
    book_title = "Libro", date = "2026-10-14"}
local label = Preview.label(card, "[Solo Kobo] ", fit)
assert(label == "[Solo Kobo] [Learn] Pregunta generada\n«Cita del libro áéíóú»\nLibro · 2026-10-14")
card.selected_text = " "
card.annotation_source = {selection = {text = "Texto de la anotación"}}
assert(Preview.fragment(card) == "Texto de la anotación")
card.annotation_source = nil
card.phrase, card.text = "Una pregunta, no una cita", "Frase generada"
assert(Preview.fragment(card) == "")
assert(Preview.label(card, "", fit):find("\nFragmento no disponible\n", 1, true))
assert(Preview.fragment({phrase = "Palabra", text = "Frase generada"}) == "Palabra")
local lines = {}
Preview.label(card, "", function(text) lines[#lines+1] = text; return "línea ajustada" end)
assert(#lines == 3 and lines[2] == "Fragmento no disponible")
print("PASS: separate source-selection line, Unicode/whitespace normalization, provenance fallback and no fabricated quotes")

-- Exercise the real card list configuration, not just its text helper.
local menu, fitted, freed, closed, returned = nil, 0, 0, 0, 0
package.loaded.gettext = function(s) return s end
for _, name in ipairs({"ui/widget/buttondialog", "ui/widget/confirmbox", "ui/widget/notification", "ui/widget/infomessage"}) do
    package.loaded[name] = {new = function(_, spec) return spec end}
end
package.loaded["ui/widget/menu"] = {new = function(_, spec) menu = spec; return spec end}
package.loaded["ui/uimanager"] = {show = function() end, close = function() closed = closed + 1 end}
for _, name in ipairs({"ui/event", "anki_sync", "anki_import", "learning", "card_sync", "card_generator", "card_viewer",
    "image_generator", "ui/network/manager"}) do package.loaded[name] = {} end
card.selected_text = "Fragmento original"
package.loaded.card_storage = {load_cards = function() return {card} end, load_anki_settings = function() return {} end}
package.loaded.device = {screen = {getWidth = function() return 800 end, getHeight = function() return 1000 end,
    scaleBySize = function(_, n) return n end}}
package.loaded["ui/font"] = {getFace = function(_, _, size) return {size = size} end}
package.loaded["ui/widget/textwidget"] = {new = function(_, spec)
    if spec.max_width then assert(spec.max_width == 620) end
    return {getFittedText = function() fitted = fitted + 1; return spec.text, false end,
        getSize = function() return {h = spec.face.size} end,
        free = function() freed = freed + 1 end}
end}
require("card_manager").show({}, nil, nil, nil, function() returned = returned + 1 end)
assert(menu.items_per_page == 6 and menu.perpage == nil and menu.items_font_size == 20 and menu.multilines_forced and not menu.multilines_show_more_text)
assert(menu.item_table[2].text:find("\n«Fragmento original»\n", 1, true))
assert(fitted == 3 and freed == 6)
assert(menu.is_borderless and menu.onReturn and menu.item_table[2].card_preview[2] == "«Fragmento original»")
assert(not menu.item_table[2].text:find("[Enviada]", 1, true))
menu:onReturn()
assert(closed == 1 and returned == 1)
print("PASS: native card menu uses fixed multiline rows and fits each line separately without leaking text widgets")

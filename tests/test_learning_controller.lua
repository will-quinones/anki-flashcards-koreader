-- luajit tests/test_learning_controller.lua
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local queue, views, notices, statuses, closed = {}, {}, {}, {}, 0
local Learn = dofile("AnkiFlashcards.koplugin/learning_card.lua")
local State = dofile("AnkiFlashcards.koplugin/settings_state.lua")
package.loaded.learning_card, package.loaded.settings_state = Learn, State
local source = {selected = "Una idea completa del libro", context = "El entorno reduce pasos para empezar.",
    context_quality = "document", title = "Libro", author = "Autor", chapter = "Hábitos"}
package.loaded.learning_context = {capture = function(_, selection) assert(selection.text); return source end}
local generated, sent = 0, 0
package.loaded.card_generator = {generate_learning = function(config, captured)
    generated = generated + 1
    assert(config.text_provider == "openrouter" and captured.context == source.context)
    return {kind = "learn", card_id = Learn.id(captured), phrase = "Pregunta", question = "Pregunta",
        answer = "Respuesta", selected_text = captured.selected, source_context = captured.context,
        book_title = captured.title, book_author = captured.author, chapter = captured.chapter}
end}
local stored = {}
package.loaded.card_storage = {
    load_anki_settings = function() return {text_provider = "openrouter", url = "http://fake:8765"} end,
    find_learning_card = function(id) return stored[id] end,
    save_learning_card = function(card) stored[card.card_id] = card; return true end,
}
package.loaded.anki_sync = {send_card = function(config, card)
    assert(config.url == "http://fake:8765" and card.kind == "learn")
    sent = sent + 1; card.sent_to_anki = true; return true
end}
package.loaded.card_viewer = {new = function(_, spec) views[#views+1] = spec; return spec end}
package.loaded["ui/widget/infomessage"] = {new = function(_, spec) notices[#notices+1] = spec.text; return spec end}
package.loaded["ui/widget/notification"] = {new = function(_, spec) return spec end}
package.loaded["ui/uimanager"] = {show = function(_, spec) if spec.text then statuses[#statuses+1] = spec.text end end, close = function() end,
    scheduleIn = function(_, _, callback) queue[#queue+1] = callback end}
package.loaded["ui/network/manager"] = {runWhenOnline = function(_, callback) callback() end}
local Learning = dofile("AnkiFlashcards.koplugin/learning.lua")
local ui = {highlight = {onClose = function() closed = closed + 1 end}}
Learning.start({}, ui, {text = source.selected})
assert(closed == 1 and generated == 0)
assert(statuses[#statuses] == "Generando tarjeta…")
while #queue > 0 do table.remove(queue, 1)() end
assert(generated == 1 and #views == 1 and views[1].show_back == false)
local front = views[1]
assert(front.on_save() and stored[Learn.id(source)])
front.on_show_answer()
local back = views[#views]
assert(back.show_back)
back.on_show_question()
assert(not views[#views].show_back and views[#views].card == back.card)
views[#views].on_show_answer()
back = views[#views]
assert(back.on_send())
assert(sent == 1 and back.read_only)
back.on_regenerate() -- stale visible button must not spend another AI call after send
assert(generated == 1 and #notices == 1)
Learning.start({}, ui, {text = source.selected})
assert(generated == 1 and views[#views].read_only and closed == 2)
source = {selected = "palabra", context = "palabra", context_quality = "selection"}
Learning.start({}, ui, {text = source.selected})
assert(generated == 1 and notices[#notices]:find("contexto suficiente", 1, true))
print("PASS: learning selection → preview → save/send, source reuse, and no repeated generation for saved/sent cards")

local A=require("annotation_tools")
local applied={}
local original_highlight=A.highlight_saved
A.highlight_saved=function(cfg, _, card)
    assert(card.kind=="learn" and generated>1)
    applied[#applied+1]=cfg.highlight_on_save
    return true
end
source={selected="Otra idea completa del libro",context="Contexto de una idea nueva.",context_quality="document",title="Libro",author="Autor"}
Learning.start({highlight_on_save=true},ui,{text=source.selected})
assert(#applied==0)
while #queue>0 do table.remove(queue,1)() end
assert(#applied==0)
local save=package.loaded.card_storage.save_learning_card
package.loaded.card_storage.save_learning_card=function() return nil,"failed" end
assert(not views[#views].on_save() and #applied==0)
package.loaded.card_storage.save_learning_card=save
views[#views].on_save()
assert(#applied==1 and applied[1]==true)
Learning.start({highlight_on_save=true},ui,{text=source.selected})
assert(#applied==1) -- Opening an existing card must not recreate its annotation.
views[#views].on_regenerate()
while #queue>0 do table.remove(queue,1)() end
assert(#applied==1) -- Regeneration isn't a new source selection.
source.selected="Una tercera idea completa del libro"
Learning.start({highlight_on_save=false},ui,{text=source.selected})
while #queue>0 do table.remove(queue,1)() end
assert(#applied==1)
assert(views[#views].on_save())
assert(#applied==2 and applied[2]==false)
package.loaded.card_generator.generate_learning=function() return nil,"Fallo simulado" end
source.selected="Una cuarta idea completa del libro"
Learning.start({highlight_on_save=true},ui,{text=source.selected})
while #queue>0 do table.remove(queue,1)() end
assert(#applied==2)
A.highlight_saved=function() return nil,"Highlight failed" end
assert(views[#views].on_save())
A.highlight_saved=original_highlight
print("PASS: Learn highlights only after explicit successful save, not preview, failed save, opening or regeneration; highlight errors preserve saved cards")

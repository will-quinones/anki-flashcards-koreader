package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local A, Learn = require("annotation_tools"), require("learning_card")
local queue, cards, requests, image_calls = {}, {}, 0, 0
package.loaded["ui/uimanager"] = {scheduleIn = function(_, _, fn) queue[#queue+1] = fn end, show = function() end, close = function() end}
for _, name in ipairs({"ui/widget/notification", "ui/widget/infomessage"}) do package.loaded[name] = {new = function(_, spec) return spec end} end
local ui = {document = {file = "/book.epub", getProps = function() return {title = "Libro", authors = "Autor"} end},
    annotation = {annotations = {}}}
local snapshots = {}
for i, word in ipairs({"palabra", "otras", "otras"}) do
    local annotation = {text = word, pos0 = "start" .. i, pos1 = "end" .. i, drawer = "lighten"}
    ui.annotation.annotations[i] = annotation
    snapshots[i] = A.capture(ui, annotation)
end
cards[1] = {phrase = "palabra", definition = "KEEP", origin_key = snapshots[1].origin_key}
local fail_storage, busy = false, false
package.loaded.card_storage = {
    load_anki_settings = function() return nil end, load_cards = function() return cards end,
    find_by_phrase = function(phrase) for _, card in ipairs(cards) do if card.kind ~= "learn" and card.phrase == phrase then return card end end end,
    find_learning_card = function(id) for _, card in ipairs(cards) do if card.kind == "learn" and card.card_id == id then return card end end end,
    save_card = function(card)
        if fail_storage then return false, "disk full" end
        for _, saved in ipairs(cards) do
            if card.kind == "learn" and saved.kind == "learn" and saved.card_id == card.card_id then return false, "already_saved" end
            if card.kind ~= "learn" and saved.kind ~= "learn" and saved.phrase == card.phrase then return false, "already_saved" end
        end
        card._storage_id = card._storage_id or ("saved-" .. (#cards+1)); cards[#cards+1] = card; return true
    end,
    add_annotation_alias = function(card, key) card.annotation_aliases = card.annotation_aliases or {}; table.insert(card.annotation_aliases, key); return true end,
}
package.loaded.image_generator = {is_enabled = function() return false end, generate_async = function() image_calls = image_calls + 1 end}
package.loaded.card_generator = {
    generate = function()
        requests = requests + 1
        if busy then return require("generation_feedback").http_error(503, "overloaded") end
        return {phrase = "palabra", definition = "DO NOT OVERWRITE", text = "{{c1::palabra}}"}
    end,
    generate_learning = function(_, source)
        requests = requests + 1
        return {kind = "learn", card_id = Learn.id(source), phrase = "Pregunta " .. source.selected,
            question = "Pregunta " .. source.selected, answer = "Respuesta"}
    end,
}
-- Provide document context so a one-word annotation can produce a learning card.
ui.document.getSelectedWordContext = function(_, _, _, _, _, restore) assert(not restore); return "Contexto suficiente antes", "y después del texto" end
local Batch = require("annotation_generation")
local cfg = {dashscope_api_key = "fake", target_language = "Spanish"}
local function drain() while #queue > 0 do table.remove(queue, 1)() end end
local function generate(kind)
    local report; assert(Batch.start(ui, cfg, snapshots, kind, function(r) report = r end)); drain(); return report
end
local report = generate("vocab")
assert(report.existing == 3 and report.generated == 0 and requests == 1 and cards[1].definition == "KEEP")
assert(A.find_card(snapshots[2], "vocab", cards) == cards[1])
report = generate("learn")
assert(report.generated == 2 and report.existing == 1 and #cards == 3 and image_calls == 0)
local before = requests
assert(generate("learn").generated == 0 and requests == before and #ui.annotation.annotations == 3)
assert(not Batch.start(ui, {text_provider = "ankivocab", ankivocab_api_key = "fake"}, snapshots, "learn"))
local extra = {text = "nueva", pos0 = "fresh", pos1 = "fresh-end", drawer = "lighten"}
ui.annotation.annotations[#ui.annotation.annotations+1] = extra
local snapshot = A.capture(ui, extra)
busy = true
local cancelled, job
job = assert(Batch.start(ui, cfg, {snapshot}, "vocab", function(r) cancelled = r end))
while requests == before do table.remove(queue, 1)() end
job:cancel(); drain()
assert(cancelled.cancelled and requests == before + 1 and #cards == 3)
busy, fail_storage = false, true
local failed
assert(Batch.start(ui, cfg, {snapshot}, "vocab", function(r) failed = r end)); drain()
assert(failed.failed == 1 and #cards == 3)
print("PASS: typed duplicates, canonical aliases, cancellation during retry, storage failure and zero implicit highlighting/sends")

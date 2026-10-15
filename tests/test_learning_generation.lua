-- luajit tests/test_learning_generation.lua (native text extraction + mocked AI)
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local Context = dofile("AnkiFlashcards.koplugin/learning_context.lua")
local Learn = dofile("AnkiFlashcards.koplugin/learning_card.lua")
package.loaded.learning_card = Learn
local ui = {document = {
    getProps = function() return {title = "Libro", authors = {"Autor"}} end,
    getPageFromXPointer = function() return 12 end,
    getSelectedWordContext = function(_, selected, words, pos0, pos1, restore)
        assert(selected == "fricción" and words == 180 and pos0 == "start" and pos1 == "end" and restore)
        return "El libro propone preparar el entorno. ", " significa reducir pasos para empezar."
    end,
    getTextFromPositions = function() error("Do not extract a screen or screenshot") end,
}, toc = {getTocTitleByPage = function(_, page) assert(page == 12); return "Hábitos" end}}
local source = assert(Context.capture(ui, {text = "fricción", pos0 = "start", pos1 = "end"}))
assert(source.context_quality == "document" and source.context:find("preparar el entorno", 1, true))
assert(source.title == "Libro" and source.author == "Autor" and source.chapter == "Hábitos")
assert(not Context.capture(ui, {text = string.rep("x", 6001)}))
local pdf_pages = {}
local pdf = {document = {getProps = function() return {} end,
    getPageTextBoxes = function(_, page) pdf_pages[#pdf_pages+1] = page; return {{{word = "Texto"}, {word = tostring(page)}}} end,
    getOCRText = function() error("OCR is not used") end}}
local pdf_source = assert(Context.capture(pdf, {text = "Una idea completa", pos0 = {page = 2}, pos1 = {page = 2}}))
assert(pdf_source.context_quality == "pages" and #pdf_pages == 3)
assert(pdf_source.context:find("Texto 1", 1, true) and pdf_source.context:find("Texto 3", 1, true))
local fallback = assert(Context.capture({document = {}}, {text = "Un párrafo con una idea completa"}))
assert(fallback.context_quality == "selection")
local id = Learn.id(source)
local changed = {}; for k, v in pairs(source) do changed[k] = v end
changed.context = "More context"
assert(id == Learn.id(changed))
changed.selected = "otra idea"
assert(id ~= Learn.id(changed))
print("PASS: cross-page native EPUB/PDF text, bounded context, metadata and stable identity")

local generated = {question = "¿Cómo facilita el entorno empezar?", answer = "Al reducir pasos previos.",
    explanation = "Según el fragmento, se prepara el entorno.", evidence = "El libro propone preparar el entorno."}
local prompt, payload, requests, response_status, response_headers, error_response = nil, nil, 0, 200, {}, nil
package.loaded.json = {encode = function(value)
    if value.messages then prompt = value.messages[1].content else payload = value end
    return "encoded"
end, decode = function(raw)
    if raw == "provider" then return error_response or {choices = {{message = {content = "{}"}}}} end
    assert(raw == "{}")
    return generated
end}
package.loaded.ltn12 = {source = {string = function(s) return s end},
    sink = {table = function(t) return function(s) t[#t+1] = s end end}}
local requester = {request = function(args) requests = requests + 1; args.sink("provider"); return 1, response_status, response_headers end}
package.loaded["ssl.https"], package.loaded["socket.http"] = requester, requester
local Generator = dofile("AnkiFlashcards.koplugin/card_generator.lua")
local cfg = {text_provider = "openrouter", openrouter_api_key = "fake", target_language = "Spanish"}
local card = assert(Generator.generate_learning(cfg, source))
assert(card.kind == "learn" and card.card_id == id and card.question == generated.question)
assert(card.image_prompt == "" and not card.ipa and payload.book == "Libro")
assert(prompt:find("in Spanish", 1, true) and prompt:find("untrusted book text", 1, true))
generated.evidence = "Invented quote"
assert(not Generator.generate_learning(cfg, source))
generated = {insufficient_context = true, reason = "Selecciona más texto."}
local no_card, err = Generator.generate_learning(cfg, source)
assert(not no_card and err:find("Falta contexto", 1, true))
local before = requests
assert(not Generator.generate_learning({text_provider = "ankivocab"}, source))
assert(requests == before)
print("PASS: source-grounded questions, real quote validation, insufficient context and unsupported gateway")
response_status, response_headers = 503, {['retry-after'] = '60'}
local _, safe_error, info = Generator.generate_learning(cfg, source)
assert(info.kind == "busy" and info.retry_after == 60 and safe_error:find("saturado", 1, true))
response_status, error_response = 200, {error = {type = "overloaded_error"}}
_, safe_error, info = Generator.generate(cfg, "palabra", "contexto", "Libro", "Autor")
assert(info.kind == "busy" and not safe_error:find("HTTP", 1, true))
print("PASS: provider status/retry metadata propagates for both Vocab and Learn, including HTTP-200 errors")
error_response, response_headers = nil, {}
generated = {phrase = "WORD", definition = "Definition", text = "Use {{c1::word}} here.", kind = "learn", card_id = "unexpected"}
local vocab = assert(Generator.generate(cfg, "word", "context", "Book", "Author"))
assert(vocab.phrase == "word" and vocab.kind == nil and vocab.card_id == nil)
generated.text = "No cloze here"
assert(not Generator.generate(cfg, "word", "context", "Book", "Author"))
print("PASS: malformed vocabulary is rejected and model output cannot change the chosen action type")

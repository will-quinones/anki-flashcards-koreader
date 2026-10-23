-- luajit tests/test_inbox_generation_errors.lua -- no real requests or files.
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local Feedback = require("generation_feedback")
local A = require("annotation_tools")
local queue, shown, calls, saved = {}, {}, 0, {}
package.loaded["ui/widget/notification"] = {new = function(_, spec) return spec end}
package.loaded["ui/widget/infomessage"] = {new = function() error("Batch errors must be summarized") end}
package.loaded["ui/uimanager"] = {show = function(_, spec) shown[#shown+1] = spec end, close = function() end,
    scheduleIn = function(_, _, fn) queue[#queue+1] = fn end}
package.loaded.card_storage = {load_cards = function() return saved end,
    load_anki_settings = function() return nil end,
    save_card = function(card) card._storage_id = "saved-" .. (#saved+1); saved[#saved+1] = card; return true end}
package.loaded.image_generator = {is_enabled = function() return false end}
package.loaded.card_generator = {generate = function(_, phrase)
    calls = calls + 1
    if calls == 1 then return {phrase = phrase, definition = "Definición", text = "{{c1::word}}"} end
    return Feedback.http_error(503, "provider overloaded private-key")
end}
local Batch = require("annotation_generation")
local ui = {annotation = {annotations = {}}, document = {file = "/book.epub",
    getProps = function() return {title = "Libro", authors = "Autor"} end}}
local snapshots = {}
for i, word in ipairs({"uno", "dos", "tres"}) do
    local annotation = {text = word, pos0 = "start" .. i, pos1 = "end" .. i}
    ui.annotation.annotations[#ui.annotation.annotations+1] = annotation
    snapshots[#snapshots+1] = A.capture(ui, annotation)
end
local report
assert(Batch.start(ui, {target_language = "Spanish", dashscope_api_key = "fake"}, snapshots, "vocab", function(result) report = result end))
while #queue > 0 do table.remove(queue, 1)() end
assert(calls == 3 and #saved == 1 and report.generated == 1 and report.failed == 1 and report.remaining == 1)
assert(report.errors[1]:find("saturado", 1, true) and not report.errors[1]:find("private-key", 1, true))
print("PASS: bulk generation keeps completed cards and stops after bounded overload retries")

-- Annotation batch persistence/media regressions. The native annotation menu
-- is now Learn-only; vocabulary media cases exercise its actual batch engine.
package.path = "./AnkiFlashcards.koplugin/?.lua;" .. package.path
local K = dofile("tests/support/koreader.lua")
K.install()
local function run_case(save_result, save_error, assign_id, options)
    options = options or {}
    local queue, report, calls, updates, cleanup, saved = {}, nil, 0, 0, {}, nil
    for _, name in ipairs({"annotation_generation", "card_storage", "card_generator", "image_generator", "ui/uimanager"}) do package.loaded[name] = nil end
    package.loaded["ui/uimanager"] = {show = function() end, close = function() end,
        scheduleIn = function(_, _, fn) queue[#queue+1] = fn end}
    local known = {phrase = "duplicate", _storage_id = "existing"}
    package.loaded.card_storage = {
        load_anki_settings = function() return {} end, load_cards = function() return {} end,
        find_by_phrase = function() return known end,
        add_annotation_alias = function(card) assert(card == known); return true end,
        save_card = function(card)
            saved = card
            if save_result and assign_id then card._storage_id = "saved-generation" end
            return save_result, save_error
        end,
        update_image_path = function(card, path)
            assert(card._storage_id == "saved-generation" and path == "/test/inbox-image.png")
            updates = updates+1; return not options.update_image_fails
        end,
        remove_image_if_unreferenced = function(path) cleanup[#cleanup+1] = path end,
    }
    package.loaded.card_generator = {generate = function()
        return {phrase = "duplicate", definition = "definition", text = "A {{c1::duplicate}}.", image_prompt = "scene"}
    end}
    package.loaded.image_generator = {is_enabled = function() return true end,
        generate_async = function(_, _, _, success)
            calls = calls+1
            if options.invalidate_before_callback then saved._storage_id = "replacement" end
            success("/test/inbox-image.png")
        end}
    local annotation = {text = "selected expression", pos0 = "start", pos1 = "end"}
    local ui = {document = {file = "/book.epub", getProps = function() return {title = "Book", authors = "Author"} end},
        annotation = {annotations = {annotation}}}
    local A = require("annotation_tools")
    assert(require("annotation_generation").start(ui, {dashscope_api_key = "fake", image_provider = "dashscope"},
        {A.capture(ui, annotation)}, "vocab", function(result) report = result end))
    while #queue > 0 do table.remove(queue,1)() end
    assert(report, "Every batch must finish with a report")
    return calls, updates, report, cleanup
end
local images, updates, report = run_case(false, "already_saved", false)
assert(images == 0 and updates == 0 and report.generated == 0 and report.existing == 1)
images, updates, report = run_case(false, "write_failed", false)
assert(images == 0 and updates == 0 and report.generated == 0 and report.failed == 1)
images, updates, report = run_case(true, nil, false)
assert(images == 0 and updates == 0 and report.generated == 0 and report.failed == 1)
images, updates, report = run_case(true, nil, true)
assert(images == 1 and updates == 1 and report.generated == 1 and report.failed == 0)
local cleanup
images, updates, report, cleanup = run_case(true, nil, true, {update_image_fails = true})
assert(images == 1 and updates == 1 and #cleanup == 1 and cleanup[1] == "/test/inbox-image.png")
images, updates, report, cleanup = run_case(true, nil, true, {invalidate_before_callback = true})
assert(images == 1 and updates == 0 and #cleanup == 1 and cleanup[1] == "/test/inbox-image.png")
print("PASS: annotation duplicates/write failures/missing identities never start media; current media persists and stale/failed images are cleaned")

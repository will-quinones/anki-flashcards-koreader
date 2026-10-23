-- LuaJIT regression harness for issue #13 bulk deletion by book.
package.path = "./AnkiFlashcards.koplugin/?.lua;" .. package.path
local KOReader = dofile("tests/support/koreader.lua")
KOReader.install()

local function clone(entries)
    local result = {}
    for i, card in ipairs(entries or {}) do
        result[i] = {}
        for key, value in pairs(card) do result[i][key] = value end
    end
    return result
end

-- Storage deletes only the requested exact group, retains media shared by cards
-- that survive, and never removes records/assets when persistence fails.
do
    local saved_open, saved_rename, saved_remove = io.open, os.rename, os.remove
    local files, encoded, serial, removed, fail_rename = {}, {}, 0, {}, false
    package.loaded["card_storage"], package.loaded["datastorage"], package.loaded["json"] = nil, nil, nil
    package.preload["datastorage"] = function()
        return { getDataDir = function() return "/issue13-storage" end }
    end
    package.preload["json"] = function()
        return {
            encode = function(entries)
                serial = serial + 1
                local token = "encoded-" .. serial
                encoded[token] = clone(entries)
                return token
            end,
            decode = function(token) return clone(encoded[token] or {}) end,
        }
    end
    io.open = function(path, mode)
        if mode == "r" then
            if files[path] == nil then return nil end
            return { read = function() return files[path] end, close = function() return true end }
        end
        if mode ~= "w" then return nil end
        local buffer = ""
        return {
            write = function(_, data) buffer = buffer .. data; return true end,
            close = function() files[path] = buffer; return true end,
        }
    end
    os.rename = function(from, to)
        if fail_rename then return false end
        files[to], files[from] = files[from], nil
        return true
    end
    os.remove = function(path)
        removed[#removed + 1] = path
        files[path] = nil
        return true
    end

    local CardStorage = require("card_storage")
    local cards_path, shared = require("storage_paths").cards, "/issue13-storage/shared.png"
    local function seed()
        files, encoded, serial, removed = {}, {}, 0, {}
        encoded.live = {
            { phrase = "literal", book_title = "Unknown book", image_path = "/issue13-storage/literal.png" },
            { phrase = "missing", book_title = "", image_path = "/issue13-storage/missing.png" },
            { phrase = "target one", book_title = "Target", kind = "vocab", image_path = shared },
            { phrase = "target two", book_title = "Target", kind = "learn", question = "Question", answer = "Answer", image_path = "/issue13-storage/target.png" },
            { phrase = "other", book_title = "Other", image_path = shared, anki_sync_state = "conflict", anki_note_id = 9 },
        }
        files[cards_path] = "live"
        files[shared], files["/issue13-storage/target.png"] = "shared", "target"
        files["/issue13-storage/literal.png"], files["/issue13-storage/missing.png"] = "literal", "missing"
    end

    seed()
    local ok, count = CardStorage.delete_cards_for_book("Target", false)
    assert(ok and count == 2, "exact selected book must report both deletions")
    local remaining = CardStorage.load_cards()
    assert(#remaining == 3 and remaining[1].phrase == "literal" and remaining[2].phrase == "missing"
           and remaining[3].phrase == "other", "exact selected book must retain other book groups")
    assert(remaining[3].anki_sync_state == "conflict" and remaining[3].anki_note_id == 9,
           "cleanup must preserve synchronization metadata on retained cards")
    assert(files[shared] == "shared", "shared media referenced by a remaining card must survive")
    assert(files["/issue13-storage/target.png"] == nil, "unreferenced deleted-book media must be removed")

    ok, count = CardStorage.delete_cards_for_book(nil, true)
    assert(ok and count == 1, "missing-book selection must delete only missing-book cards")
    remaining = CardStorage.load_cards()
    assert(#remaining == 2 and remaining[1].phrase == "literal" and remaining[2].phrase == "other",
           "missing-book selection must not delete a literal Unknown book title")

    local previous_serial = serial
    ok, count = CardStorage.delete_cards_for_book("Absent", false)
    assert(ok and count == 0 and serial == previous_serial, "empty groups must not rewrite storage")
    ok, count = CardStorage.delete_cards_for_book(nil, false)
    assert(not ok and count == "invalid_book" and serial == previous_serial,
           "an invalid book must never mutate storage")

    seed()
    fail_rename = true
    ok, count = CardStorage.delete_cards_for_book("Target", false)
    assert(not ok and count == "write_failed", "failed bulk persistence must report write_failed")
    remaining = CardStorage.load_cards()
    assert(#remaining == 5 and files[shared] == "shared" and files["/issue13-storage/target.png"] == "target",
           "failed bulk persistence must retain records and image assets")
    fail_rename = false
    io.open, os.rename, os.remove = saved_open, saved_rename, saved_remove
    package.loaded["card_storage"] = nil
end

-- Native statistics expose deletion on long press; cancellation/failure retain
-- cards and successful local deletion refreshes all three synchronization counts.
do
    local state = {
        shown = {}, closed = 0, delete_calls = 0, send_calls = 0,
        cards = {
            { phrase = "literal", book_title = "Libro no identificado", sent_to_anki = true },
            { phrase = "missing", book_title = "" },
            { phrase = "review", book_title = "Target", sent_to_anki = true,
              anki_note_id = 4, anki_sync_state = "conflict" },
        },
    }
    for _, name in ipairs({
        "card_manager", "gettext", "ui/widget/buttondialog", "ui/widget/confirmbox", "ui/widget/menu",
        "ui/widget/notification", "ui/widget/infomessage", "ui/uimanager", "ui/event", "card_storage",
        "anki_sync", "card_generator", "card_viewer", "image_generator", "ui/network/manager",
    }) do package.loaded[name] = nil end
    package.preload["gettext"] = function() return function(s) return s end end
    for _, name in ipairs({ "ui/widget/buttondialog", "ui/widget/confirmbox", "ui/widget/menu",
                            "ui/widget/notification", "ui/widget/infomessage" }) do
        package.preload[name] = function() return { new = function(_, options) return options end } end
    end
    package.preload["ui/uimanager"] = function()
        return {
            show = function(_, widget) state.shown[#state.shown + 1] = widget end,
            close = function() state.closed = state.closed + 1 end,
            setDirty = function() end,
        }
    end
    package.preload["card_storage"] = function()
        return {
            load_anki_settings = function() return nil end,
            load_cards = function() return state.cards end,
            delete_cards_for_book = function(title, include_missing)
                state.delete_calls = state.delete_calls + 1
                state.last_title, state.last_missing = title, include_missing
                if state.fail_delete then return false, "write_failed" end
                local kept, count = {}, 0
                for _, card in ipairs(state.cards) do
                    if (include_missing and (not card.book_title or card.book_title == ""))
                        or (not include_missing and card.book_title == title) then count = count + 1
                    else kept[#kept + 1] = card end
                end
                state.cards = kept
                return true, count
            end,
        }
    end
    package.preload["anki_sync"] = function()
        return { send_card = function() state.send_calls = state.send_calls + 1; error("Unexpected Anki request") end }
    end
    package.preload["card_generator"] = function() return {} end
    package.preload["card_viewer"] = function() return {} end
    package.preload["image_generator"] = function() return { is_enabled = function() return false end } end

    local function last_shown() return state.shown[#state.shown] end
    local CardManager = require("card_manager")
    CardManager.show_stats()
    local stats = last_shown()
    assert(stats.title == "Estadísticas — 3 tarjetas" and stats.is_borderless and stats.onReturn,
           "statistics must remain in the native borderless menu with back navigation")
    assert(stats.item_table[1].text == "1 enviadas · 1 pendientes · 1 por revisar",
           "review conflicts must remain distinct from both sent and pending cards")
    assert(#stats.item_table == 4 and stats.item_table[2].hold_callback and stats.item_table[3].hold_callback,
           "a literal missing-book label must remain a separate group from untitled cards")
    assert(stats.item_table[4].text:find("1 por revisar", 1, true), "per-book review count must be preserved")
    stats:onMenuHold(stats.item_table[1])
    assert(last_shown() == stats, "summary rows must have no destructive action")
    stats:onMenuHold(stats.item_table[2])
    local actions = last_shown()
    assert(actions.buttons[1][1].text == "Borrar tarjetas de este libro…",
           "long press must expose the adapted bulk-delete action")
    actions.buttons[1][1].callback()
    local confirm = last_shown()
    assert(confirm.text:find("1 tarjeta de «Libro no identificado» del Kobo", 1, true)
        and confirm.text:find("Se conservarán las notas de Anki y los subrayados", 1, true)
        and confirm.ok_text == "Borrar del Kobo",
        "confirmation must identify the local group, count, and preservation of Anki/annotations")
    confirm.cancel_callback()
    assert(state.delete_calls == 0 and #state.cards == 3, "cancellation must not mutate storage")

    state.fail_delete = true
    confirm.ok_callback()
    assert(last_shown().text:find("No se pudieron borrar", 1, true) and #state.cards == 3,
           "failed persistence must keep cards and report failure without refreshing statistics")
    state.fail_delete = false
    stats.item_table[2].hold_callback()
    last_shown().buttons[1][1].callback()
    last_shown().ok_callback()
    assert(state.last_title == "Libro no identificado" and state.last_missing == false,
           "a literal missing-book label must retain its exact non-missing identity")
    assert(state.delete_calls == 2 and state.send_calls == 0 and #state.cards == 2,
           "confirmed deletion must be local only")
    assert(state.shown[#state.shown - 1].text == "Se borró 1 tarjeta del Kobo para «Libro no identificado».",
           "successful deletion must provide local-only feedback")
    stats = last_shown()
    assert(stats.title == "Estadísticas — 2 tarjetas" and stats.item_table[1].text == "0 enviadas · 1 pendientes · 1 por revisar",
           "successful deletion must refresh statistics and retain recovery counts")

    stats.item_table[2].hold_callback()
    last_shown().buttons[1][1].callback()
    last_shown().ok_callback()
    assert(state.last_title == nil and state.last_missing == true and #state.cards == 1,
           "the missing-book group must be deleted using its separate identity")

    -- A stale menu entry must not open a confirmation for an empty group.
    stats.item_table[2].hold_callback()
    last_shown().buttons[1][1].callback()
    assert(last_shown().title == "Estadísticas — 1 tarjeta" and state.delete_calls == 3,
           "empty groups must refresh statistics without another destructive call")

    stats = last_shown()
    stats.item_table[2].hold_callback()
    last_shown().buttons[1][1].callback()
    last_shown().ok_callback()
    stats = last_shown()
    assert(stats.title == "Estadísticas — 0 tarjetas" and #stats.item_table == 2
        and stats.item_table[1].text == "0 enviadas · 0 pendientes · 0 por revisar"
        and stats.item_table[2].text == "Todavía no hay tarjetas",
        "deleting the final book must leave an accurate empty native statistics menu")
    local closed = state.closed
    stats:onReturn()
    assert(state.closed == closed + 1 and state.send_calls == 0, "native back navigation must close statistics")
end

print("issue #13 bulk-delete-book harness: PASS")

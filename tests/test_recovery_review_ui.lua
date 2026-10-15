-- Confirmation boundaries: no local replacement without an explicit choice.
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local menu, dialog, confirm, done, applied
local widget = function(kind) return {new = function(_, spec)
    spec.kind = kind
    if kind == "menu" then menu = spec elseif kind == "dialog" then dialog = spec elseif kind == "confirm" then confirm = spec end
    return spec
end} end
package.loaded.gettext = function(s) return s end
package.loaded["ui/widget/menu"] = widget("menu")
package.loaded["ui/widget/buttondialog"] = widget("dialog")
package.loaded["ui/widget/confirmbox"] = widget("confirm")
package.loaded["ui/widget/notification"] = widget("notification")
package.loaded["ui/widget/infomessage"] = widget("info")
package.loaded["ui/uimanager"] = {show = function() end, close = function() end}
for _, name in ipairs({"ui/event", "card_generator", "card_viewer", "image_generator", "ui/network/manager", "learning", "card_sync", "anki_sync"}) do
    package.loaded[name] = {}
end
package.loaded.card_storage = {load_anki_settings = function() return {} end}
package.loaded.anki_import = {
    start = function(_, callback) done = callback; return {cancel = function() end} end,
    apply_updates = function(_, changes) applied = changes; return {cancel = function() end} end,
}
local Manager = require("card_manager")
local function change(id, conflict)
    return {id = id, conflict = conflict, reason = conflict and "conflict" or "remote_changed",
        local_card = {phrase = "palabra" .. id, definition = "LOCAL"}, remote_card = {phrase = "palabra" .. id, definition = "ANKI"}}
end
local report = {source = {profile = "Will"}, imported = 0, existing = 2, moved = 1, changed = 1, conflicts = 1,
    missing = 1, out_of_scope = 0, foreign = 0, failed = 0, image_warnings = 0, issues = {}, errors = {}, changes = {change(1, false), change(2, true)}}
local function start()
    Manager.recover_from_anki({anki = {url = "http://fake:8765"}})
    confirm.ok_callback()
    done(report)
end
local function menu_item(prefix)
    for _, item in ipairs(menu.item_table) do if item.text:sub(1, #prefix) == prefix then return item end end
    error(prefix)
end
local function dialog_button(prefix)
    for _, row in ipairs(dialog.buttons) do
        for _, item in ipairs(row) do if item.text:sub(1, #prefix) == prefix then return item end end
    end
    error(prefix)
end
start()
menu_item("Actualizar cambios sin conflicto").callback()
assert(applied == nil)
confirm.ok_callback()
assert(#applied == 1 and applied[1].id == 1)
applied = nil
start()
menu_item("[Conflicto]").callback()
dialog_button("Conservar la versión local").callback()
assert(applied == nil)
menu_item("[Conflicto]").callback()
dialog_button("Usar versión de Anki").callback()
assert(applied == nil)
confirm.ok_callback()
assert(#applied == 1 and applied[1].id == 2)
applied, report.source_changed = nil, true
start()
local blocked = menu_item("Actualizar cambios sin conflicto")
assert(blocked.select_enabled == false)
blocked.callback()
assert(applied == nil)
print("PASS: safe batch excludes conflicts, per-card replacement needs confirmation, source changes block updates")

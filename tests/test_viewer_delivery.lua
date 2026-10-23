-- luajit tests/test_viewer_delivery.lua -- shared actions on both card sides.
local widget = {new = function(_, spec) return spec end}
for _, name in ipairs({"ui/bidi", "ui/widget/buttondialog", "ui/widget/buttontable",
    "ui/widget/confirmbox",
    "ui/widget/container/centercontainer", "ui/font", "ui/widget/container/framecontainer",
    "ui/geometry", "ui/gesturerange", "ui/widget/imagewidget", "ui/widget/infomessage",
    "ui/widget/inputdialog", "ui/widget/container/movablecontainer", "ui/widget/notification",
    "ui/widget/scrolltextwidget", "ui/widget/titlebar", "ui/widget/horizontalgroup",
    "ui/widget/verticalgroup", "ui/widget/verticalspan", "ui/rendertext",
    "ui/widget/container/widgetcontainer"}) do package.loaded[name] = widget end
package.loaded["ui/widget/container/inputcontainer"] = {extend = function(_, spec) return spec end}
package.loaded["ui/size"] = {padding = {large = 10, default = 5}, margin = {small = 2}}
package.loaded.device = {screen = {}}
package.loaded["ffi/blitbuffer"] = {ColorRGB32 = function() return {} end}
package.loaded.gettext = function(s) return s end
local saved, notice = false, nil
package.loaded.card_storage = {is_saved = function() return saved end,
    saved_card = function() return {_storage_id = "local-1"} end,
    ensure_identity = function() return true end,
    delete_card_by_id = function(id) assert(id == "local-1"); saved = false; return true end}
package.loaded["ui/uimanager"] = {show = function(_, spec) notice = spec.text end}
local Viewer = dofile("AnkiFlashcards.koplugin/card_viewer.lua")
for _, back in ipairs({false, true}) do
    saved = false
    local button = {setText = function(self, text) self.text = text end,
        enable = function(self) self.disabled = false end,
        disable = function(self) self.disabled = true end, refresh = function() end}
    local saves, sends = 0, 0
    local viewer = setmetatable({show_back = back, card = {phrase = "palabra"},
        button_table = {getButtonById = function() return button end},
        on_save = function() saves = saves + 1; saved = true; return true end,
        on_send = function() sends = sends + 1; saved = true; return true end,
    }, {__index = Viewer})
    local actions = viewer:delivery_buttons()
    assert(#actions == 2 and actions[1].id == "save" and actions[2].id == "send")
    assert(actions[1].enabled and actions[2].enabled)
    actions[1].callback()
    assert(saves == 1 and not button.disabled and button.text == "Borrar del Kobo…" and viewer.show_back == back)
    button.disabled, saved = false, false
    actions[2].callback()
    assert(sends == 1 and button.disabled and viewer.show_back == back)
    assert(viewer:delivery_buttons()[1].enabled == true)
    viewer.on_send = function() return nil, "connection refused" end
    saved, button.disabled = false, false
    viewer:delivery_buttons()[2].callback()
    assert(not button.disabled and notice:find("connection refused", 1, true))
    assert(viewer.show_back == back)
end
local no_actions = setmetatable({card = {phrase = "palabra"}}, {__index = Viewer}):delivery_buttons()
assert(not no_actions[1].enabled and not no_actions[2].enabled)
local attempts = 0
for _, kind in ipairs({"vocab", "learn"}) do
    local card = {kind = kind, sent_to_anki = true, anki_note_id = 123}
    local viewer = setmetatable({card = card, on_send = function() attempts = attempts + 1 end}, {__index = Viewer})
    local action = viewer:delivery_buttons()[2]
    assert(action.text == "✓ Enviada a Anki" and not action.enabled)
    action.callback()
    assert(attempts == 0)
    card.anki_sync_state = "missing"
    action = viewer:delivery_buttons()[2]
    assert(action.text == "No está en Anki" and not action.enabled)
end
local highlighted = false
local button = {setText = function(self, text) self.text = text end,
    disable = function(self) self.disabled = true end, refresh = function() end}
local with_highlight = setmetatable({card = {phrase = "fragmento"}, show_back = false,
    on_add_highlight = function() highlighted = true; return true end,
    is_highlighted = function() return highlighted end, can_add_highlight = function() return true end,
    button_table = {getButtonById = function(_, id) assert(id == "highlight"); return button end}}, {__index = Viewer})
local actions = with_highlight:delivery_buttons()
assert(#actions == 3 and actions[3].id == "highlight" and actions[3].enabled)
actions[3].callback()
assert(button.disabled and highlighted and with_highlight.show_back == false)
assert(not with_highlight:delivery_buttons()[3].enabled)
print("PASS: Save/Send available on both sides, without flipping; failures allow retry")
local live, online, deleted, sent, confirmed = "present", true, 0, 0, 0
package.loaded["ui/network/manager"] = {isOnline = function() return online end,
    runWhenOnline = function(_, fn) fn() end}
package.loaded.settings_state = {merge = function() return {} end}
package.loaded.card_storage.load_anki_settings = function() return {} end
package.loaded.anki_note_actions = {
    status = function() return live, not live and "unreachable" or nil end,
    confirm_delete = function(_, _, cb)
        confirmed = confirmed + 1
        -- Simulate the confirmation box: no deletion until this is called.
        package.loaded.anki_note_actions.confirm = function() deleted = deleted + 1; live = "absent"; cb(true, "deleted") end
    end,
}
for _, back in ipairs({false, true}) do
    local btn = {setText = function(self, text) self.text = text end, refresh = function() end,
        enable = function(self) self.disabled = false end, disable = function(self) self.disabled = true end}
    local viewer = setmetatable({anki_base = {}, card = {sent_to_anki = true, anki_note_id = 42}, show_back = back,
        button_table = {getButtonById = function(_, id) return id == "send" and btn or nil end},
        on_send = function() sent = sent + 1; live = "present"; return true end}, {__index = Viewer})
    live = "present"
    viewer:refresh_anki_status()
    assert(btn.text == "Eliminar de Anki…" and not btn.disabled)
    local before = deleted
    viewer:delivery_buttons()[2].callback()
    assert(deleted == before and confirmed > 0)
    package.loaded.anki_note_actions.confirm()
    assert(deleted == before + 1 and btn.text == "Enviar a Anki")
    viewer:delivery_buttons()[2].callback()
    assert(sent > 0 and btn.text == "Eliminar de Anki…")
    live = "absent" -- Deleted outside the plugin after the last refresh.
    local previous = sent
    viewer:delivery_buttons()[2].callback()
    assert(sent == previous and btn.text == "Enviar a Anki")
    online = false
    viewer:refresh_anki_status()
    assert(btn.text == "Verificar en Anki" and not viewer.anki_status)
    online, live = true, nil
    viewer:refresh_anki_status()
    viewer:delivery_buttons()[2].callback()
    assert(sent == previous and viewer.anki_status_error == "unreachable")
    assert(viewer.show_back == back)
end
print("PASS: live Send/Delete button on both sides, confirmation, external deletion, offline and no action reversal")

local confirmation, updates = nil, 0
package.loaded["ui/uimanager"].show = function(_, spec) confirmation = spec end
local btn = {setText = function(self, text) self.text = text end, refresh = function() end,
    enable = function() end, disable = function() end}
local viewer = setmetatable({card = {phrase = "word"}, on_save = function() saved = true; return true end,
    button_table = {getButtonById = function() return btn end}, update = function() updates = updates + 1 end}, {__index = Viewer})
saved = true
local action = viewer:delivery_buttons()[1]
assert(action.enabled and action.text == "Borrar del Kobo…")
action.callback()
assert(saved and confirmation.ok_callback) -- Cancellation preserves the card.
confirmation.ok_callback()
assert(not saved and btn.text == "Guardar" and updates == 1)
viewer:delivery_buttons()[1].callback()
assert(saved and btn.text == "Borrar del Kobo…")
saved = true -- External deletion: tapping Delete cannot turn into Save.
action = viewer:delivery_buttons()[1]
saved = false
action.callback()
assert(not saved and btn.text == "Guardar")
print("PASS: local Save/Delete toggles, confirms deletion, allows saving again and rechecks external changes")

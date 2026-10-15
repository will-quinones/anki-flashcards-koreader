-- luajit tests/test_viewer_delivery.lua -- shared actions on both card sides.
local widget = {new = function(_, spec) return spec end}
for _, name in ipairs({"ui/bidi", "ui/widget/buttondialog", "ui/widget/buttontable",
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
package.loaded.card_storage = {is_saved = function() return saved end}
package.loaded["ui/uimanager"] = {show = function(_, spec) notice = spec.text end}
local Viewer = dofile("AnkiFlashcards.koplugin/card_viewer.lua")
for _, back in ipairs({false, true}) do
    saved = false
    local button = {setText = function(self, text) self.text = text end,
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
    assert(saves == 1 and button.disabled and viewer.show_back == back)
    button.disabled, saved = false, false
    actions[2].callback()
    assert(sends == 1 and button.disabled and viewer.show_back == back)
    assert(viewer:delivery_buttons()[1].enabled == false)
    viewer.on_send = function() return nil, "connection refused" end
    saved, button.disabled = false, false
    viewer:delivery_buttons()[2].callback()
    assert(not button.disabled and notice:find("connection refused", 1, true))
    assert(viewer.show_back == back)
end
local no_actions = setmetatable({card = {phrase = "palabra"}}, {__index = Viewer}):delivery_buttons()
assert(not no_actions[1].enabled and not no_actions[2].enabled)
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

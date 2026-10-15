-- luajit tests/test_highlight_menu.lua: tap redirect without editing core/data.
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
package.loaded.util = {tableDeepCopy = copy}
package.loaded.gettext = function(text) return text end
local FullMenu = dofile("AnkiFlashcards.koplugin/highlight_menu.lua")
local annotations = {{text = "fragmento", pos0 = {page = 2, x = 10}, pos1 = {page = 2, x = 90}}}
local edited, full, closed, registrations, fail = 0, 0, 0, {}, false
local highlight = {ui = {annotation = {annotations = annotations}},
    showHighlightDialog = function(_, index) assert(index == 1); edited = edited + 1 end,
    onShowHighlightMenu = function(self, index)
        assert(index == 1 and self.selected_text.text == "fragmento")
        full = full + 1
    end,
    addToHighlightDialog = function(_, id, factory) registrations[id] = factory end,
    onClose = function() closed = closed + 1 end,
    onTap = function(self)
        if fail then error("native tap error") end
        self:showHighlightDialog(1)
        return true
    end,
}
assert(FullMenu.install(highlight))
local wrapped = highlight.onTap
assert(FullMenu.install(highlight) and highlight.onTap == wrapped)
assert(highlight:onTap() and full == 1 and edited == 0)
assert(highlight.selected_text ~= annotations[1] and highlight.selected_text.pos0 ~= annotations[1].pos0)
highlight.selected_text.text = "changed selection"
assert(annotations[1].text == "fragmento")
local button = registrations.ankiflashcards_edit_highlight(highlight, 1)
assert(button.text == "Editar subrayado" and button.show_in_highlight_dialog_func())
button.callback()
assert(edited == 1 and closed == 1)
highlight:showHighlightDialog(1) -- boundary editing remains native, outside tap scope
assert(edited == 2 and full == 1)
fail = true
assert(not pcall(highlight.onTap, highlight))
highlight:showHighlightDialog(1) -- errors must not leave a sticky redirect
assert(edited == 3 and full == 1)
fail = false
assert(highlight:onTap() and full == 2)
assert(not registrations.ankiflashcards_edit_highlight(highlight, nil).show_in_highlight_dialog_func())
annotations[1] = nil
button.callback() -- deleted annotation between opening menu and pressing action
assert(edited == 3)
assert(not FullMenu.install({}))
print("PASS: native taps open the complete menu; annotations stay intact and native editing still works")

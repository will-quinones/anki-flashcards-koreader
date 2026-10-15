package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local freed, updated = 0, 0
local function group(_, spec)
    spec.free = function() freed = freed + 1 end
    return spec
end
for _, name in ipairs({"verticalgroup", "horizontalgroup", "horizontalspan"}) do
    package.loaded["ui/widget/" .. name] = {new = group}
end
package.loaded["ui/font"] = {getFace = function(_, _, size) return {size = size} end}
package.loaded["ui/widget/textwidget"] = {new = function(_, spec) return spec end}
local function make_item()
    local container = {{free = function() freed = freed + 1 end}}
    return {entry = {card_preview = {"↗ [Learn] Pregunta", "«Fragmento original»", "Libro · fecha"}},
        content_width = 600, _underline_container = {{{{}, container}}}, bold = false,
        ges_events = {native = true}}
end
local menu = {item_group = {make_item()}}
menu.updateItems = function(self) updated = updated + 1; self.item_group = {make_item()} end
local Rows = require("card_list_rows")
Rows.install(menu)
local function check()
    local item = menu.item_group[1]
    local lines = item._underline_container[1][1][2][1][2]
    assert(lines[1].text == "↗ [Learn] Pregunta" and lines[1].face.size == 20)
    assert(lines[2].text == "«Fragmento original»" and lines[2].face.size == 17)
    assert(lines[3].face.size == 15 and lines[2].max_width == 600)
    assert(item.ges_events.native and item._underline_container)
end
check()
menu:updateItems(2)
check()
assert(updated == 1 and freed == 2)
print("PASS: true separate source line at smaller font, native gestures/focus preserved, and pagination rerenders safely")

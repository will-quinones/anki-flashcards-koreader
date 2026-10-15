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

-- KOReader ignores 'perpage' at initialization: items_per_page must override
-- the user's global density, with enough physical space at every DPI.
local scale, screen_height = 1, 1000
package.loaded.device = {screen = {scaleBySize = function(_, n) return n * scale end,
    getHeight = function() return screen_height end}}
package.loaded["ui/widget/textwidget"] = {new = function(_, spec)
    return {getSize = function() return {h = spec.face.size * scale} end, free = function() end}
end}
assert(Rows.per_page() == 6)
scale, screen_height = 2, 1448
assert(Rows.per_page() == 6)
local count = Rows.per_page(600)
assert(count == 3 and 600 / count >= (20 + 17 + 15 + 24) * scale)
assert(Rows.per_page(200) == 1)
local enabled = 0
local actual = {available_height = 600, item_group = {}, onReturn = function() end,
    page_return_arrow = {enable = function() enabled = enabled + 1 end}}
actual.updateItems = function(self)
    self.perpage = self.items_per_page or 18 -- actual native setting precedence
    self.item_height = self.available_height / self.perpage
end
Rows.install(actual)
assert(actual.items_per_page == 3 and actual.perpage == 3 and actual.item_height >= 152)
actual:updateItems()
assert(enabled == 2)
print("PASS: measured DPI-aware row heights override global density via items_per_page; native back remains enabled")

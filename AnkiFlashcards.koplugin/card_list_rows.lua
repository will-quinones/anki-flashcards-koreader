-- Preserve native MenuItem gestures, focus underline and shortcuts, replacing
-- only its text content: KOReader's default MenuItem flattens newline characters.
local Rows = {}
local font_sizes = {20, 17, 15}
function Rows.per_page(available_height)
    local Screen = require("device").screen
    local Font = require("ui/font")
    local Text = require("ui/widget/textwidget")
    local row_height = Screen:scaleBySize(24)
    for _, size in ipairs(font_sizes) do
        local widget = Text:new {text = "Ágj", face = Font:getFace("smallinfofont", size)}
        row_height = row_height + widget:getSize().h
        widget:free()
    end
    -- Reserve title, subtitle and native footer before the menu is constructed;
    -- install() refines this using its actual available height afterwards.
    local available = available_height or (Screen:getHeight() - Screen:scaleBySize(150))
    return math.max(1, math.min(6, math.floor(available / row_height)))
end
function Rows.render(menu)
    for _, item in ipairs(menu.item_group or {}) do
        local parts = item.entry and item.entry.card_preview
        local underline = item._underline_container
        local overlap = underline and underline[1] and underline[1][1]
        local container = overlap and overlap[2]
        if parts and container and container[1] then
            local Font = require("ui/font")
            local Text = require("ui/widget/textwidget")
            local Vertical = require("ui/widget/verticalgroup")
            local Horizontal = require("ui/widget/horizontalgroup")
            local Span = require("ui/widget/horizontalspan")
            local indent = (item.entry.indent or 0) + (item.state_w or 0)
            local width = math.max(1, item.content_width - indent)
            local sizes = #parts == 2 and {font_sizes[1], font_sizes[2]} or font_sizes
            local lines = Vertical:new {align = "left"}
            for i, size in ipairs(sizes) do
                lines[#lines+1] = Text:new {text = parts[i], face = Font:getFace("smallinfofont", size),
                    max_width = width, bold = i == 1 and item.bold or false}
            end
            container[1]:free()
            container[1] = Horizontal:new {Span:new {width = indent}, lines}
        end
    end
    -- Native Menu disables its return arrow when its own path stack is empty.
    -- This list has an external parent and handles the return via onReturn.
    if menu.onReturn and menu.page_return_arrow then menu.page_return_arrow:enable() end
end
function Rows.install(menu)
    local original = menu.updateItems
    if type(original) == "function" then
        menu.updateItems = function(self, ...)
            local result = original(self, ...)
            Rows.render(self)
            return result
        end
    end
    if menu.available_height and type(menu.updateItems) == "function" then
        menu.items_per_page = Rows.per_page(menu.available_height)
        menu:updateItems(1)
    else
        Rows.render(menu)
    end
    return menu
end
return Rows

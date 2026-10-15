-- Preserve native MenuItem gestures, focus underline and shortcuts, replacing
-- only its text content: KOReader's default MenuItem flattens newline characters.
local Rows = {}
local font_sizes = {20, 17, 15}
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
            local lines = Vertical:new {align = "left"}
            for i, size in ipairs(font_sizes) do
                lines[#lines+1] = Text:new {text = parts[i], face = Font:getFace("smallinfofont", size),
                    max_width = width, bold = i == 1 and item.bold or false}
            end
            container[1]:free()
            container[1] = Horizontal:new {Span:new {width = indent}, lines}
        end
    end
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
    Rows.render(menu)
    return menu
end
return Rows

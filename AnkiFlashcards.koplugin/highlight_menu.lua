-- Tapping an existing highlight opens its full action menu directly.
-- Scope the redirect to a native tap: boundary editing must keep its toolbar.
local util = require("util")
local _ = require("gettext")
local FullMenu = {}

function FullMenu.install(highlight)
    if highlight._anki_full_menu_installed then return true end
    if type(highlight.onTap) ~= "function" or type(highlight.showHighlightDialog) ~= "function"
        or type(highlight.onShowHighlightMenu) ~= "function" or type(highlight.addToHighlightDialog) ~= "function" then
        return false
    end
    local original_tap, original_edit = highlight.onTap, highlight.showHighlightDialog
    local tap_depth = 0
    highlight.showHighlightDialog = function(self, index)
        local annotations = self.ui and self.ui.annotation and self.ui.annotation.annotations
        local annotation = annotations and annotations[index]
        if tap_depth > 0 and annotation then
            -- Exactly the selection preparation used by KOReader's ellipsis.
            self.selected_text = util.tableDeepCopy(annotation)
            return self:onShowHighlightMenu(index)
        end
        return original_edit(self, index)
    end
    highlight.onTap = function(self, ...)
        tap_depth = tap_depth + 1
        local ok, result = pcall(original_tap, self, ...)
        tap_depth = tap_depth - 1
        if not ok then error(result, 0) end
        return result
    end
    highlight:addToHighlightDialog("ankiflashcards_edit_highlight", function(self, index)
        return {
            text = _("Editar subrayado"),
            show_in_highlight_dialog_func = function()
                local annotations = self.ui and self.ui.annotation and self.ui.annotation.annotations
                return index ~= nil and annotations and annotations[index] ~= nil
            end,
            callback = function()
                local annotations = self.ui and self.ui.annotation and self.ui.annotation.annotations
                if not index or not annotations or not annotations[index] then return end
                self:onClose()
                original_edit(self, index)
            end,
        }
    end)
    highlight._anki_full_menu_installed = true
    return true
end
return FullMenu

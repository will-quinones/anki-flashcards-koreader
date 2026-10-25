-- Briefly invert only the source text. This view module never changes the
-- reader's selection, annotations, current page or document rendering state.
local Marker = {}
local FLASH_TOGGLES = 6 -- three complete on/off flashes
local logger_ok, logger = pcall(require, "logger")
local function trace(phase)
    if logger_ok then logger.info("Anki reading marker:", phase) end
end
function Marker.clear(ui)
    local view = ui and ui.view
    local marker = view and view.view_modules and view.view_modules.ankivocab_return
    if marker then marker:finish() end
end
function Marker.flash(ui, snapshot)
    trace("prepare")
    local A = require("annotation_tools")
    if not ui or not A.same_book(ui, snapshot) or not A.valid_range(snapshot.selection) then return end
    local view, selection = ui.view, snapshot.selection
    if not view or not view.registerViewModule then return end
    Marker.clear(ui)
    local UI = require("ui/uimanager")
    local state = view.state or {}
    local page, pos, zoom, rotation = state.page, state.pos, state.zoom, state.rotation
    local boxes = {}
    local ok = pcall(function()
        trace("boxes:query")
        if type(selection.pos0) == "string" then
            boxes = ui.document:getScreenBoxesFromPositions(selection.pos0, selection.pos1, true) or {}
        else
            local pages = selection.ext or {[selection.pos0.page] = selection}
            for p, selected in pairs(pages) do
                local pboxes = ui.document:getPageBoxesFromPositions(p, selected.pos0, selected.pos1) or selected.pboxes or {}
                for _, box in ipairs(pboxes) do
                    local rect = view:pageToScreenTransform(p, box)
                    if rect then boxes[#boxes+1] = rect end
                end
            end
        end
    end)
    trace("boxes:ready")
    if not ok or #boxes == 0 then return end
    local Screen = require("device").screen
    local Geom = require("ui/geometry")
    local width, height = Screen:getWidth(), Screen:getHeight()
    local function clipped(rect, w, h)
        local x, y = math.max(0, math.floor(rect.x)), math.max(0, math.floor(rect.y))
        local right, bottom = math.min(w, math.ceil(rect.x + rect.w)), math.min(h, math.ceil(rect.y + rect.h))
        if rect.w > 0 and rect.h > 0 and right > x and bottom > y then
            return Geom:new {x=x, y=y, w=right-x, h=bottom-y}
        end
    end
    local regions = {}
    for _, rect in ipairs(boxes) do
        local region = clipped(rect, width, height)
        if region then regions[#regions+1] = region end
    end
    if #regions == 0 then return end
    boxes = regions
    local function refresh()
        for _, rect in ipairs(boxes) do
            local region = clipped(rect, Screen:getWidth(), Screen:getHeight())
            -- "partial" counts towards KOReader's periodic full-screen flash.
            -- UI refreshes keep the same text fidelity without that promotion.
            -- Keep separate segments: their union could cover most of the page.
            if region then UI:setDirty(ui, "ui", region) end
        end
    end
    local marker = {visible = false, ticks = 0}
    local function valid()
        local now = view.state or {}
        return A.same_book(ui, snapshot) and now.page == page and now.pos == pos
            and now.zoom == zoom and now.rotation == rotation
            and Screen:getWidth() == width and Screen:getHeight() == height
    end
    function marker:finish()
        if self.finished then return end
        self.finished = true
        if UI.unschedule then UI:unschedule(self.tick) end
        if view.view_modules.ankivocab_return == self then view.view_modules.ankivocab_return = nil end
        if self.visible and ui.document and not ui.tearing_down then
            self.visible = false
            refresh()
        end
    end
    function marker:paintTo(bb)
        if not self.visible or not valid() then return end
        trace("paint:start")
        local width, height = bb:getWidth(), bb:getHeight()
        for _, rect in ipairs(boxes) do
            local x, y = math.max(0, rect.x), math.max(0, rect.y)
            local w, h = math.min(width, rect.x + rect.w) - x, math.min(height, rect.y + rect.h) - y
            if w > 0 and h > 0 then bb:invertRect(x, y, w, h) end
        end
        trace("paint:done")
    end
    marker.tick = function()
        if marker.finished then return end
        if not valid() or marker.ticks == FLASH_TOGGLES then marker:finish(); return end
        marker.ticks = marker.ticks + 1
        marker.visible = not marker.visible
        refresh()
        UI:scheduleIn(0.35, marker.tick)
    end
    view:registerViewModule("ankivocab_return", marker)
    UI:scheduleIn(0, marker.tick)
end
return Marker

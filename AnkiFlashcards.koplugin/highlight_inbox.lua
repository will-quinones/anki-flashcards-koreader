-- Learning-only annotation preview: fixed checkbox, excerpt and action columns.
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UI = require("ui/uimanager")
local Network = require("ui/network/manager")
local Device = require("device")
local Storage = require("card_storage")
local A = require("annotation_tools")
local Batch = require("annotation_generation")
local Inbox = {}
local Screen = Device.screen
local function message(text) UI:show(InfoMessage:new {text = text}) end
local function preview(value, max)
    local result, count = {}, 0
    for char in (value or ""):gsub("%s+", " "):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > max then return table.concat(result) .. "…" end
        result[#result+1] = char
    end
    return table.concat(result)
end
function Inbox.collect(ui)
    local entries = {}
    for _, annotation in ipairs((ui.annotation and ui.annotation.annotations) or {}) do
        local has_text = type(annotation.text) == "string" and annotation.text:match("%S")
        local has_note = type(annotation.note) == "string" and annotation.note:match("%S")
        if has_text or has_note then
            local snapshot = A.capture(ui, annotation)
            local valid = has_text and A.valid_range(annotation)
            entries[#entries+1] = {snapshot = snapshot, valid = not not valid,
                reason = not valid and "Esta anotación no tiene un fragmento de libro seleccionado. Selecciona el texto original para crear una tarjeta." or nil}
        end
    end
    return entries
end
function Inbox.show(ui, base)
    local entries = Inbox.collect(ui)
    if #entries == 0 then message("Este libro todavía no tiene subrayados ni anotaciones con texto."); return end
    local state = {page = 1, selected = {}, closed = false}
    local dialog
    local scale = Screen.scaleBySize and Screen:scaleBySize(64) or 64
    local page_size = math.max(2, math.min(6, math.floor(Screen:getHeight() / scale) - 4))
    local render
    local function close_dialog() if dialog then UI:close(dialog); dialog = nil end end
    local function redraw()
        UI:scheduleIn(0, function() if not state.closed then render() end end)
    end
    local function statuses(cards)
        local result = {}
        for index, entry in ipairs(entries) do
            result[index] = A.find_card(entry.snapshot, "learn", cards) or false
        end
        return result
    end
    local function full_text(entry)
        local selection = entry.snapshot.selection
        local text = selection.text or ""
        if selection.note and selection.note ~= "" then text = text .. "\n\nTu nota:\n" .. selection.note end
        if not entry.valid then text = text .. "\n\n" .. entry.reason end
        UI:show(require("ui/widget/textviewer"):new {title = "Anotación", text = text})
    end
    local function start(selected, single)
        local cards, fresh, existing, invalid = Storage.load_cards(), 0, 0, 0
        local snapshots = {}
        for _, entry in ipairs(selected) do
            snapshots[#snapshots+1] = entry.snapshot
            if not entry.valid then invalid = invalid + 1
            elseif A.find_card(entry.snapshot, "learn", cards) then existing = existing + 1
            else fresh = fresh + 1 end
        end
        if fresh == 0 then message(existing .. " ya tienen tarjeta de aprendizaje; " .. invalid .. " no tienen texto válido."); return end
        UI:show(ConfirmBox:new {
            text = "Crear " .. fresh .. " tarjetas de aprendizaje en el Kobo.\n\n"
                .. existing .. " ya existentes se omitirán. Puede consumir cuota del proveedor de texto."
                .. "\n\nSe enviarán los fragmentos y su contexto a la IA. Tus notas se usan como orientación, no como citas."
                .. "\n\nNo se envían a Anki automáticamente. Si hay tarjetas solo en el ordenador, usa primero Recuperar desde Anki.",
            ok_text = "Generar", ok_callback = function()
                Network:runWhenOnline(function()
                    close_dialog()
                    local progress, job
                    local function cancel_job()
                        UI:scheduleIn(0, function() if job then job:cancel() end end)
                    end
                    local function show_progress(report)
                        if progress then UI:close(progress) end
                        progress = ButtonDialog:new {title = "Anotaciones: " .. report.processed .. "/" .. report.total,
                            tap_close_callback = cancel_job,
                            buttons = {{{text = "Cancelar", callback = cancel_job}}}}
                        UI:show(progress)
                    end
                    local err
                    job, err = Batch.start(ui, base, snapshots, "learn", function(report)
                        if progress then UI:close(progress) end
                        local current = Storage.load_cards()
                        for i, entry in ipairs(entries) do
                            if A.find_card(entry.snapshot, "learn", current) then state.selected[i] = false end
                        end
                        if not ui.tearing_down and A.same_book(ui, entries[1].snapshot) then render() else state.closed = true end
                        if single and report.generated == 1 and report.cards[1] then
                            require("card_manager").open_card(base, report.cards[1], ui)
                            return
                        end
                        local text = (report.cancelled and "Generación cancelada.\n\n" or "")
                            .. report.generated .. " guardadas · " .. report.existing .. " ya existentes"
                            .. "\n" .. report.invalid .. " no válidas · " .. report.failed .. " errores"
                            .. "\n" .. report.remaining .. " sin procesar"
                        if report.errors[1] then text = text .. "\n\n" .. report.errors[1] end
                        message(text)
                    end, show_progress)
                    if not job then render(); message(err); return end
                    show_progress({processed = 0, total = #snapshots})
                end)
            end,
        })
    end
    render = function()
        if state.closed then return end
        close_dialog()
        local status = statuses(Storage.load_cards())
        local selectable, selected_count = {}, 0
        for index, entry in ipairs(entries) do
            if entry.valid then
                selectable[#selectable+1] = index
                if state.selected[index] == nil then state.selected[index] = not status[index] end
                if state.selected[index] then selected_count = selected_count + 1 end
            else state.selected[index] = false end
        end
        local pages = math.max(1, math.ceil(#entries / page_size))
        state.page = math.max(1, math.min(state.page, pages))
        local rows = {}
        local width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.94)
        local function scaled(n) return Screen.scaleBySize and Screen:scaleBySize(n) or n end
        local cell_height, icon_size = scaled(32), scaled(24)
        local checkbox_width, action_width = scaled(48), scaled(52)
        for index = (state.page - 1) * page_size + 1, math.min(#entries, state.page * page_size) do
            local i, entry = index, entries[index]
            local check = not entry.valid and "—" or (state.selected[i] and "☑" or "☐")
            local selection = entry.snapshot.selection
            local summary = type(selection.text) == "string" and selection.text:match("%S") and selection.text or selection.note
            rows[#rows+1] = {
                {text = check, width = checkbox_width, height = cell_height,
                    font_size = 20, font_bold = false, avoid_text_truncation = false, enabled = entry.valid,
                    allow_hold_when_disabled = true,
                    callback = function()
                        if not entry.valid then full_text(entry); return end
                        state.selected[i] = not state.selected[i]; redraw()
                    end,
                    hold_callback = function() full_text(entry) end},
                {text = preview(summary, 160), align = "left", height = cell_height,
                    font_size = 20, font_bold = false, avoid_text_truncation = false,
                    callback = function() full_text(entry) end,
                    hold_callback = function() full_text(entry) end},
                {icon = status[i] and "check" or "plus", enabled = entry.valid,
                    width = action_width, height = cell_height, icon_width = icon_size, icon_height = icon_size,
                    callback = function()
                        local existing = A.find_card(entry.snapshot, "learn", Storage.load_cards())
                        if existing then
                            A.bind(existing, entry.snapshot)
                            require("card_manager").open_card(base, existing, ui)
                        else start({entry}, true) end
                    end,
                    hold_callback = function() full_text(entry) end},
            }
        end
        rows[#rows+1] = {
            {text = "‹ Anterior", enabled = state.page > 1, callback = function() state.page = state.page - 1; redraw() end},
            {text = "Cerrar", callback = function() state.closed = true; close_dialog() end},
            {text = "Siguiente ›", enabled = state.page < pages, callback = function() state.page = state.page + 1; redraw() end},
        }
        rows[#rows+1] = {
            {text = "Generar seleccionadas (" .. selected_count .. ")", enabled = selected_count > 0,
                font_size = 18, avoid_text_truncation = false, callback = function()
                local selected = {}; for _, i in ipairs(selectable) do if state.selected[i] then selected[#selected+1] = entries[i] end end
                if #selected > 0 then start(selected, false) end
            end},
            {text = #selectable > 0 and selected_count == #selectable and "Desmarcar todas" or "Marcar todas",
                font_size = 18, avoid_text_truncation = false,
                enabled = #selectable > 0, callback = function()
                    local value = selected_count ~= #selectable
                    for _, i in ipairs(selectable) do state.selected[i] = value end
                    redraw()
                end},
        }
        dialog = ButtonDialog:new {title = "Aprendizaje desde anotaciones (" .. #entries .. ") · " .. state.page .. "/" .. pages .. "\n+ Generar · ✓ Abrir guardada · mantener texto para leer",
            width = width, buttons = rows, tap_close_callback = function() state.closed = true end}
        UI:show(dialog)
    end
    render()
end
return Inbox

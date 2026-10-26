-- Card lists, native statistics, exports and explicit card actions.

local ButtonDialog   = require("ui/widget/buttondialog")
local ConfirmBox     = require("ui/widget/confirmbox")
local Menu           = require("ui/widget/menu")
local Notification   = require("ui/widget/notification")
local UIManager      = require("ui/uimanager")
local _              = require("gettext")

local Event          = require("ui/event")
local CardStorage    = require("card_storage")
local AnkiSync       = require("anki_sync")
local AnkiImport     = require("anki_import")
local Learning       = require("learning")
local SettingsState  = require("settings_state")
local NoteTypes      = require("note_types")
local CardSync       = require("card_sync")
local Feedback       = require("generation_feedback")
local Recovery       = require("anki_recovery")
local Annotations    = require("annotation_tools")
local CardGenerator  = require("card_generator")
local CardViewer     = require("card_viewer")
local ImageGenerator = require("image_generator")
local NetworkMgr     = require("ui/network/manager")
local CardMedia      = require("card_media")

local InfoMessage   = require("ui/widget/infomessage")

local CardManager = {}

local function notify(text)
    UIManager:show(Notification:new { text = text })
end

local function notify_error(text)
    UIManager:show(InfoMessage:new { text = text, timeout = 5 })
end

-- Handles both full CONFIGURATION (with nested .anki) and a flat Anki-only table.
local function effective_config(base)
    return SettingsState.merge(base, CardStorage.load_anki_settings())
end

local function is_anki_ready(anki_config)
    return anki_config.url
        and anki_config.url ~= ""
        and not anki_config.url:find("192.168.x.x")
end

local function send_one(anki_config, card, tts_config, quiet)
    if not is_anki_ready(anki_config) then
        local err = _("Configura la dirección de Anki en Ajustes.")
        if not quiet then notify_error(err) end
        return false, err
    end
    local ok, err, receipt = AnkiSync.send_card(anki_config, card, tts_config)
    if ok then
        return true, nil, receipt
    else
        if not quiet then notify_error(_("Anki error: ") .. (err or "unknown")) end
        return false, err
    end
end

local MISSING_BOOK = {}

local function cards_for_book(cards, book_key)
    local filtered = {}
    local is_missing_book = book_key == MISSING_BOOK
    for _, card in ipairs(cards) do
        if (is_missing_book and (not card.book_title or card.book_title == ""))
           or (not is_missing_book and card.book_title == book_key) then
            table.insert(filtered, card)
        end
    end
    return filtered
end

local function show_stats()
    local all_cards = CardStorage.load_cards()
    local book_order, book_stats = {}, {}
    local total_all, sent_all, review_all = #all_cards, 0, 0
    for _i, card in ipairs(all_cards) do
        local book_key = (card.book_title and card.book_title ~= "") and card.book_title or MISSING_BOOK
        if not book_stats[book_key] then
            book_stats[book_key] = {
                total = 0, sent = 0, review = 0,
                label = book_key == MISSING_BOOK and _("Libro no identificado") or book_key,
            }
            table.insert(book_order, book_key)
        end
        local stats = book_stats[book_key]
        stats.total = stats.total + 1
        if Recovery.needs_review(card) then
            stats.review, review_all = stats.review + 1, review_all + 1
        elseif card.sent_to_anki then
            stats.sent, sent_all = stats.sent + 1, sent_all + 1
        end
    end

    local stats_menu
    local function refresh_stats()
        if stats_menu then UIManager:close(stats_menu) end
        show_stats()
    end
    local function delete_book(book_key, label)
        local current_cards = cards_for_book(CardStorage.load_cards(), book_key)
        if #current_cards == 0 then
            notify(_("Este libro ya no tiene tarjetas guardadas en el Kobo."))
            refresh_stats()
            return
        end
        UIManager:show(ConfirmBox:new {
            text = _("¿Borrar ") .. tostring(#current_cards)
                .. (#current_cards == 1 and _(" tarjeta de «") or _(" tarjetas de «"))
                .. label .. _("» del Kobo? Esta acción no se puede deshacer. Se conservarán las notas de Anki y los subrayados del libro."),
            ok_text = _("Borrar del Kobo"),
            cancel_callback = function() end,
            ok_callback = function()
                local book_title
                if book_key ~= MISSING_BOOK then book_title = book_key end
                local deleted, count_or_err = CardStorage.delete_cards_for_book(book_title, book_key == MISSING_BOOK)
                if not deleted then
                    notify_error(_("No se pudieron borrar las tarjetas del libro. No se guardaron los cambios."))
                    return
                end
                if count_or_err == 0 then
                    notify(_("Este libro ya no tiene tarjetas guardadas en el Kobo."))
                else
                    notify((count_or_err == 1 and _("Se borró 1 tarjeta del Kobo para «")
                        or _("Se borraron ") .. tostring(count_or_err) .. _(" tarjetas del Kobo para «"))
                        .. label .. _("»."))
                end
                refresh_stats()
            end,
        })
    end

    local stat_items = {{ text = sent_all .. _(" enviadas · ") .. (total_all - sent_all - review_all)
        .. _(" pendientes · ") .. review_all .. _(" por revisar") }}
    if #book_order == 0 then
        table.insert(stat_items, { text = _("Todavía no hay tarjetas") })
    end
    for _i, book_key in ipairs(book_order) do
        local stats = book_stats[book_key]
        local unsent = stats.total - stats.sent - stats.review
        local line = stats.label .. "  —  " .. tostring(stats.total)
            .. (stats.total == 1 and _(" tarjeta · ") or _(" tarjetas · ")) .. tostring(stats.sent) .. _(" enviadas")
        if unsent > 0 then line = line .. " · " .. tostring(unsent) .. _(" pendientes") end
        if stats.review > 0 then line = line .. " · " .. stats.review .. _(" por revisar") end
        local selected_key, selected_label = book_key, stats.label
        table.insert(stat_items, {
            text = line,
            hold_callback = function()
                local actions
                actions = ButtonDialog:new {
                    title = selected_label,
                    buttons = {
                        {{ text = _("Borrar tarjetas de este libro…"), callback = function()
                            UIManager:close(actions)
                            delete_book(selected_key, selected_label)
                        end }},
                        {{ text = _("Cancelar"), callback = function() UIManager:close(actions) end }},
                    },
                }
                UIManager:show(actions)
            end,
        })
    end

    stats_menu = Menu:new {
        title = _("Estadísticas — ") .. tostring(total_all) .. (total_all == 1 and _(" tarjeta") or _(" tarjetas")),
        item_table = stat_items,
        is_borderless = true,
        onReturn = function(self) UIManager:close(self) end,
        onMenuHold = function(_, item)
            if item and item.hold_callback then item.hold_callback() end
        end,
    }
    UIManager:show(stats_menu)
end

-- ── Card export ─────────────────────────────────────────────────────────────

local function current_book_title(opts)
    local document = opts and opts.ui and opts.ui.document
    if not document or not document.getProps then return nil end
    local ok, props = pcall(document.getProps, document)
    if not (ok and props and type(props.title) == "string" and props.title ~= "") then return nil end
    local title = props.title:gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
    if #title > 100 then title = title:sub(1, 100) end
    return title ~= "" and title or nil
end

local function show_export_format(cards)
    local format_dialog
    local function close_format_dialog()
        if format_dialog then
            UIManager:close(format_dialog)
            format_dialog = nil
        end
    end
    local function export(format)
        local path, count, err = CardStorage.export_cards(cards, format)
        close_format_dialog()
        if path then
            local count_label = count == 1 and _("1 card")
                                or tostring(count) .. _(" cards")
            notify(_("Exported ") .. count_label .. _(" to ") .. path)
        elseif err == "no_cards" then
            notify(_("No cards to export"))
        else
            notify_error(_("Could not export cards"))
        end
    end

    format_dialog = ButtonDialog:new {
        title = _("Export Cards"),
        buttons = {
            {{ text = _("Export as CSV"), callback = function() export("csv") end }},
            {{ text = _("Export as TSV"), callback = function() export("tsv") end }},
            {{ text = _("Cancel"), callback = close_format_dialog }},
        },
    }
    UIManager:show(format_dialog)
end

local function show_export_scope(opts)
    local all_cards = CardStorage.load_cards()
    if #all_cards == 0 then
        notify(_("No cards to export"))
        return
    end

    local scope_dialog
    local function close_scope_dialog()
        if scope_dialog then
            UIManager:close(scope_dialog)
            scope_dialog = nil
        end
    end
    local function choose_cards(cards)
        close_scope_dialog()
        if #cards == 0 then
            notify(_("No cards to export"))
            return
        end
        show_export_format(cards)
    end

    local buttons = {
        {{ text = _("All Cards (") .. tostring(#all_cards) .. ")", callback = function()
            choose_cards(all_cards)
        end }},
    }

    local current_book = current_book_title(opts)
    if current_book then
        table.insert(buttons, {{ text = _("Current Book: ") .. current_book, callback = function()
            choose_cards(cards_for_book(all_cards, current_book))
        end }})
    end

    table.insert(buttons, {{ text = _("Choose Book"), callback = function()
        close_scope_dialog()
        local books, seen = {}, {}
        for index, card in ipairs(all_cards) do
            local book_key = (card.book_title and card.book_title ~= "")
                             and card.book_title or MISSING_BOOK
            if not seen[book_key] then
                seen[book_key] = true
                table.insert(books, {
                    key = book_key,
                    label = book_key == MISSING_BOOK and _("Unknown book") or book_key,
                })
            end
        end
        table.sort(books, function(left, right)
            if left.label == right.label then
                return left.key == MISSING_BOOK and right.key ~= MISSING_BOOK
            end
            return left.label < right.label
        end)

        local book_dialog
        local book_buttons = {}
        for _, book in ipairs(books) do
            local selected_book = book
            table.insert(book_buttons, {{ text = selected_book.label, callback = function()
                UIManager:close(book_dialog)
                choose_cards(cards_for_book(all_cards, selected_book.key))
            end }})
        end
        table.insert(book_buttons, {{ text = _("Cancel"), callback = function()
            UIManager:close(book_dialog)
        end }})
        book_dialog = ButtonDialog:new {
            title = _("Export Book"),
            buttons = book_buttons,
        }
        UIManager:show(book_dialog)
    end }})
    table.insert(buttons, {{ text = _("Cancel"), callback = function()
        close_scope_dialog()
    end }})

    scope_dialog = ButtonDialog:new {
        title = _("Export Cards"),
        buttons = buttons,
    }
    UIManager:show(scope_dialog)
end

-- ── Management submenu ────────────────────────────────────────────────────────

local function show_recovery_report(base_config, report)
    local menu
    local function apply(changes)
        if menu then UIManager:close(menu) end
        local progress, job
        local function show_progress(state)
            if progress then UIManager:close(progress) end
            progress = ButtonDialog:new {title = _("Actualizando en el Kobo: ") .. state.processed .. "/" .. state.total,
                tap_close_callback = function() if job then job:cancel() end end,
                buttons = {{{text = _("Cancelar"), callback = function() if job then job:cancel() end end}}}}
            UIManager:show(progress)
        end
        local err
        job, err = AnkiImport.apply_updates(effective_config(base_config), changes, function(result)
            if progress then UIManager:close(progress) end
            local text = result.updated .. _(" tarjetas actualizadas en el Kobo.") .. "\n" .. result.failed .. _(" no aplicadas.")
            if (result.skipped or 0) > 0 then text = text .. "\n" .. result.skipped .. _(" sin procesar.") end
            if result.cancelled then text = _("Actualización cancelada. Lo completado se conserva.\n") .. text end
            if #result.errors > 0 then text = text .. "\n\n" .. table.concat(result.errors, "\n") end
            UIManager:show(InfoMessage:new {text = text .. _("\n\nAnki no se ha modificado. Vuelve a recuperar para revisar el estado actual.")})
        end, function(state) if state.processed % 5 == 0 or state.processed == state.total then show_progress(state) end end)
        if not job then notify_error(err); return end
        show_progress({processed = 0, total = #changes})
    end
    local function compare(change)
        local dialog
        local reasons = {remote_changed = _("Cambió en Anki; no se detectaron cambios locales."),
            conflict = _("Hay cambios tanto en el Kobo como en Anki."),
            unverified_change = _("La vinculación es antigua y no hay una base de comparación fiable.")}
        dialog = ButtonDialog:new {title = _("Comparar versiones"), buttons = {
            {{text = _("Ver qué campos cambiaron"), callback = function()
                local fields = Recovery.differences(change.local_card, change.remote_card)
                UIManager:show(InfoMessage:new {text = (#fields > 0 and table.concat(fields, ", ") or _("Se detectó un cambio de versión o de imagen.")) ..
                    _("\n\nLas vistas son resúmenes. Para examinar campos largos completos, revísalos en Anki antes de confirmar.")})
            end}},
            {{text = _("Ver versión del Kobo"), callback = function() UIManager:show(InfoMessage:new {text = Recovery.preview(change.local_card)}) end}},
            {{text = _("Ver versión de Anki"), callback = function() UIManager:show(InfoMessage:new {text = Recovery.preview(change.remote_card)}) end}},
            {{text = _("Usar versión de Anki en el Kobo"), enabled = not report.source_changed, callback = function()
                UIManager:show(ConfirmBox:new {text = (reasons[change.reason] or "") ..
                    _("\n\n¿Reemplazar el contenido de esta tarjeta local por la versión de Anki? Se conservan las posiciones locales de subrayados y no se modifica Anki."),
                    ok_text = _("Actualizar en el Kobo"), ok_callback = function() UIManager:close(dialog); apply({change}) end})
            end}},
            {{text = _("Conservar la versión local"), callback = function() UIManager:close(dialog) end}},
        }}
        UIManager:show(dialog)
    end
    local safe = {}
    for _i, change in ipairs(report.changes) do if not change.conflict then safe[#safe+1] = change end end
    local items = {
        {text = _("Perfil: ") .. (report.source and report.source.profile or _("no verificado")), select_enabled = false},
        {text = report.imported .. _(" nuevas · ") .. report.existing .. _(" vinculadas revisadas"), select_enabled = false},
        {text = report.moved .. _(" cambios de baraja · ") .. report.changed .. _(" cambios de contenido"), select_enabled = false},
        {text = report.conflicts .. _(" conflictos · ") .. report.missing .. _(" no encontradas"), select_enabled = false},
        {text = report.out_of_scope .. _(" fuera de ámbito · ") .. report.foreign .. _(" de otro origen"), select_enabled = false},
        {text = report.failed .. _(" errores · ") .. report.image_warnings .. _(" avisos de imagen"), select_enabled = false},
        {text = _("Actualizar cambios sin conflicto (") .. #safe .. ")", select_enabled = #safe > 0 and not report.source_changed,
            callback = function()
                if #safe == 0 or report.source_changed then return end
                UIManager:show(ConfirmBox:new {text = _("¿Adoptar en el Kobo los cambios de Anki sin conflicto local? Se volverán a comprobar ambas versiones antes de guardar. No se modifica Anki ni se borran tarjetas."),
                    ok_text = _("Actualizar en el Kobo"), ok_callback = function() apply(safe) end})
            end},
    }
    if report.cancelled then table.insert(items, 1, {text = _("Cancelada: se conserva lo completado"), select_enabled = false}) end
    if report.incomplete and not report.cancelled then table.insert(items, 1, {text = _("Revisión incompleta: se conserva lo completado"), select_enabled = false}) end
    if report.source_changed then table.insert(items, 1, {text = _("Origen distinto: revisión detenida"), select_enabled = false}) end
    for _i, change in ipairs(report.changes) do
        local entry = change
        local title = entry.local_card.phrase or tostring(entry.id)
        if #title > 100 then title = (title:sub(1, 90):match("^(.*)%s") or tostring(entry.id)) .. "…" end
        items[#items+1] = {text = (entry.conflict and _("[Conflicto] ") or _("[Cambió] ")) .. title,
            callback = function() compare(entry) end}
    end
    for _i, issue in ipairs(report.issues) do
        local entry = issue
        local title = entry.phrase or tostring(entry.id)
        if #title > 100 then title = (title:sub(1, 90):match("^(.*)%s") or tostring(entry.id)) .. "…" end
        items[#items+1] = {text = _("[Revisar] ") .. title, callback = function() UIManager:show(InfoMessage:new {text = entry.reason}) end}
    end
    items[#items+1] = {text = _("Ayuda y errores de recuperación"), callback = function()
        local text = _("Los cambios de baraja solo actualizan metadatos. Las notas desaparecidas se conservan y no se recrean automáticamente. Si cambiaste de tipo o etiqueta, revísalas en Anki. Conservar la versión local no envía ni sobrescribe nada en Anki.")
        if #report.errors > 0 then text = text .. "\n\n" .. table.concat(report.errors, "\n") end
        UIManager:show(InfoMessage:new {text = text})
    end}
    menu = Menu:new {title = _("Recuperación desde Anki"), item_table = items, is_borderless = true,
        onReturn = function(self) UIManager:close(self) end,
        onMenuSelect = function(_, item) if item.select_enabled ~= false and item.callback then item.callback() end; return true end}
    UIManager:show(menu)
end

function CardManager.recover_from_anki(base_config)
    local cfg = effective_config(base_config)
    local model = NoteTypes.VOCABULARY
    UIManager:show(ConfirmBox:new {
        text = _("Recuperar del ordenador las notas de tipo ") .. model .. _(" y KOReader Learn")
            .. _(" con etiqueta KOReader.\n\nSe importan las nuevas y se revisan las vinculadas, aunque hayan cambiado de baraja, tipo o etiqueta. Los cambios de contenido requieren confirmación. No se borran tarjetas ni se modifica Anki."),
        ok_text = _("Recuperar"),
        ok_callback = function()
            local progress, job
            local function close_progress()
                if progress then UIManager:close(progress); progress = nil end
            end
            local function show_progress(report)
                close_progress()
                progress = ButtonDialog:new {
                    title = _("Recuperando de Anki: ") .. report.processed .. "/" .. report.total,
                    tap_close_callback = function() if job then job:cancel() end end,
                    buttons = {{{text = _("Cancelar"), callback = function()
                        if job then job:cancel() end
                    end}}},
                }
                UIManager:show(progress)
            end
            local err
            job, err = AnkiImport.start(cfg, function(report)
                close_progress()
                show_recovery_report(base_config, report)
            end, function(report)
                if report.processed == 0 or report.processed % 5 == 0 or report.processed == report.total then
                    show_progress(report)
                end
            end)
            if not job then notify_error(err); return end
            show_progress({processed = 0, total = 0})
        end,
    })
end

-- Actions are consumed directly by KOReader's native Tools menu.
function CardManager.menu_items(base_config, opts)
    local item_table = {
        {
            text = _("Sincronizar entre lectores"),
            enabled_func = function() return effective_config(base_config).sync_server ~= nil end,
            callback = function()
                local cfg = effective_config(base_config)
                if cfg.sync_server then CardSync.run_sync(cfg.sync_server, false, opts and opts.ui) end
            end,
        },
        {
            text = _("Recuperar desde Anki"),
            keep_menu_open = true,
            callback = function() CardManager.recover_from_anki(base_config) end,
        },
        {
            text = _("Enviar todas las pendientes a Anki"),
            bold = true,
            callback = function()
                local fresh        = CardStorage.load_cards()
                local sent, existing, skipped, failed, review = 0, 0, 0, 0, 0
                local errors = {}
                for _i, card in ipairs(fresh) do
                    if Recovery.needs_review(card) then review = review + 1
                    elseif not card.sent_to_anki then
                        local ok, err, receipt = send_one(effective_config(base_config), card, base_config, true)
                        if ok then
                            if receipt and receipt.status == "existing" then existing = existing + 1
                            else sent = sent + 1 end
                        else
                            failed = failed + 1
                            if #errors < 3 then errors[#errors+1] = (card.phrase or "") .. ": " .. tostring(err) end
                        end
                    else
                        skipped = skipped + 1
                    end
                end
                local msg = tostring(sent) .. _(" nuevas enviadas")
                    .. "\n" .. tostring(existing) .. _(" ya estaban en Anki")
                    .. "\n" .. tostring(skipped) .. _(" ya marcadas como enviadas")
                if review > 0 then msg = msg .. "\n" .. tostring(review) .. _(" requieren revisión; no reenviadas") end
                if failed > 0 then
                    msg = msg .. "\n" .. tostring(failed) .. _(" pendientes por error")
                        .. "\n\n" .. table.concat(errors, "\n")
                    notify_error(msg)
                else notify(msg) end
            end,
        },
        {
            text     = _("Aprendizaje desde anotaciones"),
            bold     = true,
            enabled  = opts and opts.on_inbox ~= nil or false,
            callback = function()
                if opts and opts.on_inbox then opts.on_inbox() end
            end,
        },
        {
            text = _("Exportar tarjetas"),
            bold = true,
            callback = function() show_export_scope(opts) end,
        },
        {
            text = _("Borrar tarjetas guardadas en el Kobo"),
            bold = true,
            callback = function()
                UIManager:show(ConfirmBox:new {
                    text        = _("¿Borrar todas las tarjetas guardadas en el Kobo? No borra las notas de Anki. Esta acción no se puede deshacer."),
                    ok_text     = _("Borrar del Kobo"),
                    ok_callback = function()
                        local ok = CardStorage.clear_all()
                        if not ok then notify_error(_("No se pudieron borrar las tarjetas del Kobo. No se guardaron los cambios.")); return end
                        notify(_("All cards cleared"))
                    end,
                })
            end,
        },
    }

    return item_table
end

CardManager.show_stats = show_stats

-- ── Card list with optional book filter ───────────────────────────────────────

local SORT_LABELS = {
    newest = _("Más recientes"),
    oldest = _("Más antiguas"),
    alpha = _("A–Z"),
}

local function card_added_order(card, index)
    local created_at = tonumber(card.created_at)
    local day
    if created_at then
        local ok, value = pcall(os.date, "%Y-%m-%d", created_at)
        if ok then day = value else created_at = nil end
    elseif type(card.date) == "string" then
        day = card.date:match("^(%d%d%d%d%-%d%d%-%d%d)")
    end
    return {day = day, timestamp = created_at, index = index}
end

local function newer_first(left, right)
    if left.order.day ~= right.order.day then
        if not left.order.day then return false end
        if not right.order.day then return true end
        return left.order.day > right.order.day
    end
    if left.order.timestamp and right.order.timestamp
        and left.order.timestamp ~= right.order.timestamp then
        return left.order.timestamp > right.order.timestamp
    end
    -- Legacy cards have only a calendar date. They were appended as they were
    -- added, so preserve that order within the same day.
    return left.order.index > right.order.index
end

local function card_sort_text(card)
    local text = card.kind == "learn" and (card.question or card.phrase) or card.phrase
    return type(text) == "string" and text:lower() or ""
end

function CardManager.show(base_config, filter_book, ui, target, on_back, options)
    options = options or {}
    local current_book = options.current_book or current_book_title({ui = ui})
    local scope_mode = options.scope_mode
    local sort_mode = options.sort_mode or "newest"
    if not SORT_LABELS[sort_mode] then sort_mode = "newest" end
    if options.auto_current_book and not filter_book then
        filter_book = current_book
        scope_mode = filter_book and "current" or "all"
    elseif not scope_mode then
        scope_mode = filter_book and (filter_book == current_book and "current" or "book") or "all"
    end
    if scope_mode == "all" then filter_book = nil end
    if scope_mode == "current" and current_book then filter_book = current_book end
    local anki_config = effective_config(base_config)
    local menu_instance

    local function refresh()
        if menu_instance then UIManager:close(menu_instance) end
        CardManager.show(base_config, filter_book, ui, nil, on_back, {
            current_book = current_book, scope_mode = scope_mode, sort_mode = sort_mode,
        })
    end

    local all_cards  = CardStorage.load_cards()
    local item_table = {}

    local function reopen_list(next_book, next_scope, next_sort, dialog)
        UIManager:close(dialog)
        if menu_instance then UIManager:close(menu_instance) end
        CardManager.show(base_config, next_book, ui, nil, on_back, {
            current_book = current_book, scope_mode = next_scope, sort_mode = next_sort,
        })
    end

    local function choose_book(dialog)
        UIManager:close(dialog)
        local books, seen = {}, {}
        for _, card in ipairs(all_cards) do
            local title = card.book_title
            if type(title) == "string" and title ~= "" and not seen[title] then
                seen[title] = true
                books[#books+1] = title
            end
        end
        table.sort(books, function(left, right) return left:lower() < right:lower() end)
        local picker
        local book_buttons = {}
        for _, title in ipairs(books) do
            local selected = title
            table.insert(book_buttons, {{ text = selected, callback = function()
                UIManager:close(picker)
                if menu_instance then UIManager:close(menu_instance) end
                CardManager.show(base_config, selected, ui, nil, on_back, {
                    current_book = current_book, scope_mode = "book", sort_mode = sort_mode,
                })
            end }})
        end
        table.insert(book_buttons, {{ text = _("Cancelar"),
            callback = function() UIManager:close(picker) end }})
        picker = ButtonDialog:new {title = _("Elegir libro"), buttons = book_buttons}
        UIManager:show(picker)
    end

    -- ── Filter and sort controls ───────────────────────────────────────────────
    local filter_label
    if scope_mode == "current" and filter_book then
        filter_label = _("Libro actual: ") .. filter_book
    elseif filter_book then
        filter_label = _("Libro: ") .. filter_book
    else
        filter_label = _("Libro: todos")
    end
    table.insert(item_table, {
        text = filter_label,
        bold = true,
        callback = function()
            local choices
            local buttons = {}
            if current_book then
                table.insert(buttons, {{ text = (scope_mode == "current" and "✓ " or "")
                    .. _("Solo el libro actual: ") .. current_book, callback = function()
                    reopen_list(current_book, "current", sort_mode, choices)
                end }})
            end
            table.insert(buttons, {{ text = (scope_mode == "all" and "✓ " or "")
                .. _("Todos los libros"), callback = function()
                reopen_list(nil, "all", sort_mode, choices)
            end }})
            table.insert(buttons, {{ text = _("Elegir otro libro…"), callback = function()
                choose_book(choices)
            end }})
            table.insert(buttons, {{ text = _("Cancelar"), callback = function()
                UIManager:close(choices)
            end }})
            choices = ButtonDialog:new {title = _("Filtrar tarjetas"), buttons = buttons}
            UIManager:show(choices)
        end,
    })
    table.insert(item_table, {
        text = _("Orden: ") .. SORT_LABELS[sort_mode],
        bold = true,
        callback = function()
            local choices
            local buttons = {}
            for _, mode in ipairs({"newest", "oldest", "alpha"}) do
                local selected_mode = mode
                table.insert(buttons, {{ text = (sort_mode == selected_mode and "✓ " or "")
                    .. SORT_LABELS[selected_mode], callback = function()
                    reopen_list(filter_book, scope_mode, selected_mode, choices)
                end }})
            end
            table.insert(buttons, {{ text = _("Cancelar"), callback = function()
                UIManager:close(choices)
            end }})
            choices = ButtonDialog:new {title = _("Ordenar tarjetas"), buttons = buttons}
            UIManager:show(choices)
        end,
    })

    -- ── Filtered card list ────────────────────────────────────────────────────
    local card_entries = {}
    local function matches_target(card)
        if not target then return true end
        if (target.kind == "learn") ~= (card.kind == "learn") then return false end
        if target.kind == "learn" then return card.card_id == target.card_id end
        if target.anki_note_id then return tostring(card.anki_note_id) == tostring(target.anki_note_id) end
        return card.phrase == target.phrase and (card.book_title or "") == (target.book_title or "")
            and (card.book_author or "") == (target.book_author or "")
            and (target.definition == nil or card.definition == target.definition)
            and (target.text == nil or card.text == target.text)
    end
    for source_index, card in ipairs(all_cards) do
        if (not filter_book or card.book_title == filter_book) and matches_target(card) then
            card_entries[#card_entries+1] = {
                card = card, source_index = source_index,
                order = card_added_order(card, source_index),
            }
        end
    end
    table.sort(card_entries, function(left, right)
        if sort_mode == "alpha" then
            local left_text, right_text = card_sort_text(left.card), card_sort_text(right.card)
            if left_text ~= right_text then return left_text < right_text end
            return newer_first(left, right)
        end
        if sort_mode == "oldest" then return newer_first(right, left) end
        return newer_first(left, right)
    end)
    local cards, source_indices = {}, {}
    for index, entry in ipairs(card_entries) do
        cards[index], source_indices[index] = entry.card, entry.source_index
    end

    if #cards == 0 then
        table.insert(item_table, {
            text = filter_book and _("(no cards for this book)")
                               or  _("(no saved cards yet)"),
        })
    end

    -- Fit each logical line at a fixed font size so the source fragment never
    -- gets pushed out by a long generated question or book title.
    local fit_line
    if #cards > 0 and not target then
        local Screen = require("device").screen
        local TextWidget = require("ui/widget/textwidget")
        local face = require("ui/font"):getFace("smallinfofont", 20)
        local margin = Screen:scaleBySize(100)
        local max_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9) - margin
        fit_line = function(text)
            local widget = TextWidget:new {text = text, face = face, max_width = max_width}
            local fitted, truncated = widget:getFittedText()
            widget:free()
            return fitted .. (truncated and "…" or "")
        end
    end
    for i, card in ipairs(cards) do
        local idx    = source_indices[i]
        local prefix = card.sent_to_anki and "↗ " or "○ "
        local warnings = {missing = _("[No encontrada] "), unverified_missing = _("[Revisar origen] "),
            unverified_scope = _("[Revisar origen] "), out_of_scope = _("[Fuera de ámbito] "),
            conflict = _("[Conflicto] "), unverified_change = _("[Revisar] "),
            identity_conflict = _("[Identidad distinta] "), remote_changed = _("[Cambió en Anki] "), local_changed = _("[Cambio local] ")}
        prefix = warnings[card.anki_sync_state] or prefix
        local label = not target and require("card_list_preview").label(card, prefix, fit_line) or ""

        local function open_viewer()
            if target and target.annotation_source then Annotations.bind(card, target.annotation_source) end
            if card.kind == "learn" then Learning.show(base_config, card, ui); return end
            local durable_identity = CardStorage.ensure_identity(card)
            local viewer_ref = {}
            local card_ref   = card
            local function media_callback(c, kind, callback)
                return CardMedia.wrap(c, kind, callback, function()
                    return viewer_ref[1] ~= nil and viewer_ref[1].card == c
                end)
            end
            local function make_viewer(show_back)
                local v
                if not card.image_path or card.image_path == "" then
                    local latest = CardStorage.find_by_phrase(card.phrase)
                    if latest and latest.image_path and latest.image_path ~= "" then card.image_path = latest.image_path end
                end
                local annotation_actions = Annotations.viewer_actions(ui or {}, card)
                v = CardViewer:new {
                    anki_base = base_config,
                    card      = card,
                    show_back = show_back,
                    read_only = false,
                    on_add_highlight = annotation_actions.on_add_highlight,
                    is_highlighted = annotation_actions.is_highlighted,
                    can_add_highlight = annotation_actions.can_add_highlight,
                    on_dismiss = function()
                        CardMedia.invalidate(card)
                        viewer_ref[1] = nil
                        require("reading_marker").flash(ui, card.annotation_source)
                    end,
                    on_show_answer = function()
                        -- Close whichever viewer is currently showing
                        -- (may differ from v after an async image update).
                        local cur = viewer_ref[1] or v
                        cur._replacing = true
                        UIManager:close(cur)
                        viewer_ref[1] = make_viewer(true)
                    end,
                    on_show_question = function()
                        local cur = viewer_ref[1] or v
                        cur._replacing = true
                        UIManager:close(cur)
                        viewer_ref[1] = make_viewer(false)
                    end,
                    on_viewer_updated = function(updated) viewer_ref[1] = updated end,
                    on_save = function()
                        local ok, err = CardStorage.save_card(card)
                        if ok then Annotations.highlight_saved(effective_config(base_config), ui, card) end
                        return ok, err
                    end,
                    on_regenerate = function()
                        NetworkMgr:runWhenOnline(function()
                            if not viewer_ref[1] or viewer_ref[1]._anki_closed then return end
                            local source = card.annotation_source
                            local selection = source and source.selection
                            local phrase = selection and selection.text or card.selected_text or card.phrase
                            require("vocab_generation").start(base_config, {phrase = phrase,
                                context = card.source_context or (selection and selection.text) or phrase,
                                title = card.book_title, author = card.book_author}, function(generated)
                                generated.book_title, generated.book_author = card.book_title, card.book_author
                                generated.source = generated.source or card.source
                                generated.highlight_pos0, generated.highlight_pos1 = card.highlight_pos0, card.highlight_pos1
                                Annotations.bind(generated, source)
                                if CardStorage.is_saved(card) then
                                    local ok, err = CardStorage.replace_card(card, generated)
                                    if not ok then notify_error(_("No se pudo guardar la tarjeta regenerada.")); return end
                                end
                                local current = viewer_ref[1]
                                CardMedia.invalidate(card)
                                if current then current._replacing = true; UIManager:close(current) end
                                card, card_ref = generated, generated
                                durable_identity = generated._storage_id ~= nil
                                viewer_ref[1] = make_viewer(false)
                            end, {regenerating = true, is_valid = function()
                                return viewer_ref[1] ~= nil and not (ui and ui.tearing_down)
                            end})
                        end)
                    end,
                    on_send = function()
                        return AnkiSync.send_card(anki_config, card, base_config)
                    end,
                    on_navigate_to_source = Annotations.can_navigate(ui, card) and function()
                        local cur = viewer_ref[1]
                        if cur then UIManager:close(cur) end
                        if menu_instance then UIManager:close(menu_instance) end
                        if ui.menu and ui.menu.onCloseReaderMenu then ui.menu:onCloseReaderMenu() end
                        local event_name = ui.paging and "GotoPage" or "GotoXPointer"
                        ui:handleEvent(Event:new(event_name, card.highlight_pos0))
                    end or nil,
                    on_update = function(updated_card)
                        local ok, err = CardStorage.update_card(card_ref, updated_card)
                        if ok then card_ref.phrase = updated_card.phrase; CardMedia.invalidate(card) end
                        return ok, err
                    end,
                    on_prepare_update = function(editing_card)
                        return CardStorage.ensure_identity(editing_card)
                    end,
                    on_regen_text = function()
                        NetworkMgr:runWhenOnline(function()
                            Feedback.run(function() return CardGenerator.generate_text(base_config, card.phrase) end,
                            function(new_text, new_prompt)
                                local old_text, old_prompt = card.text, card.image_prompt
                                card.text         = new_text
                                card.image_prompt = new_prompt
                                local saved, save_err = CardStorage.update_card(card_ref, card)
                                if not saved then
                                    card.text, card.image_prompt = old_text, old_prompt
                                    notify_error(save_err or _("Could not save regenerated text"))
                                    return
                                end
                                CardMedia.invalidate(card)
                                if viewer_ref[1] then viewer_ref[1]._replacing = true; UIManager:close(viewer_ref[1]) end
                                viewer_ref[1] = make_viewer(true)
                                -- Kick off image generation with new prompt.
                                if new_prompt then
                                    ImageGenerator.generate_async(
                                        base_config,
                                        new_prompt,
                                        card.phrase,
                                        media_callback(card, "image", function(img_path)
                                            local old_image = card.image_path
                                            card.image_path = img_path
                                            local image_saved = CardStorage.update_image_path(card, img_path)
                                            if not image_saved and card._storage_id then
                                                card.image_path = old_image
                                                CardStorage.remove_image_if_unreferenced(img_path)
                                                notify_error(_("Could not save the new image"))
                                                return
                                            end
                                            if old_image and old_image ~= "" then
                                                CardStorage.remove_image_if_unreferenced(old_image)
                                            end
                                            if Feedback.is_top(viewer_ref[1]) then
                                                viewer_ref[1] = viewer_ref[1]:update(card)
                                            end
                                        end),
                                        nil
                                    )
                                end
                            end, nil, {label = Feedback.REGENERATING})
                        end)
                    end,
                    on_regen_image = ImageGenerator.is_enabled(base_config) and function()
                        if not durable_identity then
                            notify_error(_("Could not safely update this card's image"))
                            return
                        end
                        if not card.image_prompt or card.image_prompt == "" then
                            notify(_("No image prompt available"))
                            return
                        end
                        local old_image = card.image_path
                        notify(_("Generando imagen…"))
                        ImageGenerator.generate_async(
                            base_config,
                            card.image_prompt,
                            card.phrase,
                            media_callback(card, "image", function(img_path)
                                card.image_path = img_path
                                local saved = CardStorage.update_image_path(card, img_path)
                                if not saved then
                                    CardStorage.remove_image_if_unreferenced(img_path)
                                    card.image_path = old_image
                                    notify_error(_("Could not save the new image"))
                                    return
                                end
                                if old_image and old_image ~= "" then
                                    CardStorage.remove_image_if_unreferenced(old_image)
                                end
                                if Feedback.is_top(viewer_ref[1]) then
                                    viewer_ref[1] = viewer_ref[1]:update(card)
                                end
                                UIManager:setDirty(nil, "full")
                                notify(_("New image loaded!"))
                            end),
                            function(err)
                                notify_error(_("Imagen: ") .. Feedback.image_message(err))
                            end
                        )
                    end,
                    on_regen_ipa = function(new_phrase, updated_card, new_viewer)
                        NetworkMgr:runWhenOnline(function()
                            UIManager:scheduleIn(0.05, function()
                                if updated_card.phrase ~= new_phrase then return end
                                local ipa, err = CardGenerator.generate_ipa(base_config, new_phrase)
                                if updated_card.phrase ~= new_phrase then return end
                                if ipa then
                                    updated_card.ipa = ipa
                                    CardStorage.update_card(card_ref, updated_card)
                                    local still_shown = false
                                    for w in UIManager:topdown_widgets_iter() do
                                        if w == new_viewer then still_shown = true; break end
                                    end
                                    if still_shown then new_viewer:update() end
                                    notify(_("IPA updated"))
                                else
                                    notify_error(_("IPA regen failed: ") .. (err or "unknown"))
                                end
                            end)
                        end)
                    end,
                }
                UIManager:show(v)
                return v
            end
            viewer_ref[1] = make_viewer(false)
            -- Auto-regenerate image if missing (e.g. synced card).
            -- Only poll AnkiVocab for cards that were created via AnkiVocab
            -- (_ankivocab_word is set); otherwise use the local image_prompt.
            local img_cfg = base_config
            local is_ankivocab_card = card._ankivocab_word and card._ankivocab_word ~= ""
            if is_ankivocab_card and ImageGenerator.is_enabled(base_config) then
                img_cfg = {}
                for k, v in pairs(base_config) do img_cfg[k] = v end
                img_cfg.image_provider = "ankivocab"
                img_cfg._ankivocab_word = card._ankivocab_word
            end
            local has_image_source = (card.image_prompt and card.image_prompt ~= "")
                                  or is_ankivocab_card
            if (not card.image_path or card.image_path == "")
                and has_image_source
                and ImageGenerator.is_enabled(base_config)
                and not (target and target._skip_auto_image)
                and not (ImageGenerator.is_pending and ImageGenerator.is_pending(card.phrase))
                and NetworkMgr:isOnline() and durable_identity then
                ImageGenerator.generate_async(
                    img_cfg,
                    card.image_prompt,
                    card.phrase,
                    media_callback(card, "image", function(img_path)
                        local previous = card.image_path
                        card.image_path = img_path
                        if not CardStorage.update_image_path(card, img_path) then
                            card.image_path = previous
                            CardStorage.remove_image_if_unreferenced(img_path)
                            return
                        end
                        if Feedback.is_top(viewer_ref[1]) then
                            viewer_ref[1] = viewer_ref[1]:update(card)
                        end
                    end),
                    nil  -- silent on error
                )
            end
            if card._audio_status == "pending" and is_ankivocab_card and NetworkMgr:isOnline() then
                require("audio_generator").poll_ankivocab_async(base_config, card._ankivocab_word,
                    media_callback(card, "audio", function(url)
                        if CardStorage.update_audio_url(card, url) then card._audio_url = url end
                    end), nil)
            end
        end

        local function open_context_menu()
            local dialog
            dialog = ButtonDialog:new {
                title   = card.phrase or "",
                buttons = {
                    {{ text = card.anki_note_id and _("Eliminar de Anki…") or _("Enviar a Anki"), callback = function()
                        UIManager:close(dialog)
                        if card.anki_note_id then
                            NetworkMgr:runWhenOnline(function()
                                require("anki_note_actions").confirm_delete(base_config, card, function(ok, message)
                                    if ok then refresh() end
                                    UIManager:show(InfoMessage:new {text = message})
                                end)
                            end)
                            return
                        end
                        if send_one(anki_config, card, base_config) then
                            notify(_("Sent!"))
                            refresh()
                        end
                    end }},
                    {{ text = _("Eliminar del Kobo…"), callback = function()
                        UIManager:close(dialog)
                        UIManager:show(ConfirmBox:new {
                            text        = _("¿Eliminar solo la copia del Kobo?\n\n") .. (card.phrase or "") .. _("\n\nNo se eliminará de Anki."),
                            ok_text     = _("Eliminar del Kobo"),
                            ok_callback = function()
                                if not CardStorage.ensure_identity(card) then
                                    notify_error(_("Could not safely delete this card"))
                                    return
                                end
                                local ok, err = CardStorage.delete_card_by_id(card._storage_id)
                                if not ok then
                                    notify_error(_("No se pudo borrar la tarjeta del Kobo. No se guardaron los cambios."))
                                    return
                                end
                                refresh()
                            end,
                        })
                    end }},
                    {{ text = _("Cancel"), callback = function()
                        UIManager:close(dialog)
                    end }},
                },
            }
            UIManager:show(dialog)
        end

        if target then open_viewer(); return end
        table.insert(item_table, {
            text          = label,
            card_preview  = require("card_list_preview").parts(card, prefix),
            callback      = open_viewer,
            hold_callback = open_context_menu,
        })
    end

    if target then notify_error(_("La tarjeta ya no está guardada. Actualiza la lista de anotaciones.")); return end
    local count_label = tostring(#cards) .. _(" de ") .. #all_cards

    local ListRows = require("card_list_rows")
    menu_instance = Menu:new {
        title      = _("Mis tarjetas (") .. count_label .. ")",
        subtitle = _("↗ Enviada a Anki · ○ Solo Kobo"),
        is_borderless = true,
        onReturn = function(self)
            UIManager:close(self)
            if filter_book then CardManager.show(base_config, nil, ui, nil, on_back, {
                current_book = current_book, scope_mode = "all", sort_mode = sort_mode,
            })
            elseif on_back then on_back() end
        end,
        items_per_page = ListRows.per_page(),
        items_font_size = 20,
        single_line = false,
        multilines_forced = true,
        multilines_show_more_text = false,
        item_table = item_table,
        onMenuHold = function(self, item)
            if item and item.hold_callback then item.hold_callback() end
        end,
    }
    ListRows.install(menu_instance)
    UIManager:show(menu_instance)
end

function CardManager.open_card(base_config, card, ui)
    CardManager.show(base_config, nil, ui, card)
end

return CardManager

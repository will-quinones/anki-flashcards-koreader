-- Card Manager: card list (with filter) + separate management submenu.

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

local function show_stats()
    local all_cards  = CardStorage.load_cards()
    local book_order = {}
    local book_stats = {}
    for _i, card in ipairs(all_cards) do
        local title = (card.book_title and card.book_title ~= "")
                      and card.book_title or _("Libro no identificado")
        if not book_stats[title] then
            book_stats[title] = { total = 0, sent = 0, review = 0 }
            table.insert(book_order, title)
        end
        book_stats[title].total = book_stats[title].total + 1
        if Recovery.needs_review(card) then book_stats[title].review = book_stats[title].review + 1
        elseif card.sent_to_anki then book_stats[title].sent = book_stats[title].sent + 1 end
    end

    local total_all, sent_all, review_all = #all_cards, 0, 0
    for _i, card in ipairs(all_cards) do
        if Recovery.needs_review(card) then review_all = review_all + 1
        elseif card.sent_to_anki then sent_all = sent_all + 1 end
    end

    local stat_items = {}
    if #book_order == 0 then
        table.insert(stat_items, { text = _("Todavía no hay tarjetas") })
    end
    for _i, title in ipairs(book_order) do
        local s      = book_stats[title]
        local unsent = s.total - s.sent - s.review
        local line   = title .. "  —  " .. tostring(s.total)
                       .. (s.total == 1 and _(" tarjeta · ") or _(" tarjetas · ")) .. tostring(s.sent) .. _(" enviadas")
        if unsent > 0 then
            line = line .. " · " .. tostring(unsent) .. _(" pendientes")
        end
        if s.review > 0 then line = line .. " · " .. s.review .. _(" por revisar") end
        table.insert(stat_items, { text = line })
    end

    local title_str = _("Estadísticas — ") .. tostring(total_all) .. (total_all == 1 and _(" tarjeta") or _(" tarjetas"))
    table.insert(stat_items, 1, {text = sent_all .. _(" enviadas · ") .. (total_all - sent_all - review_all)
        .. _(" pendientes · ") .. review_all .. _(" por revisar")})
    UIManager:show(Menu:new { title = title_str, item_table = stat_items, is_borderless = true,
        onReturn = function(self) UIManager:close(self) end })
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

function CardManager.show_manage(base_config, opts, collect)
    local manage_menu

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
                if manage_menu then UIManager:close(manage_menu) end
                if opts and opts.on_inbox then opts.on_inbox() end
            end,
        },
        {
            text = _("Borrar tarjetas guardadas en el Kobo"),
            bold = true,
            callback = function()
                UIManager:show(ConfirmBox:new {
                    text        = _("¿Borrar todas las tarjetas guardadas en el Kobo? No borra las notas de Anki. Esta acción no se puede deshacer."),
                    ok_text     = _("Borrar del Kobo"),
                    ok_callback = function()
                        CardStorage.clear_all()
                        notify(_("All cards cleared"))
                        if manage_menu then UIManager:close(manage_menu) end
                    end,
                })
            end,
        },
    }

    if collect then collect(item_table); return end
    manage_menu = Menu:new {
        title      = _("Manage"),
        item_table = item_table,
        is_borderless = true,
        onReturn = function(self) UIManager:close(self) end,
    }
    UIManager:show(manage_menu)
end

-- The native Tools menu reuses card actions, but never settings entries.
function CardManager.menu_items(base_config, opts)
    local items
    -- Build the same actions without showing a second configuration panel.
    CardManager.show_manage(base_config, opts, function(actions) items = actions end)
    return items
end

CardManager.show_stats = show_stats

-- ── Card list with optional book filter ───────────────────────────────────────

function CardManager.show(base_config, filter_book, ui, target, on_back)
    local anki_config = effective_config(base_config)
    local menu_instance

    local function refresh()
        if menu_instance then UIManager:close(menu_instance) end
        CardManager.show(base_config, filter_book, ui, nil, on_back)
    end

    local all_cards  = CardStorage.load_cards()
    local item_table = {}

    -- ── Filter entry ──────────────────────────────────────────────────────────
    local filter_label = filter_book
                         and (_("Libro: ") .. filter_book .. _(" (toca para ver todos)"))
                         or  _("Libro: todos · Learn y Vocab")
    table.insert(item_table, {
        text = filter_label,
        bold = true,
        callback = function()
            if filter_book then
                -- Clear filter.
                if menu_instance then UIManager:close(menu_instance) end
                CardManager.show(base_config, nil, ui, nil, on_back)
                return
            end
            -- Build book picker from stored cards.
            local books, seen = {}, {}
            for _i, card in ipairs(all_cards) do
                local t = (card.book_title and card.book_title ~= "")
                          and card.book_title or _("Unknown book")
                if not seen[t] then seen[t] = true; table.insert(books, t) end
            end
            local picker
            local book_buttons = {}
            for _i, b in ipairs(books) do
                local bref = b
                table.insert(book_buttons, {{ text = bref, callback = function()
                    UIManager:close(picker)
                    if menu_instance then UIManager:close(menu_instance) end
                    CardManager.show(base_config, bref, ui, nil, on_back)
                end }})
            end
            table.insert(book_buttons, {{ text = _("Cancel"),
                callback = function() UIManager:close(picker) end }})
            picker = ButtonDialog:new {
                title   = _("Filter by Book"),
                buttons = book_buttons,
            }
            UIManager:show(picker)
        end,
    })

    -- ── Filtered card list ────────────────────────────────────────────────────
    local cards = {}
    local source_indices = {}
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
            table.insert(cards, card)
            source_indices[#cards] = source_index
        end
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
            local viewer_ref = {}
            local card_ref   = { phrase = card.phrase }
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
                    on_show_answer = function()
                        -- Close whichever viewer is currently showing
                        -- (may differ from v after an async image update).
                        local cur = viewer_ref[1] or v
                        UIManager:close(cur)
                        viewer_ref[1] = make_viewer(true)
                    end,
                    on_show_question = function()
                        UIManager:close(viewer_ref[1] or v)
                        viewer_ref[1] = make_viewer(false)
                    end,
                    on_viewer_updated = function(updated) viewer_ref[1] = updated end,
                    on_save = function()
                        return nil, _("Already saved")
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
                        local ok, err = CardStorage.update_card(card_ref.phrase, updated_card)
                        if ok then card_ref.phrase = updated_card.phrase end
                        return ok, err
                    end,
                    on_regen_text = function()
                        NetworkMgr:runWhenOnline(function()
                            Feedback.run(function() return CardGenerator.generate_text(base_config, card.phrase) end,
                            function(new_text, new_prompt)
                                card.text         = new_text
                                card.image_prompt = new_prompt
                                CardStorage.update_card(card_ref.phrase, card)
                                if viewer_ref[1] then UIManager:close(viewer_ref[1]) end
                                viewer_ref[1] = make_viewer(true)
                                -- Kick off image generation with new prompt.
                                if new_prompt then
                                    ImageGenerator.generate_async(
                                        base_config,
                                        new_prompt,
                                        card.phrase,
                                        function(img_path)
                                            card.image_path = img_path
                                            CardStorage.update_image_path(card.phrase, img_path)
                                            if Feedback.is_top(viewer_ref[1]) then
                                                viewer_ref[1] = viewer_ref[1]:update(card)
                                            end
                                        end,
                                        nil
                                    )
                                end
                            end, nil, {label = Feedback.REGENERATING})
                        end)
                    end,
                    on_regen_image = ImageGenerator.is_enabled(base_config) and function()
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
                            function(img_path)
                                if old_image and old_image ~= "" then
                                    os.remove(old_image)
                                end
                                card.image_path = img_path
                                CardStorage.update_image_path(card.phrase, img_path)
                                if Feedback.is_top(viewer_ref[1]) then
                                    viewer_ref[1] = viewer_ref[1]:update(card)
                                end
                                UIManager:setDirty(nil, "full")
                                notify(_("New image loaded!"))
                            end,
                            function(err)
                                notify_error(_("Imagen: ") .. Feedback.image_message(err))
                            end
                        )
                    end,
                    on_regen_ipa = function(new_phrase, updated_card, new_viewer)
                        NetworkMgr:runWhenOnline(function()
                            UIManager:scheduleIn(0.05, function()
                                local ipa, err = CardGenerator.generate_ipa(base_config, new_phrase)
                                if ipa then
                                    updated_card.ipa = ipa
                                    CardStorage.update_card(updated_card.phrase, updated_card)
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
                and not (target and target._skip_auto_image)
                and not (ImageGenerator.is_pending and ImageGenerator.is_pending(card.phrase))
                and NetworkMgr:isOnline() then
                ImageGenerator.generate_async(
                    img_cfg,
                    card.image_prompt,
                    card.phrase,
                    function(img_path)
                        card.image_path = img_path
                        CardStorage.update_image_path(card.phrase, img_path)
                        if Feedback.is_top(viewer_ref[1]) then
                            viewer_ref[1] = viewer_ref[1]:update(card)
                        end
                    end,
                    nil  -- silent on error
                )
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
                                CardStorage.delete_card(idx)
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
            if filter_book then CardManager.show(base_config, nil, ui, nil, on_back)
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

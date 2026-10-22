-- Sequential, cancellable generation from a confirmed selection of annotations.
-- No sends to Anki: all successful cards are saved locally for review.
local Storage = require("card_storage")
local Generator = require("card_generator")
local Context = require("learning_context")
local A = require("annotation_tools")
local State = require("settings_state")
local Feedback = require("generation_feedback")
local UI = require("ui/uimanager")
local ImageGenerator = require("image_generator")
local Batch = {}
local running = false

local function current(ui, snapshot)
    if ui.tearing_down or not A.same_book(ui, snapshot) then return nil, "El libro cambió o se cerró. Se conserva lo generado." end
    local s = snapshot.selection
    for _, ann in ipairs((ui.annotation and ui.annotation.annotations) or {}) do
        if A.same_position(ann.pos0, s.pos0) and A.same_position(ann.pos1, s.pos1)
            and ann.text == s.text and (ann.note or "") == (s.note or "") then return ann end
    end
    return nil, "La anotación se borró o cambió. Actualiza la lista antes de generar."
end

function Batch.start(ui, base, snapshots, kind, on_done, on_progress)
    if running then return nil, "Ya hay una generación por lotes en curso." end
    if kind ~= "vocab" and kind ~= "learn" then return nil, "Elige Anki Vocab o Anki Learn." end
    if #snapshots == 0 then return nil, "No hay anotaciones seleccionadas." end
    local cfg = State.merge(base, Storage.load_anki_settings())
    local provider = cfg.text_provider or "dashscope"
    local keys = {gemini = "gemini_api_key", openrouter = "openrouter_api_key",
        deepseek = "deepseek_api_key", openai = "openai_api_key",
        dashscope = "dashscope_api_key", ankivocab = "ankivocab_api_key"}
    if not keys[provider] then return nil, "Selecciona un servicio de texto válido en Configuración." end
    if kind == "learn" and provider == "ankivocab" then return nil, "AnkiVocab solo genera vocabulario. Elige otro servicio para Learn." end
    if not State.has_key(cfg[keys[provider]] or (provider == "dashscope" and cfg.api_key)) then
        return nil, "Añade la clave API del servicio antes de generar tarjetas."
    end
    running = true
    local job, runner, ended = {cancelled = false}, nil, false
    local report = {generated = 0, existing = 0, invalid = 0, failed = 0, processed = 0,
        total = #snapshots, cards = {}, errors = {}}
    local index, attempted, consecutive_failures = 1, {}, 0
    local function detail(err) if #report.errors < 5 then report.errors[#report.errors+1] = tostring(err) end end
    local function finish()
        if ended then return end
        ended, running = true, false
        report.cancelled, report.remaining = job.cancelled, #snapshots - report.processed
        if on_done then on_done(report) end
    end
    function job:cancel()
        self.cancelled = true
        if runner then runner:cancel() else finish() end
    end
    local step
    local function next_item()
        if ended then return end
        index, report.processed = index + 1, report.processed + 1
        if on_progress then on_progress(report, job) end
        UI:scheduleIn(0.05, step)
    end
    step = function()
        if ended then return end
        runner = nil
        if job.cancelled or index > #snapshots then finish(); return end
        local snapshot = snapshots[index]
        if not snapshot or not A.valid_range(snapshot.selection)
            or type(snapshot.selection.text) ~= "string" or not snapshot.selection.text:match("%S") then
            report.invalid = report.invalid + 1; detail("La anotación no tiene un fragmento de libro utilizable."); next_item(); return
        end
        local ann, err = current(ui, snapshot)
        if not ann then
            report.invalid = report.invalid + 1; detail(err)
            if ui.tearing_down or not A.same_book(ui, snapshot) then report.processed = report.processed + 1; finish() else next_item() end
            return
        end
        local existing = A.find_card(snapshot, kind, Storage.load_cards())
        if existing or attempted[snapshot.origin_key] then
            report.existing = report.existing + 1
            if existing then report.cards[#report.cards+1] = existing end
            next_item(); return
        end
        attempted[snapshot.origin_key] = true
        local source; source, err = Context.capture(ui, ann, {restore_selection = false, include_reader_note = kind == "learn"})
        if not source or (kind == "vocab" and #source.selected > 2000) then
            report.invalid = report.invalid + 1; detail(err or "El fragmento es muy largo para Vocab. Usa Learn."); next_item(); return
        end
        if kind == "learn" and source.context_quality == "selection" and not source.selected:match("%S+%s+%S+%s+%S+%s+%S+") then
            report.invalid = report.invalid + 1; detail("Falta contexto para esta idea. Selecciona una frase o párrafo."); next_item(); return
        end
        if on_progress then on_progress(report, job) end
        if ended or job.cancelled then finish(); return end
        runner = Feedback.run(function()
            if kind == "learn" then return Generator.generate_learning(cfg, source) end
            return Generator.generate(cfg, source.selected, source.context, source.title, source.author)
        end, function(card)
            local still_current, why = current(ui, snapshot)
            if not still_current then report.invalid = report.invalid + 1; report.processed = report.processed + 1; detail(why); finish(); return end
            if type(card) ~= "table" or type(card.phrase) ~= "string" or not card.phrase:match("%S")
                or (kind == "vocab" and (type(card.definition) ~= "string" or type(card.text) ~= "string")) then
                report.failed, consecutive_failures = report.failed + 1, consecutive_failures + 1
                detail("La IA devolvió una tarjeta incompleta. No se guardó.")
                if consecutive_failures >= 3 then report.processed = report.processed + 1; finish() else next_item() end
                return
            end
            consecutive_failures = 0
            if kind == "vocab" then
                card.book_title, card.book_author = source.title, source.author
                if not card.source or card.source == "" then
                    card.source = (cfg.target_language or "English") == "English" and
                        ("https://dictionary.cambridge.org/dictionary/english/" .. (card.phrase or ""):lower():gsub("%s+", "-"))
                        or ((source.title or "") .. " — " .. (source.author or ""))
                end
            end
            A.bind(card, snapshot)
            local write_ok, saved, save_err = pcall(Storage.save_card, card)
            if not write_ok then saved, save_err = false, "storage_error" end
            if saved then
                report.generated = report.generated + 1; report.cards[#report.cards+1] = card
                if kind == "vocab" and card.image_prompt and ImageGenerator.is_enabled(cfg) then
                    card._skip_auto_image = true -- reviewing this result must not start a second paid job
                    local image_cfg = cfg
                    if cfg.image_provider == "ankivocab" then
                        image_cfg = {}; for key, value in pairs(cfg) do image_cfg[key] = value end
                        image_cfg._ankivocab_word = card._ankivocab_word or source.selected
                        image_cfg._ankivocab_image_url = card._image_url
                    end
                    ImageGenerator.generate_async(image_cfg, card.image_prompt, card.phrase, function(path)
                        card.image_path = path; Storage.update_image_path(card.phrase, path)
                    end, nil)
                end
            elseif save_err == "already_saved" then
                local known
                if kind == "learn" then known = Storage.find_learning_card(card.card_id)
                else known = Storage.find_by_phrase(card.phrase) end
                if known then
                    local linked = Storage.add_annotation_alias(known, snapshot.origin_key)
                    if not linked then
                        report.failed = report.failed + 1; report.processed = report.processed + 1
                        detail("La tarjeta ya existe, pero no se pudo guardar su relación con esta anotación."); finish(); return
                    end
                    report.cards[#report.cards+1] = known
                else
                    report.failed = report.failed + 1; report.processed = report.processed + 1
                    detail("La lista de tarjetas cambió durante la generación. Actualízala antes de continuar."); finish(); return
                end
                report.existing = report.existing + 1
            else
                report.failed = report.failed + 1; report.processed = report.processed + 1
                detail("No se pudo guardar en el lector. Se conserva lo completado."); finish(); return
            end
            next_item()
        end, function(message, info)
            if info.kind == "cancelled" then finish(); return end
            report.failed, consecutive_failures = report.failed + 1, consecutive_failures + 1; detail(message)
            if (info.kind == "validation" or info.kind == "invalid") and consecutive_failures < 3 then next_item()
            else report.processed = report.processed + 1; finish() end
        end, {quiet = true, label = "Generando tarjeta " .. index .. "/" .. #snapshots .. "…"})
    end
    UI:scheduleIn(0.05, step)
    return job
end
return Batch

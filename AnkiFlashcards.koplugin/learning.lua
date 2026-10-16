local Context = require("learning_context")
local Learn = require("learning_card")
local Generator = require("card_generator")
local Storage = require("card_storage")
local State = require("settings_state")
local AnkiSync = require("anki_sync")
local Viewer = require("card_viewer")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local InfoMessage = require("ui/widget/infomessage")
local Feedback = require("generation_feedback")
local Annotations = require("annotation_tools")
local Learning = {}
local function message(text) UIManager:show(InfoMessage:new {text = text}) end

function Learning.show(base, card, ui)
    local current
    local function open(back)
        local viewer
        local annotation_actions = Annotations.viewer_actions(ui or {}, card)
        viewer = Viewer:new {
            anki_base = base,
            card = card, show_back = back or false, read_only = card.sent_to_anki == true,
            on_show_answer = function() if current then UIManager:close(current) end; open(true) end,
            on_show_question = function() if current then UIManager:close(current) end; open(false) end,
            on_viewer_updated = function(updated) current = updated end,
            on_add_highlight = annotation_actions.on_add_highlight,
            is_highlighted = annotation_actions.is_highlighted,
            can_add_highlight = annotation_actions.can_add_highlight,
            on_save = function()
                local ok, err = Storage.save_learning_card(card)
                if ok then
                    local cfg = State.merge(base, Storage.load_anki_settings())
                    local highlighted, highlight_err = Annotations.highlight_saved(cfg, ui, card)
                    if not highlighted then message(highlight_err or "La tarjeta se guardó, pero no se pudo subrayar.") end
                end
                return ok, err == "already_saved" and "La tarjeta ya está guardada." or err
            end,
            on_send = function()
                local cfg = State.merge(base, Storage.load_anki_settings())
                local ok, err = AnkiSync.send_card(cfg, card)
                if ok and current then current.read_only = true end
                return ok, err
            end,
            on_update = function(updated)
                updated.phrase = updated.question
                if Storage.find_learning_card(updated.card_id) then
                    return Storage.save_learning_card(updated, true)
                end
                return true
            end,
            on_regenerate = not card.sent_to_anki and function()
                if card.sent_to_anki then message("La tarjeta ya está en Anki. Edítala allí."); return end
                local source = {selected = card.selected_text, context = card.source_context,
                    title = card.book_title, author = card.book_author, chapter = card.chapter,
                    location = card.location, context_quality = card.context_quality,
                    reader_note = card.reader_note,
                    pos0 = card.highlight_pos0, pos1 = card.highlight_pos1}
                NetworkMgr:runWhenOnline(function()
                    Feedback.run(function()
                        local cfg = State.merge(base, Storage.load_anki_settings())
                        return Generator.generate_learning(cfg, source)
                    end, function(candidate)
                        candidate.card_id = card.card_id
                        Annotations.bind(candidate, card.annotation_source)
                        if Storage.find_learning_card(card.card_id) then
                            local ok, save_err = Storage.save_learning_card(candidate, true)
                            if not ok then message(save_err); return end
                        end
                        if current then UIManager:close(current) end
                        card = candidate
                        open(false)
                    end, nil, {label = Feedback.REGENERATING})
                end)
            end or nil,
        }
        current = viewer
        UIManager:show(viewer)
        return viewer
    end
    return open(false)
end

function Learning.start(base, ui, selection)
    local source, err = Context.capture(ui, selection)
    if not source then message(err); return end
    local snapshot = Annotations.capture(ui, selection)
    local existing = Storage.find_learning_card(Learn.id(source))
    if existing then
        Annotations.bind(existing, snapshot)
        if ui.highlight then ui.highlight:onClose() end
        return Learning.show(base, existing, ui)
    end
    if source.context_quality == "selection" and not source.selected:match("%S+%s+%S+%s+%S+%s+%S+") then
        message("No se pudo extraer contexto suficiente. Selecciona una frase o párrafo que explique la idea.")
        return
    end
    local cfg = State.merge(base, Storage.load_anki_settings())
    -- All text and positions are captured before closing the dictionary or
    -- selection. The scheduled request uses this immutable source snapshot.
    if ui.highlight then ui.highlight:onClose() end
    NetworkMgr:runWhenOnline(function()
        Feedback.run(function() return Generator.generate_learning(cfg, source) end, function(card)
            Annotations.bind(card, snapshot)
            Learning.show(base, card, ui)
        end)
    end)
end
return Learning

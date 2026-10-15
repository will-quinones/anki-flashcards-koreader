-- Explicit remote deletion only. Requires AnkiConnect's session-protected
-- RPC API; never fall back to an unguarded delete in a possibly changed profile.
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("json")
local Sync = require("anki_sync")
local Storage = require("card_storage")
local R = require("anki_recovery")
local Types = require("note_types")
local Actions = {}

-- Live, read-only toward Anki. A successful match may repair a missing local
-- delivery receipt; never infer absence from a transport or profile error.
function Actions.status(config, card)
    if not config or not config.url or config.url == "" then return nil, "Configura la conexión con Anki." end
    local source, err = Sync.source_identity(config.url)
    if not source then return nil, err end
    if card.anki_source and not R.same_source(card.anki_source, source) then
        return nil, "Abre el perfil de Anki vinculado a esta tarjeta."
    end
    local ids = card.anki_note_id and {card.anki_note_id}
    if not ids then
        local function quote(s) return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
        local field = card.kind == "learn" and ("PluginID:" .. (card.card_id or "")) or ("Phrase:" .. (card.phrase or ""))
        ids, err = Sync.read(config.url, "findNotes", {query = "note:" .. quote(Types.model_name(card.kind)) .. " " .. quote(field)})
        if type(ids) ~= "table" then return nil, err or "No se pudo buscar la nota en Anki." end
    end
    local notes
    if #ids > 0 then
        notes, err = Sync.read(config.url, "notesInfo", {notes = ids})
        if type(notes) ~= "table" then return nil, err or "No se pudo consultar la nota de Anki." end
    else notes = {} end
    local match
    for _, note in ipairs(notes) do
        if type(note) == "table" and note.noteId then
            local fields = note.fields or {}
            local key = card.kind == "learn" and "PluginID" or "Phrase"
            local expected = card.kind == "learn" and card.card_id or card.phrase
            if note.modelName ~= Types.model_name(card.kind) or not fields[key] or fields[key].value ~= expected then
                return nil, "La identidad de la nota cambió. Usa Recuperar desde Anki."
            end
            if match then return nil, "Hay varias notas coincidentes. Revísalas en Anki antes de eliminar." end
            if not card.anki_note_id then
                local expected_fields = card.kind == "learn" and require("learning_card").fields(card)
                    or {Definition = card.definition or "", Text = card.text or ""}
                for _, name in ipairs(card.kind == "learn" and {"Question", "Answer"} or {"Definition", "Text"}) do
                    if not fields[name] or fields[name].value ~= expected_fields[name] then
                        return nil, "La nota existente tiene otro contenido. Usa Recuperar desde Anki."
                    end
                end
            end
            match = note
        elseif type(note) ~= "table" or next(note) ~= nil then
            return nil, "Anki devolvió una nota inválida. No se pudo verificar su estado."
        end
    end
    local again; again, err = Sync.source_identity(config.url)
    if not again or not R.same_source(source, again) then return nil, err or "El perfil de Anki cambió durante la consulta." end
    if not match then return "absent" end
    if not card.anki_note_id then
        local cards; cards, err = Sync.read(config.url, "cardsInfo", {cards = match.cards or {}})
        if type(cards) ~= "table" or not cards[1] or not cards[1].deckName then return nil, err or "No se pudo verificar el deck de la nota." end
        again, err = Sync.source_identity(config.url)
        if not again or not R.same_source(source, again) then return nil, err or "El perfil de Anki cambió durante la consulta." end
        local saved; saved, err = Storage.record_sent(card, {note_id = match.noteId, source = source,
            model = match.modelName, deck = cards[1].deckName})
        if not saved then return nil, err end
    end
    return "present"
end

local function rpc(config, method, params)
    local body = json.encode({jsonrpc = "2.0", id = 1, method = method, params = params or {}})
    local response = {}
    http.TIMEOUT = 5
    local ok, result, code = pcall(http.request, {url = config.url:gsub("/+$", "") .. "/api/v1", method = "POST",
        headers = {["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body)},
        source = ltn12.source.string(body), sink = ltn12.sink.table(response)})
    if not ok or not result then return nil, "No se pudo conectar con Anki. No se confirmó ninguna eliminación." end
    if tostring(code) ~= "200" then return nil, "Este AnkiConnect no permite el borrado protegido. Elimina la nota desde Anki." end
    local decoded, data = pcall(json.decode, table.concat(response))
    if not decoded or type(data) ~= "table" then return nil, "Anki devolvió una respuesta inválida. No se confirmó la eliminación." end
    if data.error then
        local kind = type(data.error.data) == "table" and data.error.data.type
        if kind == "staleSession" then return nil, "Anki cambió de colección o perfil. Vuelve a revisar la tarjeta antes de eliminar.", kind end
        if kind == "notFound" then return nil, "La nota ya no está en Anki.", kind end
        if kind == "editorConflict" or kind == "busy" then return nil, "Anki está ocupado. Cierra su editor e inténtalo de nuevo.", kind end
        return nil, "No se pudo preparar una eliminación segura. Usa Anki o actualiza AnkiConnect.", kind
    end
    if data.result == nil then return nil, "Anki no confirmó el resultado." end
    return data.result
end
local function note_fingerprint(note)
    local values = {tostring(note.id), tostring(note.modifiedAt or ""), tostring(note.noteType.id), note.noteType.name}
    local keys = {}; for key in pairs(note.fields) do keys[#keys+1] = key end; table.sort(keys)
    for _, key in ipairs(keys) do
        local value = tostring(note.fields[key])
        values[#values+1] = #key .. ":" .. key .. #value .. ":" .. value
    end
    for _, id in ipairs(note.cardIds or {}) do values[#values+1] = tostring(id) end
    return R.hash(table.concat(values, "\0"))
end
local function linked(card)
    local found
    for _, item in ipairs(Storage.load_cards()) do
        if tostring(item.anki_note_id) == tostring(card.anki_note_id) then
            if found then return nil end
            found = item
        end
    end
    return found
end
function Actions.prepare_delete(config, card)
    if not config or not config.url or config.url == "" or not card.anki_note_id then return nil, "La tarjeta no tiene una nota de Anki vinculada." end
    local local_card = linked(card)
    if not local_card then return nil, "No se pudo verificar la tarjeta local. Usa Recuperar desde Anki." end
    local collection, err = rpc(config, "collection.get", {})
    if type(collection) ~= "table" or type(collection.session) ~= "string" then return nil, err or "No se pudo proteger la colección de Anki." end
    local source; source, err = Sync.source_identity(config.url)
    if not source or source.profile ~= collection.profile then return nil, err or "El perfil de Anki cambió. Reintenta." end
    if local_card.anki_source and not R.same_source(local_card.anki_source, source) then
        return nil, "La tarjeta pertenece a otro perfil/origen. Abre el perfil correcto."
    end
    local note, kind
    note, err, kind = rpc(config, "notes.get", {id = tostring(card.anki_note_id), session = collection.session})
    if not note then
        if kind == "notFound" and local_card.anki_source then
            return {id = card.anki_note_id, source = source, session = collection.session,
                local_stamp = R.stamp(local_card), missing = true}
        end
        return nil, err
    end
    local model_id = card.kind == "learn" and source.learn_id or source.vocabulary_id
    if type(note) ~= "table" or tostring(note.id) ~= tostring(card.anki_note_id) or type(note.noteType) ~= "table"
        or not model_id or tostring(note.noteType.id) ~= tostring(model_id)
        or note.noteType.name ~= Types.model_name(card.kind) or type(note.fields) ~= "table" then
        return nil, "La nota cambió de identidad o tipo. Revísala con Recuperar desde Anki."
    end
    if card.kind == "learn" then
        if note.fields.PluginID ~= card.card_id then return nil, "El ID de Learn no coincide. No se eliminará ninguna nota." end
        if not local_card.anki_source then
            local expected = require("learning_card").fields(card)
            if note.fields.Question ~= expected.Question or note.fields.Answer ~= expected.Answer then
                return nil, "La vinculación antigua no coincide con el contenido actual. Recupera y revisa la nota antes de eliminar."
            end
        end
    else
        if note.fields.Phrase ~= card.phrase then return nil, "La expresión de Anki cambió. Recupérala y revísala antes de eliminar." end
        if not local_card.anki_source and (note.fields.Definition ~= (card.definition or "") or note.fields.Text ~= (card.text or "")) then
            return nil, "No se pudo verificar la vinculación antigua. Recupera la tarjeta antes de eliminar."
        end
    end
    return {id = card.anki_note_id, source = source, session = collection.session, local_stamp = R.stamp(local_card),
        fingerprint = note_fingerprint(note), title = card.kind == "learn" and note.fields.Question or note.fields.Phrase,
        cards = #(note.cardIds or {})}
end
function Actions.delete_prepared(config, card, proof)
    if not proof or tostring(card.anki_note_id) ~= tostring(proof.id) then return nil, "La vinculación cambió. No se eliminó ninguna nota." end
    local local_card = linked(card)
    if not local_card or R.stamp(local_card) ~= proof.local_stamp then return nil, "La tarjeta local cambió. Vuelve a revisar antes de eliminar." end
    if not proof.missing then
        local note, err = rpc(config, "notes.get", {id = tostring(proof.id), session = proof.session})
        if not note then return nil, err end
        if type(note) ~= "table" or type(note.noteType) ~= "table" or type(note.fields) ~= "table"
            or note_fingerprint(note) ~= proof.fingerprint then return nil, "La nota de Anki cambió después de la confirmación. Vuelve a revisarla." end
    end
    local source, err = Sync.source_identity(config.url)
    if not source or not R.same_source(proof.source, source) then return nil, err or "El origen de Anki cambió. No se eliminó ninguna nota." end
    -- Bind the verified origin first. A network timeout can then be reconciled
    -- safely without automatically retrying a destructive request.
    local saved, save_err = Storage.recovery_patch(proof.id, proof.local_stamp, {anki_source = source}, false)
    if not saved then return nil, save_err end
    card.anki_source = source
    if not proof.missing then
        local result; result, err = rpc(config, "notes.delete", {ids = {tostring(proof.id)}, session = proof.session})
        if not result or type(result.items) ~= "table" or not result.items[1] or not result.items[1].result
            or result.items[1].result.changed ~= true then
            return nil, err or "No se pudo confirmar la eliminación. Usa Recuperar desde Anki antes de reintentar."
        end
    end
    local current = linked(card)
    if not current then return nil, "La nota se eliminó, pero la copia local cambió. Recupera su estado desde Anki." end
    saved, save_err = Storage.recovery_patch(proof.id, R.stamp(current), {anki_source = source, anki_sync_state = "missing"}, false)
    if not saved then return nil, "Anki confirmó la eliminación, pero no se guardó el estado local. Usa Recuperar desde Anki." end
    card.anki_sync_state = "missing"
    return true, proof.missing and "La nota ya no estaba en Anki. La copia local se conserva." or "Eliminada de Anki. La copia del Kobo se conserva."
end
function Actions.confirm_delete(base, card, on_done)
    local UI = require("ui/uimanager")
    local function complete(ok, message)
        if on_done then on_done(ok, message)
        else UI:show(require("ui/widget/infomessage"):new {text = message}) end
    end
    local config = require("settings_state").merge(base, Storage.load_anki_settings())
    local proof, err = Actions.prepare_delete(config, card)
    if not proof then complete(nil, err); return end
    if proof.missing then complete(Actions.delete_prepared(config, card, proof)); return end
    local title = tostring(proof.title or "")
    if #title > 160 then title = (title:sub(1, 150):match("^(.*)%s") or "Nota vinculada") .. "…" end
    UI:show(require("ui/widget/confirmbox"):new {
        text = "¿Eliminar esta nota de Anki?\n\nPerfil: " .. proof.source.profile .. "\n" .. title
            .. "\n\nSe eliminarán la nota y sus " .. proof.cards .. " tarjetas de repaso. La copia del Kobo se conserva y no se reenviará automáticamente.",
        ok_text = "Eliminar de Anki", ok_callback = function() complete(Actions.delete_prepared(config, card, proof)) end,
    })
end
return Actions

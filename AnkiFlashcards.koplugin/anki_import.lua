-- One-way, read-only recovery from Anki. It never creates/updates Anki notes.
local AnkiSync = require("anki_sync")
local Storage = require("card_storage")
local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local mime = require("mime")
local Learn = require("learning_card")
local NoteTypes = require("note_types")
local R = require("anki_recovery")
local Import = {}
local running = false

local function quote(value)
    return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end
local function field(note, name)
    local entry = note.fields and note.fields[name]
    return type(entry) == "table" and type(entry.value) == "string" and entry.value or ""
end
local function image_name(note)
    local html = field(note, "ImageFront") .. field(note, "ImageBack")
    local name = html:match('[sS][rR][cC]%s*=%s*["\'](.-)["\']')
    if not name then return nil end
    return name:gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&#39;", "'")
end
local function download_image(url, note)
    local name = image_name(note)
    if not name then return nil end
    -- Only Anki's local media, never arbitrary URLs or filesystem paths.
    if name:find("[/\\]") or name:find("..", 1, true) or name:find("%c") then
        return nil, "Unsupported image reference"
    end
    local data, err = AnkiSync.read(url, "retrieveMediaFile", {filename = name})
    if type(data) ~= "string" or data == "" then return nil, err or "Image not found in Anki" end
    if #data > 12 * 1024 * 1024 then return nil, "Image too large for this reader" end
    local dir = DataStorage:getDataDir() .. "/.anki_images"
    if lfs.attributes(dir, "mode") ~= "directory" then
        local made, mkdir_err = lfs.mkdir(dir)
        if not made then return nil, mkdir_err end
    end
    local extension = name:lower():match("%.(%w+)$") or "png"
    local formats = {png = true, jpg = true, jpeg = true, gif = true, webp = true}
    if not formats[extension] then return nil, "Unsupported image format" end
    local path = dir .. "/anki_" .. tostring(note.noteId) .. "_" .. R.hash(data) .. "." .. extension
    if lfs.attributes(path) then return path end
    local ok, bytes = pcall(mime.unb64, data)
    if not ok or type(bytes) ~= "string" or bytes == "" then return nil, "Invalid image data" end
    local tmp = path .. ".tmp"
    local file, open_err = io.open(tmp, "wb")
    if not file then return nil, open_err end
    local written, write_err = file:write(bytes)
    local closed, close_err = file:close()
    if not written or not closed then os.remove(tmp); return nil, write_err or close_err end
    local renamed, rename_err = os.rename(tmp, path)
    if not renamed then os.remove(tmp); return nil, rename_err end
    return path
end

local function verify(config, source)
    local current, err = AnkiSync.source_identity(config.url)
    if not current then return nil, err end
    if source and not R.same_source(source, current) then return nil, "El perfil o la colección de Anki cambió. No se mezclaron datos.", true end
    return current
end
local function in_scope(note)
    if note.modelName ~= NoteTypes.VOCABULARY and note.modelName ~= Learn.MODEL then return false end
    for _, tag in ipairs(type(note.tags) == "table" and note.tags or {}) do
        if type(tag) == "string" and (tag:lower() == "koreader" or tag:lower():sub(1, 10) == "koreader::") then return true end
    end
    return false
end
local function decode_note(note)
    if note.modelName == Learn.MODEL then return Learn.from_note(note) end
    if note.modelName ~= NoteTypes.VOCABULARY or not field(note, "Phrase"):match("%S") then return nil end
    return {phrase = field(note, "Phrase"), ipa = field(note, "IPA"), definition = field(note, "Definition"),
        synonyms = field(note, "Synonyms"), text = field(note, "Text"), source = field(note, "Source"), sound = field(note, "Sound"),
        book_title = "", book_author = "", image_path = "", image_prompt = "", sent_to_anki = true,
        anki_note_id = note.noteId, anki_model = note.modelName, imported_from_anki = true}
end
local function read_note(config, id)
    local notes, err = AnkiSync.read(config.url, "notesInfo", {notes = {id}})
    if type(notes) ~= "table" then return nil, err or "Respuesta de notas inválida." end
    local note = notes[1]
    if note == nil or (type(note) == "table" and next(note) == nil) then return false end
    if type(note) ~= "table" or note.noteId ~= id then return nil, "Respuesta de nota inválida." end
    return note
end
local function read_decks(config, note)
    if type(note.cards) ~= "table" or #note.cards == 0 then return nil, "No se pudieron verificar las tarjetas de la nota." end
    local cards, err = AnkiSync.read(config.url, "cardsInfo", {cards = note.cards})
    if type(cards) ~= "table" or #cards ~= #note.cards then return nil, err or "Respuesta de barajas incompleta." end
    local decks, seen = {}, {}
    for _, card in ipairs(cards) do
        if type(card) ~= "table" or type(card.deckName) ~= "string" or card.deckName == "" then return nil, "Baraja no válida." end
        if not seen[card.deckName] then decks[#decks+1], seen[card.deckName] = card.deckName, true end
    end
    table.sort(decks)
    return decks
end
local function metadata(remote, decks, source, state)
    return {anki_source = source, anki_deck = decks[1], anki_decks = decks,
        anki_model = remote.anki_model, anki_sync_state = state, anki_remote_mod = remote.anki_remote_mod or 0, sent_to_anki = true}
end
local function begin(config)
    if running then return nil, "Ya hay una recuperación en curso." end
    if not config or not config.url or config.url == "" then return nil, "Configura primero la conexión con Anki." end
    running = true
    local job = {cancelled = false}
    function job:cancel() self.cancelled = true end
    return job
end

function Import.start(config, on_done, on_progress)
    local job, err = begin(config); if not job then return nil, err end
    local report = {imported = 0, existing = 0, conflicts = 0, failed = 0, moved = 0, changed = 0,
        missing = 0, out_of_scope = 0, foreign = 0, local_changed = 0, image_warnings = 0,
        processed = 0, total = 0, errors = {}, changes = {}, issues = {}}
    local ids, queried, index, source, finished = {}, {}, 1, nil, false
    local function detail(message) if #report.errors < 5 then report.errors[#report.errors+1] = tostring(message) end end
    local function issue(card, state, reason)
        if #report.issues < 100 then report.issues[#report.issues+1] = {phrase = card.phrase, id = card.anki_note_id, state = state, reason = reason} end
    end
    local function finish()
        if finished then return end
        finished, running, report.cancelled = true, false, job.cancelled
        report.incomplete = report.processed < report.total
        if on_done then on_done(report) end
    end
    local function check_source()
        local current, why, changed = verify(config, source)
        if not current then report.source_changed = changed; report.failed = report.failed + 1; detail(why); finish(); return false end
        return true
    end
    local function patch(card, values)
        local ok, why = Storage.recovery_patch(card.anki_note_id, R.stamp(card), values, false)
        if not ok then report.failed = report.failed + 1; detail(why); return nil end
        return Storage.find_by_anki_id(card.anki_note_id)
    end
    local function process(id)
        local local_card = Storage.find_by_anki_id(id)
        if local_card and local_card.anki_source and not R.same_source(local_card.anki_source, source) then
            return
        end
        local note, why = read_note(config, id)
        if note == nil then report.failed = report.failed + 1; detail(why); finish(); return end
        if not check_source() then return end
        if note == false then
            if local_card then
                report.missing = report.missing + 1
                issue(local_card, "missing", "No se encontró en el perfil actual. Se conserva localmente y no se reenvía automáticamente.")
                patch(local_card, {anki_sync_state = R.same_source(local_card.anki_source, source) and "missing" or "unverified_missing"})
            end
            return
        end
        if note.profile and note.profile ~= source.profile then report.source_changed = true; detail("El perfil cambió durante la lectura."); finish(); return end
        if not in_scope(note) and not (queried[id] and type(note.tags) ~= "table" and
            (note.modelName == NoteTypes.VOCABULARY or note.modelName == Learn.MODEL)) then
            if local_card then
                report.out_of_scope = report.out_of_scope + 1
                issue(local_card, "out_of_scope", "La nota existe, pero cambió de tipo o perdió la etiqueta KOReader. No se convierte ni se borra.")
                if R.same_source(local_card.anki_source, source) then patch(local_card, {anki_sync_state = "out_of_scope", anki_model = note.modelName})
                else patch(local_card, {anki_sync_state = "unverified_scope"}) end
            end
            return
        end
        local remote = decode_note(note)
        if not remote then report.failed = report.failed + 1; detail(tostring(id) .. ": contenido no compatible."); return end
        local decks; decks, why = read_decks(config, note)
        if not decks then report.failed = report.failed + 1; detail(why); return end
        remote.anki_deck, remote.anki_decks, remote.anki_source = decks[1], decks, source
        remote.anki_image_name, remote.anki_remote_mod = image_name(note) or "", note.mod or 0
        if not check_source() then return end
        if not local_card then
            if (remote.kind == "learn" and Storage.find_learning_card(remote.card_id)) or
                (remote.kind ~= "learn" and Storage.find_by_phrase(remote.phrase)) then
                report.conflicts = report.conflicts + 1
                issue(remote, "duplicate", "Hay otra tarjeta local con la misma identidad/frase y un ID diferente. No se duplicó.")
                return
            end
            local path, image_err = download_image(config.url, note)
            if not check_source() then return end
            remote.image_path, remote.anki_image_pending = path or "", image_err ~= nil
            if image_err then report.image_warnings = report.image_warnings + 1; detail(image_err) end
            remote.anki_sync_state = "ok"
            remote.anki_remote_fingerprint = R.remote_fingerprint(remote)
            remote.anki_local_fingerprint = R.local_fingerprint(remote)
            local ok, save_err = Storage.import_anki_card(remote)
            if ok then report.imported = report.imported + 1
            elseif save_err == "already_imported" then report.existing = report.existing + 1
            elseif save_err == "phrase_conflict" then report.conflicts = report.conflicts + 1
            else report.failed = report.failed + 1; detail(save_err or "No se pudo guardar.") end
            return
        end
        report.existing = report.existing + 1
        local state = R.classify(local_card, remote)
        if state == "identity_conflict" then
            report.conflicts = report.conflicts + 1
            issue(local_card, state, "Cambió el tipo o el ID interno Learn. No se altera la identidad local.")
            patch(local_card, {anki_sync_state = "identity_conflict"})
            return
        end
        local values = metadata(remote, decks, source, state == "same" and "ok" or state)
        if not local_card.anki_source and state ~= "same" then values.anki_source = nil end
        local moved = local_card.anki_deck and local_card.anki_deck ~= "" and R.deck_changed(local_card, decks)
        if state == "same" then
            if (local_card.anki_image_pending or not local_card.image_path or local_card.image_path == "" or not lfs.attributes(local_card.image_path)) and image_name(note) then
                local path, image_err = download_image(config.url, note)
                if not check_source() then return end
                values.anki_image_pending = image_err ~= nil
                if path then values.image_path, values.recover_image = path, true end
                if image_err then report.image_warnings = report.image_warnings + 1; detail(image_err) end
            end
            local projected = {}; for key, value in pairs(local_card) do projected[key] = value end
            if values.image_path then projected.image_path = values.image_path end
            values.anki_image_name = remote.anki_image_name
            values.anki_remote_fingerprint = R.remote_fingerprint(remote)
            values.anki_local_fingerprint = R.local_fingerprint(projected)
        elseif state == "local_changed" then report.local_changed = report.local_changed + 1 end
        -- Metadata-only changes are safe for verified origins. Legacy content
        -- differences need an explicit per-card adoption before binding.
        if local_card.anki_source or state == "same" then
            local updated = patch(local_card, values)
            if not updated then return end
            local_card = updated
            if moved then report.moved = report.moved + 1 end
        else
            local updated = patch(local_card, {anki_sync_state = state})
            if not updated then return end
            local_card = updated
        end
        if state == "remote_changed" or state == "conflict" or state == "unverified_change" then
            local conflict = state ~= "remote_changed"
            if conflict then report.conflicts = report.conflicts + 1 else report.changed = report.changed + 1 end
            report.changes[#report.changes+1] = {id = id, source = source, expected_stamp = R.stamp(local_card),
                local_card = local_card, remote_card = remote, remote_fingerprint = R.remote_fingerprint(remote),
                remote_mod = note.mod or 0, conflict = conflict, reason = state}
        end
    end
    local step
    step = function()
        if finished then return end
        if job.cancelled or index > #ids then finish(); return end
        if not check_source() then return end
        local ok = pcall(process, ids[index])
        if not ok then report.failed = report.failed + 1; detail("No se pudo revisar una nota. Se conserva lo guardado; reintenta la recuperación."); finish(); return end
        if finished then return end
        index, report.processed = index + 1, report.processed + 1
        if on_progress then on_progress(report, job) end
        UIManager:scheduleIn(0.05, step)
    end
    UIManager:scheduleIn(0.1, function()
        if job.cancelled then finish(); return end
        local why; source, why = verify(config)
        if not source then report.failed = 1; detail(why); finish(); return end
        report.source = source
        local local_cards, compatible, foreign = Storage.load_cards(), 0, 0
        for _, card in ipairs(local_cards) do
            if card.anki_note_id and card.anki_source then
                if R.same_source(card.anki_source, source) then compatible = compatible + 1
                else
                    foreign = foreign + 1
                    issue(card, "foreign", "Esta vinculación pertenece a otro perfil/origen. No se modificó.")
                end
            end
        end
        report.foreign = foreign
        if foreign > 0 and compatible == 0 then
            report.source_changed, report.foreign = true, foreign
            detail("Este lector está vinculado a otro perfil/origen de Anki. Abre el perfil correcto; no se mezclaron tarjetas.")
            finish(); return
        end
        local found, find_err = AnkiSync.read(config.url, "findNotes", {
            query = "(note:" .. quote(NoteTypes.VOCABULARY) .. " OR note:" .. quote(Learn.MODEL) .. ") tag:KOReader"})
        if type(found) ~= "table" then report.failed = 1; detail(find_err or "Búsqueda inválida."); finish(); return end
        local seen = {}
        for _, id in ipairs(found) do
            if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then report.failed = 1; detail("ID de nota inválido."); finish(); return end
            queried[id] = true
            if not seen[id] then ids[#ids+1], seen[id] = id, true end
        end
        for _, card in ipairs(local_cards) do
            local id = card.anki_note_id
            if type(id) == "number" and not seen[id] and (not card.anki_source or R.same_source(card.anki_source, source)) then
                ids[#ids+1], seen[id] = id, true
            end
        end
        report.total = #ids
        if on_progress then on_progress(report, job) end
        UIManager:scheduleIn(0.05, step)
    end)
    return job
end

-- Only called after explicit UI confirmation. Re-read both sides so a stale
-- comparison can never overwrite newer edits or a switched Anki profile.
function Import.apply_updates(config, changes, on_done, on_progress)
    local job, err = begin(config); if not job then return nil, err end
    local report = {updated = 0, failed = 0, processed = 0, total = #changes, errors = {}}
    local index = 1
    local function fail(why) report.failed = report.failed + 1; if #report.errors < 5 then report.errors[#report.errors+1] = tostring(why) end end
    local function apply_one(change)
        local current, why = verify(config, change.source)
        local local_card = Storage.find_by_anki_id(change.id)
        if not current then fail(why); report.abort = true
        elseif not local_card or R.stamp(local_card) ~= change.expected_stamp then fail("La tarjeta local cambió. Vuelve a recuperar.")
        else
            local note; note, why = read_note(config, change.id)
            local remote = note and decode_note(note)
            if not remote or not in_scope(note) then
                fail(why or "La nota dejó de estar disponible o cambió de tipo/etiqueta.")
                if note == nil then report.abort = true end
            else
                remote.anki_image_name, remote.anki_remote_mod = image_name(note) or "", note.mod or 0
                if R.remote_fingerprint(remote) ~= change.remote_fingerprint or remote.anki_remote_mod ~= change.remote_mod then
                    fail("Anki cambió después de la comparación. Vuelve a recuperar.")
                else
                    local decks; decks, why = read_decks(config, note)
                    if not decks then fail(why)
                    else
                        local path, image_err = download_image(config.url, note)
                        current, why = verify(config, change.source)
                        if not current then fail(why); report.abort = true
                        else
                            remote.image_path = path or (image_err and local_card.image_path or "") or ""
                            local values = metadata(remote, decks, current, "ok")
                            for _, key in ipairs(R.keys(remote)) do values[key] = remote[key] or "" end
                            values.kind, values.card_id, values.image_path = remote.kind, remote.card_id, remote.image_path
                            values.anki_image_name, values.anki_image_pending = remote.anki_image_name, image_err ~= nil
                            values.anki_remote_fingerprint = R.remote_fingerprint(remote)
                            -- Preserve a vocabulary card's local book/highlight provenance.
                            local projected = {}; for key, value in pairs(local_card) do projected[key] = value end
                            for _, key in ipairs(R.keys(remote)) do projected[key] = remote[key] or "" end
                            projected.image_path = remote.image_path
                            values.anki_local_fingerprint = R.local_fingerprint(projected)
                            local ok, save_err = Storage.recovery_patch(change.id, change.expected_stamp, values, true)
                            if ok then report.updated = report.updated + 1; if image_err and #report.errors < 5 then report.errors[#report.errors+1] = "Imagen pendiente: " .. image_err end
                            else fail(save_err) end
                        end
                    end
                end
            end
        end
    end
    local step
    step = function()
        if job.cancelled or report.abort or index > #changes then
            running = false
            report.cancelled, report.skipped = job.cancelled, #changes - report.processed
            if on_done then on_done(report) end
            return
        end
        local ok = pcall(apply_one, changes[index])
        if not ok then fail("No se pudo aplicar una actualización. La tarjeta local se conserva; vuelve a recuperar.") end
        index, report.processed = index + 1, report.processed + 1
        if on_progress then on_progress(report, job) end
        UIManager:scheduleIn(0.05, step)
    end
    UIManager:scheduleIn(0.05, step)
    return job
end

return Import

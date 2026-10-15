-- AnkiConnect HTTP client.
-- Uses socket.http + ltn12, bundled in KOReader.
-- The AnkiConnect URL must be the LAN IP of the device running Anki (e.g. http://192.168.x.x:8765),
-- not localhost — the Kobo cannot reach the host via localhost.

local http  = require("socket.http")
local ltn12 = require("ltn12")
local json  = require("json")
local CardStorage = require("card_storage")
local NoteTypes = require("note_types")
local SettingsState = require("settings_state")
local Recovery = require("anki_recovery")

-- Pure-Lua base64 encoder (avoids mime streaming-filter pitfalls).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64_encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        b = b or 0; c = c or 0
        local n = a * 65536 + b * 256 + c
        out[#out+1] = B64:sub(math.floor(n/262144)%64+1, math.floor(n/262144)%64+1)
        out[#out+1] = B64:sub(math.floor(n/4096)%64+1,   math.floor(n/4096)%64+1)
        out[#out+1] = (i+1 <= #data) and B64:sub(math.floor(n/64)%64+1, math.floor(n/64)%64+1) or "="
        out[#out+1] = (i+2 <= #data) and B64:sub(n%64+1, n%64+1) or "="
    end
    return table.concat(out)
end

local TIMEOUT = 5  -- fail fast on offline/unreachable host

local AnkiSync = {}

-- Build the Anki deck name for a card.
-- 'configured' sends everything to config.deck. 'book' (the legacy default)
-- uses <top-level parent>::<book title>, falling back to config.deck when the
-- title is missing. Switching mode never moves previously sent cards.
local function build_deck_name(config, card, ignore_split)
    local base = (config and config.deck and config.deck ~= "")
                 and config.deck or "KOReader"
    local destination = base
    local title = card and card.book_title and card.book_title ~= "" and card.book_title
    if title and (not config or config.deck_mode ~= "configured") then
        local safe = title:gsub(":", " -"):match("^%s*(.-)%s*$")
        if safe ~= "" then destination = SettingsState.book_parent(config or {}) .. "::" .. safe end
    end
    if config and config.split_card_types and not ignore_split then
        destination = destination .. "::" .. SettingsState.type_deck_name(config, card and card.kind)
    end
    return destination
end

local function post(url, action, params)
    local body     = json.encode({ action = action, version = 6, params = params or {} })
    local response = {}
    http.TIMEOUT = TIMEOUT
    local transport_ok, ok, code = pcall(http.request, {
        url     = url,
        method  = "POST",
        headers = {
            ["Content-Type"]   = "application/json",
            ["Content-Length"] = tostring(#body),
        },
        source = ltn12.source.string(body),
        sink   = ltn12.sink.table(response),
    })
    if not transport_ok then return nil, "No se pudo conectar con Anki. Comprueba la dirección y el Wi-Fi." end
    if not ok or tostring(code) ~= "200" then
        local reason = tostring(code)
        if reason == "timeout" or reason:find("unreachable") or reason:find("refused") then
            return nil, "Cannot reach Anki. Check URL in Anki Settings."
        end
        return nil, "HTTP error: " .. reason
    end
    local ok2, result = pcall(json.decode, table.concat(response))
    if not ok2 or type(result) ~= "table" then return nil, "Invalid response from AnkiConnect" end
    return result
end

-- Read-only access used by recovery from Anki. No note/deck writes here.
function AnkiSync.read(url, action, params)
    local allowed = {findNotes = true, notesInfo = true, cardsInfo = true, retrieveMediaFile = true,
        getActiveProfile = true, modelNamesAndIds = true}
    if not allowed[action] then return nil, "Unsupported read action" end
    local reply, err = post(url, action, params)
    if not reply then return nil, err end
    if type(reply.error) == "string" then return nil, reply.error end
    if reply.result == nil then return nil, "Invalid AnkiConnect response" end
    return reply.result
end

-- Fingerprint is profile + stable note-type IDs, not the computer's IP.
-- It is a conservative lineage check, not a globally unique collection UUID.
function AnkiSync.source_identity(url)
    local profile, err = AnkiSync.read(url, "getActiveProfile", {})
    if type(profile) ~= "string" or profile == "" then return nil, err or "Abre un perfil de Anki." end
    local models; models, err = AnkiSync.read(url, "modelNamesAndIds", {})
    if type(models) ~= "table" then return nil, err or "No se pudo verificar la colección de Anki." end
    local again; again, err = AnkiSync.read(url, "getActiveProfile", {})
    if again ~= profile then return nil, err or "El perfil cambió durante la comprobación. Reintenta." end
    local source = {profile = profile, vocabulary_id = models[NoteTypes.VOCABULARY], learn_id = models[NoteTypes.LEARN]}
    for _, key in ipairs({"vocabulary_id", "learn_id"}) do
        local id = source[key]
        if id ~= nil and not ((type(id) == "number" and id > 0 and id == math.floor(id)) or
            (type(id) == "string" and id:match("^%d+$"))) then return nil, "La identificación de la colección no es válida." end
    end
    if not source.vocabulary_id and not source.learn_id then return nil, "No se pudo verificar el origen: faltan los tipos KOReader en este perfil." end
    return source
end

-- Store a media file in Anki's media folder. Returns stored filename or nil + err.
local function store_media_file(url, filename, b64_data)
    local result, err = post(url, "storeMediaFile", {
        filename = filename,
        data     = b64_data,
    })
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    return result.result or filename
end

-- Check that AnkiConnect is reachable. Returns true or nil + error.
function AnkiSync.test_connection(url)
    -- Probe a real action: permission discovery may hide authentication errors.
    local result, err = post(url, "version", {})
    if not result then return nil, err end
    if type(result.error) == "string" then return nil, result.error end
    if type(result.result) ~= "number" then return nil, "Invalid response from AnkiConnect" end
    return true
end

local function quote_search(value)
    return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function normalize_phrase(value)
    return (value or ""):lower():match("^%s*(.-)%s*$")
end

-- Do not treat a duplicate error alone as proof of delivery. Verify the
-- phrase, model and exact destination (deck searches also include children).
local function find_existing(url, note, legacy_deck)
    local learning = note.fields.PluginID ~= nil
    local query = learning and ("note:" .. quote_search(note.modelName) .. " " .. quote_search("PluginID:" .. note.fields.PluginID))
        or ("deck:" .. quote_search(legacy_deck or note.deckName)
        .. " note:" .. quote_search(note.modelName)
        .. " " .. quote_search("Phrase:" .. note.fields.Phrase))
    local found, err = post(url, "findNotes", { query = query })
    if not found then return nil, err end
    if type(found.error) == "string" then return nil, found.error end
    if type(found.result) ~= "table" then return nil, "Invalid note search response" end
    if #found.result == 0 then return false end
    local notes
    notes, err = post(url, "notesInfo", { notes = found.result })
    if not notes then return nil, err end
    if type(notes.error) == "string" then return nil, notes.error end
    if type(notes.result) ~= "table" then return nil, "Invalid notes response" end
    for _, existing in ipairs(notes.result) do
        if learning and existing.modelName == note.modelName and existing.fields
            and existing.fields.PluginID and existing.fields.PluginID.value == note.fields.PluginID then
            if not existing.fields.Question or not existing.fields.Answer
                or existing.fields.Question.value ~= note.fields.Question
                or existing.fields.Answer.value ~= note.fields.Answer then
                return nil, "Ya existe otra versión de esta tarjeta Learn en Anki. Usa Recuperar desde Anki; no se sobrescribirá."
            end
            local cards, read_err = post(url, "cardsInfo", {cards = existing.cards or {}})
            if not cards then return nil, read_err end
            if type(cards.error) == "string" then return nil, cards.error end
            if type(cards.result) ~= "table" or not cards.result[1] then return nil, "No se pudo verificar la nota Learn existente." end
            return existing.noteId, nil, cards.result[1].deckName
        end
        local phrase = existing.fields and existing.fields.Phrase
        if existing.modelName == note.modelName and phrase
            and normalize_phrase(phrase.value) == normalize_phrase(note.fields.Phrase)
            and type(existing.cards) == "table" and #existing.cards > 0 then
            local cards
            cards, err = post(url, "cardsInfo", { cards = existing.cards })
            if not cards then return nil, err end
            if type(cards.error) == "string" then return nil, cards.error end
            if type(cards.result) ~= "table" then return nil, "Invalid cards response" end
            for _, card in ipairs(cards.result) do
                if card.deckName == note.deckName or (legacy_deck and type(card.deckName) == "string" and
                    (card.deckName == legacy_deck or card.deckName:sub(1, #legacy_deck + 2) == legacy_deck .. "::")) then
                    return existing.noteId, nil, card.deckName
                end
            end
        end
    end
    return false
end

local function ensure_model(url, kind)
    local spec = NoteTypes.model_params(kind)
    local names, err = post(url, "modelNames", {})
    if not names then return nil, err end
    if type(names.error) == "string" then return nil, names.error end
    if type(names.result) ~= "table" then return nil, "Invalid model list" end
    local exists = false
    for _, name in ipairs(names.result) do if name == spec.modelName then exists = true end end
    if not exists then
        local created
        created, err = post(url, "createModel", spec)
        if not created then return nil, err end
        if type(created.error) == "string" then return nil, created.error end
    end
    local fields
    fields, err = post(url, "modelFieldNames", {modelName = spec.modelName})
    if not fields then return nil, err end
    if type(fields.error) == "string" then return nil, fields.error end
    if type(fields.result) ~= "table" or fields.result[1] ~= spec.inOrderFields[1] then
        return nil, "El tipo " .. spec.modelName .. " existe con una estructura incompatible. No se ha modificado."
    end
    local known = {}
    for _, field in ipairs(fields.result) do known[field] = true end
    for _, field in ipairs(spec.inOrderFields) do
        if not known[field] then return nil, "Falta el campo " .. field .. " en " .. spec.modelName .. ". No se ha modificado el tipo de nota." end
    end
    return true
end

local function record_delivery(card, note, id, status, source)
    local receipt = {note_id = id, deck = note.deckName, model = note.modelName, status = status, source = source}
    local saved, err = CardStorage.record_sent(card, receipt)
    if not saved then
        return nil, "Anki received the card, but its local sent status could not be saved: "
            .. tostring(err or "storage error")
    end
    return true, nil, receipt
end

-- Send a full flashcard to Anki.
-- config:     { url, deck, model, tags, tts_enabled, elevenlabs_voice_id }
-- card:       { phrase, ipa, definition, synonyms, text, source }
-- tts_config: full CONFIGURATION table (optional — provides elevenlabs_api_key)
-- Returns true or nil + error string.
function AnkiSync.send_card(config, card, tts_config)
    if not config or not config.url or config.url == "" then
        return nil, "Anki URL not configured"
    end
    if Recovery.needs_review(card) and card.anki_sync_state ~= "missing" then
        return nil, "Esta tarjeta tiene diferencias u origen pendientes de revisión. Usa Recuperar desde Anki antes de reenviarla."
    end
    local verified_source
    if card.anki_source then
        local err
        verified_source, err = AnkiSync.source_identity(config.url)
        if not verified_source then return nil, err end
        if not Recovery.same_source(card.anki_source, verified_source) then
            return nil, "Esta tarjeta está vinculada a otro perfil/origen de Anki. Abre el perfil correcto antes de enviarla."
        end
    end

    local model = NoteTypes.model_name(card.kind)
    local is_learning = card.kind == "learn"
    if is_learning then
        if type(card.card_id) ~= "string" or not card.card_id:match("^learn%-%x+$")
            or type(card.question) ~= "string" or not card.question:match("%S")
            or type(card.answer) ~= "string" or not card.answer:match("%S") then
            return nil, "Tarjeta Learn incompleta."
        end
    end
    local ready, model_err = ensure_model(config.url, card.kind)
    if not ready then return nil, model_err end

    local fields = {
        ["Phrase"]     = card.phrase     or "",
        ["IPA"]        = card.ipa        or "",
        ["Definition"] = card.definition or "",
        ["Synonyms"]   = card.synonyms   or "",
        ["Text"]       = card.text       or "",
        ["Source"]     = card.source     or "",
    }

    local note = {
        deckName  = build_deck_name(config, card),
        modelName = model,
        fields    = fields,
        options   = {
            allowDuplicate = false,
            duplicateScope = "deck",
        },
        tags = config.tags or { "KOReader" },
    }
    if is_learning then note.fields = require("learning_card").fields(card); fields = note.fields end
    local tags, seen_tags = {}, {}
    local function tag(value)
        if type(value) == "string" and value ~= "" and not seen_tags[value] then
            tags[#tags+1] = value; seen_tags[value] = true
        end
    end
    for _, value in ipairs(type(note.tags) == "table" and note.tags or {}) do tag(value) end
    tag("KOReader")
    tag(is_learning and "KOReader::Learn" or "KOReader::Vocab")
    note.tags = tags

    -- createDeck is idempotent and also creates missing parent decks.
    -- Ensure the destination before uploading media or sending the note.
    local deck_result, deck_err = post(config.url, "createDeck", { deck = note.deckName })
    if not deck_result then return nil, deck_err end
    if type(deck_result.error) == "string" then
        return nil, "Cannot create deck '" .. note.deckName .. "': " .. deck_result.error
    end
    if not deck_result.result then
        return nil, "Cannot create deck '" .. note.deckName .. "': invalid response"
    end

    -- A newly enabled split must also recognize vocabulary previously sent
    -- to the unsplit book deck, without moving it or creating another copy.
    local legacy_deck = not is_learning and config.split_card_types and build_deck_name(config, card, true) or nil
    local existing, search_err, existing_deck = find_existing(config.url, note, legacy_deck)
    if existing == nil then return nil, search_err end
    if existing then
        if existing_deck then note.deckName = existing_deck end
        return record_delivery(card, note, existing, "existing", verified_source)
    end

    if not is_learning then
    -- Store image via storeMediaFile and reference it in ImageFront/ImageBack fields.
    if card.image_path then
        pcall(function()
            local f = io.open(card.image_path, "rb")
            if not f then return end
            local raw = f:read("*a")
            f:close()
            local b64         = base64_encode(raw)
            local phrase_slug = (card.phrase or "card"):gsub("[^%w]", "_"):lower()
            local fname       = phrase_slug .. "_" .. tostring(os.time()) .. ".png"
            local stored      = store_media_file(config.url, fname, b64)
            if stored then
                local img_ref        = '<img src="' .. stored .. '">'
                fields["ImageFront"] = img_ref
                fields["ImageBack"]  = img_ref
            end
        end)
    end

    -- Attach TTS audio.  Priority:
    --   1. Pre-downloaded bytes (card._audio_bytes)
    --   2. AnkiVocab server-generated audio (card._audio_url)
    --   3. ElevenLabs TTS fallback
    local mp3_bytes
    if card._audio_bytes then
        mp3_bytes = card._audio_bytes
    elseif type(card._audio_url) == "string" and card._audio_url ~= "" then
        pcall(function()
            local AudioGenerator = require("audio_generator")
            mp3_bytes = AudioGenerator.download_url(card._audio_url)
        end)
    end
    if not mp3_bytes then
        local tts_api_key = tts_config and tts_config.elevenlabs_api_key
        local tts_on      = (config and config.tts_enabled)
                          or (tts_config and tts_config.tts_enabled)
        if tts_on and tts_api_key and tts_api_key ~= "" then
            pcall(function()
                local AudioGenerator = require("audio_generator")
                local tts_cfg = {
                    elevenlabs_api_key  = tts_api_key,
                    elevenlabs_voice_id = config.elevenlabs_voice_id
                                          or (tts_config and tts_config.elevenlabs_voice_id),
                }
                mp3_bytes = AudioGenerator.generate(tts_cfg, card)
            end)
        end
    end
    if mp3_bytes then
        pcall(function()
            local b64         = base64_encode(mp3_bytes)
            local phrase_slug = (card.phrase or "card"):gsub("[^%w]", "_"):lower()
            local fname       = phrase_slug .. "_" .. tostring(os.time()) .. ".mp3"
            local stored      = store_media_file(config.url, fname, b64)
            if stored then
                fields["Sound"] = "[sound:" .. stored .. "]"
            end
        end)
    end

    end -- Vocabulary-only media/TTS. Learning cards are source-grounded text.
    local params = { note = note }

    local result, err = post(config.url, "addNote", params)
    if not result then return nil, err end
    if type(result.error) == "string" then
        if result.error:lower():find("duplicate", 1, true) then
            -- Another send may have completed between the check and addNote.
            local id, _, actual_deck = find_existing(config.url, note, legacy_deck)
            if id then
                if actual_deck then note.deckName = actual_deck end
                return record_delivery(card, note, id, "existing", verified_source)
            end
        end
        return nil, result.error
    end
    if type(result.result) ~= "number" then return nil, "Invalid addNote response" end
    return record_delivery(card, note, result.result, "created", verified_source)
end

return AnkiSync

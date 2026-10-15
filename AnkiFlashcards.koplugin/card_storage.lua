-- Local storage for Anki flashcards.
-- Follows the same pattern as vocab_builder.lua from AI_Dictionary.

local DataStorage = require("datastorage")
local json        = require("json")

local CARDS_FILE    = DataStorage:getDataDir() .. "/anki_flashcards.json"
local SETTINGS_FILE = DataStorage:getDataDir() .. "/anki_flashcards_settings.json"

local CardStorage = {}

local function normalize(phrase)
    return (phrase or ""):lower():match("^%s*(.-)%s*$")
end

-- Naive English stemmer: strip common inflectional suffixes.
local function stem(word)
    local w = normalize(word)
    -- Order matters — try longest suffixes first.
    w = w:gsub("ies$", "y")       -- "stories" → "story"
    w = w:gsub("ying$", "y")      -- "studying" → "study" (approximate)
    w = w:gsub("ving$", "ve")     -- "having" → "have"
    w = w:gsub("ting$", "t")      -- "sitting" → "sit" (approximate)
    w = w:gsub("ning$", "n")      -- "running" → "run"
    w = w:gsub("ging$", "g")      -- "nagging" → "nag"
    w = w:gsub("ding$", "d")      -- "adding" → "add"
    w = w:gsub("bing$", "b")      -- "rubbing" → "rub"
    w = w:gsub("ping$", "p")      -- "tapping" → "tap"
    w = w:gsub("ming$", "m")      -- "swimming" → "swim"
    w = w:gsub("zing$", "z")      -- "buzzing" → "buz" (close enough)
    w = w:gsub("sing$", "s")      -- "missing" → "mis" (approximate)
    w = w:gsub("ing$", "")        -- "taxing" → "tax"
    w = w:gsub("ied$", "y")       -- "studied" → "study"
    w = w:gsub("ved$", "ve")      -- "moved" → "move"
    w = w:gsub("ced$", "ce")      -- "danced" → "dance"
    w = w:gsub("sed$", "se")      -- "closed" → "close"
    w = w:gsub("ted$", "t")       -- "dotted" → "dot"
    w = w:gsub("ned$", "n")       -- "planned" → "plan"
    w = w:gsub("ged$", "g")       -- "nagged" → "nag"
    w = w:gsub("ded$", "d")       -- "added" → "add"
    w = w:gsub("bed$", "b")       -- "rubbed" → "rub"
    w = w:gsub("ped$", "p")       -- "tapped" → "tap"
    w = w:gsub("med$", "m")       -- "trimmed" → "trim"
    w = w:gsub("ed$", "")         -- "walked" → "walk"
    w = w:gsub("es$", "")         -- "cogs" won't match but "boxes" → "box"
    w = w:gsub("s$", "")          -- "cogs" → "cog"
    w = w:gsub("ly$", "")         -- "quickly" → "quick"
    w = w:gsub("er$", "")         -- "bigger" → "bigg" (approximate)
    w = w:gsub("est$", "")        -- "biggest" → "bigg"
    return w
end

local function load_raw()
    local f = io.open(CARDS_FILE, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()
    if not content or content == "" then return {} end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then return data end
    return {}
end

local function save_file(path, data)
    local ok, encoded = pcall(json.encode, data)
    if not ok or type(encoded) ~= "string" then return false, "Cannot encode data" end
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then return false, err end
    local written, write_err = f:write(encoded)
    local closed, close_err = f:close()
    if not written or not closed then os.remove(tmp); return false, write_err or close_err end
    local replaced, rename_err = os.rename(tmp, path)
    if not replaced then os.remove(tmp); return false, rename_err end
    return true
end

local function save_raw(entries)
    return save_file(CARDS_FILE, entries)
end

-- Save a new card. Returns true on success or false + reason string.
function CardStorage.save_card(card)
    if card.kind == "learn" then return CardStorage.save_learning_card(card) end
    local key     = normalize(card.phrase)
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and normalize(e.phrase) == key then
            return false, "already_saved"
        end
    end
    table.insert(entries, {
        phrase      = card.phrase      or "",
        ipa         = card.ipa         or "",
        definition  = card.definition  or "",
        synonyms    = card.synonyms    or "",
        text        = card.text        or "",
        source      = card.source      or "",
        book_title  = card.book_title  or "",
        book_author = card.book_author or "",
        image_path     = card.image_path    or "",
        image_prompt   = card.image_prompt  or "",
        _audio_url       = card._audio_url       or "",
        _ankivocab_word  = card._ankivocab_word  or "",
        highlight_pos0 = card.highlight_pos0,
        highlight_pos1 = card.highlight_pos1,
        annotation_source = card.annotation_source,
        origin_key = card.origin_key,
        selected_text = card.selected_text,
        date           = os.date("%Y-%m-%d"),
        updated_at     = os.time(),
        sent_to_anki   = false,
    })
    return save_raw(entries)
end

-- Returns the full list of saved cards.
function CardStorage.load_cards()
    return load_raw()
end

-- Update image_path on an already-saved card (called after async generation).
function CardStorage.update_image_path(phrase, path)
    local key     = normalize(phrase)
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and normalize(e.phrase) == key then
            e.image_path = path
            return save_raw(entries)
        end
    end
    return false
end

-- Update _audio_url on an already-saved card (called after async polling).
function CardStorage.update_audio_url(phrase, url)
    local key     = normalize(phrase)
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and normalize(e.phrase) == key then
            e._audio_url = url
            return save_raw(entries)
        end
    end
    return false
end

-- Update editable fields of an already-saved card (matched by original phrase).
-- Does not touch book metadata, image_path, date or sent_to_anki.
function CardStorage.update_card(original_phrase, new_card)
    local key     = normalize(original_phrase)
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and normalize(e.phrase) == key then
            e.phrase       = new_card.phrase       or ""
            e.ipa          = new_card.ipa          or ""
            e.definition   = new_card.definition   or ""
            e.synonyms     = new_card.synonyms     or ""
            e.text         = new_card.text         or ""
            e.source       = new_card.source       or ""
            e.image_prompt = new_card.image_prompt or e.image_prompt or ""
            e.updated_at   = os.time()
            return save_raw(entries)
        end
    end
    return false
end

-- Remove card by 1-based index; also deletes its image file if present.
function CardStorage.delete_card(idx)
    local entries = load_raw()
    local card    = entries[idx]
    if card and card.image_path and card.image_path ~= "" then
        os.remove(card.image_path)
    end
    table.remove(entries, idx)
    save_raw(entries)
end

-- Empty the entire card list and delete all associated image files.
function CardStorage.clear_all()
    local entries = load_raw()
    for _, card in ipairs(entries) do
        if card.image_path and card.image_path ~= "" then
            os.remove(card.image_path)
        end
    end
    save_raw({})
end

-- Find and return a saved card by phrase (case-insensitive, trimmed).
-- Returns the card table or nil.
function CardStorage.find_by_phrase(phrase)
    local key     = normalize(phrase)
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and normalize(e.phrase) == key then
            return e
        end
    end
    return nil
end

-- Find a saved card by phrase with fuzzy stem matching.
-- Tries exact (normalized) match first, then falls back to stem comparison.
-- Returns the card table or nil.
function CardStorage.find_by_phrase_fuzzy(phrase)
    local exact = CardStorage.find_by_phrase(phrase)
    if exact then return exact end
    local key     = stem(phrase)
    if key == "" then return nil end
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and stem(e.phrase) == key then
            return e
        end
    end
    return nil
end

-- Find a saved card by highlight position.
-- Returns the card table or nil.
function CardStorage.find_by_position(pos0, pos1)
    if not pos0 then return nil end
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.highlight_pos0 == pos0 then
            return e
        end
    end
    return nil
end

-- Returns true if phrase is already saved (case-insensitive, trimmed).
function CardStorage.is_saved(phrase)
    if type(phrase) == "table" then
        if phrase.kind == "learn" then return CardStorage.find_learning_card(phrase.card_id) ~= nil end
        phrase = phrase.phrase
    end
    local key     = normalize(phrase)
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and normalize(e.phrase) == key then
            return true
        end
    end
    return false
end

function CardStorage.find_learning_card(id)
    for _, card in ipairs(load_raw()) do
        if card.kind == "learn" and card.card_id == id then return card end
    end
end

local function copy_learning(card)
    local result = {}
    for _, field in ipairs({"kind", "card_id", "phrase", "question", "answer", "explanation", "evidence",
        "selected_text", "source_context", "context_quality", "book_title", "book_author", "chapter",
        "location", "highlight_pos0", "highlight_pos1", "sent_to_anki", "anki_note_id", "anki_deck", "anki_model",
        "anki_source", "anki_decks", "anki_sync_state", "anki_remote_fingerprint", "anki_local_fingerprint",
        "anki_image_name", "anki_image_pending", "anki_remote_mod", "annotation_source", "origin_key", "reader_note", "annotation_aliases"}) do
        result[field] = card[field]
    end
    result.image_path, result.image_prompt = "", ""
    result.date = card.date or os.date("%Y-%m-%d")
    result.updated_at = os.time()
    return result
end

function CardStorage.save_learning_card(card, overwrite)
    if type(card.card_id) ~= "string" or not card.card_id:match("^learn%-%x+$")
        or type(card.question) ~= "string" or not card.question:match("%S")
        or type(card.answer) ~= "string" or not card.answer:match("%S") then
        return false, "invalid_learning_card"
    end
    local entries = load_raw()
    for i, entry in ipairs(entries) do
        if entry.kind == "learn" and entry.card_id == card.card_id then
            if not overwrite then return false, "already_saved" end
            if entry.sent_to_anki then return false, "already_sent" end
            entries[i] = copy_learning(card)
            return save_raw(entries)
        end
    end
    entries[#entries+1] = copy_learning(card)
    return save_raw(entries)
end

function CardStorage.find_by_anki_id(id)
    for _, card in ipairs(load_raw()) do
        if tostring(card.anki_note_id) == tostring(id) then return card end
    end
end

function CardStorage.save_annotation_link(card)
    local entries = load_raw()
    for _, entry in ipairs(entries) do
        local same = card.kind == "learn" and entry.kind == "learn" and entry.card_id == card.card_id
            or card.kind ~= "learn" and entry.kind ~= "learn" and normalize(entry.phrase) == normalize(card.phrase)
        if same then
            if entry.origin_key and card.origin_key and entry.origin_key ~= card.origin_key then
                if entry.annotation_aliases ~= nil and type(entry.annotation_aliases) ~= "table" then return false, "No se pudo conservar la relación anterior." end
                entry.annotation_aliases = entry.annotation_aliases or {}
                local found = false
                for _, key in ipairs(entry.annotation_aliases) do if key == entry.origin_key then found = true end end
                if not found then entry.annotation_aliases[#entry.annotation_aliases+1] = entry.origin_key end
            end
            for _, key in ipairs({"annotation_source", "origin_key", "selected_text", "highlight_pos0", "highlight_pos1"}) do entry[key] = card[key] end
            entry.updated_at = os.time()
            return save_raw(entries)
        end
    end
    return true -- Highlighting is independent of saving the generated card.
end

function CardStorage.add_annotation_alias(card, origin_key)
    local entries = load_raw()
    for _, entry in ipairs(entries) do
        local matches = card.kind == "learn" and entry.kind == "learn" and entry.card_id == card.card_id
            or card.kind ~= "learn" and entry.kind ~= "learn" and normalize(entry.phrase) == normalize(card.phrase)
        if matches then
            if entry.annotation_aliases ~= nil and type(entry.annotation_aliases) ~= "table" then return false end
            entry.annotation_aliases = entry.annotation_aliases or {}
            if entry.origin_key == origin_key then return true end
            for _, key in ipairs(entry.annotation_aliases) do if key == origin_key then return true end end
            entry.annotation_aliases[#entry.annotation_aliases+1] = origin_key
            entry.updated_at = os.time()
            return save_raw(entries)
        end
    end
    return false
end

-- Optimistic concurrency: a confirmation must never overwrite a card edited
-- after the recovery scan. Only explicitly whitelisted fields are changed.
function CardStorage.recovery_patch(id, expected_stamp, patch, replace_content)
    local R = require("anki_recovery")
    local entries, target, matches = load_raw(), nil, 0
    for _, entry in ipairs(entries) do
        if tostring(entry.anki_note_id) == tostring(id) then target = entry; matches = matches + 1 end
    end
    if not target or matches ~= 1 then return false, "La vinculación local es inexistente o ambigua." end
    if R.stamp(target) ~= expected_stamp then return false, "La tarjeta local cambió. Vuelve a recuperar antes de actualizar." end
    if replace_content then
        if (target.kind == "learn") ~= (patch.kind == "learn") or
            (target.kind == "learn" and target.card_id ~= patch.card_id) then
            return false, "Cambió la identidad de la tarjeta. No se reemplazó."
        end
        local phrase = target.kind == "learn" and patch.question or patch.phrase
        if type(phrase) ~= "string" or not phrase:match("%S") then return false, "El contenido recibido no es válido." end
        for _, other in ipairs(entries) do
            if other ~= target and other.kind ~= "learn" and target.kind ~= "learn" and normalize(other.phrase) == normalize(phrase) then
                return false, "Ya hay otra tarjeta local con esa frase. No se reemplazó."
            end
        end
        for _, key in ipairs(R.keys(target)) do target[key] = patch[key] or "" end
        target.phrase = phrase
        if patch.image_path ~= nil then target.image_path = patch.image_path end
    end
    if not replace_content and patch.recover_image and patch.image_path ~= nil then target.image_path = patch.image_path end
    for _, key in ipairs({"anki_source", "anki_deck", "anki_decks", "anki_model", "anki_sync_state",
        "anki_remote_fingerprint", "anki_local_fingerprint", "anki_image_name", "anki_image_pending", "anki_remote_mod"}) do
        if patch[key] ~= nil then target[key] = patch[key] end
    end
    if patch.sent_to_anki == true then target.sent_to_anki = true end
    target.updated_at = os.time()
    return save_raw(entries)
end

-- Imported notes keep Anki's identity. Existing local content is never
-- overwritten, including a different note which happens to share a phrase.
function CardStorage.import_anki_card(card)
    if not card.anki_note_id or normalize(card.phrase) == "" then return false, "invalid_card" end
    local entries = load_raw()
    for _, existing in ipairs(entries) do
        if tostring(existing.anki_note_id) == tostring(card.anki_note_id) then
            return false, "already_imported"
        end
    end
    for _, existing in ipairs(entries) do
        if card.kind == "learn" then
            if existing.kind == "learn" and existing.card_id == card.card_id then return false, "phrase_conflict" end
        elseif existing.kind ~= "learn" and normalize(existing.phrase) == normalize(card.phrase) then
            return false, "phrase_conflict"
        end
    end
    local imported = {}
    for k, v in pairs(card) do imported[k] = v end
    imported.sent_to_anki = true
    imported.date = imported.date or os.date("%Y-%m-%d")
    imported.updated_at = os.time()
    entries[#entries+1] = imported
    return save_raw(entries)
end

function CardStorage.attach_import_image(id, path)
    local entries = load_raw()
    for _, card in ipairs(entries) do
        if tostring(card.anki_note_id) == tostring(id) then
            if card.image_path and card.image_path ~= "" then
                local existing_file = io.open(card.image_path, "rb")
                if existing_file then existing_file:close(); return true end
            end
            card.image_path = path
            card.updated_at = os.time()
            return save_raw(entries)
        end
    end
    return false, "Imported card not found"
end

-- Mark a phrase as sent to Anki.
function CardStorage.record_sent(card, receipt)
    local entries = load_raw()
    local key = normalize(card.phrase)
    local target
    for _, entry in ipairs(entries) do
        if card.kind == "learn" then
            if entry.kind == "learn" and entry.card_id == card.card_id then target = entry; break end
        elseif entry.kind ~= "learn" and normalize(entry.phrase) == key then target = entry; break end
    end
    if not target then
        target = card.kind == "learn" and copy_learning(card) or {}
        -- Persist card fields, but not transient downloaded audio bytes.
        for _, field in ipairs({"phrase", "ipa", "definition", "synonyms", "text", "source",
            "book_title", "book_author", "image_path", "image_prompt", "_audio_url",
            "_ankivocab_word", "highlight_pos0", "highlight_pos1", "annotation_source", "origin_key", "selected_text"}) do
            target[field] = card[field]
        end
        target.date = os.date("%Y-%m-%d")
        entries[#entries+1] = target
    end
    target.sent_to_anki = true
    target.anki_note_id = receipt.note_id
    target.anki_deck = receipt.deck
    target.anki_model = receipt.model
    -- A new delivery has no reconciliation baseline until verified by the
    -- next recovery. Do not retain a stale fingerprint from another profile.
    target.anki_source, target.anki_remote_fingerprint, target.anki_local_fingerprint = receipt.source, nil, nil
    target.anki_sync_state, target.anki_decks = "unverified", {receipt.deck}
    target.updated_at = os.time()
    local saved, err = save_raw(entries)
    if not saved then return false, err end
    card.sent_to_anki = true
    card.anki_note_id = receipt.note_id
    card.anki_deck = receipt.deck
    card.anki_model = receipt.model
    card.anki_source, card.anki_remote_fingerprint, card.anki_local_fingerprint = receipt.source, nil, nil
    card.anki_sync_state, card.anki_decks = "unverified", {receipt.deck}
    return true
end

function CardStorage.mark_sent(phrase)
    local key     = normalize(phrase)
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and normalize(e.phrase) == key then
            e.sent_to_anki = true
            break
        end
    end
    save_raw(entries)
end

-- Persist Anki connection settings (override configuration.lua at runtime).
function CardStorage.save_anki_settings(settings)
    -- Encode first and replace atomically: never truncate stored API keys
    -- when encoding, writing or closing the new settings fails.
    return save_file(SETTINGS_FILE, settings)
end

-- Load saved Anki settings. Returns a table or nil if not yet set.
function CardStorage.load_anki_settings()
    local f = io.open(SETTINGS_FILE, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    if not content or content == "" then return nil end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then return data end
    return nil
end

return CardStorage

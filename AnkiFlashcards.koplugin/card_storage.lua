-- Local storage for Anki flashcards.
-- Follows the same pattern as vocab_builder.lua from AI_Dictionary.

local DataStorage = require("datastorage")
local json        = require("json")
local Paths       = require("storage_paths")

local CARDS_FILE    = Paths.cards
-- Resolve the actual plugin folder (including renamed/external installations),
-- not a hard-coded folder beneath the KOReader data directory.
local MODULE_DIR = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local SETTINGS_FILE = MODULE_DIR .. "anki_flashcards_settings.json"
local LEGACY_SETTINGS_FILE = DataStorage:getDataDir() .. "/anki_flashcards_settings.json"
local EXPORT_PREFIX = DataStorage:getDataDir() .. "/anki_flashcards_export_"

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
    local ready, err = Paths.initialize()
    CardStorage.data_migration_error = not ready and err or nil
    local f = io.open(CARDS_FILE, "r")
    if not f and not ready then f = io.open(Paths.legacy_cards, "r") end
    if not f then return {} end
    local content = f:read("*all")
    f:close()
    if not content or content == "" then return {} end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then
        for _, card in ipairs(data) do
            local relocated = Paths.resolve_image(card.image_path)
            if relocated ~= card.image_path then
                local R = require("anki_recovery")
                local clean = card.anki_local_fingerprint and card.anki_local_fingerprint == R.local_fingerprint(card)
                card.image_path = relocated
                if clean then card.anki_local_fingerprint = R.local_fingerprint(card) end
            end
        end
        return data
    end
    return {}
end

local function save_file(path, data)
    local ok, encoded = pcall(json.encode, data)
    if not ok or type(encoded) ~= "string" then return false, "Cannot encode data" end
    local tmp = path .. ".tmp-" .. tostring(os.time()) .. "-" .. tostring(math.random(1, 2147483646))
    local f, err = io.open(tmp, "w")
    if not f then return false, err end
    local wrote, write_result = pcall(f.write, f, encoded)
    if not wrote or not write_result then
        pcall(f.close, f)
        os.remove(tmp)
        return false, "Could not write temporary file"
    end
    local closed, close_result = pcall(f.close, f)
    if not closed or not close_result then os.remove(tmp); return false, "Could not close temporary file" end
    local replaced, rename_err = os.rename(tmp, path)
    if not replaced then os.remove(tmp); return false, rename_err end
    return true
end

local function save_raw(entries)
    local ready, err = Paths.initialize()
    if not ready then return false, err end
    return save_file(CARDS_FILE, entries)
end

function CardStorage.migrate_data()
    local ok, err = Paths.initialize()
    CardStorage.data_migration_error = not ok and err or nil
    return ok, err
end

-- Remove an image only when no persisted card still points at it. This makes
-- cleanup safe even if legacy data or a provider accidentally reuses a path.
function CardStorage.remove_image_if_unreferenced(path)
    if not path or path == "" then return false end
    for _, entry in ipairs(load_raw()) do
        if entry.image_path == path then return false end
    end
    return os.remove(path)
end

local function new_storage_id(entries)
    local prefix = tostring(os.time()) .. "-"
    local suffix = math.random(1, 2147483646)
    local id = prefix .. suffix
    local exists = true
    while exists do
        exists = false
        for _, entry in ipairs(entries) do
            if entry._storage_id == id then
                exists = true
                suffix = suffix + 1
                id = prefix .. suffix
                break
            end
        end
    end
    return id
end

-- Prefer a stable per-generation identity when available. Phrase is retained as
-- a fallback for cards written before identities were introduced.
local function find_entry(entries, target)
    if type(target) == "table" and target._storage_id then
        for _, entry in ipairs(entries) do
            if entry._storage_id == target._storage_id then
                return entry
            end
        end
        return nil
    end
    local phrase = type(target) == "table" and target.phrase or target
    local key = normalize(phrase)
    for _, entry in ipairs(entries) do
        if normalize(entry.phrase) == key then
            return entry
        end
    end
    return nil
end

local function has_other_normalized_phrase(entries, entry, phrase)
    local key = normalize(phrase)
    for _, other in ipairs(entries) do
        if other ~= entry and other.kind ~= "learn" and normalize(other.phrase) == key then
            return true
        end
    end
    return false
end

-- Records written before stable identities were introduced are safe for
-- synchronous phrase operations, but async callbacks must never keep using a
-- phrase-only identity. Persist an id before the caller starts its mutation and
-- copy it to the in-memory card used by that callback.
local function ensure_entry_identity(entries, entry, target)
    if entry._storage_id then
        if type(target) == "table" then target._storage_id = entry._storage_id end
        return true
    end
    entry._storage_id = new_storage_id(entries)
    if not save_raw(entries) then
        entry._storage_id = nil
        return false
    end
    if type(target) == "table" then target._storage_id = entry._storage_id end
    return true
end

-- Bind a pre-identity record to a durable generation before scheduling async
-- work. Phrase lookup is deliberately confined to this eager migration step;
-- callbacks must already carry _storage_id.
function CardStorage.ensure_identity(target)
    if type(target) ~= "table" then return false end
    if target._storage_id then return true end
    local entries = load_raw()
    local entry = find_entry(entries, target)
    if not entry then return false end
    return ensure_entry_identity(entries, entry, target)
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
    local entry = {
        _storage_id    = new_storage_id(entries),
        phrase         = card.phrase         or "",
        ipa            = card.ipa            or "",
        definition     = card.definition     or "",
        synonyms       = card.synonyms       or "",
        text           = card.text           or "",
        source         = card.source         or "",
        book_title     = card.book_title     or "",
        book_author    = card.book_author    or "",
        image_path     = card.image_path     or "",
        image_prompt   = card.image_prompt   or "",
        _audio_url     = card._audio_url     or "",
        _ankivocab_word = card._ankivocab_word or "",
        highlight_pos0 = card.highlight_pos0,
        highlight_pos1 = card.highlight_pos1,
        annotation_source = card.annotation_source,
        origin_key = card.origin_key,
        selected_text = card.selected_text,
        date           = os.date("%Y-%m-%d"),
        updated_at     = os.time(),
        sent_to_anki   = false,
    }
    table.insert(entries, entry)
    if not save_raw(entries) then return false, "write_failed" end
    card._storage_id = entry._storage_id
    card.sent_to_anki = entry.sent_to_anki
    return true
end

-- Returns the full list of saved cards.
function CardStorage.load_cards()
    return load_raw()
end

-- ── Card export ─────────────────────────────────────────────────────────────

local function escape_export_cell(value, delimiter)
    value = tostring(value or "")
    -- Spreadsheet applications may evaluate cells that begin with formula
    -- markers, including after leading whitespace. Prefix an apostrophe so the
    -- original value is imported as literal text.
    if value:match("^%s*[=+%-@]") then
        value = "'" .. value
    end
    if value:find('"', 1, true)
       or value:find(delimiter, 1, true)
       or value:find("\r", 1, true)
       or value:find("\n", 1, true) then
        return '"' .. value:gsub('"', '""') .. '"'
    end
    return value
end

local function image_filename(path)
    if not path or path == "" then return "" end
    return path:match("([^/\\]+)$") or path
end

local function export_path(format)
    local stamp = os.date("%Y%m%d-%H%M%S")
    local path = EXPORT_PREFIX .. stamp .. "." .. format
    local suffix = 2
    local existing = io.open(path, "r")
    while existing do
        existing:close()
        path = EXPORT_PREFIX .. stamp .. "_" .. tostring(suffix) .. "." .. format
        suffix = suffix + 1
        existing = io.open(path, "r")
    end
    return path
end

-- Export cards as CSV or TSV. Images are represented by filename only.
-- Returns output path and count, or nil, 0, and an error code.
function CardStorage.export_cards(cards, format)
    if format ~= "csv" and format ~= "tsv" then
        return nil, 0, "unsupported_format"
    end
    if not cards or #cards == 0 then
        return nil, 0, "no_cards"
    end

    local delimiter = format == "csv" and "," or "\t"
    local path = export_path(format)
    local temp_path = path .. ".tmp"
    local file = io.open(temp_path, "w")
    if not file then return nil, 0, "write_failed" end

    local fields = { "Phrase", "IPA", "Definition", "Synonyms", "Text", "Source", "Image" }
    if not file:write(table.concat(fields, delimiter), "\r\n") then
        file:close()
        os.remove(temp_path)
        return nil, 0, "write_failed"
    end
    for _, card in ipairs(cards) do
        card = card or {}
        local row = {
            tostring(card.phrase or ""),
            tostring(card.ipa or ""),
            tostring(card.definition or ""),
            tostring(card.synonyms or ""),
            tostring(card.text or ""),
            tostring(card.source or ""),
            tostring(image_filename(card.image_path) or ""),
        }
        for i = 1, #row do
            row[i] = escape_export_cell(row[i], delimiter)
        end
        if not file:write(table.concat(row, delimiter), "\r\n") then
            file:close()
            os.remove(temp_path)
            return nil, 0, "write_failed"
        end
    end
    if not file:close() then
        os.remove(temp_path)
        return nil, 0, "write_failed"
    end

    if not os.rename(temp_path, path) then
        os.remove(temp_path)
        return nil, 0, "write_failed"
    end
    return path, #cards
end

-- Update image_path on an already-saved card (called after async generation).
-- target may be a card table, so delayed work follows its generation identity
-- instead of a phrase that may have been edited or regenerated.
function CardStorage.update_image_path(target, path)
    local entries = load_raw()
    local e = find_entry(entries, target)
    if e and e.kind ~= "learn" then
        if not ensure_entry_identity(entries, e, target) then return false end
        e.image_path = path
        return save_raw(entries)
    end
    return false
end

-- Update _audio_url on an already-saved card (called after async polling).
function CardStorage.update_audio_url(target, url)
    local entries = load_raw()
    local e = find_entry(entries, target)
    if e and e.kind ~= "learn" then
        if not ensure_entry_identity(entries, e, target) then return false end
        e._audio_url = url
        return save_raw(entries)
    end
    return false
end

-- Update editable fields of an already-saved card (matched by original phrase
-- or stable identity). Does not touch book metadata, image_path, date or sent_to_anki.
function CardStorage.update_card(target, new_card)
    local entries = load_raw()
    local e = find_entry(entries, target)
    if e and e.kind ~= "learn" then
        -- Editing a card may change its phrase, but must not create a second
        -- record with the same normalized phrase.
        if has_other_normalized_phrase(entries, e, new_card.phrase) then
            return false, "already_saved"
        end
        if not ensure_entry_identity(entries, e, target) then return false, "write_failed" end
        e.phrase       = new_card.phrase       or ""
        e.ipa          = new_card.ipa          or ""
        e.definition   = new_card.definition   or ""
        e.synonyms     = new_card.synonyms     or ""
        e.text         = new_card.text         or ""
        e.source       = new_card.source       or ""
        e.image_prompt = new_card.image_prompt or e.image_prompt or ""
        e.updated_at   = os.time()
        if not save_raw(entries) then return false, "write_failed" end
        new_card._storage_id = e._storage_id
        new_card.sent_to_anki = e.sent_to_anki
        return true
    end
    return false, "not_saved"
end

-- Replace a saved card after a full regeneration. The replacement deliberately
-- gets a new identity so delayed image/audio callbacks for the previous
-- generation cannot overwrite it. Local metadata and Anki send state survive.
function CardStorage.replace_card(target, new_card)
    local entries = load_raw()
    local e = find_entry(entries, target)
    if not e then return false, "not_saved" end
    -- Check before changing identity or fields so a rejected regeneration
    -- leaves the saved card exactly as it was.
    if has_other_normalized_phrase(entries, e, new_card.phrase) then
        return false, "already_saved"
    end
    if not ensure_entry_identity(entries, e, target) then return false, "write_failed" end

    local sent_to_anki = e.sent_to_anki
    local date = e.date
    local old_image_path = e.image_path
    e._storage_id     = new_storage_id(entries)
    e.phrase          = new_card.phrase          or ""
    e.ipa             = new_card.ipa             or ""
    e.definition      = new_card.definition      or ""
    e.synonyms        = new_card.synonyms        or ""
    e.text            = new_card.text            or ""
    e.source          = new_card.source          or ""
    e.book_title      = new_card.book_title      or e.book_title or ""
    e.book_author     = new_card.book_author     or e.book_author or ""
    e.image_path      = new_card.image_path      or ""
    e.image_prompt    = new_card.image_prompt    or ""
    e._audio_url      = new_card._audio_url      or ""
    e._ankivocab_word = new_card._ankivocab_word or ""
    e.highlight_pos0  = new_card.highlight_pos0 ~= nil and new_card.highlight_pos0 or e.highlight_pos0
    e.highlight_pos1  = new_card.highlight_pos1 ~= nil and new_card.highlight_pos1 or e.highlight_pos1
    e.annotation_source = new_card.annotation_source ~= nil and new_card.annotation_source or e.annotation_source
    e.origin_key = new_card.origin_key ~= nil and new_card.origin_key or e.origin_key
    e.selected_text = new_card.selected_text ~= nil and new_card.selected_text or e.selected_text
    e.annotation_aliases = new_card.annotation_aliases ~= nil and new_card.annotation_aliases or e.annotation_aliases
    e.date            = date
    e.updated_at      = os.time()
    e.sent_to_anki    = sent_to_anki
    if not save_raw(entries) then return false, "write_failed" end
    new_card._storage_id = e._storage_id
    new_card.sent_to_anki = sent_to_anki
    -- Persistence comes first. A failed asset cleanup must not roll back or
    -- reintroduce a stale record; at worst it leaves an obsolete file.
    if old_image_path and old_image_path ~= "" and old_image_path ~= e.image_path then
        CardStorage.remove_image_if_unreferenced(old_image_path)
    end
    return true
end

-- Remove card by 1-based index. Persist the revised list before deleting its
-- image so a failed write cannot leave a saved card pointing at a missing asset.
function CardStorage.delete_card(idx)
    local entries = load_raw()
    local card    = entries[idx]
    if not card then return false, "not_saved" end

    table.remove(entries, idx)
    if not save_raw(entries) then return false, "write_failed" end

    if card.image_path and card.image_path ~= "" then
        CardStorage.remove_image_if_unreferenced(card.image_path)
    end
    return true
end

-- Delete by stable identity, never by the position of a filtered display list.
function CardStorage.delete_card_by_id(storage_id)
    if not storage_id or storage_id == "" then return false, "not_saved" end
    local entries = load_raw()
    for idx, card in ipairs(entries) do
        if card._storage_id == storage_id then
            return CardStorage.delete_card(idx)
        end
    end
    return false, "not_saved"
end

-- Empty the entire card list and delete all associated image files. Persist the
-- empty list first so a write failure leaves every saved record and asset intact.
function CardStorage.clear_all()
    local entries = load_raw()
    if not save_raw({}) then return false, "write_failed" end

    for _, card in ipairs(entries) do
        if card.image_path and card.image_path ~= "" then
            CardStorage.remove_image_if_unreferenced(card.image_path)
        end
    end
    return true
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

-- Apply a worker receipt only to the same still-pending local snapshot.
-- Never recreate deleted cards or overwrite edits made while it was sending.
function CardStorage.record_sent_guarded(snapshot, expected_stamp, receipt)
    local id = type(receipt) == "table" and receipt.note_id
    if not ((type(id) == "number" and id > 0 and id % 1 == 0)
        or (type(id) == "string" and id:match("^%d+$") and tonumber(id) > 0)) then
        return false, "Anki no devolvió un ID de nota válido."
    end
    local R = require("anki_recovery")
    for _, card in ipairs(load_raw()) do
        local same = snapshot.kind == "learn" and card.kind == "learn" and card.card_id == snapshot.card_id
            or snapshot.kind ~= "learn" and card.kind ~= "learn" and normalize(card.phrase) == normalize(snapshot.phrase)
        if same then
            if card.sent_to_anki and tostring(card.anki_note_id) == tostring(receipt.note_id) then return true end
            if card.sent_to_anki or R.needs_review(card) or R.stamp(card) ~= expected_stamp then
                return false, "La tarjeta cambió durante el envío. Usa Recuperar desde Anki."
            end
            return CardStorage.record_sent(card, receipt)
        end
    end
    return false, "La tarjeta local ya no existe. No se ha recreado."
end

function CardStorage.mark_sent(phrase)
    local key     = normalize(phrase)
    local entries = load_raw()
    for _, e in ipairs(entries) do
        if e.kind ~= "learn" and normalize(e.phrase) == key then
            e.sent_to_anki = true
            return save_raw(entries)
        end
    end
    return false
end

-- Persist Anki connection settings (override configuration.lua at runtime).
function CardStorage.save_anki_settings(settings)
    -- Encode first and replace atomically: never truncate stored API keys
    -- when encoding, writing or closing the new settings fails.
    return save_file(SETTINGS_FILE, settings)
end

local function read_settings(path)
    local f, err, code = io.open(path, "r")
    if not f then
        -- Do not treat permission/read errors as a missing local configuration.
        return nil, err, code == 2 or (err == nil and code == nil)
    end
    local content = f:read("*all")
    local closed = f:close()
    if not closed or not content or content == "" then return nil, "No se pudo leer la configuración del complemento.", false end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then return data, nil, false end
    return nil, "La configuración del complemento no contiene JSON válido.", false
end

-- The plugin-local file is authoritative, including when restored by ChronoSync.
-- Migrate only if it does not exist; never merge over or replace a restored file.
function CardStorage.load_anki_settings()
    local data, err, missing = read_settings(SETTINGS_FILE)
    CardStorage.settings_migration_error = nil
    CardStorage.settings_load_error = not missing and not data and err or nil
    if not missing then return data, err end
    local legacy, legacy_err, legacy_missing = read_settings(LEGACY_SETTINGS_FILE)
    if not legacy then
        CardStorage.settings_load_error = not legacy_missing and legacy_err or nil
        return nil, legacy_err
    end
    -- Rename preserves the original bytes/keys and removes the isolated file.
    -- If this fails (read-only plugin, full filesystem, etc.), keep using the
    -- intact old file and report that the move still needs attention.
    local moved = os.rename(LEGACY_SETTINGS_FILE, SETTINGS_FILE)
    if not moved then
        CardStorage.settings_migration_error = "No se pudo mover la configuración a la carpeta del complemento. Se conserva y se usa el archivo anterior."
        return legacy, CardStorage.settings_migration_error
    end
    return legacy
end

return CardStorage

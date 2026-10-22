-- Shared configuration rules. No UI dependencies or network requests.
local State = {}
local OPTIONAL_VALUES = {"model", "image_model", "gemini_text_model", "gemini_image_model", "openai_model",
    "openai_image_model", "openrouter_model", "openrouter_image_model", "deepseek_model",
    "text_provider", "target_language",
    "deck", "book_parent", "vocab_deck_name", "learn_deck_name", "elevenlabs_voice_id"}
local function clear_blanks(values)
    for _, key in ipairs(OPTIONAL_VALUES) do
        if type(values[key]) == "string" and not values[key]:match("%S") then values[key] = nil end
    end
end

function State.has_key(value)
    return type(value) == "string" and value:match("%S") ~= nil
        and not value:match("^YOUR_") and not value:match("^PENDIENTE")
end

function State.merge(base, saved)
    local cfg = {}
    for k, v in pairs(base or {}) do if k ~= "anki" then cfg[k] = v end end
    for k, v in pairs((base or {}).anki or {}) do
        cfg[k == "model" and "anki_model" or k] = v
    end
    for k, v in pairs(saved or {}) do cfg[k] = v end
    if saved and not saved.settings_version and not saved.anki_model and saved.model and saved.model ~= "" then
        cfg.anki_model = saved.model
        cfg.model = base and base.model or "qwen-plus"
    end
    clear_blanks(cfg)
    if cfg.deck_mode ~= "configured" then cfg.deck_mode = "book" end
    if cfg.highlight_on_save == nil then cfg.highlight_on_save = cfg.highlight_on_generate end
    cfg.highlight_on_generate = nil -- Preserve the previous checkbox preference, not its trigger.
    for _, key in ipairs({"split_card_types", "auto_send_wifi", "tts_enabled", "cloud_auto_sync", "highlight_on_save"}) do cfg[key] = cfg[key] == true end
    if type(cfg.sync_server) ~= "table" then cfg.sync_server = nil end
    return cfg
end

function State.apply(base, cfg)
    if not base then return end
    local anki_keys = {url = true, deck = true, book_parent = true, deck_mode = true,
        vocab_deck_name = true, learn_deck_name = true,
        tags = true, auto_send_wifi = true, split_card_types = true}
    -- Do not keep shadow copies of plugin settings in the Anki subtable.
    -- In particular a removed cloud server must not reappear on the next merge.
    base.anki, base.anki_model = {}, nil
    base.sync_server = cfg.sync_server
    for k, v in pairs(cfg) do
        if anki_keys[k] then
            base.anki[k] = v
        elseif k ~= "anki_model" then
            base[k] = v
        end
    end
    clear_blanks(base)
    clear_blanks(base.anki)
end

-- Read old note-type keys only to disambiguate legacy AI model settings.
-- Never write them back as editable configuration.
function State.persistable(cfg)
    local clean = {}
    for k, v in pairs(cfg) do if k ~= "anki_model" and k ~= "anki" then clean[k] = v end end
    clean.settings_version = 2 -- 'model' is now always an AI model, never a note type.
    return clean
end

function State.book_parent(cfg)
    if type(cfg.book_parent) == "string" and cfg.book_parent:match("%S") then return cfg.book_parent end
    return (cfg.deck or "KOReader"):match("^([^:]+)") or "KOReader"
end

function State.normalize_type_deck_name(value)
    if type(value) ~= "string" then return nil, "Escribe un nombre para cada subbaraja." end
    local name = value:match("^%s*(.-)%s*$")
    if name == "" then return nil, "Los nombres de las subbarajas no pueden estar vacíos." end
    if name:find("::", 1, true) or name:find("%c") then
        return nil, "Escribe solo el nombre de la subbaraja, sin :: ni saltos de línea. El Deck Padre se configura aparte."
    end
    if #name > 160 then return nil, "El nombre de la subbaraja es demasiado largo." end
    return name
end

function State.validate_type_deck_names(vocab, learn)
    local v, err = State.normalize_type_deck_name(vocab)
    if not v then return nil, err end
    local l; l, err = State.normalize_type_deck_name(learn)
    if not l then return nil, err end
    local ok, utf8 = pcall(require, "ffi/utf8proc")
    local lower = ok and utf8.lowercase or string.lower
    if lower(v) == lower(l) then return nil, "Usa nombres distintos para Vocab y Learn." end
    return {vocab = v, learn = l}
end

function State.type_deck_name(cfg, kind)
    local names = State.validate_type_deck_names(cfg.vocab_deck_name or "Vocabulario", cfg.learn_deck_name or "Aprendizaje")
    if not names then return kind == "learn" and "Aprendizaje" or "Vocabulario" end
    return kind == "learn" and names.learn or names.vocab
end

function State.extra_tags(tags)
    local out, seen = {}, {}
    if type(tags) ~= "table" then return out end
    for _, value in ipairs(tags) do
        if type(value) == "string" then
            local tag = value:match("^%s*(.-)%s*$"):gsub("%s+", "_")
            local key = tag:lower()
            if tag ~= "" and key ~= "koreader" and key ~= "koreader::vocab" and key ~= "koreader::learn" and not seen[key] then
                out[#out+1], seen[key] = tag, true
            end
        end
    end
    return out
end

function State.normalize_url(value)
    value = (value or ""):match("^%s*(.-)%s*$")
    if value == "" then return nil, "Introduce la IP del ordenador donde está Anki." end
    if not value:find("://", 1, true) then value = "http://" .. value end
    local host, port = value:match("^http://([%w%.%-]+):?(%d*)/?$")
    if not host then return nil, "Usa una IP o nombre de red, por ejemplo 192.168.50.213:8765." end
    if host == "localhost" or host == "127.0.0.1" or host == "0.0.0.0" then
        return nil, "Usa la IP de tu ordenador, no localhost. El Kobo es otro dispositivo."
    end
    if port == "" then port = "8765" end
    if tonumber(port) < 1 or tonumber(port) > 65535 then return nil, "El puerto debe estar entre 1 y 65535." end
    return "http://" .. host .. ":" .. port
end

return State

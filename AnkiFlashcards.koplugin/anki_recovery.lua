-- Pure reconciliation rules. No Anki writes, file operations or UI.
local bit = require("bit")
local R = {}
local VOCAB = {"phrase", "ipa", "definition", "synonyms", "text", "source", "sound"}
local LEARN = {"question", "answer", "explanation", "evidence", "selected_text", "source_context",
    "context_quality", "book_title", "book_author", "chapter", "location"}
function R.keys(card) return card.kind == "learn" and LEARN or VOCAB end
function R.hash(value)
    local a, b = bit.tobit(2166136261), bit.tobit(2246822519)
    for i = 1, #value do
        a, b = bit.bxor(a, value:byte(i)), bit.bxor(b, value:byte(i))
        a, b = bit.tobit(a * 403 + bit.lshift(a, 24)), bit.tobit(b * 403 + bit.lshift(b, 24))
    end
    return bit.tohex(a) .. bit.tohex(b)
end
local function encoded(values)
    local parts = {}
    for _, value in ipairs(values) do
        value = tostring(value or "")
        parts[#parts+1] = #value .. ":" .. value
    end
    return table.concat(parts, "|")
end
function R.content(card)
    local parts = {card.kind == "learn" and "learn" or "vocab"}
    for _, key in ipairs(R.keys(card)) do parts[#parts+1] = card[key] or "" end
    return R.hash(encoded(parts))
end
function R.remote_fingerprint(card)
    return R.hash(encoded({R.content(card), card.anki_image_name or ""}))
end
function R.local_fingerprint(card)
    return R.hash(encoded({R.content(card), card.image_path or "", card.image_prompt or ""}))
end
function R.same_source(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or a.profile ~= b.profile then return false end
    local shared = false
    for _, key in ipairs({"vocabulary_id", "learn_id"}) do
        if a[key] and b[key] then
            if tostring(a[key]) ~= tostring(b[key]) then return false end
            shared = true
        end
    end
    return shared
end
function R.source_key(source)
    if type(source) ~= "table" then return "" end
    return encoded({source.profile or "", source.vocabulary_id or "", source.learn_id or ""})
end
function R.stamp(card)
    return R.hash(encoded({R.local_fingerprint(card), card.kind or "", card.card_id or "", card.anki_note_id or "",
        R.source_key(card.anki_source), card.anki_deck or "", table.concat(type(card.anki_decks) == "table" and card.anki_decks or {}, "\0"),
        card.anki_remote_fingerprint or "", card.anki_local_fingerprint or "", card.anki_sync_state or "",
        tostring(card.anki_image_pending == true), card.updated_at or ""}))
end
function R.classify(local_card, remote_card)
    if (local_card.kind == "learn") ~= (remote_card.kind == "learn") then return "identity_conflict" end
    if local_card.kind == "learn" and local_card.card_id ~= remote_card.card_id then return "identity_conflict" end
    if R.content(local_card) == R.content(remote_card) and
        (not local_card.anki_remote_fingerprint or R.remote_fingerprint(remote_card) == local_card.anki_remote_fingerprint) then
        if local_card.anki_local_fingerprint and R.local_fingerprint(local_card) ~= local_card.anki_local_fingerprint then return "local_changed" end
        return "same"
    end
    if not local_card.anki_remote_fingerprint or not local_card.anki_local_fingerprint then return "unverified_change" end
    local remote_changed = R.remote_fingerprint(remote_card) ~= local_card.anki_remote_fingerprint
    local local_changed = R.local_fingerprint(local_card) ~= local_card.anki_local_fingerprint
    if remote_changed and local_changed then return "conflict" end
    if remote_changed then return "remote_changed" end
    if local_changed then return "local_changed" end
    return "same"
end
function R.deck_changed(card, decks)
    local before = type(card.anki_decks) == "table" and card.anki_decks or (card.anki_deck and {card.anki_deck}) or {}
    return table.concat(before, "\0") ~= table.concat(decks, "\0")
end
function R.preview(card)
    local text = card.kind == "learn" and ((card.question or "") .. "\n\n" .. (card.answer or ""))
        or ((card.phrase or "") .. "\n\n" .. (card.definition or "") .. "\n\n" .. (card.text or ""))
    if #text > 650 then text = (text:sub(1, 630):match("^(.*)%s") or "Texto largo") .. "…" end
    return text
end
function R.needs_review(card)
    local state = card.anki_sync_state
    return card.anki_note_id ~= nil and state ~= nil and state ~= "ok" and state ~= "unverified"
end
function R.differences(a, b)
    local labels = {phrase = "Expresión", ipa = "Pronunciación", definition = "Definición", synonyms = "Sinónimos",
        text = "Frase", source = "Fuente", sound = "Audio", question = "Pregunta", answer = "Respuesta",
        explanation = "Explicación", evidence = "Cita", selected_text = "Selección", source_context = "Contexto",
        context_quality = "Tipo de contexto", book_title = "Libro", book_author = "Autor", chapter = "Capítulo", location = "Ubicación"}
    local fields = {}
    for _, key in ipairs(R.keys(a)) do if (a[key] or "") ~= (b[key] or "") then fields[#fields+1] = labels[key] or key end end
    if (a.anki_image_name or "") ~= (b.anki_image_name or "") then fields[#fields+1] = "Referencia de imagen" end
    return fields
end
return R

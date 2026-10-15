-- Keep the original selection visible independently of the generated question.
local Preview = {}
local function line(value)
    return type(value) == "string" and value:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end
function Preview.fragment(card)
    local selected = line(card.selected_text)
    if selected ~= "" then return selected end
    local source = card.annotation_source
    selected = line(type(source) == "table" and type(source.selection) == "table" and source.selection.text)
    if selected ~= "" then return selected end
    -- For vocabulary the selected expression is the only available fallback;
    -- never present an AI-generated cloze or question as a book quotation.
    return card.kind ~= "learn" and line(card.phrase) or ""
end
function Preview.parts(card, prefix)
    local heading = prefix .. (card.kind == "learn" and "[Learn] " or "[Vocab] ")
        .. line(card.kind == "learn" and (card.question or card.phrase) or card.phrase)
    local fragment = Preview.fragment(card)
    local book = line(card.book_title)
    if book == "" then book = "Libro desconocido" end
    local date = line(card.date)
    return {heading, fragment ~= "" and ("«" .. fragment .. "»") or "Fragmento no disponible",
        book .. (date ~= "" and (" · " .. date) or "")}
end
function Preview.label(card, prefix, fit)
    local parts = Preview.parts(card, prefix)
    for i, text in ipairs(parts) do parts[i] = fit(text) end
    return table.concat(parts, "\n")
end
return Preview

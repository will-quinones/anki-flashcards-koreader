-- Native document text only: no screenshots, OCR, or navigation changes.
local Context = {}
local function trim(text) return (text or ""):match("^%s*(.-)%s*$") end
local function safe_call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, a, b = pcall(object[method], object, ...)
    if ok then return a, b end
end
local function bounded(text, tail)
    if #text <= 4500 then return text end
    -- Cut at spaces rather than splitting a UTF-8 character.
    return tail and (text:sub(-4500):match("%s(.*)$") or "")
        or (text:sub(1, 4500):match("^(.*)%s") or "")
end
local function flatten(boxes)
    local parts = {}
    local function walk(value)
        if type(value) == "string" then parts[#parts+1] = value
        elseif type(value) == "table" then
            if type(value.word) == "string" then parts[#parts+1] = value.word
            elseif type(value.text) == "string" then parts[#parts+1] = value.text
            else for _, child in ipairs(value) do walk(child) end end
        end
    end
    walk(boxes)
    return table.concat(parts, " ")
end
function Context.capture(ui, selection, options)
    local selected = type(selection) == "table" and selection.text or selection
    if type(selected) ~= "string" or trim(selected) == "" then return nil, "Selecciona una idea o fragmento del libro." end
    if #selected > 6000 then return nil, "La selección es muy larga. Elige una idea o unos pocos párrafos." end
    local document = ui.document
    if type(selection) == "table" and selection.text_edited then
        local original = safe_call(document, "getTextFromXPointers", selection.pos0, selection.pos1)
        if type(original) ~= "string" or not original:match("%S") then
            return nil, "La anotación tiene texto editado y no se pudo recuperar el fragmento original. Selecciónalo de nuevo en el libro."
        end
        selected = original
        if #selected > 6000 then return nil, "La selección original es demasiado larga. Selecciona una idea más concreta." end
    end
    local props = safe_call(document, "getProps") or {}
    if type(props) ~= "table" then props = {} end
    local author = props.authors or props.author or ""
    if type(author) == "table" then author = table.concat(author, ", ") end
    if type(author) ~= "string" then author = "" end
    local pos0 = type(selection) == "table" and selection.pos0
    local pos1 = type(selection) == "table" and selection.pos1
    local page = type(pos0) == "table" and pos0.page or safe_call(document, "getPageFromXPointer", pos0)
    local source = {selected = trim(selected), title = type(props.title) == "string" and props.title or "", author = author,
        chapter = safe_call(ui.toc, "getTocTitleByPage", page) or "",
        location = page and ("Página " .. tostring(page)) or "",
        context = trim(selected), context_quality = "selection", pos0 = pos0, pos1 = pos1}
    source.book_key = props.identifier or props.isbn or source.title
    if options and options.include_reader_note and type(selection) == "table" and type(selection.note) == "string" then
        source.reader_note = trim(selection.note)
        if #source.reader_note > 2000 then source.reader_note = source.reader_note:sub(1, 2000):match("^(.*)%s") or "" end
    end
    if type(source.chapter) ~= "string" then source.chapter = "" end
    if type(pos0) == "string" and type(pos1) == "string" then
        -- crengine retrieves surrounding words across rendered page boundaries.
        local before, after = safe_call(document, "getSelectedWordContext", selected, 180, pos0, pos1,
            not options or options.restore_selection ~= false)
        if type(before) == "string" or type(after) == "string" then
            source.context = bounded(before or "", true) .. "\n" .. source.selected .. "\n" .. bounded(after or "", false)
            if trim(before or "") ~= "" or trim(after or "") ~= "" then source.context_quality = "document" end
        end
    elseif type(page) == "number" and document.getPageTextBoxes then
        -- Native PDF text from the selected page and neighbours, not OCR.
        local texts = {}
        local last = type(pos1) == "table" and pos1.page or page
        if type(last) ~= "number" or last < page or last - page > 2 then return nil, "Selecciona un fragmento de hasta tres páginas." end
        local end_page = math.min(last + 1, page + 2)
        local count = document.info and document.info.number_of_pages
        if type(count) == "number" then end_page = math.min(end_page, count) end
        for p = math.max(1, page - 1), end_page do
            local text = flatten(safe_call(document, "getPageTextBoxes", p))
            if text ~= "" then texts[#texts+1] = bounded(text, false) end
        end
        if #texts > 0 then
            source.context = source.selected .. "\n\n" .. table.concat(texts, "\n\n")
            source.context_quality = "pages"
        end
    end
    if #source.context > 20000 then
        source.context = source.context:sub(1, 20000):match("^(.*)%s") or source.selected
    end
    return source
end
return Context

-- Source identity and optional native highlighting. No generated-card writes.
local Learn = require("learning_card")
local function copy(value) return require("util").tableDeepCopy(value) end
local A = {}
local function text(value) return type(value) == "string" and value or "" end
local function normalize(value) return text(value):gsub("%s+", " "):match("^%s*(.-)%s*$") end
local function call(object, method, ...)
    if not object or type(object[method]) ~= "function" then return nil end
    local ok, result = pcall(object[method], object, ...)
    if ok then return result end
end
function A.same_position(a, b, field)
    if type(a) ~= type(b) then return false end
    if type(a) == "number" and field ~= "page" then return math.abs(a - b) <= 0.01 end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not A.same_position(value, b[key], key) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
function A.valid_range(selection)
    local a, b = selection and selection.pos0, selection and selection.pos1
    if type(a) == "string" and type(b) == "string" then return a ~= "" and b ~= "" end
    return type(a) == "table" and type(b) == "table" and type(a.page) == "number" and type(b.page) == "number"
end
function A.book(ui)
    local props = call(ui.document, "getProps") or {}
    if type(props) ~= "table" then props = {} end
    local author = props.authors or props.author
    if type(author) == "table" then author = table.concat(author, ", ") end
    return {file = text(ui.document and ui.document.file), title = text(props.title), author = text(author),
        key = text(props.identifier or props.isbn or props.title)}
end
function A.capture(ui, selection)
    if type(selection) ~= "table" then return nil end
    local book = A.book(ui)
    local saved = {}
    for _, key in ipairs({"text", "pos0", "pos1", "pboxes", "ext", "drawer", "color", "note", "chapter", "text_edited"}) do
        saved[key] = type(selection[key]) == "table" and copy(selection[key]) or selection[key]
    end
    local page = type(saved.pos0) == "table" and saved.pos0.page or call(ui.document, "getPageFromXPointer", saved.pos0)
    local chapter = text(call(ui.toc, "getTocTitleByPage", page))
    if chapter == "" then chapter = text(saved.chapter) end
    local key = Learn.id({selected = normalize(saved.text), title = book.title, author = book.author,
        book_key = book.key ~= "" and book.key or book.file, chapter = chapter})
    return {book = book, selection = saved, origin_key = key, chapter = chapter}
end
function A.same_book(ui, snapshot)
    if not ui.document or ui.tearing_down or not snapshot or not snapshot.book then return false end
    local now, saved = A.book(ui), snapshot.book
    if now.file ~= "" and saved.file ~= "" then return now.file == saved.file end
    return now.title ~= "" and now.title == saved.title and now.author == saved.author
end
function A.find_highlight(ui, snapshot)
    if not A.same_book(ui, snapshot) then return nil end
    local selected = snapshot.selection
    if not selected or not selected.pos0 or not selected.pos1 then return nil end
    for index, annotation in ipairs((ui.annotation and ui.annotation.annotations) or {}) do
        if annotation.drawer and A.same_position(annotation.pos0, selected.pos0)
            and A.same_position(annotation.pos1, selected.pos1) then return index end
    end
end
function A.can_highlight(ui, snapshot)
    local s = snapshot and snapshot.selection
    if not A.valid_range(s) or not A.same_book(ui, snapshot) or not normalize(s.text):match("%S") then return false end
    if not ui.highlight or type(ui.highlight.saveHighlight) ~= "function" then return false end
    if type(s.pos0) == "table" and not s.pboxes and not s.ext and not A.find_highlight(ui, snapshot) then return false end
    return true
end
function A.bind(card, snapshot)
    if not snapshot then return end
    card.annotation_source, card.origin_key = snapshot, snapshot.origin_key
    card.selected_text = card.selected_text or snapshot.selection.text
    card.highlight_pos0, card.highlight_pos1 = snapshot.selection.pos0, snapshot.selection.pos1
end
function A.highlight(ui, snapshot)
    if not A.can_highlight(ui, snapshot) then return nil, "Abre el libro original y selecciona de nuevo el fragmento para subrayarlo." end
    local existing = A.find_highlight(ui, snapshot)
    if existing then return true, nil, existing end
    local highlight, before = ui.highlight, ui.highlight.selected_text
    highlight.selected_text = copy(snapshot.selection)
    local ok, index = pcall(highlight.saveHighlight, highlight)
    highlight.selected_text = before -- Never disturb another current selection.
    local found = A.find_highlight(ui, snapshot)
    if found then return true, nil, found end
    if ok and type(index) == "number" then return true, nil, index end
    return nil, "No se pudo crear el subrayado. No se volverá a intentar automáticamente."
end
function A.find_card(snapshot, kind, cards, exact_source_only)
    if not snapshot then return nil end
    local selection, book = snapshot.selection, snapshot.book
    for _, card in ipairs(cards) do
        if (card.kind == "learn") == (kind == "learn") then
            if card.origin_key == snapshot.origin_key or (kind == "learn" and card.card_id == snapshot.origin_key) then return card end
            for _, key in ipairs(type(card.annotation_aliases) == "table" and card.annotation_aliases or {}) do if key == snapshot.origin_key then return card end end
            local same_book = book.title ~= "" and card.book_title == book.title and (card.book_author or "") == book.author
            if same_book and selection.pos0 and selection.pos1 and A.same_position(card.highlight_pos0, selection.pos0)
                and A.same_position(card.highlight_pos1, selection.pos1) then return card end
            if same_book and normalize(card.selected_text) ~= "" and normalize(card.selected_text) == normalize(selection.text) then return card end
            -- Vocabulary storage is currently unique by canonical phrase.
            if not exact_source_only and kind ~= "learn" and normalize(card.phrase):lower() == normalize(selection.text):lower() then return card end
        end
    end
end
function A.viewer_actions(ui, card)
    if not card.annotation_source then return {} end
    return {
        is_highlighted = function() return A.find_highlight(ui, card.annotation_source) ~= nil end,
        can_add_highlight = function() return A.can_highlight(ui, card.annotation_source) end,
        on_add_highlight = function()
            local ok, err = A.highlight(ui, card.annotation_source)
            if not ok then return nil, err end
            local saved = require("card_storage").save_annotation_link(card)
            if not saved then return true, "Subrayado creado; no se pudo actualizar el vínculo de la tarjeta." end
            return true
        end,
    }
end
function A.can_navigate(ui, card)
    if not ui or not ui.document or ui.tearing_down or not card.highlight_pos0 then return false end
    if card.annotation_source then return A.same_book(ui, card.annotation_source) end
    local book = A.book(ui)
    return book.title ~= "" and card.book_title == book.title and (card.book_author or "") == book.author
end
return A

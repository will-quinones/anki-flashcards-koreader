-- Learning cards have their own identity/schema; no user-visible profiles.
local bit = require("bit")
local Learn = {MODEL = "KOReader Learn"}
Learn.FIELDS = {"PluginID", "Question", "Answer", "Explanation", "SelectedText",
    "SourceExcerpt", "BookTitle", "Author", "Chapter", "Location", "Context", "ContextQuality"}
local function normalized(text)
    return (type(text) == "string" and text or ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
end
function Learn.id(source)
    local data = table.concat({normalized(source.book_key or source.title), normalized(source.author),
        normalized(source.chapter), normalized(source.selected)}, "\0")
    local function hash(seed)
        local h = bit.tobit(seed)
        for i = 1, #data do
            h = bit.bxor(h, data:byte(i))
            h = bit.tobit(h * 403 + bit.lshift(h, 24))
        end
        return bit.tohex(h)
    end
    return "learn-" .. hash(2166136261) .. hash(2246822519)
end
function Learn.escape(text)
    return (text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end
local function unescape(text)
    return (text or ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
        :gsub("&#39;", "'"):gsub("&amp;", "&")
end
function Learn.fields(card)
    local values = {PluginID = card.card_id, Question = card.question, Answer = card.answer,
        Explanation = card.explanation, SelectedText = card.selected_text,
        SourceExcerpt = card.evidence, BookTitle = card.book_title, Author = card.book_author,
        Chapter = card.chapter, Location = card.location, Context = card.source_context,
        ContextQuality = card.context_quality}
    for key, value in pairs(values) do values[key] = Learn.escape(value) end
    return values
end
function Learn.from_note(note)
    local function field(key)
        local entry = note.fields and note.fields[key]
        return type(entry) == "table" and type(entry.value) == "string" and unescape(entry.value) or ""
    end
    local id, question, answer = field("PluginID"), field("Question"), field("Answer")
    if not id:match("^learn%-%x+$") or question:match("^%s*$") or answer:match("^%s*$") then return nil end
    return {kind = "learn", card_id = id, phrase = question, question = question, answer = answer,
        explanation = field("Explanation"), selected_text = field("SelectedText"), evidence = field("SourceExcerpt"),
        book_title = field("BookTitle"), book_author = field("Author"), chapter = field("Chapter"),
        location = field("Location"), source_context = field("Context"), context_quality = field("ContextQuality"),
        image_path = "", image_prompt = "", sent_to_anki = true,
        anki_note_id = note.noteId, anki_model = Learn.MODEL, imported_from_anki = true}
end
function Learn.model_params()
    return {modelName = Learn.MODEL, inOrderFields = Learn.FIELDS, isCloze = false,
        css = ".card{font-family:Arial,sans-serif;font-size:20px;text-align:left;line-height:1.5;padding:20px}.answer{font-weight:bold}.source{font-size:15px;opacity:.8;white-space:pre-wrap}",
        cardTemplates = {{Name = "Pregunta", Front = "<div>{{Question}}</div>",
            Back = "{{FrontSide}}<hr id=answer><div class=answer>{{Answer}}</div>{{#Explanation}}<p>{{Explanation}}</p>{{/Explanation}}<div class=source>{{#SourceExcerpt}}<blockquote>{{SourceExcerpt}}</blockquote>{{/SourceExcerpt}}{{BookTitle}} — {{Author}}<br>{{Chapter}} {{Location}}</div>"}}}
end
return Learn

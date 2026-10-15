-- Internal contracts, not user settings. Both actions own their note type.
local Types = {VOCABULARY = "KOReader Vocabulary", LEARN = "KOReader Learn"}
function Types.model_name(kind)
    return kind == "learn" and Types.LEARN or Types.VOCABULARY
end
function Types.model_params(kind)
    if kind == "learn" then return require("learning_card").model_params() end
    local design = require("card_design").vocabulary()
    return {
        modelName = Types.VOCABULARY, isCloze = true,
        inOrderFields = {"Phrase", "IPA", "Definition", "Synonyms", "Text", "Source", "ImageFront", "ImageBack", "Sound"},
        css = design.css,
        cardTemplates = {design.template},
    }
end
return Types

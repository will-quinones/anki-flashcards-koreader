-- Internal contracts, not user settings. Both actions own their note type.
local Types = {VOCABULARY = "KOReader Vocabulary", LEARN = "KOReader Learn"}
function Types.model_name(kind)
    return kind == "learn" and Types.LEARN or Types.VOCABULARY
end
function Types.model_params(kind)
    if kind == "learn" then return require("learning_card").model_params() end
    return {
        modelName = Types.VOCABULARY, isCloze = true,
        inOrderFields = {"Phrase", "IPA", "Definition", "Synonyms", "Text", "Source", "ImageFront", "ImageBack", "Sound"},
        css = ".card{font-family:Arial,sans-serif;font-size:18px;text-align:center;padding:20px}.phrase{font-size:28px;font-weight:bold;color:#1a73e8;margin-bottom:8px}.ipa{font-size:20px;color:#d93025;margin-bottom:16px}.definition{font-size:18px;margin-bottom:16px}.synonyms{font-size:16px;color:#b35c00;font-weight:bold;margin-bottom:16px}.image-container img{max-width:100%;max-height:280px;border-radius:8px;margin-bottom:16px}.cloze{font-size:17px;line-height:1.6;margin-bottom:16px}.cloze b{color:#1a73e8}.source a{font-size:13px;color:#888;text-decoration:none}",
        cardTemplates = {{Name = "Card 1",
            Front = '<div class="definition">{{Definition}}</div><div class="synonyms">{{Synonyms}}</div><div class="image-container">{{ImageFront}}</div><div class="cloze">{{cloze:Text}}</div>',
            Back = '<div class="definition">{{Definition}}</div><div class="image-container">{{ImageBack}}</div><div class="phrase">{{Phrase}}</div><div class="ipa">{{IPA}}</div><div class="cloze">{{cloze:Text}}</div>{{Sound}}<div class="source"><a href="{{Source}}">{{Source}}</a></div>'}},
    }
end
return Types

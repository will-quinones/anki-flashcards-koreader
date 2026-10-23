-- Reject media belonging to dismissed, edited or superseded card content.
-- Per-card state is transient and never written into the saved collection.
local Media = {}
local states = setmetatable({}, {__mode = "k"})
function Media.invalidate(card)
    states[card] = nil
end
function Media.wrap(card, kind, callback, is_live)
    local state = states[card] or {}
    states[card] = state
    state[kind] = (state[kind] or 0) + 1
    local token, phrase, text, prompt, word = state[kind], card.phrase, card.text, card.image_prompt, card._ankivocab_word
    return function(value)
        local valid = states[card] == state and state[kind] == token and card.phrase == phrase
            and card.text == text and card.image_prompt == prompt and card._ankivocab_word == word
            and (not is_live or is_live())
        if valid then return callback(value) end
        if kind == "image" then require("card_storage").remove_image_if_unreferenced(value) end
    end
end
return Media

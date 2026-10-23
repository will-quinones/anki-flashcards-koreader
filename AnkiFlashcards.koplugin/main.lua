-- AnkiFlashcards KOReader plugin.
-- Tools menu for management and saved cards, plus card generation from
-- highlight selections and single-word dictionary popups.

local Device         = require("device")
local InfoMessage    = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr     = require("ui/network/manager")
local Notification   = require("ui/widget/notification")
local UIManager      = require("ui/uimanager")
local _              = require("gettext")

local get_selection_in_context = require("selection_context")

local CardGenerator    = require("card_generator")
local CardViewer       = require("card_viewer")
local CardStorage      = require("card_storage")
local AnkiSync         = require("anki_sync")
local CardManager      = require("card_manager")
local CardSync         = require("card_sync")
local HighlightInbox   = require("highlight_inbox")
local ImageGenerator   = require("image_generator")
local AudioGenerator   = require("audio_generator")
local SettingsViewer   = require("settings_viewer")
local SettingsState    = require("settings_state")
local Learning         = require("learning")
local Feedback         = require("generation_feedback")
local Recovery         = require("anki_recovery")
local HighlightMenu    = require("highlight_menu")
local Annotations      = require("annotation_tools")
local VocabGeneration  = require("vocab_generation")
local ReadingMarker    = require("reading_marker")
local CardMedia        = require("card_media")

local MAX_HL    = 2000
local MAX_TITLE = 100

local function copy_card(card)
    local copy = {}
    for key, value in pairs(card or {}) do copy[key] = value end
    return copy
end

local function copy_card_into(target, source)
    for key in pairs(target) do target[key] = nil end
    for key, value in pairs(source) do target[key] = value end
end

-- Load configuration from configuration.lua; saved anki settings (from the
-- settings UI) are merged on top at startup and at send time.
local CONFIGURATION = nil
do
    local ok, conf = pcall(require, "configuration")
    if ok then CONFIGURATION = conf end
    CONFIGURATION = CONFIGURATION or {}
    local saved_anki = CardStorage.load_anki_settings()
    if saved_anki then
        CONFIGURATION = CONFIGURATION or {}
        -- Old files used `model` for a note type and later `anki_model` to
        -- disambiguate it. New files use settings_version and automatic types.
        -- Read legacy aliases only to avoid mistaking an old note name for
        -- an AI model; never infer old note names from a hard-coded allowlist.
        if not saved_anki.settings_version and not saved_anki.anki_model and saved_anki.model and saved_anki.model ~= "" then
            saved_anki.anki_model = saved_anki.model
            saved_anki.model = nil
        end
        CONFIGURATION.anki = saved_anki
        -- Promote plugin-level settings from saved anki settings to top level.
        for _, key in ipairs({
            "target_language",
            "text_provider",
            "image_provider",
            "model",
            "image_model",
            "gemini_text_model",
            "gemini_image_model",
            "openai_model",
            "openai_image_model",
            "dashscope_api_key",
            "gemini_api_key",
            "openai_api_key",
            "openrouter_api_key",
            "openrouter_model",
            "openrouter_image_model",
            "deepseek_api_key",
            "deepseek_model",
            "elevenlabs_api_key",
            "ankivocab_api_key",
        }) do
            if (key == "image_provider" or key:match("_api_key$")) and saved_anki[key] ~= nil then
                -- An explicitly cleared image provider must override the file.
                CONFIGURATION[key] = saved_anki[key]
            elseif saved_anki[key] and saved_anki[key] ~= "" then
                CONFIGURATION[key] = saved_anki[key]
            end
        end
    end
end

-- Apply the same normalization used by the settings UI to generation/send
-- paths too; an empty displayed model must really use the provider default.
SettingsState.apply(CONFIGURATION, SettingsState.merge(CONFIGURATION, CardStorage.load_anki_settings()))

local AnkiFlashcards = InputContainer:new {
    name        = "ankiflashcards",
    is_doc_only = false,
}

-- Strip control chars, normalise whitespace, and truncate.
local function clean_str(s, max_len)
    if not s then return "" end
    s = s:gsub("[\r\n]+", " "):match("^%s*(.-)%s*$")
    if max_len and #s > max_len then s = s:sub(1, max_len) end
    return s
end

local function capitalize_first(s)
    return (s:gsub("^%l", string.upper))
end

local function cambridge_url(phrase)
    local lang = CONFIGURATION and CONFIGURATION.target_language or "English"
    if lang ~= "English" then return nil end
    local slug = (phrase or ""):lower():gsub("%s+", "-")
    return "https://dictionary.cambridge.org/dictionary/english/" .. slug
end

-- Safely unwrap rhi.selected_text which may be a string, a table with a
-- .text field, or a nested structure depending on the KOReader backend.
local function extract_text(sel)
    if type(sel) == "string" then return sel end
    if type(sel) ~= "table"  then return "" end
    if type(sel.text) == "string" then return sel.text end
    -- Nested spans/lines: collect string leaves
    local parts = {}
    local function collect(t)
        for _, v in ipairs(t) do
            if type(v) == "string" then
                parts[#parts + 1] = v
            elseif type(v) == "table" then
                if type(v.text) == "string" then parts[#parts + 1] = v.text end
                if v.spans    then collect(v.spans)    end
                if v.segments then collect(v.segments) end
                if v.lines    then collect(v.lines)    end
            end
        end
    end
    collect(sel)
    return table.concat(parts)
end

-- Build the effective Anki config by merging saved settings on top of
-- the config table loaded at startup.
local function get_anki_config()
    return SettingsState.merge(CONFIGURATION, CardStorage.load_anki_settings())
end

-- Build an image-generator config for a card.  When the image provider is
-- "ankivocab", copies CONFIGURATION and adds the keys the generator needs
-- to poll the API for the image URL.
local function make_image_config(card)
    local cfg = CONFIGURATION
    if CONFIGURATION.image_provider == "ankivocab" then
        cfg = {}
        for k, v in pairs(CONFIGURATION) do cfg[k] = v end
        cfg.image_provider = "ankivocab"
        if type(card._image_url) == "string" and card._image_url ~= "" then
            cfg._ankivocab_image_url = card._image_url
        end
        -- Use the original word sent to the API (persisted on card), falling
        -- back to the canonical phrase.  The API indexes by original word, so
        -- polling with the canonical form may not find the cached image.
        cfg._ankivocab_word = card._ankivocab_word or card.phrase
    end
    return cfg
end

-- Return true if the card has enough info to kick off image generation.
-- For ankivocab, only trigger if the card was actually created via AnkiVocab
-- (_ankivocab_word is set), not just because the current provider is ankivocab.
local function can_generate_image(card, img_cfg)
    if not ImageGenerator.is_enabled(img_cfg) then return false end
    local has_prompt = card.image_prompt and card.image_prompt ~= ""
    local is_ankivocab_card = img_cfg.image_provider == "ankivocab"
                          and card._ankivocab_word and card._ankivocab_word ~= ""
    return has_prompt or is_ankivocab_card
end

-- ── Quick Lookup cache + popup (purple highlights) ──────────────────────────
local quick_lookup_cache = {}

local PTF_BOLD_ON  = "\xEF\xBF\xB2"
local PTF_BOLD_OFF = "\xEF\xBF\xB3"

local function show_quick_lookup_popup(phrase, lookup, on_delete)
    local Blitbuffer      = require("ffi/blitbuffer")
    local ButtonTable     = require("ui/widget/buttontable")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font            = require("ui/font")
    local FrameContainer  = require("ui/widget/container/framecontainer")
    local Geom            = require("ui/geometry")
    local GestureRange    = require("ui/gesturerange")
    local InputContainer  = require("ui/widget/container/inputcontainer")
    local Size            = require("ui/size")
    local TextBoxWidget   = require("ui/widget/textboxwidget")
    local VerticalGroup   = require("ui/widget/verticalgroup")
    local VerticalSpan    = require("ui/widget/verticalspan")

    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local popup_w  = math.floor(screen_w * 0.82)
    local pad      = Size.padding.large

    local COLOR_BLUE = Blitbuffer.ColorRGB32(0x00, 0x3A, 0x75, 0xFF)
    local COLOR_RED  = Blitbuffer.ColorRGB32(0xBB, 0x00, 0x00, 0xFF)

    local inner_w = popup_w - pad * 2

    local phrase_w = TextBoxWidget:new {
        text      = capitalize_first(phrase),
        face      = Font:getFace("cfont", 24),
        fgcolor   = COLOR_BLUE,
        width     = inner_w,
        alignment = "center",
        bold      = true,
    }
    local ipa_w = TextBoxWidget:new {
        text      = lookup.ipa or "",
        face      = Font:getFace("cfont", 20),
        fgcolor   = COLOR_RED,
        width     = inner_w,
        alignment = "center",
    }
    local def_w = TextBoxWidget:new {
        text      = lookup.definition or "",
        face      = Font:getFace("cfont", 20),
        width     = inner_w,
        alignment = "center",
    }

    local content = VerticalGroup:new {
        align = "center",
        phrase_w,
        VerticalSpan:new { width = Size.padding.default },
        ipa_w,
        VerticalSpan:new { width = Size.padding.default },
        def_w,
    }

    -- Add a "Delete Highlight" button if a delete callback is provided.
    -- popup_ref is set after the popup widget is created (below).
    local popup_ref = {}
    if on_delete then
        local btn_table = ButtonTable:new {
            width = inner_w,
            buttons = {{
                {
                    text     = _("Delete Highlight"),
                    callback = function()
                        if popup_ref[1] then UIManager:close(popup_ref[1]) end
                        on_delete()
                    end,
                },
            }},
            zero_sep = true,
        }
        content[#content + 1] = VerticalSpan:new { width = Size.padding.large }
        content[#content + 1] = btn_table
    end

    local frame = FrameContainer:new {
        background   = Blitbuffer.COLOR_WHITE,
        bordersize   = Size.border.window,
        radius       = Size.radius.window,
        padding      = pad,
        content,
    }

    local popup
    popup = InputContainer:new {
        ges_events = {
            TapClose = {
                GestureRange:new {
                    ges   = "tap",
                    range = Geom:new { x = 0, y = 0, w = screen_w, h = screen_h },
                },
            },
        },
        CenterContainer:new {
            dimen = Geom:new { w = screen_w, h = screen_h },
            frame,
        },
    }
    function popup:onTapClose()
        UIManager:close(self)
        return true
    end
    function popup:onAnyKeyPressed()
        UIManager:close(self)
        return true
    end

    popup_ref[1] = popup
    UIManager:show(popup)
end

function AnkiFlashcards:init()
    self.ui.menu:registerToMainMenu(self)
    if CardStorage.migrate_data then CardStorage.migrate_data() end
    local storage_warning = CardStorage.settings_migration_error or CardStorage.settings_load_error or CardStorage.data_migration_error
    if storage_warning then
        UIManager:scheduleIn(0, function()
            if not self.ui.tearing_down then UIManager:show(InfoMessage:new {text = storage_warning}) end
        end)
    end
    -- Settings and saved cards are also accessible from the file browser.
    if not self.ui.highlight then return end

    -- ── Entry 4: Anki Card (primary action, registered last = bottom) ───────────
    local function card_button(rhi)
        return {
            text    = _("Anki Vocab"),
            enabled = Device:hasClipboard(),
            callback = function()
                local ui = self.ui

                -- Capture book metadata.
                local title  = clean_str(ui.document:getProps().title, MAX_TITLE)
                local author = ui.document:getProps().authors
                if type(author) == "table" then
                    author = table.concat(author, ", ")
                end
                author = clean_str(
                    (author and author ~= "") and author or "Unknown Author",
                    MAX_TITLE
                )

                -- Highlighted text, position, and surrounding context.
                local sel = rhi.selected_text
                local annotation_snapshot = Annotations.capture(ui, sel)
                ReadingMarker.clear(ui)
                local existing_card = Annotations.find_card(annotation_snapshot, "vocab", CardStorage.load_cards())
                if existing_card then
                    Annotations.bind(existing_card, annotation_snapshot)
                    ui.highlight:onClose()
                    CardManager.open_card(CONFIGURATION, existing_card, ui)
                    return
                end
                local highlighted = extract_text(sel or "")
                local phrase      = capitalize_first(clean_str(highlighted, MAX_HL))
                local highlight_pos0 = sel and sel.pos0
                local highlight_pos1 = sel and sel.pos1
                local context     = clean_str(
                    get_selection_in_context(ui.document, highlighted, 10),
                    MAX_HL
                )

                -- Source string shown in the Source field of the card.
                local source
                if title ~= "" and author ~= "" then
                    source = title .. " — " .. author
                elseif title ~= "" then
                    source = title
                else
                    source = author
                end

                -- The selection is captured first; optional highlighting
                -- only runs after the explicit Save action succeeds.
                ui.highlight:onClose()

                local function on_generated(card)
                    -- AnkiVocab returns its own source URL; other providers use Cambridge.
                    if not card.source or card.source == "" then
                        card.source = cambridge_url(card.phrase)
                    end
                    card.book_title     = title
                    card.book_author    = author
                    card.highlight_pos0 = highlight_pos0
                    card.highlight_pos1 = highlight_pos1
                    Annotations.bind(card, annotation_snapshot)

                    -- Keep _audio_url so AnkiConnect can download and attach
                    -- the server-generated audio when sending to Anki.

                    -- viewer_ref[1] always holds the currently visible CardViewer.
                    local viewer_ref = {}
                    local function media_callback(c, kind, callback)
                        return CardMedia.wrap(c, kind, callback, function()
                            return viewer_ref[1] ~= nil and viewer_ref[1].card == c
                        end)
                    end

                    -- make_viewer creates a CardViewer for card c.
                    -- show_back=false → front (question) side.
                    local function make_viewer(c, show_back_flag)
                        local v
                        local annotation_actions = Annotations.viewer_actions(ui, c)
                        v = CardViewer:new {
                            card      = c,
                            anki_base = CONFIGURATION,
                            show_back = show_back_flag or false,
                            on_add_highlight = annotation_actions.on_add_highlight,
                            is_highlighted = annotation_actions.is_highlighted,
                            can_add_highlight = annotation_actions.can_add_highlight,
                            on_dismiss = function()
                                CardMedia.invalidate(c)
                                viewer_ref[1] = nil
                                ReadingMarker.flash(ui, annotation_snapshot)
                            end,

                            on_show_answer = function()
                                -- Close whichever viewer is currently showing
                                -- (may differ from v after an async update).
                                local cur = viewer_ref[1] or v
                                cur._replacing = true
                                UIManager:close(cur)
                                local nv = make_viewer(c, true)
                                viewer_ref[1] = nv
                            end,
                            on_show_question = function()
                                local cur = viewer_ref[1] or v
                                cur._replacing = true
                                UIManager:close(cur)
                                viewer_ref[1] = make_viewer(c, false)
                            end,
                            on_viewer_updated = function(updated) viewer_ref[1] = updated end,

                            on_save = function()
                                local ok2, save_err = CardStorage.save_card(c)
                                if ok2 then
                                    local highlighted, highlight_err = Annotations.highlight_saved(get_anki_config(), ui, c)
                                    if not highlighted then
                                        UIManager:show(Notification:new {text = highlight_err or _("La tarjeta se guardó, pero no se pudo subrayar."), timeout = 5})
                                    end
                                    return true
                                else
                                    local msg = (save_err == "already_saved")
                                                and _("Already saved")
                                                or  _("Could not save")
                                    return nil, msg
                                end
                            end,

                            on_prepare_update = function(editing_card)
                                return not CardStorage.is_saved(editing_card) or CardStorage.ensure_identity(editing_card)
                            end,
                            on_update = function(updated_card)
                                if not CardStorage.is_saved(c) then CardMedia.invalidate(c); return true end
                                local ok, err = CardStorage.update_card(c, updated_card)
                                if ok then CardMedia.invalidate(c) end
                                return ok, err
                            end,

                            on_send = function()
                                local ok, err = AnkiSync.send_card(get_anki_config(), c, CONFIGURATION)
                                return ok, err
                            end,

                            on_regenerate = function()
                                NetworkMgr:runWhenOnline(function()
                                    if not viewer_ref[1] or viewer_ref[1]._anki_closed then return end
                                    VocabGeneration.start(CONFIGURATION, {phrase = phrase, context = context, title = title, author = author}, function(new_card)
                                        new_card.source         = new_card.source or cambridge_url(new_card.phrase)
                                        new_card.book_title     = title
                                        new_card.book_author    = author
                                        new_card.highlight_pos0 = highlight_pos0
                                        new_card.highlight_pos1 = highlight_pos1
                                        Annotations.bind(new_card, annotation_snapshot)
                                        local replaced, replace_err = true, nil
                                        if CardStorage.is_saved(c) then
                                            replaced, replace_err = CardStorage.replace_card(c, new_card)
                                        end
                                        if not replaced then
                                            UIManager:show(InfoMessage:new {
                                                text = replace_err == "already_saved"
                                                    and _("A card with this phrase is already saved")
                                                    or (_("Could not replace generated card: ") .. (replace_err or "unknown")),
                                                timeout = 5,
                                            })
                                            return
                                        end
                                        -- Regenerated card starts on front again.
                                        CardMedia.invalidate(c)
                                        if viewer_ref[1] then viewer_ref[1]._replacing = true; UIManager:close(viewer_ref[1]) end
                                        viewer_ref[1] = make_viewer(new_card, false)
                                        local regen_image_config = make_image_config(new_card)
                                        new_card._image_url = nil
                                        if can_generate_image(new_card, regen_image_config) then
                                            ImageGenerator.generate_async(
                                                regen_image_config, new_card.image_prompt, new_card.phrase,
                                                media_callback(new_card, "image", function(img_path)
                                                    local old_image = new_card.image_path
                                                    new_card.image_path = img_path
                                                    if new_card._storage_id and not CardStorage.update_image_path(new_card, img_path) then
                                                        new_card.image_path = old_image
                                                        CardStorage.remove_image_if_unreferenced(img_path)
                                                        UIManager:show(InfoMessage:new {
                                                            text = _("Could not save the generated image"), timeout = 5,
                                                        })
                                                        return
                                                    end
                                                    if Feedback.is_top(viewer_ref[1]) then viewer_ref[1] = viewer_ref[1]:update(new_card) end
                                                end),
                                                nil  -- image errors are non-fatal
                                            )
                                        end
                                        if new_card._audio_status == "pending" and new_card._ankivocab_word then
                                            AudioGenerator.poll_ankivocab_async(CONFIGURATION, new_card._ankivocab_word,
                                                media_callback(new_card, "audio", function(url)
                                                    new_card._audio_url = url
                                                    if new_card._storage_id then CardStorage.update_audio_url(new_card, url) end
                                                end), nil)
                                        end
                                    end, {regenerating = true, is_valid = function()
                                        return Annotations.same_book(ui, annotation_snapshot) and viewer_ref[1] ~= nil
                                    end})
                                end)
                            end,

                            on_regen_text = function()
                                NetworkMgr:runWhenOnline(function()
                                    Feedback.run(function() return CardGenerator.generate_text(CONFIGURATION, c.phrase) end,
                                    function(new_text, new_prompt)
                                        local candidate = copy_card(c)
                                        candidate.text = new_text
                                        candidate.image_prompt = new_prompt
                                        local saved, save_err = CardStorage.update_card(c, candidate)
                                        if not saved then
                                            UIManager:show(InfoMessage:new {
                                                text = _("Could not save regenerated sentence: ") .. (save_err or "unknown"),
                                                timeout = 5,
                                            })
                                            return
                                        end
                                        copy_card_into(c, candidate)
                                        CardMedia.invalidate(c)
                                        if viewer_ref[1] then viewer_ref[1]._replacing = true; UIManager:close(viewer_ref[1]) end
                                        viewer_ref[1] = make_viewer(c, true)
                                        -- Kick off image generation with new prompt.
                                        if new_prompt then
                                            ImageGenerator.generate_async(
                                                CONFIGURATION,
                                                new_prompt,
                                                c.phrase,
                                                media_callback(c, "image", function(img_path)
                                                    local old_image = c.image_path
                                                    c.image_path = img_path
                                                    local image_saved = CardStorage.update_image_path(c, img_path)
                                                    if not image_saved then
                                                        c.image_path = old_image
                                                        CardStorage.remove_image_if_unreferenced(img_path)
                                                        UIManager:show(InfoMessage:new {
                                                            text = _("Could not save the new image"), timeout = 5,
                                                        })
                                                        return
                                                    end
                                                    if old_image and old_image ~= "" then
                                                        CardStorage.remove_image_if_unreferenced(old_image)
                                                    end
                                                    if Feedback.is_top(viewer_ref[1]) then
                                                        viewer_ref[1] = viewer_ref[1]:update(c)
                                                    end
                                                end),
                                                nil
                                            )
                                        end
                                    end, nil, {label = Feedback.REGENERATING})
                                end)
                            end,

                            on_regen_image = ImageGenerator.is_enabled(CONFIGURATION) and function()
                                if not c.image_prompt or c.image_prompt == "" then
                                    UIManager:show(Notification:new {
                                        text    = _("No image prompt available"),
                                        timeout = 3,
                                    })
                                    return
                                end
                                local old_image = c.image_path
                                UIManager:show(Notification:new {
                                    text    = _("Generando imagen…"),
                                    timeout = 60,
                                })
                                ImageGenerator.generate_async(
                                    CONFIGURATION,
                                    c.image_prompt,
                                    c.phrase,
                                    media_callback(c, "image", function(img_path)
                                        c.image_path = img_path
                                        local saved = CardStorage.update_image_path(c, img_path)
                                        if not saved and c._storage_id then
                                            CardStorage.remove_image_if_unreferenced(img_path)
                                            c.image_path = old_image
                                            UIManager:show(InfoMessage:new {
                                                text = _("Could not save the new image"), timeout = 5,
                                            })
                                            return
                                        end
                                        if old_image and old_image ~= "" then
                                            CardStorage.remove_image_if_unreferenced(old_image)
                                        end
                                        if Feedback.is_top(viewer_ref[1]) then
                                            viewer_ref[1] = viewer_ref[1]:update(c)
                                        end
                                        UIManager:setDirty(nil, "full")
                                        UIManager:show(Notification:new {
                                            text    = _("New image loaded!"),
                                            timeout = 3,
                                        })
                                    end),
                                    function(err)
                                        UIManager:show(InfoMessage:new {
                                            text    = _("Imagen: ") .. Feedback.image_message(err),
                                            timeout = 5,
                                        })
                                    end
                                )
                            end,
                        }
                        UIManager:show(v)
                        return v
                    end

                    -- Open on the front side.
                    local initial_viewer = make_viewer(card, false)
                    viewer_ref[1] = initial_viewer

                    -- Start image generation in background.
                    local img_config = make_image_config(card)
                    card._image_url = nil
                    if can_generate_image(card, img_config) then
                        ImageGenerator.generate_async(
                            img_config,
                            card.image_prompt,
                            card.phrase,
                            media_callback(card, "image", function(img_path)
                                local old_image = card.image_path
                                card.image_path = img_path
                                if card._storage_id and not CardStorage.update_image_path(card, img_path) then
                                    card.image_path = old_image
                                    CardStorage.remove_image_if_unreferenced(img_path)
                                    UIManager:show(InfoMessage:new {
                                        text = _("Could not save the generated image"), timeout = 5,
                                    })
                                    return
                                end
                                -- Refresh whichever side is showing.
                                if Feedback.is_top(viewer_ref[1]) then
                                    local nv = viewer_ref[1]:update(card)
                                    viewer_ref[1] = nv
                                end
                            end),
                            nil  -- image errors are non-fatal
                        )
                    end

                    -- Poll for audio URL in background when AnkiVocab
                    -- generated it asynchronously (audio_status = "pending").
                    if card._audio_status == "pending"
                       and card._ankivocab_word and card._ankivocab_word ~= "" then
                        AudioGenerator.poll_ankivocab_async(
                            CONFIGURATION,
                            card._ankivocab_word,
                            media_callback(card, "audio", function(audio_url)
                                card._audio_url = audio_url
                                if card._storage_id then CardStorage.update_audio_url(card, audio_url) end
                            end),
                            nil  -- audio polling errors are non-fatal
                        )
                    end
                end

                NetworkMgr:runWhenOnline(function()
                    if not Annotations.same_book(ui, annotation_snapshot) then return end
                    VocabGeneration.start(CONFIGURATION, {phrase = phrase, context = context, title = title, author = author},
                        on_generated, {is_valid = function() return Annotations.same_book(ui, annotation_snapshot) end,
                            on_cancel = function() ReadingMarker.flash(ui, annotation_snapshot) end,
                            on_failure = function() ReadingMarker.flash(ui, annotation_snapshot) end})
                end)
            end,
        }
    end
    self.ui.highlight:addToHighlightDialog("ankiflashcards_4", card_button)
    self.ui.highlight:addToHighlightDialog("ankiflashcards_5", function(rhi)
        return {text = _("Anki Learn"), callback = function()
            Learning.start(CONFIGURATION, self.ui, rhi.selected_text)
        end}
    end)
    -- Dictionary popups are used for single-word selections. Use KOReader's
    -- extension API rather than replacing the dictionary or its lookup action.
    if self.ui.dictionary and self.ui.dictionary.addToDictButtons then
        self.ui.dictionary:addToDictButtons({
            id = "ankiflashcards_card",
            text = _("Anki Vocab"),
            menu_text = _("Anki Vocab"),
            show_func = function(popup)
                return not popup.is_wiki and popup.highlight ~= nil
                    and self.ui.highlight.selected_text ~= nil
            end,
            callback = function(popup)
                -- Preserve the book selection until the existing card action
                -- captures its text, positions and context.
                popup:onClose(true)
                card_button(self.ui.highlight).callback()
            end,
        })
        self.ui.dictionary:addToDictButtons({
            id = "ankiflashcards_learn", text = _("Anki Learn"),
            menu_text = _("Anki Learn"),
            show_func = function(popup)
                return not popup.is_wiki and popup.highlight ~= nil
                    and self.ui.highlight.selected_text ~= nil
            end,
            callback = function(popup)
                local selection = self.ui.highlight.selected_text
                popup:onClose(true)
                Learning.start(CONFIGURATION, self.ui, selection)
            end,
        })
    end

    -- ── Tap-to-Show Flashcard ─────────────────────────────────────────────────
    -- Saved cards never intercept a highlight tap: keep the usual action menu.
    local highlight_module = self.ui.highlight
    HighlightMenu.install(highlight_module)
    local orig_onTap = highlight_module.onTap
    local plugin_self = self

    highlight_module.onTap = function(hl_self, arg, ges)
        -- Pass through if mid-hold or no gesture
        if hl_self.hold_pos or not ges then
            return orig_onTap(hl_self, arg, ges)
        end
        local visible = hl_self.view and hl_self.view.highlight
                        and hl_self.view.highlight.visible_boxes
        if not visible or #visible == 0 then
            return orig_onTap(hl_self, arg, ges)
        end
        local pos = hl_self.view:screenToPageTransform(ges.pos)
        if not pos then
            return orig_onTap(hl_self, arg, ges)
        end

        -- Find tapped highlight and check for a saved card
        for _i, box in ipairs(visible) do
            local r = box.rect
            if r and pos.x >= r.x and pos.y >= r.y
               and pos.x <= r.x + r.w and pos.y <= r.y + r.h then
                local ann = hl_self.ui.annotation.annotations[box.index]
                if ann then
                    local snapshot = Annotations.capture(self.ui, ann)
                    local cards = CardStorage.load_cards()
                    local vocab = Annotations.find_card(snapshot, "vocab", cards, true)
                    local learn = Annotations.find_card(snapshot, "learn", cards, true)
                    if vocab or learn then
                        hl_self.selected_text = require("util").tableDeepCopy(ann)
                        hl_self:onShowHighlightMenu(box.index)
                        return true
                    end
                    -- ── Quick Lookup for purple highlights ───────────────
                    if ann.color == "purple" and ann.text and ann.text ~= "" then
                        local phrase_text = ann.text
                        local ann_ref     = ann
                        local ui_ref      = hl_self.ui
                        local hl_idx      = box.index

                        -- Delete callback: removes the highlight via KOReader's API.
                        local function delete_highlight()
                            hl_self:deleteHighlight(hl_idx)
                        end

                        -- Check annotation note for a previously saved lookup.
                        if ann_ref.note and ann_ref.note:match("^%[IPA%]") then
                            local ipa = ann_ref.note:match("%[IPA%] (.-) | ")
                            local def = ann_ref.note:match("| (.+)$")
                            if ipa and def then
                                show_quick_lookup_popup(phrase_text, { ipa = ipa, definition = def }, delete_highlight)
                                return true
                            end
                        end

                        -- Check session cache.
                        if quick_lookup_cache[phrase_text] then
                            show_quick_lookup_popup(phrase_text, quick_lookup_cache[phrase_text], delete_highlight)
                            return true
                        end

                        if not NetworkMgr:isOnline() then
                            -- Offline: fall through to normal highlight menu.
                            break
                        end
                        local loading = Notification:new {
                            text    = _("Consultando…"),
                            timeout = 15,
                        }
                        UIManager:show(loading)
                        UIManager:scheduleIn(0.05, function()
                            UIManager:close(loading)
                            local result, err = CardGenerator.generate_quick_lookup(
                                CONFIGURATION, phrase_text
                            )
                            if result then
                                quick_lookup_cache[phrase_text] = result
                                -- Persist to annotation note for offline access.
                                ann_ref.note = "[IPA] " .. (result.ipa or "")
                                            .. " | " .. (result.definition or "")
                                local Event = require("ui/event")
                                ui_ref:handleEvent(Event:new("AnnotationsModified",
                                    { ann_ref, nb_highlights_added = 0, nb_notes_added = 1 }))
                                show_quick_lookup_popup(phrase_text, result, delete_highlight)
                            else
                                UIManager:show(InfoMessage:new {
                                    text    = Feedback.classify(err).message,
                                    timeout = 3,
                                })
                            end
                        end)
                        return true
                    end
                end
                break  -- only check first hit; fall through to original
            end
        end
        return orig_onTap(hl_self, arg, ges)
    end

    -- HTTP/DNS is isolated in a cancellable low-priority process, not a UI tick.
    if self._auto_send then self._auto_send:stop() end
    self._auto_send = require("auto_send").new {ui = self.ui, base = CONFIGURATION, get_config = get_anki_config}
    self._auto_send:start()

    -- ── Auto-Sync on Startup ──────────────────────────────────────────────
    -- One-shot silent cloud sync 45s after startup.
    UIManager:scheduleIn(45, function()
        local cfg = get_anki_config()
        if cfg.cloud_auto_sync and cfg.sync_server and NetworkMgr:isOnline() then
            CardSync.run_sync(cfg.sync_server, true, self.ui)
        end
    end)

end

function AnkiFlashcards:onCloseDocument()
    VocabGeneration.cancel_all()
    ReadingMarker.clear(self.ui)
    self._auto_send_resume = false
    if self._auto_send then self._auto_send:stop() end
end
function AnkiFlashcards:onExit()
    self:onCloseDocument()
end
function AnkiFlashcards:onSuspend()
    VocabGeneration.cancel_all()
    ReadingMarker.clear(self.ui)
    self._auto_send_resume = self._auto_send and self._auto_send.running
    if self._auto_send then self._auto_send:stop() end
end
function AnkiFlashcards:onResume()
    if self._auto_send_resume and self._auto_send then self._auto_send:start() end
    self._auto_send_resume = false
end

function AnkiFlashcards:addToMainMenu(menu_items)
    menu_items.ankiflashcards = {
        text = _("Anki Flashcards"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Configuración"),
                sub_item_table_func = function()
                    return SettingsViewer.menu_items(CONFIGURATION, function(cfg)
                        SettingsState.apply(CONFIGURATION, cfg)
                        if self._auto_send then self._auto_send:settings_changed() end
                    end, self.ui)
                end,
            },
            {
                text = _("Tarjetas"),
                sub_item_table_func = function()
                    local items = CardManager.menu_items(CONFIGURATION, { ui = self.ui,
                        on_inbox = self.ui.document and function()
                            HighlightInbox.show(self.ui, CONFIGURATION)
                        end or nil,
                    })
                    table.insert(items, 1, {
                        text = _("Mis tarjetas"),
                        keep_menu_open = true,
                        callback = function()
                            CardManager.show(CONFIGURATION, nil, self.ui)
                        end,
                    })
                    return items
                end,
            },
            {
                text = _("Estadísticas por libro"),
                keep_menu_open = true,
                callback = CardManager.show_stats,
            },
        },
    }
end

return AnkiFlashcards

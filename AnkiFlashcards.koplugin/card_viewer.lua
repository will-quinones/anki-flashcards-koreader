-- Full-screen Anki flashcard viewer with front/back experience.
--
-- Front: shows Phrase + IPA with a "Show Answer" button.
-- Back:  shows the image (when ready) + all fields + editing buttons.
-- Both sides expose Save and Send to Anki without revealing the answer.
--
-- Modelled on chatgptviewer.lua.

local BD               = require("ui/bidi")
local Blitbuffer       = require("ffi/blitbuffer")
local ButtonDialog     = require("ui/widget/buttondialog")
local ButtonTable      = require("ui/widget/buttontable")
local CenterContainer  = require("ui/widget/container/centercontainer")
local Device           = require("device")
local Font             = require("ui/font")
local FrameContainer   = require("ui/widget/container/framecontainer")
local Geom             = require("ui/geometry")
local GestureRange     = require("ui/gesturerange")
local ImageWidget      = require("ui/widget/imagewidget")
local InfoMessage      = require("ui/widget/infomessage")
local InputContainer   = require("ui/widget/container/inputcontainer")
local InputDialog      = require("ui/widget/inputdialog")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Notification     = require("ui/widget/notification")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size             = require("ui/size")
local TitleBar         = require("ui/widget/titlebar")
local UIManager        = require("ui/uimanager")
local HorizontalGroup  = require("ui/widget/horizontalgroup")
local VerticalGroup    = require("ui/widget/verticalgroup")
local VerticalSpan     = require("ui/widget/verticalspan")
local RenderText       = require("ui/rendertext")
local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local _                = require("gettext")

local Screen = Device.screen

local PTF_HEADER     = "\xEF\xBF\xB1"  -- U+FFF1  required prefix to activate PTF parsing
local PTF_BOLD_START = "\xEF\xBF\xB2"  -- U+FFF2
local PTF_BOLD_END   = "\xEF\xBF\xB3"  -- U+FFF3

local function ptf_bold(s)
    return PTF_BOLD_START .. s .. PTF_BOLD_END
end

-- ── Content formatters ────────────────────────────────────────────────────────

local function blank_cloze(text)
    return (text or ""):gsub("{{c%d+::(.-)}}",  "[...]")
end

local function reveal_cloze(text)
    return (text or ""):gsub("{{c%d+::(.-)}}",
        PTF_BOLD_START .. "%1" .. PTF_BOLD_END)
end

-- Colors for special fields (tuned for e-ink visibility).
local COLOR_ORANGE = Blitbuffer.ColorRGB32(0x7A, 0x35, 0x00, 0xFF)  -- synonyms: very dark orange
local COLOR_RED    = Blitbuffer.ColorRGB32(0xBB, 0x00, 0x00, 0xFF)  -- IPA: deep red
local COLOR_BLUE   = Blitbuffer.ColorRGB32(0x00, 0x3A, 0x75, 0xFF)  -- phrase (back): dark navy blue

-- Fields available for editing (shown on back only).
-- IPA and Source are intentionally excluded: IPA is auto-regenerated when Phrase changes,
-- and Source is auto-updated to the Cambridge URL for the new phrase.
local EDITABLE_FIELDS = {
    { key = "phrase",     label = "Phrase" },
    { key = "definition", label = "Definition" },
    { key = "synonyms",   label = "Synonyms" },
    { key = "text",       label = "Text (cloze)" },
}

-- ── Widget ────────────────────────────────────────────────────────────────────

local CardViewer = InputContainer:extend {
    card           = nil,   -- card table: { phrase, ipa, definition, synonyms, text, source, image_path, … }
    show_back      = false, -- false = front (question), true = back (answer)
    on_show_answer = nil,   -- function() — called when user flips to back
    on_show_question = nil, -- function() — called when user returns to front
    on_save        = nil,   -- function() -> true | nil, err
    on_send        = nil,   -- function() -> true | nil, err
    on_regenerate  = nil,   -- function()
    on_dismiss     = nil,   -- function() — real close only, never an internal redraw
    generating     = false,
    on_prepare_update = nil, -- function(card) -> true | false; bind stable identity before edits
    on_update      = nil,   -- function(card) — called after a field edit (to persist)
    on_regen_ipa   = nil,   -- function(new_phrase, card, new_viewer) — async IPA regen after phrase change
    on_navigate_to_source = nil, -- function() — jump to highlight position in book
    on_regen_text  = nil,   -- function() — regenerate example sentence only
    on_regen_image = nil,   -- function() — regenerate image only
    on_highlight_dialog = nil, -- function() — open KOReader's native highlight dialog (color, style, delete…)
    read_only      = false,

    text_padding   = Size.padding.large,
    text_margin    = Size.margin.small,
    button_padding = Size.padding.default,
}

function CardViewer:refresh_anki_status()
    if not self.anki_base or self._anki_closed then return end
    local Storage = require("card_storage")
    local config = require("settings_state").merge(self.anki_base, Storage.load_anki_settings())
    if require("ui/network/manager"):isOnline() then
        self.anki_status, self.anki_status_error = require("anki_note_actions").status(config, self.card)
    else
        self.anki_status, self.anki_status_error = nil, _("Sin conexión. No se pudo verificar el estado en Anki.")
    end
    local button = self.button_table and self.button_table:getButtonById("send")
    if button and not self._anki_closed then
        button:setText(self.anki_status == "present" and _("Eliminar de Anki…")
            or self.anki_status == "absent" and _("Enviar a Anki") or _("Verificar en Anki"), button.width)
        if self.anki_status == "present" or self.on_send or not self.anki_status then button:enable() else button:disable() end
        button:refresh()
    end
    return self.anki_status
end

function CardViewer:anki_action()
    local intended = self.anki_status
    local status = self:refresh_anki_status()
    if not status then
        UIManager:show(InfoMessage:new {text = self.anki_status_error or _("No se pudo verificar Anki.")})
        return
    end
    -- A refresh must not turn a user's Send tap into a Delete (or vice versa).
    if status ~= intended then return end
    if status == "present" then
        require("anki_note_actions").confirm_delete(self.anki_base, self.card, function(ok, message)
            if not self._anki_closed then self:refresh_anki_status() end
            UIManager:show(InfoMessage:new {text = message})
        end)
    elseif self.on_send then
        local ok, err = self.on_send()
        self:refresh_anki_status()
        self:refresh_local_status()
        UIManager:show(InfoMessage:new {text = ok and _("Enviada a Anki.") or (err or _("No se pudo enviar."))})
    end
end

function CardViewer:refresh_local_status()
    local saved = not not (self.card and require("card_storage").is_saved(self.card))
    self._local_saved = saved
    local button = self.button_table and self.button_table:getButtonById("save")
    if button then
        button:setText(saved and _("Borrar del Kobo…") or _("Guardar"), button.width)
        if saved or self.on_save then button:enable() else button:disable() end
        button:refresh()
    end
    return saved
end

function CardViewer:delivery_buttons()
    local CardStorage = require("card_storage")
    local already_saved = self.card and CardStorage.is_saved(self.card)
    self._local_saved = not not already_saved
    local function sent()
        return self.card and self.card.sent_to_anki and self.card.anki_note_id ~= nil
    end
    local function send_label()
        if self.anki_base then
            return self.anki_status == "present" and _("Eliminar de Anki…")
                or self.anki_status == "absent" and _("Enviar a Anki") or _("Verificar en Anki")
        end
        if self.card and self.card.anki_sync_state == "missing" then return _("No está en Anki") end
        return sent() and _("✓ Enviada a Anki") or _("Enviar a Anki")
    end
    local buttons = {
        {
            id = "save",
            text = already_saved and _("Borrar del Kobo…") or _("Guardar"),
            enabled = already_saved or self.on_save ~= nil,
            callback = function()
                local intended = self._local_saved
                local saved = self:refresh_local_status()
                if saved ~= intended then return end -- never reverse the intended action
                if saved then
                    -- Capture the durable record now; confirmation cannot delete
                    -- a different generation which happens to have the same phrase.
                    local target = CardStorage.saved_card(self.card)
                    if not target or not CardStorage.ensure_identity(target) then return end
                    UIManager:show(require("ui/widget/confirmbox"):new {
                        text = _("¿Borrar esta tarjeta del Kobo? Se conserva la nota de Anki y el subrayado del libro."),
                        ok_text = _("Borrar del Kobo"),
                        ok_callback = function()
                            if self._anki_closed then return end
                            local ok = CardStorage.delete_card_by_id(target._storage_id)
                            if ok then
                                self.card.image_path = ""
                                self:refresh_local_status()
                                self:update()
                            else UIManager:show(InfoMessage:new {text = _("No se pudo borrar la tarjeta del Kobo."), timeout = 5}) end
                        end,
                    })
                    return
                end
                if not self.on_save then return end
                local ok, err = self.on_save()
                if ok then
                    self:refresh_local_status()
                    UIManager:show(Notification:new {text = _("Guardada en el Kobo.")})
                else
                    UIManager:show(InfoMessage:new {text = err or _("No se pudo guardar."), timeout = 5})
                end
            end,
        },
        {
            id = "send",
            text = send_label(),
            enabled = self.anki_base ~= nil or (not sent() and self.on_send ~= nil),
            callback = function()
                if self.anki_base then
                    require("ui/network/manager"):runWhenOnline(function()
                        if not self._anki_closed then self:anki_action() end
                    end)
                    return
                end
                if sent() or not self.on_send then return end
                local ok, err = self.on_send()
                if ok then
                    -- Sending also persists the card locally. Reflect that on
                    -- either side without closing or flipping the viewer.
                    self:refresh_local_status()
                    local button = self.button_table and self.button_table:getButtonById("send")
                    if button then
                        button:setText(_("✓ Enviada a Anki"), button.width)
                        button:disable()
                        button:refresh()
                    end
                    UIManager:show(Notification:new {text = _("Enviada a Anki.")})
                else
                    UIManager:show(InfoMessage:new {text = _("Anki: ") .. (err or _("No se pudo enviar.")), timeout = 5})
                end
            end,
        },
    }
    if self.on_add_highlight then
        local highlighted = self.is_highlighted and self.is_highlighted()
        buttons[#buttons+1] = {
            id = "highlight", text = highlighted and _("✓ Subrayado") or _("Subrayar"),
            enabled = not highlighted and (not self.can_add_highlight or self.can_add_highlight()),
            callback = function()
                local ok, err = self.on_add_highlight()
                if ok then
                    local button = self.button_table and self.button_table:getButtonById("highlight")
                    if button then button:setText(_("✓ Subrayado"), button.width); button:disable(); button:refresh() end
                    UIManager:show(Notification:new {text = err or _("Subrayado creado.")})
                else UIManager:show(InfoMessage:new {text = err or _("No se pudo subrayar.")}) end
            end,
        }
    end
    return buttons
end

function CardViewer:init()
    self.align  = "center"
    self.region = Geom:new {
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    local margin = Screen:scaleBySize(30)
    self.width  = math.min(Screen:getWidth(), Screen:getHeight()) - margin
    self.height = math.floor(Screen:getHeight() * 0.85)

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    if Device:isTouchDevice() then
        local range = Geom:new { x=0, y=0, w=Screen:getWidth(), h=Screen:getHeight() }
        self.ges_events = {
            TapClose = { GestureRange:new { ges = "tap",   range = range } },
            Swipe    = { GestureRange:new { ges = "swipe", range = range } },
        }
    end

    local titlebar = TitleBar:new {
        width            = self.width,
        align            = "left",
        with_bottom_line = true,
        title            = self.card and self.card.kind == "learn" and _("Anki Learn") or _("Anki Vocab"),
        close_callback   = function() self:onClose() end,
        show_parent      = self,
    }

    -- ── Button row ────────────────────────────────────────────────────────────
    local buttons_row = {}
    local extras_row = {}
    if not self.generating then table.insert(buttons_row, {
        id = "flip",
        text = self.show_back and _("Mostrar pregunta") or _("Mostrar respuesta"),
        callback = function()
            local callback = self.on_show_answer
            if self.show_back then callback = self.on_show_question end
            if callback then callback() else self:update(nil, not self.show_back) end
        end,
    }) end
    table.insert(buttons_row, {text = _("Cerrar"), callback = function() self:onClose() end})
    if not self.generating and not self.read_only and self.on_regenerate then
        table.insert(buttons_row, {id = "regenerate", text = _("Regenerar"), callback = function() self.on_regenerate() end})
    end
    if self.show_back and not self.generating then
        if not self.read_only then
            table.insert(extras_row, {
                text     = _("Editar"),
                callback = function() self:showEditDialog() end,
            })
        end

        if self.on_navigate_to_source then
            table.insert(extras_row, {
                text     = _("Origen"),
                callback = function() self.on_navigate_to_source() end,
            })
        end

    end
    if self.on_highlight_dialog then
        table.insert(extras_row, {text = _("Subrayado"), callback = function()
            self:onClose(); self.on_highlight_dialog()
        end})
    end
    local rows = self.generating and {buttons_row} or {self:delivery_buttons(), buttons_row}
    if #extras_row > 0 then rows[#rows+1] = extras_row end
    self.button_table = ButtonTable:new {
        width       = self.width - 2 * self.button_padding,
        buttons     = rows,
        zero_sep    = true,
        show_parent = self,
    }

    -- ── Content area ──────────────────────────────────────────────────────────
    local total_content_h = self.height
                          - titlebar:getHeight()
                          - self.button_table:getSize().h
    local inner_w = self.width - 2 * self.text_padding - 2 * self.text_margin

    local content_widget

    -- Build a scaled ImageWidget (scale to width, max 40% of content height).
    -- Tapping the image opens a full-screen zoomable viewer (original, no overlay).
    -- When phrase_overlay is provided, renders uppercase white-on-black outlined
    -- text at the bottom of the image (back side only).
    local function make_image_widget(image_path, phrase_overlay)
        if not image_path or image_path == "" then return nil, 0 end
        local max_h = math.floor(total_content_h * 0.40)
        -- Scale to full width; let ImageWidget compute the natural height.
        local img = ImageWidget:new {
            file         = image_path,
            width        = inner_w,
            scale_factor = 0,
        }
        local img_h = img:getSize().h
        -- If the image is taller than 40% of content area, re-create with a height cap.
        if img_h > max_h then
            img:free()
            img = ImageWidget:new {
                file         = image_path,
                width        = inner_w,
                height       = max_h,
                scale_factor = 0,
            }
            img:getSize()  -- trigger lazy rendering so _bb is available
            img_h = max_h
        end
        -- Overlay phrase text on the image buffer (back side).
        if phrase_overlay and phrase_overlay ~= "" and img._bb then
            local bb = img._bb
            local bw, bh = bb:getWidth(), bb:getHeight()
            local text = phrase_overlay:upper()
            local font_size = math.max(16, math.floor(bh * 0.10))
            local face = Font:getFace("cfont", font_size)
            -- Shrink font if text is wider than the image (with margin).
            local tsize = RenderText:sizeUtf8Text(0, bw, face, text, true, true)
            while tsize and tsize.x > bw - 20 and font_size > 16 do
                font_size = font_size - 2
                face = Font:getFace("cfont", font_size)
                tsize = RenderText:sizeUtf8Text(0, bw, face, text, true, true)
            end
            if tsize and tsize.x > 0 then
                local tx = math.max(0, math.floor((bw - tsize.x) / 2))
                local ty = bh - math.floor(bh * 0.06)
                -- Black outline at 8 offsets for readability on any background.
                local d = math.max(1, math.floor(font_size / 16))
                for _, off in ipairs({{-d,0},{d,0},{0,-d},{0,d},{-d,-d},{d,-d},{-d,d},{d,d}}) do
                    RenderText:renderUtf8Text(bb, tx+off[1], ty+off[2], face, text, true, true, Blitbuffer.COLOR_BLACK)
                end
                -- White text on top.
                RenderText:renderUtf8Text(bb, tx, ty, face, text, true, true, Blitbuffer.COLOR_WHITE)
            end
        end
        self._tap_image_widget = img
        self._tap_image_path   = image_path
        return img, img_h
    end

    -- Build a ScrollTextWidget for one content section.
    -- justified=true enables full justification (implies left alignment).
    -- w overrides the default inner_w (used for multi-column layouts).
    local function make_text(text, face, height, color, align, justified, w)
        return ScrollTextWidget:new {
            text      = PTF_HEADER .. (text or ""),  -- header activates PTF bold parsing
            face      = face,
            fgcolor   = color,
            width     = w or inner_w,
            height    = math.max(1, height),
            dialog    = self,
            alignment = justified and "left" or (align or "center"),
            justified = justified or false,
        }
    end

    local gap = Size.padding.default
    -- Available height for all content widgets (inside the frame's padding/margin).
    local avail_h = total_content_h - 2 * self.text_padding - 2 * self.text_margin

    local big_gap = gap * 3  -- visible separator before cloze sentence

    if self.generating then
        local text = (self.generation_label or _("Generando tarjeta…")) .. "\n\n" .. (self.stream_text or "")
        local text_widget = make_text(text, Font:getFace("smallinfofont"), avail_h, nil, "left")
        self.scroll_text_w = text_widget
        content_widget = VerticalGroup:new {text_widget}
    elseif self.card and self.card.kind == "learn" then
        local c = self.card
        local face = Font:getFace("smallinfofont")
        local text = c.question or ""
        if self.show_back then
            text = (c.question or "") .. "\n\n" .. ptf_bold(c.answer or "")
            if c.explanation and c.explanation ~= "" then text = text .. "\n\n" .. c.explanation end
            text = text .. "\n\n" .. ptf_bold("Fragmento del libro") .. "\n" .. (c.evidence or "")
                .. "\n\n" .. (c.book_title or "") .. " — " .. (c.book_author or "")
                .. "\n" .. (c.chapter or "") .. " " .. (c.location or "")
            if c.context_quality == "selection" then text = text .. "\n\nContexto disponible: solo la selección." end
        end
        local text_widget = make_text(text, face, avail_h, nil, "left")
        self.scroll_text_w = text_widget
        content_widget = VerticalGroup:new {text_widget}
    elseif not self.show_back then
        -- ── FRONT ─────────────────────────────────────────────────────────────
        -- Layout: Definition · Synonyms · Image · (big gap) · Cloze
        local c          = self.card or {}
        local face       = Font:getFace("smallinfofont")
        local img_widget, image_h = make_image_widget(c.image_path)
        local text_h     = avail_h - image_h - big_gap - gap * 2
        local def_h      = math.max(1, math.floor(text_h * 0.30))
        local syn_h      = math.max(1, math.floor(text_h * 0.08))
        local cloze_h    = math.max(1, text_h - def_h - syn_h)

        local def_w   = make_text(c.definition or "",              face, def_h,   nil,          "left")
        local syn_w   = make_text(ptf_bold(c.synonyms or ""),     face, syn_h,   COLOR_ORANGE)
        local cloze_w = make_text(blank_cloze(c.text or ""),      face, cloze_h)
        self.scroll_text_w = cloze_w

        local items = { def_w, VerticalSpan:new{width=gap*2}, syn_w }
        if img_widget then
            table.insert(items, img_widget)
        end
        table.insert(items, VerticalSpan:new{width=big_gap})
        table.insert(items, cloze_w)
        content_widget = VerticalGroup:new(items)

    else
        -- ── BACK ──────────────────────────────────────────────────────────────
        -- With image:  Definition · Synonyms · Image (phrase overlaid) · IPA · (big gap) · Cloze
        -- No image:    Definition · Synonyms · Phrase (blue) · IPA · (big gap) · Cloze
        local c          = self.card or {}
        local face       = Font:getFace("smallinfofont")
        local img_widget, image_h = make_image_widget(c.image_path, c.phrase)
        local has_image  = img_widget ~= nil
        local text_h     = avail_h - image_h - big_gap - gap * 2
        local def_h      = math.max(1, math.floor(text_h * 0.30))
        local syn_h      = math.max(1, math.floor(text_h * 0.08))
        local phrase_h, ipa_h, cloze_h
        if has_image then
            ipa_h   = math.max(1, math.floor(text_h * 0.08))
            cloze_h = math.max(1, text_h - def_h - syn_h - ipa_h)
        else
            phrase_h = math.max(1, math.floor(text_h * 0.12))
            ipa_h    = math.max(1, math.floor(text_h * 0.08))
            cloze_h  = math.max(1, text_h - def_h - syn_h - phrase_h - ipa_h)
        end

        local def_w   = make_text(c.definition or "",              face, def_h,   nil, "left")
        local syn_w   = make_text(ptf_bold(c.synonyms or ""),     face, syn_h,   COLOR_ORANGE)
        local ipa_w   = make_text(ptf_bold(c.ipa or ""),           face, ipa_h,   COLOR_RED)
        local cloze_w = make_text(reveal_cloze(c.text or ""),     face, cloze_h)
        self.scroll_text_w = cloze_w

        local items = { def_w, VerticalSpan:new{width=gap*2}, syn_w }
        if has_image then
            table.insert(items, img_widget)
        else
            local phrase_w = make_text(ptf_bold(c.phrase or ""), face, phrase_h, COLOR_BLUE)
            table.insert(items, VerticalSpan:new{width=gap})
            table.insert(items, phrase_w)
        end
        table.insert(items, ipa_w)
        table.insert(items, VerticalSpan:new{width=big_gap})
        table.insert(items, cloze_w)
        content_widget = VerticalGroup:new(items)
    end

    self.textw = FrameContainer:new {
        padding    = self.text_padding,
        margin     = self.text_margin,
        bordersize = 0,
        content_widget,
    }

    self.frame = FrameContainer:new {
        radius     = Size.radius.window,
        padding    = 0,
        margin     = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new {
            titlebar,
            CenterContainer:new {
                dimen = Geom:new { w = self.width, h = self.textw:getSize().h },
                self.textw,
            },
            CenterContainer:new {
                dimen = Geom:new { w = self.width, h = self.button_table:getSize().h },
                self.button_table,
            },
        },
    }

    self.movable = MovableContainer:new {
        ignore_events = {
            "swipe", "hold", "hold_release", "hold_pan",
            "touch", "pan", "pan_release",
        },
        self.frame,
    }

    self[1] = WidgetContainer:new {
        align = self.align,
        dimen = self.region,
        self.movable,
    }
end

-- ── Edit flow (back only) ─────────────────────────────────────────────────────

function CardViewer:showEditDialog()
    if self.card and self.card.kind == "learn" and self.card.sent_to_anki then
        UIManager:show(InfoMessage:new {text = "Esta tarjeta ya está en Anki. Edítala allí para conservar una única versión."})
        return
    end
    local sel_dlg
    local field_buttons = {}
    local editable = self.card and self.card.kind == "learn" and {
        {key = "question", label = "Pregunta"}, {key = "answer", label = "Respuesta"},
        {key = "explanation", label = "Explicación"},
    } or EDITABLE_FIELDS
    for _i, f in ipairs(editable) do
        local fref = f
        table.insert(field_buttons, {{
            text     = _(fref.label),
            callback = function()
                UIManager:close(sel_dlg)
                self:editField(fref)
            end,
        }})
    end
    if self.on_regen_text then
        table.insert(field_buttons, {{
            text     = _("Regen sentence"),
            callback = function()
                UIManager:close(sel_dlg)
                self.on_regen_text()
            end,
        }})
    end
    if self.on_regen_image then
        table.insert(field_buttons, {{
            text     = _("Regen image"),
            callback = function()
                UIManager:close(sel_dlg)
                self.on_regen_image()
            end,
        }})
    end
    table.insert(field_buttons, {{
        text     = _("Cancel"),
        callback = function() UIManager:close(sel_dlg) end,
    }})
    sel_dlg = ButtonDialog:new {
        title   = _("Edit field"),
        buttons = field_buttons,
    }
    UIManager:show(sel_dlg)
end

function CardViewer:editField(field_def)
    local current = self.card and self.card[field_def.key] or ""
    local input_dlg
    input_dlg = InputDialog:new {
        title   = _("Edit: ") .. field_def.label,
        input   = current,
        buttons = {{
            {
                text     = _("Cancel"),
                callback = function() UIManager:close(input_dlg) end,
            },
            {
                text             = _("OK"),
                is_enter_default = true,
                callback         = function()
                    local new_val = input_dlg:getInputText() or ""
                    if self.card.kind == "learn" and field_def.key ~= "explanation" and not new_val:match("%S") then
                        UIManager:show(InfoMessage:new {text = "La pregunta y la respuesta no pueden estar vacías."})
                        return
                    end
                    UIManager:close(input_dlg)
                    -- Defer widget-tree changes until after the current
                    -- event cycle completes (avoids crash mid-callback).
                    UIManager:scheduleIn(0, function()
                        local before = {}
                        for k, v in pairs(self.card) do before[k] = v end
                        local old_phrase = self.card.phrase
                        if self.on_prepare_update and not self.on_prepare_update(self.card) then
                            UIManager:show(InfoMessage:new {
                                text = _("Could not save card changes"), timeout = 5,
                            })
                            return
                        end
                        self.card[field_def.key] = new_val
                        if self.card.kind == "learn" then self.card.phrase = self.card.question end
                        -- When phrase changes: auto-update Cambridge source URL,
                        -- clear stale IPA, then trigger async IPA regeneration.
                        local phrase_changed = field_def.key == "phrase"
                                               and new_val ~= old_phrase
                        if phrase_changed then
                            local slug = new_val:lower():gsub("%s+", "-")
                            self.card.source = "https://dictionary.cambridge.org/dictionary/english/" .. slug
                            self.card.ipa    = ""
                        end
                        if self.on_update then
                            local ok, err = self.on_update(self.card)
                            if ok == false then
                                for k in pairs(self.card) do self.card[k] = nil end
                                for k, v in pairs(before) do self.card[k] = v end
                                UIManager:show(InfoMessage:new {text = err or "No se pudieron guardar los cambios."})
                                return
                            end
                        end
                        local new_v = self:update()
                        if phrase_changed and self.on_regen_ipa then
                            self.on_regen_ipa(new_val, self.card, new_v)
                        end
                    end)
                end,
            },
        }},
    }
    UIManager:show(input_dlg)
    input_dlg:onShowKeyboard()
end

-- ── Update (close+recreate) ───────────────────────────────────────────────────

-- Closes this viewer and opens a fresh one with the (possibly updated) card.
-- Preserves show_back state unless new_show_back is explicitly passed.
function CardViewer:update(new_card, new_show_back)
    local card      = new_card or self.card
    local show_back = new_show_back
    if show_back == nil then show_back = self.show_back end
    self._replacing = true
    UIManager:close(self)
    local updated = CardViewer:new {
        card                  = card,
        show_back             = show_back,
        on_show_answer        = self.on_show_answer,
        on_show_question      = self.on_show_question,
        on_viewer_updated     = self.on_viewer_updated,
        on_save               = self.on_save,
        on_dismiss            = self.on_dismiss,
        generating            = self.generating,
        generation_label      = self.generation_label,
        stream_text           = self.stream_text,
        on_send               = self.on_send,
        anki_base             = self.anki_base,
        on_regenerate         = self.on_regenerate,
        on_prepare_update     = self.on_prepare_update,
        on_update             = self.on_update,
        on_regen_ipa          = self.on_regen_ipa,
        on_navigate_to_source = self.on_navigate_to_source,
        on_regen_text         = self.on_regen_text,
        on_regen_image        = self.on_regen_image,
        on_highlight_dialog   = self.on_highlight_dialog,
        on_add_highlight      = self.on_add_highlight,
        is_highlighted        = self.is_highlighted,
        can_add_highlight     = self.can_add_highlight,
        read_only             = self.read_only,
    }
    UIManager:show(updated)
    if self.on_viewer_updated then self.on_viewer_updated(updated) end
    return updated
end

-- ── Event handlers ────────────────────────────────────────────────────────────

function CardViewer:onCloseWidget()
    self._anki_closed = true
    if not self._replacing and not self._dismissed then
        self._dismissed = true
        if self.on_dismiss then self.on_dismiss() end
    end
    UIManager:setDirty(nil, function()
        return "partial", self.frame.dimen
    end)
end

function CardViewer:onShow()
    self._anki_closed = false
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
    if not self.generating then self:refresh_local_status() end
    if self.anki_base and not self.generating then
        UIManager:scheduleIn(0, function()
            if not self._anki_closed then self:refresh_anki_status() end
        end)
    end
    return true
end

function CardViewer:onTapClose(arg, ges_ev)
    -- Don't close while any dialog (InputDialog, ButtonDialog, VirtualKeyboard…) is on top.
    if UIManager:getTopmostVisibleWidget() ~= self then
        return true
    end
    -- Tap on image → open full-screen zoomable viewer.
    if self._tap_image_widget and self._tap_image_path
       and self._tap_image_widget.dimen
       and ges_ev.pos:intersectWith(self._tap_image_widget.dimen) then
        local ImageViewer = require("ui/widget/imageviewer")
        UIManager:show(ImageViewer:new {
            file       = self._tap_image_path,
            fullscreen = true,
        })
        return true
    end
    if ges_ev.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function CardViewer:onSwipe(arg, ges)
    if ges.pos:intersectWith(self.textw.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self.scroll_text_w:scrollText(1)
            return true
        elseif direction == "east" then
            self.scroll_text_w:scrollText(-1)
            return true
        else
            UIManager:setDirty(nil, "full")
            return false
        end
    end
    return self.movable:onMovableSwipe(arg, ges)
end

function CardViewer:onClose()
    UIManager:close(self)
    return true
end

return CardViewer

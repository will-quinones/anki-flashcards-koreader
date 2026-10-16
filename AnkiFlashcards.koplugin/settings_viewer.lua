-- One native TouchMenu tree, grouped by task. Note types are internal contracts.
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local Storage = require("card_storage")
local AnkiSync = require("anki_sync")
local CardSync = require("card_sync")
local State = require("settings_state")
local _ = require("gettext")
local Settings = {}

local PROVIDERS = {
    gemini = {name = "Google Gemini", key = "gemini_api_key", website = "aistudio.google.com/apikey",
        text_model = {key = "gemini_text_model", default = "gemini-2.5-flash"},
        image_model = {key = "gemini_image_model", default = "gemini-3.1-flash-image"}},
    openrouter = {name = "OpenRouter", key = "openrouter_api_key", website = "openrouter.ai/keys",
        text_model = {key = "openrouter_model", default = "anthropic/claude-3-haiku"},
        image_model = {key = "openrouter_image_model", default = "google/gemini-3.1-flash-image-preview"}},
    dashscope = {name = "Qwen / DashScope", key = "dashscope_api_key", website = "Alibaba Cloud Model Studio",
        text_model = {key = "model", default = "qwen-plus"},
        image_model = {key = "image_model", default = "qwen-image-plus"}},
    openai = {name = "OpenAI", key = "openai_api_key", website = "platform.openai.com/api-keys",
        text_model = {key = "openai_model", default = "gpt-4o-mini"},
        image_model = {key = "openai_image_model", default = "gpt-image-1"}},
    ankivocab = {name = "AnkiVocab", key = "ankivocab_api_key", website = "ankivocab.com"},
    pollinations = {name = "Pollinations (experimental)"},
    none = {name = "Sin imágenes"},
}
local LANGUAGES = {{id = "Spanish", name = "Español"}, {id = "English", name = "Inglés"},
    {id = "French", name = "Francés"}, {id = "German", name = "Alemán"}, {id = "Japanese", name = "Japonés"}}
local ORGANIZATIONS = {
    {name = "Una sola baraja", mode = "configured", split = false},
    {name = "Por tipo de tarjeta", mode = "configured", split = true},
    {name = "Por libro", mode = "book", split = false},
    {name = "Por libro y tipo", mode = "book", split = true},
}

function Settings.menu_items(base, on_saved, ui)
    local cfg = State.persistable(State.merge(base, Storage.load_anki_settings()))
    cfg.text_provider = cfg.text_provider or "dashscope"
    if not cfg.image_provider or cfg.image_provider == "" then cfg.image_provider = "none" end
    cfg.deck_mode = cfg.deck_mode or "book"
    cfg.tags = State.extra_tags(cfg.tags)
    local active_menu
    local function message(text) UIManager:show(InfoMessage:new {text = text}) end
    local function save(patch, replace)
        local next_cfg = {}
        if not replace then for key, value in pairs(cfg) do next_cfg[key] = value end end
        for key, value in pairs(patch) do next_cfg[key] = value end
        next_cfg = State.persistable(next_cfg)
        local ok, err = Storage.save_anki_settings(next_cfg)
        if not ok then message(_("No se guardaron los cambios. ") .. tostring(err or _("Comprueba el espacio libre."))); return false end
        cfg = next_cfg
        State.apply(base, cfg)
        if on_saved then on_saved(cfg) end
        if active_menu then active_menu:updateItems() end
        return true
    end
    local function action(label, callback, enabled)
        local item = {keep_menu_open = true, callback = function(menu)
            active_menu = menu or active_menu
            callback()
        end}
        if type(label) == "function" then item.text_func = label else item.text = label end
        item.enabled_func = enabled
        return item
    end
    local function submenu(label, build, enabled)
        local item = {sub_item_table_func = build, enabled_func = enabled}
        if type(label) == "function" then item.text_func = label else item.text = label end
        return item
    end
    local function edit(title, key, hint, validate, initial, secret)
        local dialog
        local original = cfg[key]
        local value = initial ~= nil and initial or original or ""
        if secret and not State.has_key(value) then value = "" end
        dialog = InputDialog:new {title = title, input = tostring(value), input_hint = hint,
            text_type = secret and "password" or nil,
            buttons = {{
                {text = _("Cancelar"), callback = function() UIManager:close(dialog) end},
                {text = _("Guardar"), is_enter_default = true, callback = function()
                    local changed = (dialog:getInputText() or ""):match("^%s*(.-)%s*$")
                    if validate then
                        local validated, err = validate(changed)
                        if validated == nil or validated == false then message(err); return end
                        changed = validated
                    end
                    local function commit()
                        if save({[key] = changed}) then UIManager:close(dialog) end
                    end
                    if secret and changed == "" and State.has_key(original) then
                        UIManager:show(ConfirmBox:new {text = _("¿Borrar esta clave? También dejará de estar disponible para los otros usos del mismo servicio."),
                            ok_text = _("Borrar clave"), ok_callback = commit})
                    else commit() end
                end},
            }}}
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end
    local function nonempty(value)
        if value == "" then return nil, _("Este valor no puede estar vacío.") end
        return value
    end
    local function chosen(category)
        local id = category == "text" and cfg.text_provider or cfg.image_provider
        return PROVIDERS[id] or {name = _("Servicio no reconocido: ") .. tostring(id)}, id
    end
    local function provider_choices(category)
        local ids = category == "text" and {"gemini", "openrouter", "dashscope", "openai", "ankivocab"}
            or {"none", "gemini", "openrouter", "dashscope", "openai", "ankivocab", "pollinations"}
        local key = category == "text" and "text_provider" or "image_provider"
        local items = {}
        for _i, id in ipairs(ids) do
            local value = id
            local label = PROVIDERS[id].name
            if category == "text" and id == "ankivocab" then label = label .. _(" (solo Vocab)") end
            local item = action(label, function() save({[key] = value}) end)
            item.checked_func = function() return cfg[key] == value end
            items[#items+1] = item
        end
        return items
    end
    local function account(category)
        return {
            action(function()
                local p = chosen(category)
                local status = p.key and (State.has_key(cfg[p.key]) and _("guardada") or _("falta añadirla")) or _("no necesaria")
                return _("Clave API: ") .. status
            end, function()
                local p = chosen(category)
                if p.key then edit(p.name .. _(" · clave API"), p.key, p.website, nil, nil, true) end
            end, function() return chosen(category).key ~= nil end),
            action(function()
                local p = chosen(category)
                local field = p[category .. "_model"]
                return field and (_("Modelo de IA: ") .. (cfg[field.key] or field.default))
                    or _("Modelo gestionado por el servicio")
            end, function()
                local field = chosen(category)[category .. "_model"]
                if field then edit(_("Identificador del modelo de IA"), field.key, field.default,
                    function(value) return value ~= "" and value or field.default end) end
            end, function() return chosen(category)[category .. "_model"] ~= nil end),
            action(_("Clave compartida y costes"), function()
                local p, id = chosen(category)
                local text = _("La clave se comparte entre texto e imágenes si eliges el mismo servicio. No tienes que crear otra clave ni volver a introducirla.\n\nLos costes dependen del modelo y de tu cuenta; el complemento no activa facturación ni compra créditos.")
                if id == "ankivocab" then text = text .. _("\n\nAnkiVocab genera vocabulario; no admite Anki Learn.") end
                if id == "pollinations" then text = text .. _("\n\nEsta integración es antigua y puede fallar o pedir pago.") end
                message(text)
            end),
        }
    end
    local function connection()
        return {
            action(function() return _("Dirección del ordenador: ") .. (cfg.url and cfg.url ~= "" and cfg.url or _("sin configurar")) end,
                function() edit(_("IP del ordenador con Anki"), "url", "192.168.1.100:8765", State.normalize_url) end),
            action(_("Comprobar conexión"), function()
                local url, err = State.normalize_url(cfg.url)
                if not url then message(err); return end
                UIManager:scheduleIn(0.1, function()
                    local ok, reason = AnkiSync.test_connection(url)
                    message(ok and _("Conexión correcta. Los tipos de nota se preparan automáticamente al enviar.") or
                        (_("No pudimos conectar con Anki.\n\n") .. tostring(reason or "") ..
                        _("\n\nAbre Anki, conecta ambos dispositivos a la misma red y comprueba la IP y el puerto 8765.")))
                end)
            end),
            action(_("Ayuda de conexión"), function()
                message(_("Usa la IP del ordenador, no la del Kobo ni localhost. AnkiConnect debe aceptar conexiones de tu red. Si cambias de Wi-Fi, revisa la IP; una reserva DHCP en el router ayuda a mantenerla estable."))
            end),
        }
    end
    local function organization()
        for _i, item in ipairs(ORGANIZATIONS) do
            if item.mode == cfg.deck_mode and item.split == (cfg.split_card_types == true) then return item.name end
        end
        return "Por libro"
    end
    local function choose_organization(selected)
        if not selected.split then
            save({deck_mode = selected.mode, split_card_types = false})
            return
        end
        local dialog
        dialog = MultiInputDialog:new {
            title = _("Nombres de las subbarajas"),
            description = _("Escribe el nombre para cada clase de tarjeta. Son subbarajas, no tipos de nota. No se mueven tarjetas existentes."),
            fields = {
                {description = _("Anki Vocab"), text = State.type_deck_name(cfg, nil), hint = _("Vocabulario")},
                {description = _("Anki Learn"), text = State.type_deck_name(cfg, "learn"), hint = _("Aprendizaje")},
            },
            buttons = {{
                {text = _("Cancelar"), callback = function() UIManager:close(dialog) end},
                {text = _("Guardar organización"), is_enter_default = true, callback = function()
                    local fields = dialog:getFields()
                    local names, err = State.validate_type_deck_names(fields[1], fields[2])
                    if not names then message(err); return end
                    if save({deck_mode = selected.mode, split_card_types = true,
                        vocab_deck_name = names.vocab, learn_deck_name = names.learn}) then
                        UIManager:close(dialog)
                    end
                end},
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end
    local function decks()
        local automatic = action(_("Enviar pendientes automáticamente"), function()
            if not cfg.auto_send_wifi and not State.normalize_url(cfg.url) then message(_("Configura primero la conexión con Anki.")); return end
            save({auto_send_wifi = not cfg.auto_send_wifi})
        end)
        automatic.checked_func = function() return cfg.auto_send_wifi == true end
        return {
            submenu(function() return _("Organización: ") .. _(organization()) end, function()
                local items = {}
                for _i, option in ipairs(ORGANIZATIONS) do
                    local selected = option
                    local item = action(_(selected.name), function() choose_organization(selected) end)
                    item.checked_func = function() return cfg.deck_mode == selected.mode and (cfg.split_card_types == true) == selected.split end
                    items[#items+1] = item
                end
                return items
            end),
            action(function() return cfg.deck_mode == "book" and (_("Deck Padre: ") .. State.book_parent(cfg))
                or ((cfg.split_card_types and _("Deck Padre: ") or _("Baraja: ")) .. (cfg.deck or "KOReader")) end, function()
                if cfg.deck_mode == "book" then
                    edit(_("Deck Padre"), "book_parent", "KOReader", nonempty, State.book_parent(cfg))
                else edit(cfg.split_card_types and _("Deck Padre") or _("Baraja de destino"), "deck", "KOReader", nonempty) end
            end),
            automatic,
            action(function() return _("Etiquetas adicionales: ") .. (#cfg.tags > 0 and table.concat(cfg.tags, ", ") or _("ninguna")) end, function()
                edit(_("Etiquetas adicionales separadas por comas"), "tags", "lectura, ideas", function(value)
                    local tags = {}; for tag in value:gmatch("[^,]+") do tags[#tags+1] = tag end
                    return State.extra_tags(tags)
                end, table.concat(cfg.tags, ", "))
            end),
            action(_("Ver ejemplo de organización"), function()
                local root = cfg.deck_mode == "book" and (State.book_parent(cfg) .. "::<Libro>") or (cfg.deck or "KOReader")
                local example = cfg.split_card_types and (root .. "::" .. State.type_deck_name(cfg, nil) .. "\n" .. root .. "::" .. State.type_deck_name(cfg, "learn")) or root
                message(example .. _("\n\nPara renombrar las subbarajas vuelve a elegir una organización por tipo. Solo cambia el destino de envíos futuros; no mueve notas existentes. Las etiquetas KOReader y las del tipo de tarjeta se añaden automáticamente. El envío automático necesita Anki abierto y no sincroniza AnkiWeb."))
            end),
        }
    end
    local function text_page()
        local auto_highlight = action(_("Subrayar al guardar tarjeta"), function()
            save({highlight_on_save = not cfg.highlight_on_save})
        end)
        auto_highlight.checked_func = function() return cfg.highlight_on_save == true end
        auto_highlight.help_text = _("Subraya la selección original solo si contiene más de una palabra y después de pulsar Guardar y guardar correctamente Anki Vocab o Anki Learn. Una sola palabra o generar la vista previa no subraya. No duplica subrayados existentes ni cambia la selección de texto de KOReader.")
        return {
            submenu(function() return _("Servicio: ") .. chosen("text").name end, function() return provider_choices("text") end),
            submenu(_("Cuenta y modelo de IA"), function() return account("text") end),
            auto_highlight,
            submenu(function()
                local label = cfg.target_language or "English"
                for _i, lang in ipairs(LANGUAGES) do if lang.id == label then label = lang.name; break end end
                return _("Idioma: ") .. _(label)
            end, function()
                local items = {}
                for _i, lang in ipairs(LANGUAGES) do
                    local value = lang
                    local item = action(_(value.name), function() save({target_language = value.id}) end)
                    item.checked_func = function() return (cfg.target_language or "English") == value.id end
                    items[#items+1] = item
                end
                items[#items+1] = action(_("Otro idioma…"), function() edit(_("Idioma del libro y de las tarjetas"), "target_language", "Italian", nonempty) end)
                return items
            end),
            action(_("Cómo se aplica a Vocab y Learn"), function()
                message(_("Ambos usan este servicio, clave e idioma. Eliges Anki Vocab o Anki Learn al seleccionar texto; no hay perfiles ni modos predeterminados.\n\nEl idioma corresponde a toda la tarjeta, no solo a una traducción. AnkiVocab es la excepción: solo admite vocabulario."))
            end),
        }
    end
    local function images()
        return {
            submenu(function() return _("Servicio: ") .. chosen("image").name end, function() return provider_choices("image") end),
            submenu(_("Cuenta y modelo de IA"), function() return account("image") end, function() return cfg.image_provider ~= "none" end),
            action(_("Solo para Anki Vocab"), function()
                message(_("Las imágenes son opcionales y solo se generan para Anki Vocab. Anki Learn usa texto y citas del libro. Sin imágenes no hace peticiones ni muestra errores de imagen. Revisa los costes de tu proveedor antes de activarlas."))
            end),
        }
    end
    local function audio()
        local enable = action(_("Añadir pronunciación al enviar Vocab"), function()
            if not cfg.tts_enabled and not State.has_key(cfg.elevenlabs_api_key) then message(_("Añade primero la clave de ElevenLabs en Cuenta y voz.")); return end
            save({tts_enabled = not cfg.tts_enabled})
        end)
        enable.checked_func = function() return cfg.tts_enabled == true end
        return {enable, submenu(_("Cuenta y voz de ElevenLabs"), function() return {
            action(function() return _("Clave API: ") .. (State.has_key(cfg.elevenlabs_api_key) and _("guardada") or _("falta añadirla")) end,
                function() edit(_("Clave de ElevenLabs"), "elevenlabs_api_key", "elevenlabs.io", nil, nil, true) end),
            action(function() return _("Voz: ") .. (cfg.elevenlabs_voice_id or "JBFqnCBsd6RMkjVDRZzb") end,
                function() edit(_("Identificador de voz de ElevenLabs"), "elevenlabs_voice_id", "JBFqnCBsd6RMkjVDRZzb", nonempty) end),
        } end), action(_("Dónde se escucha y qué consume"), function()
            message(_("Se genera al enviar Vocab a Anki y consume la cuota de ElevenLabs. Se reproduce en Anki, no en el Kobo. No se genera audio para Learn."))
        end)}
    end
    local function cloud()
        local automatic = action(_("Sincronizar al abrir KOReader"), function()
            save({cloud_auto_sync = not cfg.cloud_auto_sync})
        end, function() return cfg.sync_server ~= nil end)
        automatic.checked_func = function() return cfg.cloud_auto_sync == true end
        return {
            action(function() return _("Destino: ") .. (cfg.sync_server and (cfg.sync_server.name or _("configurado")) or _("sin configurar")) end, function()
                CardSync.choose_cloud_server(ui, function(server)
                    if type(server) ~= "table" then return false end
                    if save({sync_server = server}) then CardSync.reset_baseline(); return true end
                    return false
                end)
            end),
            automatic,
            action(_("Desvincular nube"), function()
                UIManager:show(ConfirmBox:new {text = _("¿Desvincular la nube? No borra tarjetas locales ni archivos remotos."),
                    ok_text = _("Desvincular"), ok_callback = function()
                        local draft = {}; for key, value in pairs(cfg) do draft[key] = value end
                        draft.sync_server, draft.cloud_auto_sync = nil, false
                        if save(draft, true) then CardSync.reset_baseline() end
                    end})
            end, function() return cfg.sync_server ~= nil end),
            action(_("Qué sincroniza esta nube"), function()
                message(_("Comparte tarjetas guardadas entre lectores mediante Dropbox/WebDAV. No es AnkiWeb. Para ejecutarla usa Tarjetas → Sincronizar entre lectores. Recuperar desde Anki también está en Tarjetas, no en Configuración."))
            end),
        }
    end
    return {
        submenu(_("Conexión con Anki"), connection),
        submenu(_("Barajas y envío"), decks),
        submenu(_("Generación de tarjetas"), text_page),
        submenu(_("Extras de vocabulario"), function() return {submenu(_("Imágenes"), images), submenu(_("Audio"), audio)} end),
        submenu(_("Nube entre lectores"), cloud),
        action(_("Ayuda y tipos de nota automáticos"), function()
            message(_("Selecciona texto y elige Anki Vocab para palabras o Anki Learn para ideas. Revisa la propuesta y guarda o envía desde cualquiera de sus caras.\n\nEl complemento prepara KOReader Vocabulary (Cloze) y KOReader Learn (pregunta/respuesta) al enviar. No necesitas elegir ni configurar tipos de nota. Nunca modifica tipos incompatibles ni cambia tus repasos."))
        end),
    }
end
return Settings

-- Shared, short Spanish feedback. Never display raw provider bodies or keys.
local Feedback = {GENERATING = "Generando tarjeta…", REGENERATING = "Regenerando tarjeta…",
    RETRYING = "Servicio ocupado. Reintentando…"}
local function has(text, needle) return text:find(needle, 1, true) ~= nil end
local logger_ok, logger = pcall(require, "logger")
local diagnostic_modules = { ["text_stream.lua"] = true, ["card_generator.lua"] = true,
    ["generation_worker.lua"] = true, ["https.lua"] = true, ["http.lua"] = true,
    ["ltn12.lua"] = true, ["socket.lua"] = true, ["json.lua"] = true }
local function request_diagnostic(exception, reason)
    if not logger_ok then return end
    local raw = type(reason) == "string" and reason:lower() or ""
    local category = "unknown"
    for _, known in ipairs({"response too large", "response text too large", "response frame too large",
        "wantread", "wantwrite", "timeout", "closed", "connection", "handshake", "certificate",
        "host not found", "eof", "invalid chunk size", "bad record mac", "malformed response", "reset"}) do
        if has(raw, known) then category = known; break end
    end
    local module, line = raw:match("([%w_]+%.lua):(%d+):")
    local location = module and diagnostic_modules[module] and (module .. ":" .. line) or ""
    logger.info("Anki transport:", exception and "exception" or "failure", category, location, type(reason), #raw)
end
local function shorten(text)
    if #text <= 220 then return text end
    return (text:sub(1, 210):match("^(.*)%s") or "No se pudo generar la tarjeta.") .. "…"
end
function Feedback.classify(err, details)
    if type(details) == "table" and details.kind then return details end
    local raw = type(err) == "string" and err or ""
    local text = raw:lower()
    local status = tonumber(text:match("http%s+(%d%d%d)"))
    local kind, message, retryable = "validation", raw, false
    if status == 401 or status == 403 or has(text, "invalid api key") or has(text, "invalid_api_key") or has(text, "api key not valid") then
        kind, message = "auth", "La clave API no es válida o no tiene permiso. Revisa la cuenta del servicio."
    elseif has(text, "key not configured") then
        kind, message = "config", "Falta la clave API. Añádela en Generación de tarjetas → Cuenta y modelo de IA."
    elseif status == 402 or has(text, "insufficient_quota") or has(text, "no credits") or
        (status == 429 and (has(text, "billing") or has(text, "credit") or has(text, "perday") or
            has(text, "per_day") or has(text, "daily") or has(text, "per day") or has(text, "limit: 0") or text:match('"limit"%s*:%s*0'))) then
        kind, message = "quota", "Se agotó la cuota o el saldo del servicio. Revisa tu cuenta o cambia de proveedor."
    elseif status == 429 then
        kind, message, retryable = "rate_limit", "El servicio alcanzó su límite temporal. Inténtalo más tarde.", true
    elseif status == 500 or status == 502 or status == 503 or status == 504 or
        has(text, "overloaded") or has(text, "at capacity") or has(text, "resource_exhausted") then
        kind, message, retryable = "busy", "El servicio está saturado o temporalmente no disponible. Inténtalo más tarde.", true
    elseif has(text, "timeout") or has(text, "timed out") then
        kind, message, retryable = "timeout", "El servicio tardó demasiado en responder. Comprueba el Wi-Fi y reintenta.", true
    elseif has(text, "request_failed") or has(text, "connection") or has(text, "closed") or has(text, "network") then
        kind, message, retryable = "network", "No se pudo conectar con el servicio. Comprueba el Wi-Fi y reintenta.", true
    elseif status == 404 then
        kind, message = "model", "El modelo de IA no está disponible. Revísalo en Cuenta y modelo de IA."
    elseif status == 400 then
        kind, message = "request", "El servicio rechazó la solicitud. Revisa el modelo o selecciona menos texto."
    elseif status or has(text, "http ") then
        kind, message = "service", "El servicio devolvió un error. Inténtalo más tarde o cambia de proveedor."
    elseif has(text, "json") or has(text, "response") or has(text, "no text in") or has(text, "decoded value") then
        kind, message = "invalid", "La IA devolvió una respuesta inválida. Reintenta con una selección más concreta."
    elseif has(text, "no image prompt") then
        kind, message = "validation", "No hay una descripción para crear la imagen."
    elseif has(text, "unknown image provider") then
        kind, message = "config", "Selecciona un servicio de imágenes válido en Extras de vocabulario."
    elseif has(text, "empty image") or has(text, "no image in") then
        kind, message = "invalid", "El servicio no devolvió una imagen válida. Inténtalo de nuevo."
    elseif has(text, "cannot write") or has(text, "cannot create") then
        kind, message = "storage", "No se pudo guardar el resultado. Comprueba el espacio libre del lector."
    elseif has(text, "gemini error") or has(text, "api error") or has(text, "https://") or
        has(text, "http://") or has(text, "api_key") or has(text, "bearer ") or has(text, "sk-") or has(text, "{") then
        kind, message = "service", "El servicio devolvió un error. Revisa su configuración e inténtalo más tarde."
    elseif raw == "" then
        kind, message = "unknown", "No se pudo generar la tarjeta. Inténtalo de nuevo."
    end
    return {kind = kind, message = shorten(message), retryable = retryable, status = status}
end
function Feedback.response_error(data, body, headers)
    local problem = type(data.error) == "table" and data.error or {}
    local status = tonumber(problem.code) or tonumber(problem.status)
    local label = tostring(problem.type or problem.status or problem.code or ""):lower()
    if not status then
        if has(label, "auth") or has(label, "key") then status = 401
        elseif has(label, "quota") then status = 402
        elseif has(label, "rate") or has(label, "resource_exhausted") then status = 429
        elseif has(label, "invalid_request") then status = 400
        else status = 503 end
    end
    return Feedback.http_error(status, body, headers)
end
function Feedback.image_message(err)
    local info = Feedback.classify(err)
    if info.kind == "invalid" then return "El servicio no devolvió una imagen válida. Inténtalo de nuevo." end
    if info.kind == "config" and not tostring(err):lower():find("unknown image provider", 1, true) then
        return "Añade la clave del servicio de imágenes en Extras de vocabulario."
    end
    return info.message
end
function Feedback.is_top(widget)
    local UI = require("ui/uimanager")
    return widget ~= nil and type(UI.getTopmostVisibleWidget) == "function" and UI:getTopmostVisibleWidget() == widget
end
function Feedback.http_error(code, body, headers)
    local status = tonumber(code)
    local info
    if status and status >= 100 and status <= 599 and status % 1 == 0 then
        info = Feedback.classify("HTTP " .. tostring(status) .. ": " .. tostring(body or ""))
    else
        -- LuaSec may return a transport error (including wantread or TLS EOF)
        -- instead of an HTTP status. Treat it as an interrupted connection,
        -- never as a permanent provider rejection or a successful partial card.
        info = Feedback.classify(type(code) == "string" and code or "request_failed")
        if info.kind ~= "timeout" then
            info = {kind = "network", message = "Se interrumpió la conexión con el servicio. Comprueba el Wi-Fi y reintenta.", retryable = true}
        end
        info.transport_error = true
    end
    local header = type(headers) == "table" and (headers["retry-after"] or headers["Retry-After"])
    local delay = header and tonumber(header)
    local body_delay = type(body) == "string" and tonumber(body:match('"retryDelay"%s*:%s*"([%d%.]+)s"'))
    if body_delay then delay = math.max(delay or 0, body_delay) end
    if header and not tonumber(header) then info.retryable = false end
    if delay and (delay ~= delay or delay < 0 or delay == math.huge) then info.retryable, delay = false, nil end
    info.retry_after = delay
    return nil, info.message, info
end
function Feedback.request(requester, options)
    local ok, result, code, headers = pcall(requester.request, options)
    if not ok then request_diagnostic(true, result); return nil, "request_failed" end
    if not result then request_diagnostic(false, code) end
    return result, code, headers
end
function Feedback.run(task, on_success, on_failure, options)
    local UI = require("ui/uimanager")
    local Notification = require("ui/widget/notification")
    local InfoMessage = require("ui/widget/infomessage")
    local opts, retries = options or {}, 1
    if opts.retries ~= nil then retries = opts.retries end
    local busy, finished = nil, false
    local function close_busy() if busy then UI:close(busy); busy = nil end end
    local function show(text)
        close_busy()
        busy = Notification:new {text = text, timeout = 30}
        UI:show(busy)
    end
    local attempt
    attempt = function()
        if finished then return end
        show(opts.label or Feedback.GENERATING)
        UI:scheduleIn(0.05, function()
            if finished then return end
            local ok, result, err, details = pcall(task)
            close_busy()
            if ok and result ~= nil and result ~= false then finished = true; on_success(result, err, details); return end
            local info = Feedback.classify(ok and err or nil, ok and details or nil)
            local delay = info.retry_after or 3
            if info.retryable and retries > 0 and delay <= 10 then
                retries = retries - 1
                show((info.kind == "busy" or info.kind == "rate_limit") and Feedback.RETRYING or "Reintentando conexión…")
                UI:scheduleIn(math.max(1, delay), attempt)
                return
            end
            if not opts.quiet then UI:show(InfoMessage:new {text = info.message}) end
            finished = true
            if on_failure then on_failure(info.message, info) end
        end)
    end
    attempt()
    return {cancel = function()
        if finished then return end
        finished = true
        close_busy()
        if on_failure then on_failure("Generación cancelada.", {kind = "cancelled"}) end
    end}
end
return Feedback

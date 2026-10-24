-- Explicit, read-only discovery. Keys stay in memory; only validated IDs cross
-- the worker boundary. Inspired by Anki AI Tutor's provider catalogs.
local Catalog = {}
local keys = {gemini="gemini_api_key", openrouter="openrouter_api_key",
    deepseek="deepseek_api_key", openai="openai_api_key", dashscope="dashscope_api_key"}
local endpoints = {gemini="https://generativelanguage.googleapis.com/v1beta/models",
    openrouter="https://openrouter.ai/api/v1/models", deepseek="https://api.deepseek.com/models",
    openai="https://api.openai.com/v1/models"}
local function contains(values, target)
    if type(values) ~= "table" then return false end
    for _, value in ipairs(values) do if value == target then return true end end
    return false
end
function Catalog.key(cfg, provider)
    local value = cfg[keys[provider]]
    if provider == "dashscope" and value == nil then value = cfg.api_key end
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end
function Catalog.endpoint(cfg, provider)
    if provider ~= "dashscope" then return endpoints[provider] end
    local url = cfg.provider
    if not url or url == "" then return "https://dashscope-intl.aliyuncs.com/api/v1/models" end
    local origin = url:match("^(https://[^/?#]+)[/]")
    if origin and url:find("/compatible-mode/v1/", 1, true) then return origin .. "/api/v1/models" end
end
function Catalog.identity(cfg, provider)
    -- Never serialize or display this value. A changed key/endpoint invalidates
    -- both the cache and outstanding callbacks, including across image/text use.
    return Catalog.key(cfg, provider) .. "\0" .. (Catalog.endpoint(cfg, provider) or "")
end
function Catalog.filter(models, query)
    local terms, out = {}, {}
    for term in (query or ""):lower():gmatch("%S+") do terms[#terms+1] = term end
    for _, id in ipairs(models) do
        local match, folded = true, id:lower()
        for _, term in ipairs(terms) do if not folded:find(term, 1, true) then match=false; break end end
        if match then out[#out+1] = id end
    end
    return out
end
local function model_id(value, provider)
    if type(value) ~= "string" then return end
    if provider == "gemini" then value = value:gsub("^models/", "") end
    if value == "" or #value > 200 or not value:match("^[%w][%w%._:/%-]*$") then return end
    for part in (value .. "/"):gmatch("(.-)/") do
        if part == "" or part == "." or part == ".." then return end
    end
    return value
end
local function usable(entry, provider, category, id)
    local image = category == "image"
    if provider == "openrouter" then
        local arch = type(entry.architecture) == "table" and entry.architecture or {}
        return contains(arch.input_modalities, "text") and contains(arch.output_modalities, image and "image" or "text")
    elseif provider == "gemini" then
        local is_image = id:find("image", 1, true) or id:find("nano-banana", 1, true)
        return contains(entry.supportedGenerationMethods, "generateContent")
            and (image and is_image or not image and not is_image and not id:find("tts",1,true) and not id:find("audio",1,true))
    elseif provider == "openai" then
        if image then return id:match("^gpt%-image%-") ~= nil end
        if not (id:match("^gpt%-") or id:match("^o[134]") or id:match("^chatgpt%-") or id:match("^ft:gpt%-")) then return false end
        if id:find("%-pro") then return false end -- Responses-only Pro variants.
        for _, name in ipairs({"image", "audio", "realtime", "transcribe", "tts", "search", "instruct", "codex", "deep-research"}) do
            if id:find(name, 1, true) then return false end
        end
        return true
    elseif provider == "dashscope" then
        -- The image generator uses the Qwen image endpoint, not arbitrary Wan
        -- video/async image endpoints returned by the general catalog.
        if image then return id:match("^qwen%-image") ~= nil end
        local meta = type(entry.inference_metadata) == "table" and entry.inference_metadata or {}
        return contains(entry.capabilities, "TG") or contains(entry.capabilities, "Reasoning")
            or contains(meta.response_modality, "Text")
    end
    return not image
end
function Catalog.fetch(cfg, provider, category)
    local endpoint = Catalog.endpoint(cfg, provider)
    if not endpoint then return nil, "Este servicio no ofrece un catálogo para la dirección configurada. Usa la lista incluida o escribe el modelo." end
    local key = Catalog.key(cfg, provider)
    if not require("settings_state").has_key(key) then return nil, "Añade primero la clave API de este proveedor." end
    if key:find("[^!-~]") then return nil, "La clave API contiene caracteres inválidos. Revísala en la cuenta del proveedor." end
    local json, https = require("json"), require("ssl.https")
    local Feedback = require("generation_feedback")
    local models, seen, tokens, token, count, total_bytes = {}, {}, {}, nil, 0, 0
    for page=1,20 do
        local url = endpoint
        if provider == "gemini" then
            url = url .. "?pageSize=1000" .. (token and "&pageToken=" .. token:gsub("([^%w%-._~])", function(c) return string.format("%%%02X",c:byte()) end) or "")
        elseif provider == "dashscope" then
            url = url .. "?page_size=100&page_no=" .. page .. "&capabilities=" .. (category == "image" and "IG" or "TG&capabilities=Reasoning")
        end
        local chunks, too_large = {}, false
        local headers = {Accept="application/json"}
        if provider == "gemini" then headers["x-goog-api-key"]=key else headers.Authorization="Bearer " .. key end
        local timeout = https.TIMEOUT
        https.TIMEOUT = 15
        local _, code = Feedback.request(https, {url=url, method="GET", headers=headers, redirect=false,
            sink=function(chunk)
                if chunk then
                    total_bytes = total_bytes + #chunk
                    if total_bytes > 8*1024*1024 then too_large=true; return nil,"catalog too large" end
                    chunks[#chunks+1] = chunk
                end
                return 1
            end})
        https.TIMEOUT = timeout
        if too_large then return nil, "El catálogo supera el tamaño permitido. Usa la lista incluida o escribe el modelo." end
        if tonumber(code) ~= 200 then
            local status = tonumber(code)
            if status == 401 or status == 403 then return nil, "La clave API no tiene acceso al catálogo. Revisa la cuenta del proveedor." end
            return nil, "No se pudo cargar el catálogo" .. (status and " (HTTP " .. status .. ")." or ". Comprueba el Wi-Fi y reintenta.")
        end
        local ok, data = pcall(json.decode, table.concat(chunks))
        if not ok or type(data) ~= "table" or data.error or data.success == false then return nil, "El proveedor devolvió un catálogo inválido." end
        local output = provider == "dashscope" and data.output or data
        local entries = type(output) == "table" and (provider == "gemini" and output.models or provider == "dashscope" and output.models or output.data)
        if type(entries) ~= "table" then return nil, "El proveedor devolvió un catálogo inválido." end
        count = count + #entries
        for _, entry in ipairs(entries) do
            if type(entry) == "table" then
                local id = model_id(provider == "gemini" and entry.name or provider == "dashscope" and entry.model or entry.id, provider)
                if id and usable(entry, provider, category, id) and not seen[id] then
                    seen[id]=true; models[#models+1]=id
                    if #models > 5000 then return nil, "El catálogo supera el número de modelos permitido." end
                end
            end
        end
        local more = false
        if provider == "gemini" then
            token = data.nextPageToken
            more = token ~= nil and token ~= ""
            if more and (type(token) ~= "string" or #token > 4096 or tokens[token]) then return nil, "El catálogo tiene una paginación inválida." end
            if more then tokens[token]=true end
        elseif provider == "dashscope" then
            local total = tonumber(output.total)
            if not total or total < 0 or (#entries == 0 and count < total) then return nil, "El catálogo tiene una paginación inválida." end
            more = count < total
        end
        if not more then table.sort(models); return models end
    end
    return nil, "El catálogo supera el límite de páginas permitido."
end

local serial = 0
function Catalog.launch(cfg, provider, category)
    local util = require("ffi/util")
    if not util.runInSubProcess or not util.isSubProcessDone or not util.terminateSubProcess then return nil, "El lector no admite consultas en segundo plano." end
    local Paths = require("storage_paths")
    local ready, err = Paths.initialize()
    if not ready then return nil, err end
    serial = serial+1
    local path = Paths.runtime .. "/model-catalog-" .. os.time() .. "-" .. serial .. "-" .. math.random(2147483646) .. ".json"
    local json = require("json")
    local pid = util.runInSubProcess(function()
        local ok, models, reason = pcall(Catalog.fetch, cfg, provider, category)
        -- Exceptions may contain URLs/credentials: use a fixed safe message.
        local value = models and ok and {models=models} or {error=ok and reason or "No se pudo consultar el catálogo. Inténtalo de nuevo."}
        local f = io.open(path .. ".tmp", "w")
        if f then
            local written = f:write(json.encode(value))
            local closed = f:close()
            if written and closed then os.rename(path .. ".tmp", path) else os.remove(path .. ".tmp") end
        end
    end, false)
    if not pid then return nil, "No se pudo iniciar la consulta del catálogo." end
    local job = {pid=pid, started=os.time()}
    function job:clear() os.remove(path); os.remove(path .. ".tmp") end
    function job:cancel(UI)
        if self.reaped or self.cancelled then return end
        self.cancelled=true; util.terminateSubProcess(self.pid)
        local function reap()
            if util.isSubProcessDone(self.pid) then self.reaped=true; self:clear() else UI:scheduleIn(0.2,reap) end
        end
        reap()
    end
    function job:poll(UI)
        if util.isSubProcessDone(self.pid) then
            self.reaped=true
            local f = io.open(path,"r")
            local ok, value
            if f then local raw=f:read("*all"); f:close(); ok,value=pcall(json.decode,raw or "") end
            self:clear()
            return ok and type(value)=="table" and value or {error="No se pudo cargar el catálogo. Inténtalo de nuevo."}
        elseif os.time()-self.started >= 30 then
            self:cancel(UI)
            return {error="El proveedor tardó demasiado en devolver el catálogo. Puedes reintentar o escribir el modelo."}
        end
    end
    return job
end
return Catalog

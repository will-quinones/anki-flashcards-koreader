-- Offline presets and provider-specific request controls. No keys or network I/O.
-- Sources and review date are recorded in docs/AI_PROVIDERS.md.
local AI = {}
AI.providers = {"gemini", "openrouter", "deepseek", "dashscope", "openai", "ankivocab"}
AI.fields = {
    gemini = {key = "gemini_text_model", default = "gemini-2.5-flash"},
    openrouter = {key = "openrouter_model", default = "anthropic/claude-3-haiku"},
    deepseek = {key = "deepseek_model", default = "deepseek-flash"},
    dashscope = {key = "model", default = "qwen-plus"},
    openai = {key = "openai_model", default = "gpt-4o-mini"},
}
AI.models = {
    gemini = {"gemini-3.8-flash", "gemini-4-argon", "gemini-3.6-flash", "gemini-3.5-flash-lite",
        "gemini-3.1-pro-preview", "gemini-3.1-flash-lite", "gemini-3-flash-preview",
        "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro"},
    openai = {"gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-6-astra",
        "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4-mini", "gpt-4.1-mini", "gpt-4o-mini"},
    deepseek = {"deepseek-flash", "deepseek-v4-pro"},
    dashscope = {"qwen3.8-max", "qwen3.8-flash", "qwen3.7-plus", "qwen3.7-flash",
        "qwen3.5-plus", "qwen-plus", "qwen-flash", "qwen-max"},
    openrouter = {"anthropic/claude-sonnet-5.5", "anthropic/claude-haiku-5.5",
        "openai/gpt-6.1-sol", "openai/gpt-6-luna", "google/gemini-3.8-flash",
        "deepseek/deepseek-v4.1-flash", "deepseek/deepseek-v4-pro", "anthropic/claude-3-haiku"},
}
AI.image_models = {
    gemini = {"gemini-nano-banana-2.1", "gemini-3.1-flash-image", "gemini-3-pro-image"},
    openai = {"gpt-image-2.5-flare", "gpt-image-2.5-sunburst", "gpt-image-1.5", "gpt-image-1-mini"},
    dashscope = {"qwen-image-plus", "qwen-image-max"},
    openrouter = {"google/gemini-3.1-flash-image-preview", "google/gemini-3-pro-image"},
}
AI.effort_names = {auto = "Predeterminado del modelo", minimal = "Mínimo", low = "Bajo",
    medium = "Medio", high = "Alto", xhigh = "Muy alto", max = "Máximo"}
AI.mode_names = {auto = "Predeterminado del modelo", on = "Activado", off = "Desactivado"}
local function contains(values, value)
    for _, item in ipairs(values or {}) do if item == value then return true end end
    return false
end
local function profile(style, off, efforts, default, extra)
    local value = {style = style, can_disable = off, efforts = efforts, default_effort = default}
    for k, v in pairs(extra or {}) do value[k] = v end
    return value
end
local NONE = profile("none", false, {})
local OPENAI = profile("openai", true, {"low", "medium", "high", "xhigh", "max"}, "medium")
local OPENAI_ALWAYS = profile("openai", false, OPENAI.efforts, "medium")
local DEEPSEEK = profile("deepseek", true, {"low", "high", "max"}, "high")
local GEMINI_LEVEL = profile("gemini_level", false, {"low", "medium", "high"}, "medium")
local GEMINI_MINIMAL = profile("gemini_level", false, {"minimal", "low", "medium", "high"}, "low")
local GEMINI_BUDGET = profile("gemini_budget", true, {"low", "medium", "high"}, nil,
    {budgets = {low = 1024, medium = 4096, high = 8192}})
local GEMINI_PRO = profile("gemini_budget", false, GEMINI_BUDGET.efforts, nil, {budgets = GEMINI_BUDGET.budgets})
local QWEN_EFFORT = profile("qwen_effort", true, {"low", "medium", "xhigh"}, "xhigh", {default_on = true})
local QWEN_BUDGET = profile("qwen_budget", true, {"low", "medium", "high"}, nil,
    {budgets = GEMINI_BUDGET.budgets})
local ROUTER = profile("router", true, {"minimal", "low", "medium", "high", "xhigh", "max"}, nil)

function AI.model(cfg, provider)
    local field = AI.fields[provider]
    if not field then return nil end
    local value = cfg[field.key]
    return type(value) == "string" and value:match("%S") and value or field.default
end

function AI.profile(provider, model)
    model = (model or ""):lower():gsub("^models/", "")
    if provider == "deepseek" then
        if model == "deepseek-flash" or model:match("^deepseek%-v4") then return DEEPSEEK end
    elseif provider == "openai" then
        if model:match("^gpt%-6%.1%-sol") or model:match("^gpt%-6%-astra") then return OPENAI_ALWAYS end
        if model:match("^gpt%-6%-sol") or model:match("^gpt%-6%-luna") or model:match("^gpt%-5%.6%-") then return OPENAI end
        if (model:match("^gpt%-5%.[245]") and not model:find("pro",1,true)) then
            return profile("openai", true, {"low", "medium", "high", "xhigh"}, "medium")
        end
        if model:match("^gpt%-5%.1") then return profile("openai", true, {"low", "medium", "high"}, "medium") end
        if model == "o3" or model:match("^o[34]%-mini") then
            return profile("openai", false, {"low", "medium", "high"}, "medium")
        end
    elseif provider == "gemini" then
        if model:match("^gemini%-4%-") or model:match("^gemini%-3%.8%-flash") or model:match("^gemini%-3%.1%-pro") then return GEMINI_LEVEL end
        if model:match("^gemini%-3") then return GEMINI_MINIMAL end
        if model:match("^gemini%-2%.5%-pro") then return GEMINI_PRO end
        if model:match("^gemini%-2%.5%-flash") then return GEMINI_BUDGET end
    elseif provider == "dashscope" then
        if model:match("^qwen3%.8") then
            if model:find("2.4t", 1, true) then
                return profile("qwen_effort", false, QWEN_EFFORT.efforts, "xhigh", {default_on = true})
            end
            return QWEN_EFFORT
        end
        if model == "qwen-plus" or model == "qwen-flash" or model:match("^qwen3") then
            return profile("qwen_budget", not model:find("%-thinking"), QWEN_BUDGET.efforts, nil,
                {budgets = QWEN_BUDGET.budgets, default_on = model:match("^qwen3%.[567]") ~= nil or model:find("%-thinking") ~= nil})
        end
    elseif provider == "openrouter" then
        if model == "anthropic/claude-3-haiku" or model:match("^openai/gpt%-4") then return NONE end
        local upstream, id = model:match("^([^/]+)/(.+)$")
        local known = upstream == "google" and AI.profile("gemini", id)
            or upstream == "openai" and AI.profile("openai", id)
            or upstream == "deepseek" and AI.profile("deepseek", id)
        if known and known.style ~= "none" then
            return profile("router", known.can_disable, known.efforts, known.default_effort)
        end
        return ROUTER -- OpenRouter translates its unified reasoning contract.
    end
    return NONE
end

function AI.current(cfg, provider, model)
    local caps = AI.profile(provider, model or AI.model(cfg, provider))
    local mode, effort = cfg[provider .. "_thinking"], cfg[provider .. "_reasoning_effort"]
    if mode == true then mode = "on" elseif mode == false then mode = "off" end
    if mode ~= "on" and mode ~= "off" then mode = "auto" end
    if not contains(caps.efforts, effort) then effort = "auto" end
    if caps.style == "none" then mode, effort = "auto", "auto"
    elseif mode == "off" and not caps.can_disable then mode = "auto" end
    if mode == "auto" and effort ~= "auto" then mode = "on" end
    return {mode = mode, effort = effort, caps = caps}
end

function AI.normalize(cfg)
    for _, provider in ipairs(AI.providers) do
        local current = AI.current(cfg, provider)
        for suffix, value in pairs({thinking = current.mode, reasoning_effort = current.effort}) do
            local key = provider .. "_" .. suffix
            if cfg[key] ~= nil then cfg[key] = value end
        end
    end
    return cfg
end

function AI.validate_model(value, fallback, provider)
    value = (value or ""):match("^%s*(.-)%s*$")
    if value == "" then return fallback end
    if provider == "gemini" then value = value:gsub("^models/", "") end
    if #value > 200 or value:find("%s") or value:find("%c") then
        return nil, "Usa el identificador del modelo, sin espacios ni saltos de línea (máximo 200 caracteres)."
    end
    return value
end

function AI.choices(provider, category, current, default)
    local out, seen = {}, {}
    local function add(id)
        if id and id ~= "" and not seen[id] then seen[id] = true; out[#out+1] = id end
    end
    add(current)
    for _, id in ipairs((category == "image" and AI.image_models or AI.models)[provider] or {}) do add(id) end
    add(default)
    return out
end

function AI.requires_stream(cfg, provider, model)
    local current = AI.current(cfg, provider, model)
    local caps = current.caps
    return provider == "dashscope" and caps.style ~= "none" and current.mode ~= "off"
        and (current.mode == "on" or current.effort ~= "auto" or caps.default_on == true)
end

-- Mutates only the new request body. Automatic settings omit optional controls.
function AI.apply(body, cfg, provider, model)
    local current = AI.current(cfg, provider, model)
    local mode, effort, caps = current.mode, current.effort, current.caps
    if caps.style == "none" or (mode == "auto" and effort == "auto")
        or (mode == "on" and effort == "auto" and not caps.can_disable) then return body end
    if mode == "auto" and effort ~= "auto" then mode = "on" end
    if caps.style == "gemini_level" or caps.style == "gemini_budget" then
        local thinking = {}
        if caps.style == "gemini_level" then
            thinking.thinkingLevel = effort ~= "auto" and effort or caps.default_effort
        else
            thinking.thinkingBudget = mode == "off" and 0 or (caps.budgets[effort] or -1)
        end
        body.generationConfig = body.generationConfig or {}
        body.generationConfig.thinkingConfig = thinking
    elseif caps.style == "deepseek" then
        body.thinking = {type = mode == "off" and "disabled" or "enabled"}
        if mode ~= "off" and effort ~= "auto" then body.reasoning_effort = effort end
    elseif caps.style == "openai" then
        body.reasoning_effort = mode == "off" and "none" or (effort ~= "auto" and effort or caps.default_effort)
    elseif caps.style == "router" then
        body.reasoning = {enabled = mode ~= "off", exclude = true}
        if mode ~= "off" and effort ~= "auto" then body.reasoning.effort = effort end
    elseif caps.style == "qwen_effort" or caps.style == "qwen_budget" then
        if caps.can_disable then body.enable_thinking = mode ~= "off" end
        if mode ~= "off" and effort ~= "auto" then
            if caps.style == "qwen_effort" then body.reasoning_effort = effort
            else body.thinking_budget = caps.budgets[effort] end
        end
    end
    return body
end

function AI.effort_label(current)
    if current.mode == "on" and current.effort == "auto" then
        if current.caps.style == "openai" and current.caps.can_disable then
            return AI.effort_names[current.caps.default_effort] .. " (al activar thinking)"
        end
        if current.caps.style == "gemini_budget" and current.caps.can_disable then return "Dinámico" end
    end
    return AI.effort_names[current.effort]
end

function AI.description(cfg, provider)
    local current = AI.current(cfg, provider)
    if current.caps.style == "none" then
        return provider == "ankivocab" and "Modelo, thinking y esfuerzo gestionados por AnkiVocab."
            or "Este modelo no tiene controles de razonamiento verificados. Se utiliza su configuración predeterminada."
    end
    local text = "Thinking: " .. AI.mode_names[current.mode]
    if not current.caps.can_disable then text = text .. "\nEste modelo no permite desactivar thinking." end
    if current.mode == "off" then text = text .. "\nEsfuerzo: no se aplica mientras thinking está desactivado."
    else text = text .. "\nEsfuerzo: " .. AI.effort_label(current) end
    if current.caps.budgets and current.mode ~= "off" and current.effort ~= "auto" then
        text = text .. "\nPresupuesto de razonamiento: " .. current.caps.budgets[current.effort] .. " tokens."
    end
    if provider == "openrouter" then text = text .. "\nOpenRouter adapta el esfuerzo al modelo y al proveedor que lo sirve." end
    return text
end
return AI

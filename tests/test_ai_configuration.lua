package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local AI = require("ai_configuration")
local State = require("settings_state")
local function apply(provider, model, mode, effort)
    local cfg = {[AI.fields[provider].key] = model,
        [provider .. "_thinking"] = mode, [provider .. "_reasoning_effort"] = effort}
    return AI.apply({}, cfg, provider, model), cfg
end
for _, id in ipairs(AI.providers) do
    local cfg = {text_provider=id}
    assert(next(AI.apply({}, cfg, id, AI.model(cfg, id))) == nil)
    if AI.fields[id] then
        local choices, seen = AI.choices(id, "text", "my-custom-model", AI.fields[id].default), {}
        assert(choices[1] == "my-custom-model" and #choices > 2)
        for _, model in ipairs(choices) do assert(not seen[model]); seen[model] = true end
        assert(seen[AI.fields[id].default])
    end
end
assert(AI.validate_model(" models/gemini-3.8-flash ", "fallback", "gemini") == "gemini-3.8-flash")
assert(AI.validate_model("", "fallback") == "fallback")
assert(not AI.validate_model("model\nname", "fallback"))
assert(not AI.validate_model(string.rep("x",201), "fallback"))

local body, cfg = apply("deepseek", "deepseek-flash", "on", "low")
assert(body.thinking.type == "enabled" and body.reasoning_effort == "low")
body = apply("deepseek", "deepseek-v4-pro", "off", "max")
assert(body.thinking.type == "disabled" and not body.reasoning_effort)
body = apply("openai", "gpt-6-sol", "off", "max")
assert(body.reasoning_effort == "none")
body = apply("openai", "gpt-6.1-sol", "off", "low")
assert(body.reasoning_effort == "low") -- Cannot ask this model for unsupported thinking-off.
body = apply("openai", "gpt-4o-mini", "on", "high")
assert(next(body) == nil)
body = apply("gemini", "gemini-2.5-flash", "off", "high")
assert(body.generationConfig.thinkingConfig.thinkingBudget == 0)
body = apply("gemini", "gemini-2.5-pro", "on", "high")
assert(body.generationConfig.thinkingConfig.thinkingBudget == 8192)
assert(not body.generationConfig.thinkingConfig.thinkingLevel)
body = apply("gemini", "gemini-3.8-flash", "on", "low")
assert(body.generationConfig.thinkingConfig.thinkingLevel == "low")
assert(not body.generationConfig.thinkingConfig.thinkingBudget)
body = apply("gemini", "gemini-3.8-flash", "off", "minimal")
assert(next(body) == nil) -- Neither control is valid for this model.
body = apply("gemini", "gemini-3.1-flash-lite", "on", "auto")
assert(next(body) == nil) -- Keep the model default, rather than force a level.
assert(AI.effort_label(AI.current({openai_model="gpt-5.4-mini",openai_thinking="on"},"openai")):find("Medio",1,true))
assert(AI.effort_label(AI.current({gemini_text_model="gemini-2.5-flash-lite",gemini_thinking="on"},"gemini"))=="Dinámico")
body, cfg = apply("dashscope", "qwen3.8-flash", "on", "xhigh")
assert(body.enable_thinking and body.reasoning_effort == "xhigh" and not body.thinking_budget)
assert(AI.requires_stream(cfg, "dashscope", "qwen3.8-flash"))
body, cfg = apply("dashscope", "qwen3.7-plus", "off", "high")
assert(body.enable_thinking == false and not body.thinking_budget and not AI.requires_stream(cfg,"dashscope","qwen3.7-plus"))
body, cfg = apply("dashscope", "qwen-plus", "on", "medium")
assert(body.enable_thinking and body.thinking_budget == 4096 and not body.reasoning_effort)
assert(AI.requires_stream(cfg,"dashscope","qwen-plus"))
assert(AI.requires_stream({},"dashscope","qwen3.8-flash"))
assert(not AI.requires_stream({},"dashscope","qwen-max"))
body = apply("openrouter", "anthropic/claude-sonnet-5.5", "off", "max")
assert(body.reasoning.enabled == false and body.reasoning.exclude and not body.reasoning.effort)
body = apply("openrouter", "openai/gpt-6.1-sol", "on", "max")
assert(body.reasoning.effort == "max" and not body.thinking and not body.reasoning_effort)

local saved = {settings_version=2, text_provider="deepseek", deepseek_model="deepseek-flash",
    deepseek_api_key="synthetic-secret", deepseek_thinking=false, deepseek_reasoning_effort="max",
    gemini_text_model="gemini-2.5-flash", gemini_thinking=true, gemini_reasoning_effort="medium"}
local normalized = State.merge({}, saved)
assert(normalized.deepseek_thinking == "off" and normalized.gemini_thinking == "on")
assert(saved.deepseek_thinking == false and saved.gemini_thinking == true)
local persisted = State.persistable(normalized)
local reloaded = State.merge({}, persisted)
assert(reloaded.deepseek_model == "deepseek-flash" and reloaded.deepseek_thinking == "off")
assert(reloaded.gemini_reasoning_effort == "medium" and reloaded.deepseek_api_key == "synthetic-secret")
assert(not AI.description(reloaded,"deepseek"):find("synthetic-secret",1,true))
persisted.openai_model="gpt-4o-mini"
persisted.openai_thinking="on"; persisted.openai_reasoning_effort="max"
local unsupported = State.persistable(persisted)
assert(unsupported.openai_thinking=="auto" and unsupported.openai_reasoning_effort=="auto")
assert(persisted.openai_thinking=="on")
print("PASS: provider models, compatible reasoning parameters, independent persistence and safe defaults")

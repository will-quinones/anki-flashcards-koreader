package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local AI = require("ai_configuration")
local input, message, saved, fail_save, saves = nil, nil, nil, false, 0
package.loaded.gettext = function(value) return value end
package.loaded.card_storage = {load_anki_settings=function() return saved end,
    save_anki_settings=function(cfg)
        if fail_save then return false,"disk full" end
        saved=cfg; saves=saves+1; return true
    end}
package.loaded.anki_sync = {}
package.loaded.card_sync = {}
package.loaded["ui/uimanager"] = {show=function() end, close=function() end}
package.loaded["ui/widget/infomessage"] = {new=function(_,spec) message=spec.text; return spec end}
package.loaded["ui/widget/confirmbox"] = {new=function(_,spec) return spec end}
package.loaded["ui/widget/multiinputdialog"] = {new=function() error("Not needed") end}
package.loaded["ui/widget/inputdialog"] = {new=function(_,spec)
    input=spec; spec.getInputText=function() return spec.value or spec.input end
    spec.onShowKeyboard=function() end; return spec
end}
local Settings = require("settings_viewer")
local base = {text_provider="deepseek",deepseek_api_key="synthetic-secret",anki={}}
local menu, stack = Settings.menu_items(base), {}
local function find(prefix)
    for _,item in ipairs(menu) do
        local text=item.text_func and item.text_func() or item.text
        if text:sub(1,#prefix)==prefix then return item end
    end
    error("Missing setting: "..prefix)
end
local function click(prefix)
    local item=find(prefix)
    assert(not item.enabled_func or item.enabled_func(),prefix)
    if item.sub_item_table_func then stack[#stack+1]=menu; menu=item.sub_item_table_func()
    else item.callback({updateItems=function() end}) end
end
local function back() menu=assert(table.remove(stack)) end
click("Generación de tarjetas"); click("Cuenta y modelo")
assert(saves==0)
click("Modelo de IA:")
assert(find("deepseek-flash").checked_func())
click("deepseek-v4-pro"); back()
click("Thinking:"); click("Activado"); back()
click("Esfuerzo:"); click("Máximo"); back()
assert(saved.deepseek_model=="deepseek-v4-pro" and saved.deepseek_thinking=="on" and saved.deepseek_reasoning_effort=="max")
click("Ver configuración de este proveedor")
assert(message:find("deepseek-v4-pro",1,true) and message:find("Máximo",1,true))
assert(not message:find("synthetic-secret",1,true))
click("Thinking:"); click("Desactivado"); back()
assert(not find("Esfuerzo:").enabled_func())
click("Thinking:"); click("Activado"); back()
assert(saved.deepseek_reasoning_effort=="max")
local before=saved
fail_save=true; click("Thinking:"); click("Desactivado"); back(); fail_save=false
assert(saved==before and base.deepseek_thinking=="on")

back(); click("Servicio:"); click("Google Gemini"); back(); click("Cuenta y modelo")
click("Modelo de IA:"); click("gemini-3.8-flash"); back()
click("Thinking:")
for _,item in ipairs(menu) do assert(item.text~="Desactivado") end
back(); click("Esfuerzo:"); click("Bajo"); back()
assert(saved.gemini_thinking=="on" and saved.gemini_reasoning_effort=="low")
assert(saved.deepseek_model=="deepseek-v4-pro" and saved.deepseek_reasoning_effort=="max")
click("Modelo de IA:"); click("Escribir modelo…")
input.value="models/gemini-3.6-flash"; input.buttons[1][2].callback(); back()
assert(saved.gemini_text_model=="gemini-3.6-flash")
click("Modelo de IA:"); click("Escribir modelo…")
before=saved; input.value="bad\nmodel"; input.buttons[1][2].callback()
assert(saved==before)
input.value="custom-unknown"; input.buttons[1][2].callback(); back()
assert(saved.gemini_text_model=="custom-unknown" and saved.gemini_thinking=="auto")
assert(not find("Thinking:").enabled_func() and not find("Esfuerzo:").enabled_func())

back(); click("Ver configuración de proveedores")
local count=saves
for _,prefix in ipairs({"Google Gemini","OpenRouter","DeepSeek","Qwen","OpenAI","AnkiVocab","Pollinations"}) do
    click(prefix); assert(not message:find("synthetic-secret",1,true))
end
assert(saves==count)
back(); click("Servicio:"); click("DeepSeek"); back(); click("Cuenta y modelo")
assert(find("Modelo de IA:").text_func():find("deepseek-v4-pro",1,true))
assert(find("Esfuerzo:").text_func():find("Máximo",1,true))
click("Thinking:"); click("Predeterminado del modelo"); back()
assert(saved.deepseek_thinking=="auto" and saved.deepseek_reasoning_effort=="auto")
assert(saved.deepseek_api_key=="synthetic-secret")
back(); back(); click("Extras de vocabulario"); click("Imágenes")
click("Servicio:"); click("OpenAI"); back(); click("Cuenta y modelo")
click("Modelo de IA:"); click("gpt-image-2.5-flare"); back()
assert(saved.openai_image_model=="gpt-image-2.5-flare")
click("Modelo de IA:"); click("Escribir modelo…")
input.value="my-custom-image-model"; input.buttons[1][2].callback(); back()
assert(saved.openai_image_model=="my-custom-image-model" and saved.deepseek_model=="deepseek-v4-pro")
print("PASS: model presets/manual input, provider switching, native controls, safe summaries and failed-save isolation")

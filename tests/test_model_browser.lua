package.path="AnkiFlashcards.koplugin/?.lua;"..package.path
local Catalog=require("model_catalog")
local AI=require("ai_configuration")
local tasks,visible,input={},nil,nil
package.loaded.gettext=function(value) return value end
local UI={scheduleIn=function(_,_,fn) tasks[#tasks+1]=fn end,
    unschedule=function(_,fn) for i=#tasks,1,-1 do if tasks[i]==fn then table.remove(tasks,i) end end end,
    show=function(_,widget) visible=widget end,
    close=function(_,widget) if visible==widget then visible=nil end; if widget.dismiss_callback then widget.dismiss_callback() end end}
package.loaded["ui/uimanager"]=UI
package.loaded["ui/widget/infomessage"]={new=function(_,spec) return spec end}
package.loaded["ui/widget/inputdialog"]={new=function(_,spec)
    input=spec; spec.getInputText=function() return spec.value or spec.input end; spec.onShowKeyboard=function() end; return spec
end}
local launched,cancelled,result=0,0,nil
local jobs={}
Catalog.launch=function(cfg,provider,category)
    launched=launched+1
    local job={key=cfg[provider.."_api_key"],category=category}
    function job:cancel() cancelled=cancelled+1 end
    function job:poll() return result end
    jobs[#jobs+1]=job; return job
end
local Browser=require("model_browser")
local cfg={deepseek_api_key="synthetic-secret",deepseek_model="custom-model"}
local saves,edits=0,0
local state=Browser.new {provider="deepseek",category="text",field=AI.fields.deepseek,name="DeepSeek",
    config=function() return cfg end,select=function(model) cfg.deepseek_model=model; saves=saves+1; return true end,
    edit=function() edits=edits+1 end}
local menu={item_table=state.items,updateItems=function() end}
local function find(prefix)
    for _,item in ipairs(state.items) do
        local label=item.text_func and item.text_func() or item.text
        if label:sub(1,#prefix)==prefix then return item end
    end
end
local function click(prefix) assert(find(prefix),prefix).callback(menu) end
local function tick() local fn=assert(table.remove(tasks,1)); fn() end
assert(launched==0 and saves==0 and find("custom-model").checked_func())
click("Buscar modelos")
input.value="DEEPSEEK flash"; input.buttons[1][2].callback()
assert(find("deepseek-flash") and not find("deepseek-v4-pro") and saves==0 and launched==0)
click("Cargar catálogo")
assert(visible.text:find("Toca para cancelar",1,true) and launched==1)
tick(); assert(#tasks==1 and saves==0)
result={models={"deepseek-flash","deepseek-new","vendor/PRO:free"}}
tick(); assert(find("Actualizar catálogo") and find("deepseek-flash") and not find("deepseek-new"))
assert(cfg.deepseek_model=="custom-model" and saves==0)
click("Mostrar todos")
assert(find("custom-model").checked_func() and find("deepseek-new"))
click("deepseek-new"); assert(saves==1 and cfg.deepseek_model=="deepseek-new")
click("Buscar modelos"); input.value="missing"; input.buttons[1][2].callback()
assert(find("Sin resultados") and saves==1 and launched==1)
click("Escribir modelo"); assert(edits==1)
click("Mostrar todos")
-- Failed refresh keeps catalog, custom model and selection intact.
result={error="Synthetic offline service"}; click("Actualizar catálogo"); tick()
assert(visible.text==result.error and find("deepseek-new").checked_func() and saves==1)
UI:close(visible)
result=nil; click("Actualizar catálogo"); local old=assert(tasks[1]); UI:close(visible)
assert(cancelled==1 and #tasks==0)
result={models={"late-model"}}; old(); assert(not find("late-model") and saves==1)
-- Key edits invalidate both catalogs and outstanding work, even if the key is
-- changed back before the old callback is delivered.
result=nil; click("Actualizar catálogo"); old=assert(tasks[1])
cfg.deepseek_api_key="other-secret"; Browser.configuration_changed()
assert(cancelled==2 and state.models==nil and find("deepseek-new").checked_func() and find("Cargar catálogo"))
cfg.deepseek_api_key="synthetic-secret"; Browser.configuration_changed()
result={models={"late-model"}}; old(); assert(not find("late-model"))
result=nil; click("Cargar catálogo"); Browser.cancel_all(); assert(cancelled==3 and #tasks==0)
cfg.deepseek_api_key=""; click("Cargar catálogo"); assert(visible.text:find("Añade primero",1,true))
-- Browsing/searching another provider never carries the first provider's list.
local other=Browser.new {provider="openai",category="text",field=AI.fields.openai,name="OpenAI",
    config=function() return {openai_api_key="synthetic-openai"} end,select=function() error("No selection") end,edit=function() end}
assert(other.items~=state.items and not table.concat((function() local out={}; for _,v in ipairs(other.items) do out[#out+1]=v.text or "" end; return out end)()):find("deepseek-flash",1,true))
print("PASS: explicit selection, local search, current model, refresh failure, key invalidation, late callbacks and close/suspend cancellation")

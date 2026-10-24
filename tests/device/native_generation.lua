-- Native widgets/TLS regression; invoked by tests/device/run_native.py.
require("setupkoenv")
io.stdout:setvbuf("no")
G_defaults = require("luadefaults"):open()
G_reader_settings = {
    readSetting = function(_, _, default) return default end,
    nilOrTrue = function() return true end,
    isTrue = function() return false end,
    isFalse = function() return false end,
    has = function() return false end,
}
local screen = {
    getWidth = function() return 1264 end,
    getHeight = function() return 1680 end,
    getDPI = function() return 167 end,
    getSize = function() return require("ui/geometry"):new {w=1264,h=1680} end,
    isColorEnabled = function() return false end,
    scaleBySize = function(_, n) return math.floor(n * 1.8 + 0.5) end,
    scaleByDPI = function(_, n) return math.floor(n * 1.8 + 0.5) end,
}
package.loaded.device = setmetatable({screen = screen, input = {group = {Back = {"Esc"}}}}, {
    __index = function() return function() return false end end,
})
require("document/canvascontext"):init(package.loaded.device)
package.loaded.fontlist = {fontdir = "fonts", getFontList = function()
    return {"fonts/droid/DroidSansMono.ttf", "fonts/noto/NotoSans-Regular.ttf", "fonts/noto/NotoSans-Bold.ttf", "fonts/noto/NotoSansCJKsc-Regular.otf"}
end}
local UI = {widgetRepaint = function() end}
local socket = require("socket")
local ffi = require("ffi")
ffi.cdef("int usleep(unsigned int);")
local tasks, visible = {}, nil
function UI:scheduleIn(delay, callback) tasks[#tasks+1] = {at=socket.gettime()+delay, callback=callback} end
function UI:unschedule(callback) for i=#tasks,1,-1 do if tasks[i].callback==callback then table.remove(tasks,i) end end end
package.loaded["ui/uimanager"] = UI
-- Menu closure checks the live app only to choose its repaint mode. Loading a
-- full FileManager here would initialize unrelated network/hardware listeners.
package.loaded["apps/filemanager/filemanager"] = {}
package.loaded["apps/reader/readerui"] = {}
local stage = assert(arg[1], "Pass the temporary test directory")
package.path = stage .. "/AnkiFlashcards.koplugin/?.lua;" .. package.path
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
screen.bb = Blitbuffer.new(1264,1680,Blitbuffer.TYPE_BBRGB32)
local Event = require("ui/event")
assert(Font:getFace("smallinfofont"))

local Viewer = require("card_viewer")
package.loaded.card_storage = {is_saved=function() return false end}
local closes = 0
function UI:setDirty(widget)
    if widget and widget.paintTo then
        local bb = Blitbuffer.new(1264,1680,Blitbuffer.TYPE_BBRGB32)
        bb:fill(Blitbuffer.COLOR_WHITE)
        widget:paintTo(bb,0,0)
        bb:free()
    end
end
function UI:show(widget)
    visible = widget
    if widget.paintTo then
        self:setDirty(widget)
        if widget.onShow then widget:onShow() end
    end
end
function UI:close(widget)
    closes=closes+1
    if widget.handleEvent then widget:handleEvent(Event:new("CloseWidget")) end
    if visible==widget then visible=nil end
end
local viewer=Viewer:new {card={},generating=true,generation_label="Generando tarjeta…",stream_text=""}
UI:show(viewer)
local original=viewer
for i=1,100 do
    viewer:update_generation("acción /əˈkʃən/ — texto incremental "..i)
    assert(viewer==original and closes==0)
    if i%20==0 then collectgarbage() end
end
UI:close(viewer)
print("NATIVE_IN_PLACE_RENDER_PASS")

-- All output is synthetic. No real card writes or Anki connections are allowed.
local root=stage.."/runtime"
local lfs=require("libs/libkoreader-lfs")
assert(lfs.mkdir(root))
package.loaded.storage_paths={runtime=root,initialize=function() return true end}
local book_path=root.."/synthetic.html"
local f=assert(io.open(book_path,"w"))
f:write("<html><head><title>Synthetic</title></head><body>"..string.rep("<p>This is synthetic reading text for the word action.</p>",100).."</body></html>")
f:close()
local Cre=require("document/credocument")
Cre.default_font="Noto Sans"
Cre.cacheInit=function()
    assert(lfs.mkdir(root.."/cache"))
    require("libs/libkoreader-cre").initCache(root.."/cache",8*1024*1024,true,2)
end
local doc=assert(require("document/documentregistry"):openDocument(book_path))
assert(doc:loadDocument()); doc:render()
assert(require("selection_context")(doc,"action",10):find("action",1,true))
print("NATIVE_DOCUMENT_READY")

local Generation=require("vocab_generation")
local Feedback=require("generation_feedback")
require("card_generator") -- Load native TLS in the parent, as in KOReader.
local config={text_provider="dashscope",images_enabled=false,api_key="synthetic",provider=assert(arg[2]),model="synthetic"}
local function run_until(done)
    local deadline=socket.gettime()+60
    while not done() do
        if socket.gettime()>=deadline then Generation.cancel_all(); error("Native scenario timed out") end
        table.sort(tasks,function(a,b) return a.at<b.at end)
        if tasks[1] and tasks[1].at<=socket.gettime() then table.remove(tasks,1).callback()
        else ffi.C.usleep(5000) end
    end
end

-- Real CRe positions and native pixel inversion, with refresh requests captured
-- before any hardware access. Both on/off phases must stay on the text boxes.
local Marker=require("reading_marker")
local hits=assert(doc:findAllText("action",true,0,5,false))
local hit=assert(hits[1])
assert(type(hit.start)=="string" and type(hit["end"])=="string")
local selection={pos0=hit.start,pos1=hit["end"],text="action"}
local source_boxes=doc:getScreenBoxesFromPositions(selection.pos0,selection.pos1,true)
assert(#source_boxes>0)
local reader={document=doc,view={state={pos=0},view_modules={}}}
function reader.view:registerViewModule(name,value) self.view_modules[name]=value end
local marker_dirty=UI.setDirty
local requests,painted=0,0
UI.setDirty=function(self,widget,mode,region)
    if widget~=reader then return marker_dirty(self,widget,mode,region) end
    assert(mode=="ui" and region and region.w>0 and region.h>0)
    assert(region.x>=0 and region.y>=0 and region.x+region.w<=1264 and region.y+region.h<=1680)
    assert(region.w*region.h<1264*1680)
    requests=requests+1
    local bb=Blitbuffer.new(1264,1680,Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    local marker=reader.view.view_modules.ankivocab_return
    if marker then marker:paintTo(bb) end
    local x,y=math.floor(region.x+region.w/2),math.floor(region.y+region.h/2)
    assert(bb:getPixel(x,y).a==(marker and marker.visible and 0 or 255))
    assert(bb:getPixel(1263,1679).a==255)
    if marker and marker.visible then painted=painted+1 end
    bb:free()
end
Marker.flash(reader,{book={file=doc.file},selection=selection})
run_until(function() return #tasks==0 end)
assert(requests==4*#source_boxes and painted==2*#source_boxes)
assert(not reader.view.view_modules.ankivocab_return and reader.view.state.pos==0)
UI.setDirty=marker_dirty
print("NATIVE_READING_MARKER_REGIONS_PASS")

local function show_card(card)
    local full=Viewer:new {card=card}
    UI:show(full)
    full=full:update(nil,true)
    UI:close(full)
end
local request=Feedback.request
Feedback.request=function(...)
    -- The marker crosses fork boundaries; a Lua boolean would reset on retry.
    if not lfs.attributes(root.."/injected-transport-error") then
        local marker=assert(io.open(root.."/injected-transport-error","w")); marker:close()
        return nil,"wantread"
    end
    return request(...)
end
local complete, failed=false,false
Generation.start(config,{phrase="action",context="Synthetic text",title="Synthetic",author="Test"},function(card)
    assert(card.phrase=="action"); show_card(card); complete=true
end,{on_failure=function() failed=true end})
run_until(function() return complete or failed end)
assert(complete and not failed)
Feedback.request=request
print("NATIVE_TRANSPORT_RETRY_PASS")

complete,failed=false,false
local delayed={}
for key,value in pairs(config) do delayed[key]=value end
delayed.provider=config.provider.."/delayed"
Generation.start(delayed,{phrase="action",context="Synthetic",title="Synthetic",author="Test"},function(card)
    assert(card.phrase=="action"); complete=true
end,{on_failure=function() failed=true end})
run_until(function() return complete or failed end)
assert(complete and not failed)
print("NATIVE_DELAYED_FIRST_BYTE_PASS")

complete,failed=false,false
Generation.start(config,{selected="Synthetic evidence.",context="Synthetic evidence.",title="Synthetic",author="Test"},function(card)
    assert(card.kind=="learn" and card.answer=="HIDDEN_ANSWER")
    show_card(card); complete=true
end,{kind="learn",on_failure=function() failed=true end})
run_until(function()
    if visible and visible.generating then assert(not visible.stream_text:find("HIDDEN_ANSWER",1,true)) end
    if visible and visible.generating then assert(not visible.stream_text:find("HIDDEN_REASONING",1,true)) end
    return complete or failed
end)
assert(complete and not failed)
print("NATIVE_LEARN_STREAMING_PASS")

local cancelled=0
Generation.start(config,{phrase="action",context="Synthetic",title="Synthetic",author="Test"},function()
    error("Cancelled output must never be delivered or saved")
end,{on_cancel=function() cancelled=cancelled+1 end})
local modal=visible
UI:scheduleIn(0.7,function() UI:close(modal) end)
run_until(function() return cancelled==1 and #tasks==0 end)
assert(cancelled==1)
Generation.cancel_all()

-- Actual settings widgets and summaries, backed only by synthetic memory.
local saved_settings
package.loaded.card_storage = {load_anki_settings=function() return saved_settings end,
    save_anki_settings=function(value) saved_settings=value; return true end}
package.loaded.anki_sync,package.loaded.card_sync={},{}
local Settings=require("settings_viewer")
local AI=require("ai_configuration")
local base={text_provider="deepseek",deepseek_api_key="synthetic-secret",anki={}}
local root_menu=Settings.menu_items(base)
local function item(items,prefix)
    for _,value in ipairs(items) do
        local label=value.text_func and value.text_func() or value.text
        if label:sub(1,#prefix)==prefix then return value end
    end
    error("Missing native setting: "..prefix)
end
local generation=item(root_menu,"Generación de tarjetas").sub_item_table_func()
local menu_stub={updateItems=function() end}
for _,id in ipairs({"deepseek","gemini","openai","dashscope","openrouter"}) do
    local choices=item(generation,"Servicio:").sub_item_table_func()
    local labels={deepseek="DeepSeek",gemini="Google Gemini",openai="OpenAI",dashscope="Qwen",openrouter="OpenRouter"}
    item(choices,labels[id]).callback(menu_stub)
    local account=item(generation,"Cuenta y modelo").sub_item_table_func()
    local models=item(account,"Modelo de IA:").sub_item_table_func()
    item(models,AI.models[id][1]).callback(menu_stub)
    item(item(account,"Thinking:").sub_item_table_func(),"Activado").callback(menu_stub)
    item(item(account,"Esfuerzo:").sub_item_table_func(),"Bajo").callback(menu_stub)
    item(account,"Ver configuración de este proveedor").callback(menu_stub)
    assert(visible and not visible.text:find("synthetic-secret",1,true))
    UI:close(visible)
    assert(saved_settings[AI.fields[id].key]==AI.models[id][1])
    assert(saved_settings[id.."_thinking"]=="on" and saved_settings[id.."_reasoning_effort"]=="low")
end
assert(saved_settings.deepseek_api_key=="synthetic-secret")
print("NATIVE_AI_SETTINGS_PASS")

-- Every discovery request is redirected to the local synthetic TLS service;
-- no real keys or provider requests. Exercise native LuaSec, fork, cancellation
-- and a paginated native menu with exact model identifiers.
local Catalog=require("model_catalog")
local Browser=require("model_browser")
local https=require("ssl.https")
local native_request=https.request
local catalog_provider,slow
https.request=function(options)
    assert(options.method=="GET")
    options.url=config.provider.."/catalog/"..catalog_provider..(slow and "?slow=1" or "")
    return native_request(options)
end
for _,id in ipairs({"deepseek","gemini","openai","dashscope","openrouter"}) do
    catalog_provider=id
    local job=assert(Catalog.launch({[id.."_api_key"]="synthetic"},id,"text"))
    local result
    run_until(function() result=job:poll(UI); return result~=nil end)
    assert(result.models and #result.models==1,result.error)
end
catalog_provider="deepseek"
local catalog_cfg={deepseek_api_key="synthetic",deepseek_model="my-custom-model"}
local chosen_count=0
local browser=Browser.new {provider="deepseek",category="text",name="DeepSeek",field=AI.fields.deepseek,
    config=function() return catalog_cfg end,
    select=function(value) catalog_cfg.deepseek_model=value; chosen_count=chosen_count+1; return true end,
    edit=function() error("Manual entry is covered in the settings regression") end}
browser:load()
run_until(function() return browser.job==nil and #tasks==0 end)
assert(browser.models and browser.models[1]=="deepseek-synthetic" and chosen_count==0)
local TouchMenu=require("ui/widget/touchmenu")
browser.items.icon="appbar.settings"
local selector=TouchMenu:new {tab_item_table={browser.items},width=screen:getWidth()}
UI:show(selector)
item(browser.items,"deepseek-synthetic").callback(selector)
assert(chosen_count==1 and catalog_cfg.deepseek_model=="deepseek-synthetic")
browser.query="missing-model"; browser:render()
assert(item(browser.items,"Sin resultados"))
UI:close(selector); browser.menu=nil
slow=true
browser:load(); local loading=visible
UI:scheduleIn(0.25,function() UI:close(loading) end)
run_until(function() return browser.job==nil and #tasks==0 end)
assert(chosen_count==1 and catalog_cfg.deepseek_model=="deepseek-synthetic")
https.request=native_request
print("NATIVE_MODEL_CATALOG_PASS")
doc:close()
screen.bb:free()
print("NATIVE_CANCELLATION_PASS")

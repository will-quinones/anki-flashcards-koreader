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
doc:close()
screen.bb:free()
print("NATIVE_CANCELLATION_PASS")

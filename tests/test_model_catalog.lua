package.path="AnkiFlashcards.koplugin/?.lua;"..package.path
local Catalog=require("model_catalog")
local objects, serial, requests, responses, timeout= {},0,{}, {},15
package.loaded.json={encode=function(value) serial=serial+1; objects[tostring(serial)]=value; return tostring(serial) end,
    decode=function(raw) return assert(objects[raw],"Invalid JSON") end}
local json=package.loaded.json
local transport={TIMEOUT=99,request=function(options)
    requests[#requests+1]=options
    assert(options.method=="GET" and options.source==nil and options.redirect==false)
    assert(not options.url:find("synthetic-secret",1,true))
    local headers=options.headers
    assert(headers["x-goog-api-key"]=="synthetic-secret" or headers.Authorization=="Bearer synthetic-secret")
    local response=assert(table.remove(responses,1),"Unexpected network request")
    local chunk=response.raw or json.encode(response.data)
    local ok,err=options.sink(chunk); options.sink(nil)
    return ok,ok and (response.status or 200) or err
end}
package.loaded["ssl.https"]=transport
local function run(provider,category,pages,cfg)
    requests,responses={},pages
    cfg=cfg or {[provider.."_api_key"]="synthetic-secret"}
    local models,err=Catalog.fetch(cfg,provider,category or "text")
    assert(transport.TIMEOUT==99)
    return models,err
end
local models=assert(run("deepseek","text",{{data={data={{id="deepseek-v4-pro"},{id="deepseek-flash"},{id="deepseek-flash"},
    {id="../bad"},{id="bad model"},{id="bad\nmodel"},{id="a//b"},{id={}},false}}}}))
assert(#models==2 and models[1]=="deepseek-flash")
models=assert(run("gemini","text",{
    {data={models={{name="models/gemini-fast",supportedGenerationMethods={"generateContent"}},
        {name="models/embed",supportedGenerationMethods={"embedContent"}},
        {name="models/gemini-fast-tts",supportedGenerationMethods={"generateContent"}}},nextPageToken="a+b /?"}},
    {data={models={{name="models/gemini-pro",supportedGenerationMethods={"generateContent"}}}}},
}))
assert(#models==2 and #requests==2 and requests[2].url:find("pageToken=a%2Bb%20%2F%3F",1,true))
local image={name="models/gemini-flash-image",supportedGenerationMethods={"generateContent"}}
models=assert(run("gemini","image",{{data={models={image}}}})); assert(models[1]=="gemini-flash-image")
local text={id="vendor/text:free",architecture={input_modalities={"text"},output_modalities={"text"}}}
local visual={id="vendor/image",architecture={input_modalities={"text"},output_modalities={"image"}}}
models=assert(run("openrouter","text",{{data={data={text,visual,{id="unknown"}}}}})); assert(#models==1 and models[1]==text.id)
models=assert(run("openrouter","image",{{data={data={text,visual}}}})); assert(#models==1 and models[1]==visual.id)
models=assert(run("openai","text",{{data={data={{id="gpt-6-sol"},{id="ft:gpt-custom:org:name"},{id="text-embedding-3"},
    {id="gpt-audio"},{id="gpt-realtime"},{id="gpt-image-1.5"},{id="gpt-5-codex"},{id="o3"}}}}}))
assert(#models==3)
models=assert(run("openai","image",{{data={data={{id="gpt-image-1.5"},{id="gpt-6-sol"}}}}})); assert(#models==1)
models=assert(run("dashscope","text",{
    {data={output={models={{model="qwen-plus",capabilities={"TG"}},{model="qwen-audio",capabilities={"TTS"}}},total=3}}},
    {data={output={models={{model="qwen-reasoner",inference_metadata={response_modality={"Text"}}}},total=3}}},
},{api_key="synthetic-secret",provider="https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"}))
assert(#models==2 and #requests==2 and requests[2].url:find("page_no=2",1,true))
models=assert(run("dashscope","image",{{data={output={models={{model="qwen-image-plus"},{model="wan-image"}},total=2}}}}))
assert(#models==1 and models[1]=="qwen-image-plus")
assert(not Catalog.endpoint({provider="http://unrecognized/chat"},"dashscope"))
assert(Catalog.identity({deepseek_api_key="one"},"deepseek")~=Catalog.identity({deepseek_api_key="two"},"deepseek"))
local err
for _,status in ipairs({301,400,401,403,429,500}) do
    models,err=run("deepseek","text",{{status=status,raw="synthetic-secret"}})
    assert(not models and not err:find("synthetic-secret",1,true))
end
for _,page in ipairs({{raw="invalid"},{data={error={message="synthetic-secret"}}},{data={data="invalid"}},
    {raw=string.rep("x",8*1024*1024+1)}}) do assert(not run("deepseek","text",{page})) end
assert(not run("gemini","text",{{data={models={},nextPageToken="loop"}},{data={models={},nextPageToken="loop"}}}))
assert(not run("dashscope","text",{{data={output={models={},total=1}}}}))
assert(not run("deepseek","text",{},{}))
assert(not run("deepseek","text",{},{deepseek_api_key="key\ninjected"}))
local many={}; for i=1,5000 do many[#many+1]="provider/model-"..i..":free" end
assert(#Catalog.filter(many,"MODEL-4999 :free")==1 and #many==5000)
assert(#Catalog.filter({"vendor/PRO","vendor/pro:free","else/PRO:free"},"FREE vendor")==1)
assert(#Catalog.filter(many,"[]*?")==0 and #Catalog.filter(many," \t")==5000)

-- Real worker lifecycle with simulated fork/filesystem: cancellation, timeout,
-- crash, safe errors and failed writes. No keys in job snapshots or files.
local files,execute,done,kills,clock={},nil,false,0,100
local util={runInSubProcess=function(fn) execute=fn; return 123 end,
    isSubProcessDone=function() return done end,terminateSubProcess=function() kills=kills+1; done=true end}
package.loaded["ffi/util"]=util
package.loaded.storage_paths={runtime="/fake",initialize=function() return true end}
local original={open=io.open,remove=os.remove,rename=os.rename,time=os.time,fetch=Catalog.fetch}
local fail_write=false
io.open=function(path,mode)
    if mode=="r" then if not files[path] then return end; return {read=function() return files[path] end,close=function() return true end} end
    if fail_write then return nil end
    return {write=function(self,raw) files[path]=raw; return self end,close=function() return true end}
end
os.remove=function(path) files[path]=nil end
os.rename=function(a,b) files[b],files[a]=files[a],nil; return true end
os.time=function() return clock end
local UI={scheduleIn=function() error("Expected immediate reaping") end}
Catalog.fetch=function(cfg) assert(cfg.deepseek_api_key=="synthetic-secret"); return {"deepseek-flash"} end
local job=assert(Catalog.launch({deepseek_api_key="synthetic-secret"},"deepseek","text"))
assert(not job:poll(UI)); execute(); assert(not job:poll(UI)); done=true
assert(job:poll(UI).models[1]=="deepseek-flash" and next(files)==nil)
done=false; job=assert(Catalog.launch({},"deepseek","text")); job:cancel(UI); job:cancel(UI); assert(kills==1 and next(files)==nil)
done=false; job=assert(Catalog.launch({},"deepseek","text")); clock=clock+31
assert(job:poll(UI).error and kills==2 and next(files)==nil)
done=false; Catalog.fetch=function() error("synthetic-secret") end
job=assert(Catalog.launch({},"deepseek","text")); execute(); done=true
assert(not job:poll(UI).error:find("synthetic-secret",1,true) and next(files)==nil)
done=false; fail_write=true
job=assert(Catalog.launch({},"deepseek","text")); execute(); done=true; assert(job:poll(UI).error)
fail_write=false; done=false
job=assert(Catalog.launch({},"deepseek","text")); done=true; assert(job:poll(UI).error)
io.open,os.remove,os.rename,os.time,Catalog.fetch=original.open,original.remove,original.rename,original.time,original.fetch
print("PASS: five read-only catalogs, modality filtering, pagination, bounded parsing, local search and cancellable private workers")

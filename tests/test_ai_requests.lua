package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local AI = require("ai_configuration")
local objects, serial, request, provider = {}, 0, nil, nil
local card={phrase="action",definition="A synthetic act.",text="Take {{c1::action}}."}
local learning={question="What is the synthetic fact?",answer="The fact.",evidence="Synthetic evidence."}
local response_card=card
package.loaded.json = {encode=function(value)
    serial=serial+1; local key="OBJ"..serial; objects[key]=value; return key
end, decode=function(raw)
    if objects[raw] then return objects[raw] end
    if raw=="CARD" then return response_card end
    if raw=="EVENT" then return {choices={{delta={content="CARD"}}}} end
    if raw=="RESPONSE" then
        if provider=="gemini" then return {candidates={{content={parts={{thought=true,text="HIDDEN_REASONING"},{text="CARD"}}}}}} end
        return {choices={{message={content="CARD"}}}}
    end
    error("Invalid fixture")
end}
package.loaded.ltn12={source={string=function(value) return value end},sink={table=function(out)
    return function(value) if value then out[#out+1]=value end; return 1 end
end}}
local transport={request=function(options)
    request={body=objects[options.source],url=options.url}
    if request.body.stream then
        assert(options.sink("data: EVENT\n\n")); assert(options.sink("data: [DONE]\n\n"))
    else options.sink("RESPONSE") end
    options.sink(nil); return 1,200,{}
end}
package.loaded["ssl.https"],package.loaded["socket.http"]=transport,transport
local Generator=require("card_generator")
local cases={
    {"deepseek","deepseek-flash","on","low"},
    {"openai","gpt-6-sol","on","max"},
    {"openrouter","anthropic/claude-sonnet-5.5","on","medium"},
    {"gemini","gemini-3.8-flash","on","high"},
    {"dashscope","qwen3.8-flash","on","low"},
    {"dashscope","qwen-plus","on","medium"},
}
for _,case in ipairs(cases) do
    provider=case[1]
    local cfg={text_provider=provider,images_enabled=false,[AI.fields[provider].key]=case[2],
        [provider.."_api_key"]="synthetic",[provider.."_thinking"]=case[3],[provider.."_reasoning_effort"]=case[4]}
    local function verify()
        local body=request.body
        if provider=="deepseek" then assert(body.thinking.type=="enabled" and body.reasoning_effort=="low")
        elseif provider=="openai" then assert(body.reasoning_effort=="max" and not body.thinking)
        elseif provider=="openrouter" then assert(body.reasoning.effort=="medium" and body.reasoning.exclude)
        elseif provider=="gemini" then assert(body.generationConfig.thinkingConfig.thinkingLevel=="high")
        elseif case[2]=="qwen-plus" then assert(body.enable_thinking and body.thinking_budget==4096 and body.stream)
        else assert(body.enable_thinking and body.reasoning_effort=="low" and body.stream and not body.thinking_budget) end
    end
    response_card=card
    local generated,err=Generator.generate(cfg,"action","Synthetic evidence.","book","author")
    assert(generated,err); verify()
    if provider~="gemini" then assert(request.body.model==case[2]) end
    response_card=learning
    local learned,reason=Generator.generate_learning(cfg,{selected="Synthetic evidence.",context="Synthetic evidence.",title="book",author="author"})
    assert(learned,reason); verify()
    assert(learned.answer=="The fact.")
    response_card=card
    assert(Generator.generate_text(cfg,"action")); verify()
end
provider="deepseek"
local cfg={text_provider=provider,deepseek_api_key="synthetic",deepseek_thinking="off",deepseek_reasoning_effort="max"}
assert(Generator.generate(cfg,"action","","",""))
assert(request.body.thinking.type=="disabled" and not request.body.reasoning_effort)
provider="openai"
assert(Generator.generate({text_provider=provider,openai_api_key="synthetic"},"action","","",""))
assert(not request.body.reasoning_effort and not request.body.thinking and not request.body.reasoning)
print("PASS: actual generation paths send compatible reasoning controls for Vocab, Learn and sentence regeneration")

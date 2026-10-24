"""Streaming transport tests: arbitrary chunk boundaries, real JSON fixtures, no network."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def lua(value):
    if isinstance(value, str):
        return "[====[" + value + "]====]"
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "{" + ",".join(lua(v) for v in value) + "}"
    return "{" + ",".join("[ " + lua(k) + " ]=" + lua(v) for k, v in value.items()) + "}"


def run(script):
    result = subprocess.run(["luajit", "-"], input=script, text=True, capture_output=True, cwd=ROOT)
    assert result.returncode == 0, result.stdout + result.stderr


def test_streaming_transport_and_partial_card_fields():
    card = {"phrase": "acción", "ipa": "acción", "definition": 'Una "acción" rápida 😀',
            "synonyms": "acto", "text": "Haz una {{c1::acción}}."}
    raw = json.dumps(card, ensure_ascii=False)
    deltas = [raw[:18], raw[18:45], raw[45:70], raw[70:]]
    frames, gemini = [], []
    fixtures = {raw: card}
    for delta in deltas:
        data = {"choices": [{"delta": {"content": delta}}]}
        encoded = json.dumps(data, ensure_ascii=False)
        fixtures[encoded] = data
        frames.append("data: " + encoded + "\r\n\r\n")
        data = {"candidates": [{"content": {"parts": [{"thought": True, "text": "hidden"}, {"text": delta}]}}]}
        encoded = json.dumps(data, ensure_ascii=False)
        fixtures[encoded] = data
        gemini.append("data: " + encoded + "\n\n")
    # Each partial field string accepted by a real JSON decoder is available to
    # the Lua test double; invalid/truncated escapes still raise a decode error.
    for value in card.values():
        encoded = json.dumps(value, ensure_ascii=False)
        for i in range(1, len(encoded)):
            candidate = encoded[:i] + '"'
            try:
                fixtures[candidate] = json.loads(candidate)
            except ValueError:
                pass
    complete = {"choices": [{"message": {"content": raw}}]}
    fixtures["NONSTREAM"] = complete
    error = {"error": {"code": 503, "message": "overloaded"}}
    fixtures[json.dumps(error)] = error
    script = """
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local fixtures = FIXTURES
local payload
package.loaded.json = {encode = function(value) payload = value; return "BODY" end,
    decode = function(raw) if fixtures[raw] ~= nil then return fixtures[raw] end; error("invalid JSON") end}
local Stream = require("text_stream")
local encoded = RAW
for _, provider in ipairs({"openai", "gemini"}) do
    local bytes = provider == "gemini" and GEMINI or OPENAI
    for cut = 1, #bytes do
        local progress = {}
        local stream = Stream.new(provider, function(text) progress[#progress+1] = text end)
        assert(stream:sink(bytes:sub(1, cut)))
        assert(stream:sink(bytes:sub(cut+1)))
        stream:sink(nil); stream:sink(nil)
        assert(not stream.error and stream.text == encoded and #progress == 4, tostring(cut))
    end
    local stream = Stream.new(provider, function() end)
    for i = 1, #bytes do assert(stream:sink(bytes:sub(i,i))) end
    stream:sink(nil)
    assert(stream.text == encoded)
end
for i = 1, #encoded do
    local card = Stream.preview(encoded:sub(1,i))
    for key,value in pairs(card) do assert(type(value) == "string") end
end
local preview = Stream.preview(encoded)
assert(preview.phrase == "acción" and preview.definition == 'Una "acción" rápida 😀')
local request, response = nil, OPENAI
package.loaded.ltn12 = {source = {string = function(s) return s end}, sink = {table = function(t)
    return function(s) if s then t[#t+1] = s end; return 1 end end}}
local chunks, called_early = 0, false
local transport = {request = function(options)
    request = options
    for i = 1, #response do chunks = i; options.sink(response:sub(i,i)) end
    options.sink(nil)
    return 1, 200, {}
end}
package.loaded["ssl.https"], package.loaded["socket.http"] = transport, transport
local Generator = require("card_generator")
for _, provider in ipairs({"openai", "openrouter", "deepseek", "dashscope", "gemini"}) do
    response = provider == "gemini" and GEMINI or OPENAI
    local config = {text_provider = provider, images_enabled = false}
    config[provider .. "_api_key"] = "synthetic"
    called_early = false
    local result, err = Generator.generate(config, "acción", "context", "book", "author", function(raw)
        if chunks < #response then called_early = true end
    end)
    assert(result and result.definition == preview.definition, err)
    assert(called_early)
    assert(transport.TIMEOUT == 45)
    if provider == "gemini" then assert(request.url:find(":streamGenerateContent?alt=sse", 1, true))
    else assert(payload.stream == true) end
end
response = "NONSTREAM"
assert(Generator.generate({text_provider="openai",openai_api_key="key"}, "word", "", "", "", function() end))
assert(Generator.generate({text_provider="openai",openai_api_key="key"}, "word", "", "", ""))
assert(transport.TIMEOUT == 20) -- Nonstream requests retain their existing timeout.
local stream = Stream.new("openai", function() error("error envelope must never appear as card text") end)
stream:sink(ERROR_FRAME); stream:sink(nil)
assert(stream.error and stream.details.retryable)
print("PASS: streaming across arbitrary byte boundaries, provider payloads, Unicode, partial JSON, fallback and safe errors")
"""
    substitutions = {"FIXTURES": lua(fixtures), "RAW": lua(raw),
                     "OPENAI": lua(": heartbeat\r\n\r\n" + "".join(frames) + "data: [DONE]\r\n\r\n"),
                     "GEMINI": lua("".join(gemini)),
                     "ERROR_FRAME": lua("data: " + json.dumps(error) + "\n\n")}
    # Replace markers once, before inserted fixture strings can be mistaken for markers.
    import re
    script = re.sub("|".join(substitutions), lambda m: substitutions[m.group()], script)
    run(script)


def test_stream_limits_count_card_text_separately_from_sse_metadata():
    card = {"phrase": "action", "definition": "A synthetic act.", "text": "Take {{c1::action}}."}
    raw = json.dumps(card)
    reasoning = {"id": "s" * 40, "object": "chat.completion.chunk", "created": 100,
                 "model": "synthetic", "system_fingerprint": "f" * 60,
                 "choices": [{"index": 0, "delta": {"content": None,
                              "reasoning_content": "HIDDEN_REASONING " * 8}, "finish_reason": None}]}
    content = {"choices": [{"delta": {"content": raw}}]}
    oversized = {"choices": [{"delta": {"content": "x" * 140000}}]}
    error = {"error": {"code": 503, "message": "overloaded synthetic-secret"}}
    fixtures = {raw: card}
    for value in (reasoning, content, oversized, error):
        fixtures[json.dumps(value)] = value
    script = """
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local fixtures = FIXTURES
package.loaded.json = {encode = function() return "BODY" end,
    decode = function(raw) assert(fixtures[raw], "Invalid synthetic JSON"); return fixtures[raw] end}
local Stream = require("text_stream")
local progress = {}
local stream = Stream.new("deepseek", function(text) progress[#progress+1] = text end)
for i = 1, 700 do assert(stream:sink(REASONING)) end
assert(stream.bytes > 262144 and #stream.text == 0 and #progress == 0)
assert(stream:sink(CONTENT)); assert(stream:sink("data: [DONE]\\n\\n"))
assert(stream:sink(nil) and stream.done and stream.text == RAW and #progress == 1)
assert(stream.buffer == "")

-- A missing frame delimiter, a huge card and unbounded wire traffic still stop.
local bounded = Stream.new("deepseek", function() end)
local ok, err = bounded:sink(string.rep("x", 262145))
assert(not ok and err:find("frame too large", 1, true) and #bounded.text == 0)
bounded = Stream.new("deepseek", function() end)
assert(bounded:sink(OVERSIZED))
ok, err = bounded:sink(OVERSIZED)
assert(not ok and err:find("text too large", 1, true) and #bounded.text == 140000)
bounded = Stream.new("deepseek", function() end)
for i = 1, 9000 do
    ok, err = bounded:sink(":" .. string.rep("x", 1021) .. "\\n\\n")
    if not ok then break end
end
assert(not ok and err == "Streaming response too large" and #bounded.text == 0)

local mode = "metadata"
package.loaded.ltn12 = {source = {string = function(s) return s end}, sink = {table = function(t)
    return function(s) if s then t[#t+1] = s end; return 1 end end}}
local transport = {request = function(options)
    if mode == "metadata" then
        for i = 1, 700 do
            local accepted, reason = options.sink(REASONING)
            if not accepted then return nil, reason end
        end
        assert(options.sink(CONTENT)); assert(options.sink("data: [DONE]\\n\\n"))
        assert(options.sink(nil)); return 1, 200, {}
    end
    local accepted, reason = options.sink(mode == "provider_error" and ERROR_FRAME or string.rep("x", 262145))
    assert(not accepted)
    return nil, reason -- LuaSocket reports the sink error instead of an HTTP status.
end}
package.loaded["ssl.https"], package.loaded["socket.http"] = transport, transport
local Generator = require("card_generator")
local Feedback = require("generation_feedback")
local config = {text_provider="deepseek", deepseek_api_key="synthetic", images_enabled=false}
local result, reason = Generator.generate(config, "action", "synthetic", "book", "author", function() end)
assert(result and result.definition == "A synthetic act.", reason)
mode = "limit"
local details
result, reason, details = Generator.generate(config, "action", "", "", "", function() end)
assert(not result and reason:find("frame too large", 1, true))
assert(Feedback.classify(reason, details).kind == "invalid")
assert(not Feedback.classify(reason, details).retryable)
mode = "provider_error"
result, reason, details = Generator.generate(config, "action", "", "", "", function() end)
assert(not result and details.kind == "busy" and details.status == 503 and details.retryable)
assert(not reason:find("synthetic-secret", 1, true))
print("PASS: realistic SSE overhead permits a small card; local bounds and API errors retain their real cause")
"""
    substitutions = {"FIXTURES": lua(fixtures), "RAW": lua(raw),
                     "REASONING": lua("data: " + json.dumps(reasoning) + "\n\n"),
                     "CONTENT": lua("data: " + json.dumps(content) + "\n\n"),
                     "OVERSIZED": lua("data: " + json.dumps(oversized) + "\n\n"),
                     "ERROR_FRAME": lua("data: " + json.dumps(error) + "\n\n")}
    import re
    script = re.sub("|".join(substitutions), lambda m: substitutions[m.group()], script)
    run(script)

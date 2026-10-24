-- luajit tests/test_generation_feedback.lua: bounded retries, no real requests.
local diagnostics = {}
package.loaded.logger = {info = function(...)
    local values = {...}
    for i, value in ipairs(values) do values[i] = tostring(value) end
    diagnostics[#diagnostics+1] = table.concat(values, " ")
end}
local Feedback = dofile("AnkiFlashcards.koplugin/generation_feedback.lua")
local queue, shown, delays = {}, {}, {}
package.loaded["ui/uimanager"] = {
    scheduleIn = function(_, delay, fn) delays[#delays+1] = delay; queue[#queue+1] = fn end,
    show = function(_, widget) shown[#shown+1] = widget end, close = function() end,
}
package.loaded["ui/widget/notification"] = {new = function(_, spec) spec.kind = "busy"; return spec end}
package.loaded["ui/widget/infomessage"] = {new = function(_, spec) spec.kind = "error"; return spec end}
local function drain() while #queue > 0 do table.remove(queue, 1)() end end
local function reset() queue, shown, delays = {}, {}, {} end
local calls, successes = 0, 0
Feedback.run(function()
    calls = calls + 1
    if calls == 1 then return Feedback.http_error(503, '{"message":"overloaded private-key"}', {['retry-after'] = '2'}) end
    return {phrase = "ready"}
end, function() successes = successes + 1 end)
drain()
assert(calls == 2 and successes == 1 and #shown == 3)
assert(shown[1].text == Feedback.GENERATING and shown[2].text == Feedback.RETRYING and delays[2] == 2)
for _, widget in ipairs(shown) do assert(#widget.text < 70 and not widget.text:find("private-key", 1, true)) end
reset(); calls = 0
Feedback.run(function() calls = calls + 1; return Feedback.http_error(503, "overloaded private-key") end,
    function() error("Must fail") end)
drain()
assert(calls == 2 and shown[#shown].kind == "error" and shown[#shown].text:find("saturado", 1, true))
assert(not shown[#shown].text:find("private-key", 1, true))
print("PASS: short shared Spanish statuses and one bounded retry for saturation")

for _, case in ipairs({
    {429, "rate limited", {['retry-after'] = '60'}, "rate_limit"},
    {429, '{"retryDelay":"60s"}', {}, "rate_limit"},
    {429, "insufficient_quota", {}, "quota"},
    {429, '"limit": 0', {}, "quota"},
    {401, "private-key", {}, "auth"}, {403, "forbidden", {}, "auth"},
    {404, "missing model", {}, "model"}, {402, "no credits", {}, "quota"},
}) do
    reset(); calls = 0
    local failure
    Feedback.run(function() calls = calls + 1; return Feedback.http_error(case[1], case[2], case[3]) end,
        function() error("Must fail") end, function(_, info) failure = info end)
    drain()
    assert(calls == 1 and failure.kind == case[4])
    for _, delay in ipairs(delays) do assert(delay < 1) end
end
print("PASS: quota/auth/model errors are not retried; long Retry-After is respected without freezing")

reset()
local failed
Feedback.run(function() error("private-key in internal exception") end, function() error("Must fail") end,
    function(_, info) failed = info end, {quiet = true})
drain()
assert(failed.kind == "unknown" and #shown == 1)
local result, reason = Feedback.request({request = function() error("private-key") end}, {})
assert(result == nil and reason == "request_failed")
Feedback.request({request = function() return nil, "wantread private-key" end}, {})
Feedback.request({request = function() error("text_stream.lua:37: private-key", 0) end}, {})
assert(diagnostics[#diagnostics]:find("exception unknown text_stream.lua:37", 1, true))
assert(diagnostics[#diagnostics-1]:find("failure wantread", 1, true))
for _, line in ipairs(diagnostics) do assert(not line:find("private-key", 1, true)) end
local _, _, embedded = Feedback.response_error({error = {type = "overloaded_error"}}, "at capacity", {})
assert(embedded.kind == "busy" and embedded.retryable)
assert(not Feedback.classify("Gemini error: https://example.com?key=private-key").message:find("private-key", 1, true))
assert(Feedback.image_message("Gemini API key not configured"):find("Extras", 1, true))
print("PASS: transport/embedded provider errors are safe; batch mode can handle failures without popup spam")

for _, code in ipairs({"wantread", "wantwrite", "unexpected eof while reading", "invalid transport private-key", false, 0}) do
    reset(); calls = 0
    Feedback.run(function()
        calls = calls + 1
        if calls == 1 then return Feedback.http_error(code, "private-key response body") end
        return {phrase = "ready"}
    end, function() end)
    drain()
    assert(calls == 2, "transport failures must get one bounded retry")
    local _, _, info = Feedback.http_error(code, "private-key response body")
    assert(info.kind == "network" and info.transport_error and info.retryable and not info.status)
    assert(not info.message:find("private-key", 1, true))
end
local _, _, timeout = Feedback.http_error("timeout", "private-key")
assert(timeout.kind == "timeout" and timeout.transport_error and timeout.retryable)
local _, _, missing = Feedback.http_error(nil, "private-key")
assert(missing.kind == "network" and missing.transport_error and missing.retryable)
print("PASS: non-HTTP transport errors retry once and never expose private data")

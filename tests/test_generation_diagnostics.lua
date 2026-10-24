-- Diagnostics must never include credentials, prompts, generated text or errors.
local logs = {}
package.loaded.logger = {info = function(...)
    local values = {...}
    for i, value in ipairs(values) do values[i] = tostring(value) end
    logs[#logs+1] = table.concat(values, " ")
end}
dofile("tests/test_generation_worker.lua")
assert(#logs > 0)
for _, line in ipairs(logs) do
    assert(not line:find("synthetic-secret", 1, true))
    assert(not line:find("meaning", 1, true))
    assert(not line:find("api_key", 1, true))
end
dofile("tests/test_vocab_generation.lua")
for _, line in ipairs(logs) do
    assert(not line:find("partial", 1, true))
    assert(not line:find("safe error", 1, true))
end
print("PASS: generation diagnostics record lifecycle stages without private data")

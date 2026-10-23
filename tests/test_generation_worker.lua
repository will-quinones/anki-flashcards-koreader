package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local function clone(v)
    if type(v) ~= "table" then return v end
    local result = {}; for k,x in pairs(v) do result[k] = clone(x) end; return result
end
local blobs, files, serial = {}, {}, 0
package.loaded.json = {encode = function(v) serial = serial+1; blobs[tostring(serial)] = clone(v); return tostring(serial) end,
    decode = function(s) assert(blobs[s]); return clone(blobs[s]) end}
package.loaded.storage_paths = {runtime = "/fake", initialize = function() return true end}
local execute, done, kills, pid, clock = nil, false, 0, 123, 100
package.loaded["ffi/util"] = {
    runInSubProcess = function(fn) execute = fn; return pid end,
    isSubProcessDone = function() return done end,
    terminateSubProcess = function() kills = kills+1; done = true end,
    gettime = function() clock = clock+1; return clock end,
}
local real_open, real_remove, real_rename, real_time = io.open, os.remove, os.rename, os.time
io.open = function(path, mode)
    if mode == "r" then
        if not files[path] then return nil end
        return {read = function() return files[path] end, close = function() return true end}
    end
    return {write = function(self, bytes) files[path] = bytes; return self end, close = function() return true end}
end
os.remove = function(path) files[path] = nil; return true end
os.rename = function(a,b) files[b], files[a] = files[a], nil; return true end
os.time = function() return clock end
local UI = {scheduleIn = function() error("Already reaped") end}
package.loaded["ui/uimanager"] = UI
local Worker = require("generation_worker")
local requests, progress_seen = 0, false
local job
package.loaded.card_generator = {generate = function(config, phrase, context, title, author, progress)
    requests = requests+1
    assert(config.api_key == "synthetic-secret" and phrase == "word")
    progress('{"phrase":"word"')
    assert(job:poll().kind == "progress") -- visible before request completes
    progress_seen = true
    return {phrase = "word", definition = "meaning"}
end}
job = assert(Worker.launch({api_key = "synthetic-secret"}, {phrase = "word"}))
assert(requests == 0 and not job:poll())
execute(); assert(progress_seen and requests == 1)
assert(not job:poll()) -- terminal result waits for child reaping
done = true
assert(job:poll().card.definition == "meaning" and next(files) == nil)
for _, value in pairs(blobs) do assert(not value.api_key and not value.config) end
done = false
job = assert(Worker.launch({}, {})); job:cancel(UI)
assert(kills == 1 and next(files) == nil)
job:cancel(UI); assert(kills == 1)
done = false
package.loaded.card_generator.generate = function() error("synthetic-secret") end
job = assert(Worker.launch({}, {})); execute(); done = true
local event = job:poll()
assert(event.kind == "error" and not event.info.message:find("synthetic-secret", 1, true))
done = false
job = assert(Worker.launch({}, {})); clock = clock+91
assert(job:poll().info.kind == "timeout" and kills == 2 and next(files) == nil)
pid = nil
assert(not Worker.launch({}, {}))
io.open, os.remove, os.rename, os.time = real_open, real_remove, real_rename, real_time
print("PASS: worker exposes progress before completion, isolates requests/keys, reaps children, cancels and times out safely")

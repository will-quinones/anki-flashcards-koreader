package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local execute, probe_ok, profile_ok, send_ok, source_ok, sends, persisted, barrier
local blobs, serial, files = {}, 0, {}
local function clone(v)
    if type(v) ~= "table" then return v end
    local t = {}; for k,x in pairs(v) do t[k] = clone(x) end; return t
end
package.loaded.json = {encode = function(value) serial = serial + 1; blobs[tostring(serial)] = clone(value); return tostring(serial) end,
    decode = function(bytes) assert(blobs[bytes]); return clone(blobs[bytes]) end}
package.loaded.storage_paths = {runtime = "/private/runtime", initialize = function() return true end}
package.loaded.anki_sync = {
    test_connection = function() return probe_ok end,
    read = function() return profile_ok and "Profile" or nil end,
    send_card = function(_, _, _, options)
        sends = sends + 1
        assert(options.defer_persistence)
        if not options.defer_persistence then persisted = persisted + 1 end
        return send_ok, nil, send_ok and {note_id = 42, deck = "Deck", model = "KOReader Vocabulary"} or nil
    end,
    source_identity = function() return source_ok and {profile = "Profile", vocabulary_id = 1} or nil end,
}
local done, killed, forked = false, 0, 0
package.loaded["ffi/util"] = {
    runInSubProcess = function(fn) forked = forked + 1; execute = fn; return 123 end,
    isSubProcessDone = function() return done end,
    terminateSubProcess = function() killed = killed + 1; done = true end,
}
local open, rename, remove = io.open, os.rename, os.remove
io.open = function(path, mode)
    if mode == "r" then
        if not files[path] then return nil, "not found", 2 end
        return {read = function() return files[path] end, close = function() return true end}
    end
    return {write = function(self, bytes) files[path] = bytes; return self end, close = function() return true end}
end
os.rename = function(from,to) files[to], files[from] = files[from], nil; return true end
os.remove = function(path) if not files[path] then return nil end; files[path] = nil; return true end
local Worker = require("background_send")
local card = {phrase = "word"}
probe_ok, profile_ok, send_ok, source_ok, sends, persisted = false, true, true, true, 0, 0
local job = assert(Worker.launch({url = "http://synthetic.invalid"}, card, {api_key = "test-secret-not-for-journal"}))
assert(forked == 1 and sends == 0 and not job:poll())
for _, bytes in pairs(files) do assert(blobs[bytes].api_key == nil) end
local pending = Worker.recover()
assert(pending.card.phrase == "word" and not pending.config and not pending.base)
execute(); done = true
assert(job:poll().result.kind == "offline" and sends == 0)
assert(Worker.clear())
probe_ok = true
barrier = false
local result = Worker.execute({}, card, {}, function() barrier = true; return true end)
assert(barrier and result.kind == "sent" and result.receipt.source.profile == "Profile" and sends == 1 and persisted == 0)
result = Worker.execute({}, card, {}, function() return false end)
assert(result.kind == "review" and sends == 1)
send_ok = false
assert(Worker.execute({}, card, {}).kind == "review")
send_ok, source_ok = true, false
assert(Worker.execute({}, card, {}).kind == "review")
source_ok = true
done = false
job = assert(Worker.launch({}, card, {})); execute(); done = true
assert(job:poll().result.kind == "sent")
-- A separate instance sees the receipt after exit/restart, without network.
package.loaded.background_send = nil
local restarted = require("background_send")
local intent, saved = restarted.recover()
assert(intent and saved.kind == "sent" and saved.receipt.note_id == 42)
assert(restarted.clear())
done = false
job = assert(restarted.launch({}, card, {}))
job:cancel({scheduleIn = function() error("Already reaped") end})
assert(killed == 1 and restarted.recover() == nil) -- Killed before the write barrier: safe to retry later.
io.open, os.rename, os.remove = open, rename, remove
print("PASS: real worker contract isolates network, persists no API configuration, journals receipts and safely handles cancellation/restart")

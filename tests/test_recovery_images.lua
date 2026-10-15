-- Media replacement/retry never overwrites an existing image file in place.
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in pairs(value) do out[k] = copy(v) end; return out
end
local files, blobs, serial, queue = {}, {}, 0, {}
local json = {encode = function(v) serial = serial + 1; local k = tostring(serial); blobs[k] = copy(v); return k end,
    decode = function(k) return copy(blobs[k]) end}
package.loaded.json = json
package.loaded.datastorage = {getDataDir = function() return "/fake" end}
package.loaded["ui/uimanager"] = {scheduleIn = function(_, _, fn) queue[#queue+1] = fn end}
package.loaded["libs/libkoreader-lfs"] = {attributes = function(path) return path == "/fake/.anki_images" and "directory" or files[path] end,
    mkdir = function() return true end}
package.loaded.mime = {unb64 = function(s) return s end}
local Storage = require("card_storage")
local media, downloads = {["a.png"] = "AAA", ["b.png"] = "BBB"}, 0
local note = {noteId = 1, modelName = "KOReader Vocabulary", cards = {100}, mod = 1, tags = {"KOReader"}, fields = {
    Phrase = {value = "palabra"}, Definition = {value = "Definición"}, ImageFront = {value = '<img src="a.png">'},
}}
package.loaded.anki_sync = {source_identity = function() return {profile = "Will", vocabulary_id = 100} end,
    read = function(_, action, params)
        if action == "findNotes" then return {1}
        elseif action == "notesInfo" then return {copy(note)}
        elseif action == "cardsInfo" then return {{deckName = "Libro"}}
        elseif action == "retrieveMediaFile" then downloads = downloads + 1; return media[params.filename] or false
        else error(action) end
    end}
local open, rename, remove = io.open, os.rename, os.remove
io.open = function(path, mode)
    if mode == "r" or mode == "rb" then
        if not files[path] then return nil end
        return {read = function() return files[path] end, close = function() return true end}
    end
    return {write = function(self, data) files[path] = data; return self end, close = function() return true end}
end
os.rename = function(from, to) files[to], files[from] = files[from], nil; return true end
os.remove = function(path) files[path] = nil end
local Import = require("anki_import")
local cfg = {url = "http://fake:8765"}
local function drain() while #queue > 0 do table.remove(queue, 1)() end end
local function scan() local r; Import.start(cfg, function(report) r = report end); drain(); return r end
local function apply(changes) local r; Import.apply_updates(cfg, changes, function(report) r = report end); drain(); return r end
assert(scan().imported == 1)
local first_path = Storage.find_by_anki_id(1).image_path
note.fields.ImageFront.value, note.mod = '<img src="b.png">', 2
local report = scan()
assert(report.changed == 1 and downloads == 1 and Storage.find_by_anki_id(1).image_path == first_path)
assert(apply(report.changes).updated == 1)
local second_path = Storage.find_by_anki_id(1).image_path
assert(second_path ~= first_path and files[first_path] == "AAA" and files[second_path] == "BBB")
assert(scan().changed == 0 and downloads == 2)
note.fields.ImageFront.value, note.mod = '<img src="c.png">', 3
report = scan()
assert(apply(report.changes).updated == 1)
local pending = Storage.find_by_anki_id(1)
assert(pending.image_path == second_path and pending.anki_image_pending)
media["c.png"] = "CCC"
assert(scan().changed == 0)
local recovered = Storage.find_by_anki_id(1)
assert(not recovered.anki_image_pending and files[recovered.image_path] == "CCC")
io.open, os.rename, os.remove = open, rename, remove
print("PASS: changed image references need confirmation, keep old media on failure and retry pending media safely")

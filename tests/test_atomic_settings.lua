-- In-memory filesystem: never writes actual keys or files.
package.loaded.datastorage = {getDataDir = function() return "/fake" end}
local encode_fail, write_fail, rename_fail = false, false, false
package.loaded.json = {encode = function()
    if encode_fail then error("encoding failure") end
    return "new-settings"
end}
local Storage = dofile("AnkiFlashcards.koplugin/card_storage.lua")
local file = "/fake/anki_flashcards_settings.json"
local files = {[file] = "original-settings"}
local open, rename, remove = io.open, os.rename, os.remove
io.open = function(path)
    files[path] = ""
    return {
        write = function(self, data)
            if write_fail then return nil, "disk full" end
            files[path] = data; return self
        end,
        close = function() return true end,
    }
end
os.rename = function(from, to)
    if rename_fail then return nil, "rename failed" end
    files[to], files[from] = files[from], nil
    return true
end
os.remove = function(path) files[path] = nil; return true end
encode_fail = true
assert(not Storage.save_anki_settings({}))
assert(files[file] == "original-settings")
encode_fail, write_fail = false, true
assert(not Storage.save_anki_settings({}))
assert(files[file] == "original-settings" and files[file .. ".tmp"] == nil)
write_fail, rename_fail = false, true
assert(not Storage.save_anki_settings({}))
assert(files[file] == "original-settings")
rename_fail = false
assert(Storage.save_anki_settings({}))
assert(files[file] == "new-settings" and files[file .. ".tmp"] == nil)
io.open, os.rename, os.remove = open, rename, remove
print("PASS: atomic saves preserve original settings on encoding, disk and rename failures")

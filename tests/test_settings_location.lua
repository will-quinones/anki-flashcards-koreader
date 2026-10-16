-- No actual settings or credentials are read or written.
package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local f = assert(io.open("AnkiFlashcards.koplugin/card_storage.lua", "r"))
local source = f:read("*all"); f:close()
local folder = "/external/My Plugin.koplugin/"
local path = folder .. "anki_flashcards_settings.json"
local legacy = "/data/anki_flashcards_settings.json"
local files, moves, encode_calls, rename_fail, denied = {}, 0, 0, false, false
local open, rename, remove = io.open, os.rename, os.remove
package.loaded.datastorage = {getDataDir = function() return "/data" end}
package.loaded.json = {
    decode = function(bytes)
        if bytes == "legacy-bytes\n" then return {url = "old-url", api_key = "test-secret", optional = false} end
        if bytes == "restored-bytes" then return {url = "restored-url", api_key = "restored-test-secret"} end
        error("invalid json")
    end,
    encode = function() encode_calls = encode_calls + 1; return "saved-bytes" end,
}
io.open = function(name, mode)
    if denied and name == path then return nil, "permission denied", 13 end
    if mode == "r" then
        if files[name] == nil then return nil, "not found", 2 end
        return {read = function() return files[name] end, close = function() return true end}
    end
    return {write = function(self, bytes) files[name] = bytes; return self end, close = function() return true end}
end
os.rename = function(from, to)
    moves = moves + 1
    if rename_fail then return nil, "read-only filesystem" end
    assert(files[from] ~= nil)
    files[to], files[from] = files[from], nil
    return true
end
os.remove = function(name) files[name] = nil; return true end
local Storage = assert(loadstring(source, "@" .. folder .. "card_storage.lua"))()
files[legacy] = "legacy-bytes\n"
local settings = assert(Storage.load_anki_settings())
assert(settings.api_key == "test-secret" and settings.optional == false)
assert(files[path] == "legacy-bytes\n" and files[legacy] == nil and moves == 1 and encode_calls == 0)
assert(Storage.load_anki_settings().url == "old-url" and moves == 1)
assert(Storage.save_anki_settings({}) and files[path] == "saved-bytes" and not files[legacy])
files[path], files[legacy] = "restored-bytes", "legacy-bytes\n"
assert(Storage.load_anki_settings().url == "restored-url" and moves == 2)
assert(files[legacy] == "legacy-bytes\n") -- Never discard a conflicting legacy file.
for _, bad in ipairs({"", "invalid"}) do
    files[path] = bad
    local data, err = Storage.load_anki_settings()
    assert(data == nil and err and Storage.settings_load_error and files[path] == bad and files[legacy])
end
files[path], denied = nil, true
assert(Storage.load_anki_settings() == nil and files[legacy] and moves == 2)
denied, rename_fail = false, true
settings = assert(Storage.load_anki_settings())
assert(settings.api_key == "test-secret" and files[legacy] and not files[path] and Storage.settings_migration_error)
rename_fail = false
assert(Storage.load_anki_settings().url == "old-url" and files[legacy] == nil and not Storage.settings_migration_error)
files[path], files[legacy] = nil, "invalid"
assert(Storage.load_anki_settings() == nil and files[legacy] == "invalid" and not files[path])
files[legacy] = nil
assert(Storage.load_anki_settings() == nil and not Storage.settings_load_error)
io.open, os.rename, os.remove = open, rename, remove
print("PASS: settings follow actual plugin folder; byte-preserving migration, restored-file precedence and safe failure handling")

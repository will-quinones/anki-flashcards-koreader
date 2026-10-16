package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local f = assert(io.open("AnkiFlashcards.koplugin/storage_paths.lua", "r"))
local source = f:read("*all"); f:close()
local fs, rename_fail, moves, separate_settings, cross_device, copy_fail
local open, rename, remove = io.open, os.rename, os.remove
package.loaded.datastorage = {getDataDir = function() return "/koreader" end,
    getSettingsDir = function() return separate_settings or "/koreader/settings" end}
local R = require("anki_recovery")
local card = {phrase = "word", image_path = "/koreader/.anki_images/a.png"}
card.anki_local_fingerprint = R.local_fingerprint(card)
package.loaded.json = {decode = function(bytes)
    if bytes == "cards" then
        local copy = {}; for k,v in pairs(card) do copy[k] = v end
        return {copy}
    end
    error("invalid json")
end}
package.loaded["libs/libkoreader-lfs"] = {
    attributes = function(path, attr)
        if not fs[path] then return nil end
        local mode = fs[path] == true and "directory" or "file"
        return attr == "mode" and mode or {mode = mode}
    end,
    mkdir = function(path) fs[path] = true; return true end,
}
io.open = function(path, mode)
    if mode == "wb" then
        return {write = function(self, bytes)
            if copy_fail then fs[path] = "partial"; return nil, "disk full" end
            fs[path] = bytes; return self
        end, close = function() return true end}
    end
    if type(fs[path]) ~= "string" then return nil, "not found", 2 end
    return {read = function() return fs[path] end, close = function() return true end}
end
os.rename = function(from, to)
    if cross_device == from then return nil, "different filesystem", 18 end
    if rename_fail == from then return nil, "disk failure" end
    assert(fs[from] ~= nil and fs[to] == nil)
    moves = moves + 1
    local children = {}
    for path,value in pairs(fs) do if path:sub(1,#from+1) == from .. "/" then children[path] = value end end
    fs[to], fs[from] = fs[from], nil
    for path,value in pairs(children) do fs[to .. path:sub(#from+1)], fs[path] = value, nil end
    return true
end
os.remove = function(path) fs[path] = nil; return true end
local function setup()
    fs = {["/"] = true, ["/koreader"] = true, ["/koreader/settings"] = true,
        ["/koreader/anki_flashcards.json"] = "cards", ["/koreader/anki_flashcards.json.sync"] = "baseline",
        ["/koreader/anki_flashcards.json.tmp"] = "partial", ["/koreader/.anki_images"] = true,
        ["/koreader/.anki_images/a.png"] = "image bytes", ["/tmp/anki_download.lua"] = "helper source"}
    moves, rename_fail, separate_settings, cross_device, copy_fail = 0, nil, nil, nil, false
    return assert(loadstring(source, "@AnkiFlashcards.koplugin/storage_paths.lua"))()
end
local Paths = setup()
assert(Paths.initialize())
assert(fs[Paths.cards] == "cards" and fs[Paths.cards .. ".sync"] == "baseline")
assert(fs[Paths.images .. "/a.png"] == "image bytes" and fs[Paths.runtime .. "/legacy-cards.tmp"] == "partial")
assert(fs[Paths.runtime .. "/anki_download.lua"] == "helper source")
assert(not fs[Paths.legacy_cards] and not fs[Paths.legacy_images] and not fs["/tmp/anki_download.lua"])
local before = moves
assert(Paths.initialize() and moves == before)
assert(Paths.resolve_image("/another/device/.anki_images/a.png") == Paths.images .. "/a.png")
assert(Paths.resolve_image("/another/device/settings/ankiflashcards/images/a.png") == Paths.images .. "/a.png")
assert(Paths.resolve_image("/unrelated/a.png") == "/unrelated/a.png")
assert(Paths.resolve_image("/koreader/.anki_images/missing.png") == "/koreader/.anki_images/missing.png")
package.loaded.storage_paths = Paths
package.loaded.card_storage = nil
local Storage = require("card_storage")
local loaded = Storage.load_cards()[1]
assert(loaded.image_path == Paths.images .. "/a.png" and loaded.anki_local_fingerprint == R.local_fingerprint(loaded))
assert(fs[Paths.cards] == "cards") -- Reading never rewrites content or drops fields.
card.definition = "a genuine local edit"
loaded = Storage.load_cards()[1]
assert(loaded.anki_local_fingerprint == card.anki_local_fingerprint and loaded.anki_local_fingerprint ~= R.local_fingerprint(loaded))
card.definition = nil
Paths = setup()
fs[Paths.root], fs[Paths.cards] = true, "restored cards"
assert(not Paths.initialize() and fs[Paths.cards] == "restored cards" and fs[Paths.legacy_cards] == "cards")
Paths = setup()
fs[Paths.root], fs[Paths.images] = true, true
assert(not Paths.initialize() and fs[Paths.legacy_images .. "/a.png"] == "image bytes")
Paths = setup()
fs[Paths.legacy_cards] = "broken"
assert(not Paths.initialize() and fs[Paths.legacy_cards] == "broken" and not fs[Paths.cards])
Paths = setup()
rename_fail = Paths.legacy_cards
assert(not Paths.initialize() and fs[Paths.legacy_cards] == "cards" and not fs[Paths.cards])
rename_fail = nil
assert(Paths.initialize() and fs[Paths.cards] == "cards")
Paths = setup()
cross_device = "/tmp/anki_download.lua"
assert(Paths.initialize() and fs[Paths.runtime .. "/anki_download.lua"] == "helper source" and not fs[cross_device])
Paths = setup()
cross_device, copy_fail = "/tmp/anki_download.lua", true
assert(not Paths.initialize() and fs[cross_device] == "helper source" and not fs[Paths.runtime .. "/anki_download.lua"])
assert(not fs[Paths.runtime .. "/anki_download.lua.migrating"])
copy_fail = false
assert(Paths.initialize() and not fs[cross_device])
Paths = setup()
separate_settings = "/separate/settings"
Paths = assert(loadstring(source, "@AnkiFlashcards.koplugin/storage_paths.lua"))()
assert(Paths.cards == "/separate/settings/ankiflashcards/anki_flashcards.json" and Paths.initialize())
package.loaded.storage_paths = Paths
package.loaded["ui/widget/notification"] = {new = function(_, spec) return spec end}
package.loaded["ui/uimanager"] = {show = function() end}
package.loaded.gettext = function(s) return s end
package.loaded.card_sync = nil
local synced_path
local cloud = {sync = function(_, _, path) synced_path = path end}
local Sync = require("card_sync")
assert(Sync.run_sync({}, false, {cloudstorage = cloud}) and synced_path == Paths.cards)
Sync.reset_baseline()
assert(not fs[Paths.cards .. ".sync"])
io.open, os.rename, os.remove = open, rename, remove
print("PASS: cards/images/baselines/helpers migrate intact to settings, conflicts/failures preserve data and restored media paths resolve safely")

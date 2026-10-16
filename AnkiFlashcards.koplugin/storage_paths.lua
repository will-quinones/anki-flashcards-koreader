-- Persistent plugin-owned data lives in KOReader/settings, never at its root.
local DataStorage = require("datastorage")
local settings = DataStorage.getSettingsDir and DataStorage:getSettingsDir()
    or (DataStorage:getDataDir() .. "/settings")
local Paths = {root = settings .. "/ankiflashcards"}
Paths.cards = Paths.root .. "/anki_flashcards.json"
Paths.images = Paths.root .. "/images"
Paths.runtime = Paths.root .. "/runtime"
Paths.legacy_cards = DataStorage:getDataDir() .. "/anki_flashcards.json"
Paths.legacy_images = DataStorage:getDataDir() .. "/.anki_images"
local initialized = false

local function ensure_dir(lfs, path)
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then return true end
    if mode then return nil, "La ubicación de datos del complemento no es una carpeta." end
    local parent = path:match("^(.*)/[^/]+$")
    if parent and parent ~= "" and parent ~= path then
        local ok, err = ensure_dir(lfs, parent)
        if not ok then return nil, err end
    end
    local ok = lfs.mkdir(path)
    if not ok then return nil, "No se pudo crear la carpeta de datos del complemento." end
    return true
end
local function move(lfs, from, to, validate_cards)
    if not lfs.attributes(from) then return true end
    if lfs.attributes(to) then
        return nil, "Hay datos del complemento en la ruta antigua y en settings. Se conservan ambas copias; revisa el conflicto antes de continuar."
    end
    if validate_cards then
        local f = io.open(from, "r")
        if not f then return nil, "No se pudieron leer las tarjetas antiguas; no se han movido." end
        local bytes = f:read("*all"); local closed = f:close()
        local ok, data = pcall(require("json").decode, bytes or "")
        if not closed or not ok or type(data) ~= "table" then
            return nil, "El archivo antiguo de tarjetas no contiene JSON válido; se conserva sin cambios."
        end
        for key, value in pairs(data) do
            if type(key) ~= "number" or key < 1 or key > #data or key % 1 ~= 0 or type(value) ~= "table" then
                return nil, "El archivo antiguo no contiene una lista válida de tarjetas; se conserva sin cambios."
            end
        end
    end
    local ok, _, code = os.rename(from, to)
    if not ok and code == 18 and lfs.attributes(from, "mode") == "file" then
        -- /tmp is often a different filesystem from the Kobo storage. Copy
        -- across devices only via a verified temporary file; never lose the
        -- source when a write, close, or final rename fails.
        local input = io.open(from, "rb")
        if not input then return nil, "No se pudo leer el archivo que debe trasladarse." end
        local bytes = input:read("*all"); local closed = input:close()
        if not bytes or not closed then return nil, "No se pudo leer completamente el archivo que debe trasladarse." end
        local tmp = to .. ".migrating"
        if lfs.attributes(tmp) then return nil, "Hay un traslado incompleto pendiente de revisión; se conservan los originales." end
        local output = io.open(tmp, "wb")
        if not output then return nil, "No se pudo escribir el archivo en settings." end
        local written = output:write(bytes); closed = output:close()
        if not written or not closed then os.remove(tmp); return nil, "No se pudo completar el traslado; se conserva el original." end
        local check = io.open(tmp, "rb")
        local verified = check and check:read("*all") == bytes
        if check then check:close() end
        if not verified or lfs.attributes(to) then os.remove(tmp); return nil, "No se pudo verificar el traslado; se conserva el original." end
        ok = os.rename(tmp, to)
        if not ok then os.remove(tmp); return nil, "No se pudo completar el traslado; se conserva el original." end
        local removed = os.remove(from)
        if not removed then return nil, "El archivo se copió, pero no se pudo retirar el original; se conservan ambas copias." end
    end
    if not ok then return nil, "No se pudieron trasladar los datos del complemento a settings. Los originales se conservan." end
    return true
end
function Paths.initialize()
    if initialized then return true end
    local lfs = require("libs/libkoreader-lfs")
    local ok, err = ensure_dir(lfs, Paths.runtime)
    if not ok then return nil, err end
    -- Move the image directory intact, without merging or overwriting files.
    ok, err = move(lfs, Paths.legacy_images, Paths.images)
    if not ok then return nil, err end
    ok, err = move(lfs, Paths.legacy_cards, Paths.cards, true)
    if not ok then return nil, err end
    ok, err = move(lfs, Paths.legacy_cards .. ".sync", Paths.cards .. ".sync")
    if not ok then return nil, err end
    -- Preserve interrupted writes for inspection, never promote them to cards.
    ok, err = move(lfs, Paths.legacy_cards .. ".tmp", Paths.runtime .. "/legacy-cards.tmp")
    if not ok then return nil, err end
    for _, name in ipairs({"anki_download.lua", "anki_post_image.lua", "anki_openrouter_image.lua"}) do
        ok, err = move(lfs, "/tmp/" .. name, Paths.runtime .. "/" .. name)
        if not ok then return nil, err end
    end
    ok, err = ensure_dir(lfs, Paths.images)
    if not ok then return nil, err end
    initialized = true
    return true
end
function Paths.resolve_image(path)
    if type(path) ~= "string" or path == "" then return path end
    local name = path:match("/%.anki_images/([^/]+)$")
        or path:match("/settings/ankiflashcards/images/([^/]+)$")
        or path:match("^settings/ankiflashcards/images/([^/]+)$")
    if not name or name == "." or name == ".." then return path end
    local relocated = Paths.images .. "/" .. name
    if require("libs/libkoreader-lfs").attributes(relocated) then return relocated end
    return path
end
return Paths

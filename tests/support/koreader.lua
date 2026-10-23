-- Explicit KOReader boundaries for standalone LuaJIT tests. Business modules
-- remain real; unexpected network/process calls fail instead of succeeding.
local K = {}
function K.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = K.copy(item) end
    return result
end
local function fallback(name, factory)
    if not package.loaded[name] and not package.preload[name] then package.preload[name] = factory end
end
local function widget()
    local W = {}
    function W:new(spec)
        spec = spec or {}
        return setmetatable(spec, {__index = self})
    end
    function W:extend(spec) return setmetatable(spec, {__index = self}) end
    function W:getSize() return {w = self.width or 600, h = self.height or 60} end
    function W:getHeight() return self:getSize().h end
    function W:free() end
    return W
end
function K.install()
    fallback("gettext", function() return function(text) return text end end)
    fallback("util", function() return {tableDeepCopy = K.copy} end)
    fallback("datastorage", function() return {getDataDir = function() return "/test-koreader" end} end)
    fallback("device", function() return {
        hasClipboard = function() return true end, hasKeys = function() return false end,
        isTouchDevice = function() return false end,
        screen = {getWidth = function() return 800 end, getHeight = function() return 1000 end,
            scaleBySize = function(_, value) return value end},
    } end)
    for _, name in ipairs({"ui/widget/buttondialog", "ui/widget/confirmbox", "ui/widget/menu",
        "ui/widget/notification", "ui/widget/infomessage", "ui/widget/inputdialog", "ui/widget/multiinputdialog", "ui/widget/textviewer",
        "ui/widget/container/inputcontainer", "ui/widget/container/centercontainer", "ui/widget/container/framecontainer",
        "ui/widget/container/movablecontainer", "ui/widget/container/widgetcontainer", "ui/widget/buttontable",
        "ui/widget/imagewidget", "ui/widget/scrolltextwidget", "ui/widget/titlebar", "ui/widget/horizontalgroup",
        "ui/widget/verticalgroup", "ui/widget/verticalspan", "ui/geometry", "ui/gesturerange"}) do fallback(name, widget) end
    fallback("ui/widget/textwidget", function()
        local W = widget()
        function W:getFittedText()
            local limit = math.floor((self.max_width or math.huge) / ((self.face and self.face.size or 20) * 0.6))
            local chars = {}; for c in (self.text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1] = c end
            return table.concat(chars, "", 1, math.min(#chars, limit)), #chars > limit
        end
        return W
    end)
    fallback("ui/font", function() return {getFace = function(_, _, size) return {size = size or 20} end} end)
    fallback("ui/size", function() return {border = {window = 1}, padding = {large = 10, default = 5, button = 5},
        margin = {small = 2}, radius = {window = 1}} end)
    fallback("ui/bidi", function() return {flipDirectionIfMirroredUILayout = function(direction) return direction end} end)
    fallback("ui/rendertext", function() return {} end)
    fallback("ffi/blitbuffer", function() return {ColorRGB32 = function() return {} end} end)
    fallback("ui/event", function() return {new = function(_, name, value) return {handler = "on" .. name, args = {value}} end} end)
    fallback("ui/network/manager", function() return {isOnline = function() return true end,
        runWhenOnline = function(_, callback) callback() end} end)
    fallback("ui/uimanager", function()
        local UI = {shown = {}, queue = {}}
        function UI:show(w) self.shown[#self.shown+1] = w end
        function UI:close(w) if w.onCloseWidget then w:onCloseWidget() end end
        function UI:scheduleIn(delay, fn) self.queue[#self.queue+1] = {delay = delay, callback = fn} end
        function UI:unschedule(fn) for i=#self.queue,1,-1 do if self.queue[i].callback == fn then table.remove(self.queue,i) end end end
        function UI:setDirty() end
        function UI:getTopmostVisibleWidget() return self.shown[#self.shown] end
        return UI
    end)
    fallback("ltn12", function() return {source = {string = function(s) return s end},
        sink = {table = function(t) return function(chunk) if chunk then t[#t+1] = chunk end; return 1 end end}} end)
    local function transport() return {request = function() error("Unexpected network request in test") end} end
    fallback("ssl.https", transport); fallback("socket.http", transport)
    fallback("mime", function() return {unb64 = function() error("Provide test media decoder") end} end)
    fallback("libs/libkoreader-lfs", function()
        local directories = {["/"] = true}
        return {attributes = function(path, field)
            local mode = directories[path] and "directory"
            if not mode then
                local f = io.open(path, "r")
                if f then
                    local _, _, code = f:read(0)
                    f:close(); mode = code == 21 and "directory" or "file"
                end
            end
            if not mode then return nil end
            return field == "mode" and mode or {mode = mode}
        end, mkdir = function(path) directories[path] = true; return true end}
    end)
end
function K.action(items, label)
    for _, item in ipairs(items) do if item.text == label then return item end end
    error("Missing native menu action: " .. label)
end
function K.memory_filesystem()
    local fs = {files = {}, removed = {}}
    local open, rename, remove = io.open, os.rename, os.remove
    io.open = function(path, mode)
        mode = mode or "r"
        if mode == "r" or mode == "rb" then
            if fs.files[path] == nil then return nil, "not found", 2 end
            return {read = function() return fs.files[path] end, close = function() return true end}
        end
        assert(mode == "w" or mode == "wb", "Unsupported test file mode: " .. mode)
        local bytes = ""
        return {write = function(self, data) bytes = bytes .. data; return self end,
            close = function() fs.files[path] = bytes; return true end}
    end
    os.rename = function(a,b)
        if fs.files[a] == nil then return nil, "not found", 2 end
        fs.files[b], fs.files[a] = fs.files[a], nil; return true
    end
    os.remove = function(path)
        fs.removed[#fs.removed+1] = path
        if fs.files[path] == nil then return nil, "not found", 2 end
        fs.files[path] = nil; return true
    end
    function fs:restore() io.open, os.rename, os.remove = open, rename, remove end
    return fs
end
return K

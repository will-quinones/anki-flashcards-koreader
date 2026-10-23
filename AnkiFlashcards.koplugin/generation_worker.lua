-- Only generated content crosses the process boundary; credentials stay in
-- memory. The UI owns card persistence and can kill a blocked HTTP request.
local json = require("json")
local Worker = {}
local serial = 0
local function write(path, value)
    local file = io.open(path .. ".tmp", "w")
    if not file then return false end
    local ok = file:write(json.encode(value))
    local closed = file:close()
    if not ok or not closed then os.remove(path .. ".tmp"); return false end
    return os.rename(path .. ".tmp", path)
end
function Worker.launch(config, source)
    local util = require("ffi/util")
    for _, name in ipairs({"runInSubProcess", "isSubProcessDone", "terminateSubProcess"}) do
        if type(util[name]) ~= "function" then return nil, "El lector no admite generación en segundo plano." end
    end
    local Paths = require("storage_paths")
    local ready, err = Paths.initialize()
    if not ready then return nil, err end
    serial = serial + 1
    local path = Paths.runtime .. "/vocab-generation-" .. os.time() .. "-" .. serial .. "-" .. math.random(2147483646) .. ".json"
    local pid = util.runInSubProcess(function()
        local last = 0
        local ok, card, reason, details = pcall(require("card_generator").generate,
            config, source.phrase, source.context, source.title, source.author, function(raw)
                local now = util.gettime and util.gettime() or os.time()
                if now - last >= 0.15 then
                    write(path, {kind = "progress", raw = raw})
                    last = now
                end
            end)
        if ok and card then write(path, {kind = "complete", card = card})
        else
            local info = require("generation_feedback").classify(ok and reason or nil, ok and details or nil)
            write(path, {kind = "error", info = info})
        end
    end, false)
    if not pid then return nil, "No se pudo iniciar la generación." end
    local job = {pid = pid, started = os.time()}
    function job:clear()
        os.remove(path); os.remove(path .. ".tmp")
    end
    function job:poll()
        -- Once reaped, the final atomic write is visible. Reading before
        -- waitpid could mistake an older progress snapshot for a failed exit.
        local done = util.isSubProcessDone(self.pid)
        local file = io.open(path, "r")
        local value
        if file then
            local bytes = file:read("*all"); file:close()
            local ok, decoded = pcall(json.decode, bytes or "")
            if ok and type(decoded) == "table" then value = decoded end
        end
        if done then
            self.reaped = true
            self:clear()
            if not value or value.kind == "progress" then
                return {kind = "error", info = require("generation_feedback").classify("Connection closed")}
            end
        elseif os.time() - self.started >= 90 then
            self:cancel(require("ui/uimanager"))
            return {kind = "error", info = require("generation_feedback").classify("timeout")}
        elseif value and value.kind ~= "progress" then
            -- Reap before letting another generation replace this one.
            return nil
        end
        return value
    end
    function job:cancel(UI)
        if self.reaped or self.cancelled then return end
        self.cancelled = true
        util.terminateSubProcess(self.pid)
        local function reap()
            if util.isSubProcessDone(self.pid) then self.reaped = true; self:clear()
            else UI:scheduleIn(0.2, reap) end
        end
        reap()
    end
    return job
end
return Worker

-- All HTTP/DNS/TTS work runs in KOReader's low-priority fork, never in its UI.
-- Only an intent and a receipt journal are written here, not the card collection.
local Paths = require("storage_paths")
local json = require("json")
local Worker = {}
local intent_file = Paths.runtime .. "/auto-send-job.json"
local result_file = Paths.runtime .. "/auto-send-result.json"
local function write(path, value)
    local encoded, bytes = pcall(json.encode, value)
    if not encoded then return nil end
    local file = io.open(path .. ".tmp", "w")
    if not file then return nil end
    local ok = file:write(bytes); local closed = file:close()
    if not ok or not closed then os.remove(path .. ".tmp"); return nil end
    local renamed = os.rename(path .. ".tmp", path)
    if not renamed then os.remove(path .. ".tmp") end
    return renamed
end
local function read(path)
    local f, _, code = io.open(path, "r")
    if not f then return nil, code ~= nil and code ~= 2 end
    local bytes = f:read("*all"); f:close()
    local ok, value = pcall(json.decode, bytes or "")
    if not ok or type(value) ~= "table" then return nil, true end
    return value
end
function Worker.clear()
    local removed = os.remove(intent_file)
    if not removed then return nil end
    os.remove(result_file)
    return true
end
function Worker.recover()
    local intent, bad = read(intent_file)
    if bad then return nil, nil, "review" end
    if not intent then return nil end
    if type(intent.token) ~= "string" or type(intent.card) ~= "table" or type(intent.stamp) ~= "string" then
        return nil, nil, "review"
    end
    local result = read(result_file)
    if not result or result.token ~= intent.token then return intent, nil, "review" end
    if result.kind == "sent" then
        local receipt = result.receipt
        local id = type(receipt) == "table" and receipt.note_id
        local valid_id = (type(id) == "number" and id > 0 and id % 1 == 0)
            or (type(id) == "string" and id:match("^%d+$") and tonumber(id) > 0)
        if not valid_id or receipt.model ~= require("note_types").model_name(intent.card.kind)
            or type(receipt.deck) ~= "string" or receipt.deck == ""
            or type(receipt.source) ~= "table" or type(receipt.source.profile) ~= "string" then
            return intent, nil, "review"
        end
    elseif result.kind ~= "offline" and result.kind ~= "review" and result.kind ~= "sending" then
        return intent, nil, "review"
    end
    return intent, result
end
function Worker.execute(config, card, base, before_send)
    local Sync = require("anki_sync")
    if not Sync.test_connection(config.url) then return {kind = "offline"} end
    local profile = Sync.read(config.url, "getActiveProfile", {})
    if type(profile) ~= "string" or profile == "" then return {kind = "offline"} end
    if before_send and not before_send() then return {kind = "review"} end
    local ok, _, receipt = Sync.send_card(config, card, base, {defer_persistence = true})
    if not ok or type(receipt) ~= "table" then
        -- A timeout after a write can mean Anki accepted the note. Never
        -- blindly resend this card or discard the pending intent.
        return {kind = "review"}
    end
    local source = Sync.source_identity(config.url)
    if not source or source.profile ~= profile then return {kind = "review", receipt = receipt} end
    receipt.source = source
    return {kind = "sent", receipt = receipt}
end
function Worker.launch(config, card, base)
    local ready = Paths.initialize()
    if not ready then return nil, "storage" end
    local existing, _, blocked = Worker.recover()
    if existing or blocked then return nil, "review" end
    local util = require("ffi/util")
    if type(util.runInSubProcess) ~= "function" or type(util.isSubProcessDone) ~= "function"
        or type(util.terminateSubProcess) ~= "function" then return nil, "unsupported" end
    local token = tostring(os.time()) .. "-" .. tostring(math.random(1, 2147483646))
    local intent = {token = token, card = card, stamp = require("anki_recovery").stamp(card)}
    -- No API keys or configuration are persisted to the job journal.
    if not write(intent_file, intent) then return nil, "storage" end
    local pid = util.runInSubProcess(function()
        local ok, result = pcall(Worker.execute, config, card, base, function()
            return write(result_file, {token = token, kind = "sending"})
        end)
        result = ok and result or {kind = "review"}
        result.token = token
        write(result_file, result)
    end, false)
    if not pid then Worker.clear(); return nil, "spawn" end
    local job = {pid = pid, intent = intent}
    function job:poll()
        if not util.isSubProcessDone(self.pid) then return nil end
        local saved_intent, result = Worker.recover()
        local raw, bad = read(result_file)
        if not bad and (not raw or raw.token ~= token) then result = {kind = "offline"} end
        return {intent = saved_intent or self.intent, result = result or {kind = "review"}}
    end
    function job:cancel(UI)
        util.terminateSubProcess(self.pid)
        local function reap()
            if not util.isSubProcessDone(self.pid) then
                util.terminateSubProcess(self.pid)
                UI:scheduleIn(0.2, reap)
            else
                local raw, bad = read(result_file)
                local saved = read(intent_file)
                if saved and saved.token == token and not bad
                    and (not raw or raw.token ~= token or raw.kind == "offline") then
                    -- Known dead child never crossed the durable write barrier.
                    Worker.clear()
                end
            end
        end
        reap()
        -- Keep intent/results for reconciliation after cancellation or exit.
    end
    return job
end
return Worker

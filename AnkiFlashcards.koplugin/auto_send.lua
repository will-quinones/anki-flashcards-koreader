-- Nonblocking automatic delivery: one worker/card, bounded lifetime and backoff.
local Auto = {}
Auto.__index = Auto
local BACKOFF = {60, 120, 300, 600, 1800}
function Auto.new(options)
    local o = options or {}
    local self = setmetatable({ui = o.ui, base = o.base, get_config = o.get_config,
        UI = o.UI or require("ui/uimanager"), Storage = o.Storage or require("card_storage"),
        Worker = o.Worker or require("background_send"), R = o.R or require("anki_recovery"),
        now = o.now or function()
            local time = require("ui/time")
            return time.to_s(time.now()) -- Monotonic: unaffected by clock/NTP corrections.
        end, failures = 0, sent = 0, running = false}, Auto)
    self.online = o.online or function()
        local network = require("ui/network/manager")
        -- isOnline() performs DNS on this KOReader version. Use cached state
        -- only; do not resolve names, ping, wake Wi-Fi or prompt from the UI.
        return network:getWifiState() == true and network:getConnectionState() == true
    end
    self.notify = o.notify or function(text)
        self.UI:show(require("ui/widget/notification"):new {text = text, timeout = 4})
    end
    self.tick_callback = function() self:tick() end
    self.poll_callback = function() self:poll() end
    return self
end
function Auto:schedule(delay)
    self.UI:unschedule(self.tick_callback)
    if self.running then self.UI:scheduleIn(delay, self.tick_callback) end
end
function Auto:summary()
    if self.sent > 0 then self.notify(self.sent .. " tarjetas enviadas a Anki."); self.sent = 0 end
end
function Auto:review(intent)
    if intent then
        local found
        for _, card in ipairs(self.Storage.load_cards()) do
            if (intent.card.kind == "learn" and card.kind == "learn" and card.card_id == intent.card.card_id)
                or (intent.card.kind ~= "learn" and card.kind ~= "learn" and card.phrase == intent.card.phrase) then
                found = card; break
            end
        end
        -- Explicit deletion or subsequent confirmed manual recovery/send resolves
        -- the old intent; never recreate a missing local card.
        if not found or (found.sent_to_anki and found.anki_note_id and not self.R.needs_review(found)) then
            if self.Worker.clear() then self:schedule(60); return end
        end
    end
    self:summary()
    if not self.warned then
        self.notify("Envío automático pendiente de comprobar. Usa Recuperar desde Anki antes de reenviarlo.")
        self.warned = true
    end
    self:schedule(60) -- Local reconciliation only while the journal is unresolved.
end
function Auto:completed(intent, result)
    if result and result.kind == "sent" and intent and type(result.receipt) == "table" then
        local ok = self.Storage.record_sent_guarded(intent.card, intent.stamp, result.receipt)
        if not ok or not self.Worker.clear() then self:review(intent); return end
        self.failures, self.warned = 0, false
        self.sent = self.sent + 1
        if self.sent >= 3 then self:summary(); self:schedule(60) else self:schedule(2) end
    elseif result and result.kind == "offline" then
        if not self.Worker.clear() then self:review(intent); return end
        self:summary()
        self.failures = math.min(self.failures + 1, #BACKOFF)
        self:schedule(BACKOFF[self.failures])
    else self:review(intent) end
end
function Auto:tick()
    if not self.running then return end
    if self.ui and self.ui.tearing_down then self:stop(); return end
    if self.job then return end
    local intent, result, problem = self.Worker.recover()
    if intent or problem then
        if problem then self:review(intent) else self:completed(intent, result) end
        return
    end
    local cfg = self.get_config()
    if not cfg.auto_send_wifi then self:summary(); return end
    if not cfg.url or cfg.url == "" or not self.online() then self:schedule(60); return end
    local pending
    for _, card in ipairs(self.Storage.load_cards()) do
        if not card.sent_to_anki and not self.R.needs_review(card) then pending = card; break end
    end
    if not pending then self:summary(); self:schedule(60); return end
    local job, err = self.Worker.launch(cfg, pending, self.base)
    if not job then
        if err == "review" then self:review(); return end
        self.failures = math.min(self.failures + 1, #BACKOFF)
        self:schedule(BACKOFF[self.failures]); return
    end
    self.job, self.job_url, self.started = job, cfg.url, self.now()
    self.UI:scheduleIn(0.5, self.poll_callback)
end
function Auto:poll()
    if not self.running or not self.job then return end
    local completed = self.job:poll()
    if completed then
        self.job = nil
        self:completed(completed.intent, completed.result)
        return
    end
    local cfg = self.get_config()
    if (self.ui and self.ui.tearing_down) or not cfg.auto_send_wifi or cfg.url ~= self.job_url then
        self:stop(); return
    end
    if self.now() - self.started >= 120 then
        self.job:cancel(self.UI); self.job = nil
        self:review() -- A killed write may have succeeded remotely; keep proof.
        return
    end
    self.UI:scheduleIn(0.5, self.poll_callback)
end
function Auto:start(delay)
    self:stop()
    if Auto.active and Auto.active ~= self then Auto.active:stop() end
    Auto.active, self.running = self, true
    self:schedule(delay or 30)
end
function Auto:stop()
    self.running = false
    self.UI:unschedule(self.tick_callback)
    self.UI:unschedule(self.poll_callback)
    if self.job then self.job:cancel(self.UI); self.job = nil end
    if Auto.active == self then Auto.active = nil end
end
function Auto:settings_changed()
    local cfg = self.get_config()
    if not cfg.auto_send_wifi then self:stop(); return end
    if self.job and self.job_url == cfg.url then return end
    self:start(0)
end
return Auto

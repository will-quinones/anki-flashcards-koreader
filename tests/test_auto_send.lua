package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local Auto = require("auto_send")
local function scenario(count, use_cached_network)
    if Auto.active then Auto.active:stop() end
    local state = {now = 0, tasks = {}, cards = {}, notifications = {}, launches = 0, cancellations = 0,
        config = {auto_send_wifi = true, url = "http://synthetic.invalid:8765"}, connected = true, ui = {}}
    for i = 1, count do state.cards[i] = {phrase = "pending-" .. i, revision = 1} end
    local UI = {
        scheduleIn = function(_, delay, callback) state.tasks[#state.tasks+1] = {at = state.now + delay, fn = callback} end,
        unschedule = function(_, callback)
            for i = #state.tasks, 1, -1 do if state.tasks[i].fn == callback then table.remove(state.tasks, i) end end
        end,
    }
    local Worker = {
        recover = function() return state.intent, state.result, state.intent and not state.result and "review" or nil end,
        clear = function() state.intent, state.result = nil, nil; return true end,
        launch = function(cfg, card)
            state.launches = state.launches + 1
            assert(not state.intent, "A second worker must never overlap")
            state.intent = {card = {phrase = card.phrase, revision = card.revision}, stamp = card.revision}
            return {poll = function()
                if state.result then return {intent = state.intent, result = state.result} end
            end, cancel = function() state.cancellations = state.cancellations + 1 end}
        end,
    }
    local storage = {
        load_cards = function() return state.cards end,
        record_sent_guarded = function(snapshot, stamp, receipt)
            for _, c in ipairs(state.cards) do
                if c.phrase == snapshot.phrase and c.revision == stamp and not state.disk_failure then
                    c.sent_to_anki, c.anki_note_id = true, receipt.note_id
                    return true
                end
            end
            return false
        end,
    }
    state.auto = Auto.new {UI = UI, Worker = Worker, Storage = storage, ui = state.ui, base = {},
        R = {needs_review = function(card) return card.review == true end},
        get_config = function() return state.config end, now = function() return state.now end,
        online = not use_cached_network and function() return state.connected end or nil,
        notify = function(text) state.notifications[#state.notifications+1] = text end}
    function state:next()
        assert(#self.tasks > 0)
        table.sort(self.tasks, function(a,b) return a.at < b.at end)
        local task = table.remove(self.tasks, 1)
        self.now = math.max(self.now, task.at); task.fn()
        return task
    end
    function state:delay()
        table.sort(self.tasks, function(a,b) return a.at < b.at end)
        return self.tasks[1].at - self.now
    end
    return state
end
local s = scenario(8)
s.auto:start(); assert(s:delay() == 30)
s:next(); assert(s.launches == 1 and s.auto.job and #s.tasks == 1)
-- A user interaction can run while the worker is waiting on network.
local taps = 0
s.auto.UI:scheduleIn(0.1, function() taps = taps + 1 end)
s:next(); assert(taps == 1 and s.launches == 1)
s.result = {kind = "offline"}; s:next()
assert(s:delay() == 60 and s.launches == 1 and #s.notifications == 0)
for _, delay in ipairs({120, 300, 600, 1800, 1800}) do
    s:next(); assert(s.auto.job)
    s.result = {kind = "offline"}; s:next()
    assert(s:delay() == delay)
end
assert(s.launches == 6) -- One failed probe per cycle, not 8 failed card sends.
for _, c in ipairs(s.cards) do assert(not c.sent_to_anki) end
print("PASS: unreachable Anki never blocks UI callbacks; one worker and progressive 1/2/5/10/30-minute retries")

s:next()
s.result = {kind = "sent", receipt = {note_id = 42}}; s:next()
assert(s.cards[1].sent_to_anki and s.auto.failures == 0 and s:delay() == 2)
for id = 43, 44 do s:next(); s.result = {kind = "sent", receipt = {note_id = id}}; s:next() end
assert(s.cards[3].sent_to_anki and s:delay() == 60 and #s.notifications == 1)
s.auto:stop(); assert(#s.tasks == 0)

s = scenario(0); s.auto:start(); s:next(); assert(s.launches == 0)
s = scenario(2); s.connected = false; s.auto:start(); s:next(); assert(s.launches == 0)
s = scenario(2); s.config.auto_send_wifi = false; s.auto:start(); s:next(); assert(s.launches == 0 and #s.tasks == 0)
s = scenario(2); s.cards[1].review = true; s.auto:start(); s:next(); assert(s.intent.card.phrase == "pending-2")
s.auto:settings_changed(); assert(s.cancellations == 0) -- Unrelated settings do not cancel a live write.
s.config.auto_send_wifi = false; s.auto:settings_changed()
assert(s.cancellations == 1 and #s.tasks == 0)
s = scenario(2); s.auto:start(); s.ui.tearing_down = true; s:next(); assert(s.launches == 0 and #s.tasks == 0)
s = scenario(2); s.auto:start(); s:next(); s.auto:stop(); assert(s.cancellations == 1 and #s.tasks == 0)
s = scenario(2); s.auto:start(); s:next(); s.config.url = "http://another.invalid"; s:next()
assert(s.cancellations == 1 and not s.auto.running and #s.tasks == 0)
package.loaded["ui/network/manager"] = {getWifiState = function() return true end,
    getConnectionState = function() return true end, isOnline = function() error("DNS must never run in a UI callback") end}
s = scenario(1, true); s.auto:start(); s:next(); assert(s.launches == 1); s.auto:stop()
print("PASS: no work without pending cards or Wi-Fi; disabling/closing cancels workers and scheduled callbacks")

s = scenario(2); s.auto:start(); s:next()
s.now = s.now + 121; s:next()
assert(s.cancellations == 1 and not s.auto.job and s.intent and #s.notifications == 1)
for _ = 1, 3 do s:next() end
assert(s.launches == 1 and #s.notifications == 1) -- No blind retries after an uncertain write.
s.cards[1].sent_to_anki, s.cards[1].anki_note_id = true, 42
s:next(); assert(not s.intent)

s = scenario(2); s.auto:start(); s:next()
s.cards[1].revision = 2
s.result = {kind = "sent", receipt = {note_id = 50}}; s:next()
assert(not s.cards[1].sent_to_anki and s.intent and #s.notifications == 1)
s.auto:stop()
-- Reopening can reconcile a durable completed receipt without a second send.
s = scenario(1)
s.intent = {card = {phrase = "pending-1", revision = 1}, stamp = 1}
s.result = {kind = "sent", receipt = {note_id = 77}}
s.auto:start(); s:next()
assert(s.cards[1].anki_note_id == 77 and s.launches == 0 and not s.intent)
s.auto:stop()
print("PASS: deadlines preserve uncertain writes; edits are protected and durable receipts recover without resending")

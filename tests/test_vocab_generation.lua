package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local queue, shown, current, launches, cancels, successes, dismisses = {}, {}, nil, 0, 0, 0, 0
local UI = {}
function UI:scheduleIn(delay, fn) queue[#queue+1] = {fn=fn, delay=delay} end
function UI:unschedule(fn) for i=#queue,1,-1 do if queue[i].fn == fn then table.remove(queue,i) end end end
function UI:show(viewer) current = viewer; shown[#shown+1] = viewer end
function UI:close(viewer)
    viewer._anki_closed = true
    if viewer.on_dismiss and not viewer._replacing then viewer.on_dismiss() end
end
package.loaded["ui/uimanager"] = UI
package.loaded.gettext = function(s) return s end
package.loaded["ui/widget/infomessage"] = {new=function(_,v) return v end}
package.loaded.text_stream = {preview = function(raw)
    return {definition=raw, question="visible question", answer="hidden answer", evidence="hidden evidence"}
end}
local Viewer = {}
function Viewer:new(spec) return setmetatable(spec, {__index=self}) end
function Viewer:update() error("Streaming must not replace the native modal") end
function Viewer:update_generation(text, label)
    assert(not self._anki_closed)
    self.stream_text, self.generation_label = text, label or self.generation_label
end
package.loaded.card_viewer = Viewer
local events, last_kind
package.loaded.generation_worker = {launch = function(_, _, kind)
    last_kind = kind
    launches = launches+1
    return {poll = function() return table.remove(events,1) end,
        cancel = function() cancels=cancels+1 end}
end}
local Generation = require("vocab_generation")
local function step() assert(#queue>0); table.remove(queue,1).fn() end
local function drain() local n=0; while #queue>0 do step(); n=n+1; assert(n<20) end end
local function start(opts)
    return Generation.start({}, {phrase="word"}, function(card)
        assert(card.phrase=="done"); successes=successes+1
    end, opts or {on_cancel=function() dismisses=dismisses+1 end})
end
events={{kind="progress",raw="partial"},{kind="complete",card={phrase="done"}}}
start()
assert(current.generating and current.stream_text=="" and launches==0)
step(); step()
assert(current.stream_text=="partial" and successes==0 and cancels==0)
step(); assert(successes==1 and dismisses==0 and #queue==0)
events={}
start(); UI:close(current); drain()
assert(launches==1 and successes==1 and dismisses==1) -- closed before fork
start(); step(); UI:close(current); drain()
assert(cancels==1 and dismisses==2 and successes==1)
events={{kind="error",info={kind="busy",retryable=true,message="busy",retry_after=2}}}
start({regenerating=true}); assert(current.generation_label=="Regenerando tarjeta…")
step(); step(); assert(current.generation_label=="Servicio ocupado. Reintentando…")
local previous=launches
UI:close(current); drain()
assert(launches==previous and successes==1) -- cancelled queued retry
events={{kind="error",info={kind="busy",retryable=true,message="busy",retry_after=2}}}
start(); step(); step()
events={{kind="complete",card={phrase="done"}}}; drain()
assert(successes==2)
events={}
local valid=true
start({is_valid=function() return valid end}); step(); valid=false; drain()
assert(cancels==2 and successes==2)
start(); step(); Generation.cancel_all(); drain()
assert(cancels==3 and dismisses==2)
events={{kind="error",info={kind="auth",retryable=false,message="safe error"}}}
start(); drain()
assert(current.text=="safe error" and successes==2)
print("PASS: modal opens before requests, streams, preserves callbacks, cancels queued/in-flight work, bounds retries and handles teardown")

events={{kind="progress",raw="partial"},{kind="complete",card={phrase="done"}}}
start({kind="learn"})
local modal, shown_before = current, #shown
step(); step()
assert(last_kind=="learn" and current==modal and #shown==shown_before and modal.card.kind=="learn")
assert(current.stream_text=="visible question" and not current.stream_text:find("hidden",1,true))
step(); assert(successes==3)
local _, _, interrupted = require("generation_feedback").http_error("wantread", "private error")
events={{kind="error",info=interrupted}}
start(); step(); step()
assert(current.generation_label=="Reintentando conexión…")
local before=launches
UI:close(current); drain()
assert(launches==before, "closing a transport retry must cancel its queued request")
print("PASS: Learn shares streaming/cancellation, keeps its answer hidden and retains the same native modal")

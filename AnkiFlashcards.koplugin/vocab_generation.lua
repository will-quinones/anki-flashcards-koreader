local UI = require("ui/uimanager")
local Viewer = require("card_viewer")
local Feedback = require("generation_feedback")
local Stream = require("text_stream")
local Generation = {}
local active = {}
local logger_ok, logger = pcall(require, "logger")
local function trace(phase, count)
    if logger_ok then logger.info("Anki card generation:", phase, count or "") end
end

function Generation.start(config, source, success, options)
    trace("modal:create")
    local opts, session = options or {}, {finished = false}
    active[session] = true
    local viewer, job, poll, attempt
    local function close()
        if viewer then viewer._replacing = true; UI:close(viewer); viewer = nil end
    end
    function session:cancel(quiet)
        if self.finished then return end
        trace("modal:cancel")
        self.finished = true; active[self] = nil
        if UI.unschedule then UI:unschedule(poll); UI:unschedule(attempt) end
        if job then job:cancel(UI); job = nil end
        close()
        if not quiet and opts.on_cancel then opts.on_cancel() end
    end
    local label = opts.regenerating and Feedback.REGENERATING or Feedback.GENERATING
    viewer = Viewer:new {card = {kind = opts.kind}, generating = true, generation_label = label, stream_text = "",
        on_viewer_updated = function(updated) viewer = updated end,
        on_dismiss = function() viewer = nil; session:cancel() end}
    UI:show(viewer)
    trace("modal:shown")
    local retries, previous = 1, nil
    local function valid()
        if session.finished then return false end
        if opts.is_valid and not opts.is_valid() then session:cancel(); return false end
        return true
    end
    local function fail(info)
        trace("modal:error")
        session.finished = true; active[session] = nil
        close()
        if opts.on_failure then opts.on_failure(info) end
        UI:show(require("ui/widget/infomessage"):new {text = info.message})
    end
    local polls = 0
    poll = function()
        if not valid() then return end
        polls = polls + 1
        if polls == 1 or polls % 25 == 0 then trace("worker:poll", polls) end
        local event = job:poll()
        if event and event.kind == "complete" then
            trace("worker:complete")
            job = nil; session.finished = true; active[session] = nil
            close(); trace("modal:closed"); success(event.card); trace("card:shown"); return
        elseif event and event.kind == "error" then
            job = nil
            local info = event.info
            local delay = info.retry_after or 3
            if info.retryable and retries > 0 and delay <= 10 then
                retries = retries - 1; previous = nil
                viewer:update_generation("", (info.kind == "busy" or info.kind == "rate_limit")
                    and Feedback.RETRYING or "Reintentando conexión…")
                UI:scheduleIn(math.max(1, delay), attempt)
            else fail(info) end
            return
        elseif event and event.kind == "progress" and event.raw ~= previous then
            trace("progress:parse", #event.raw)
            previous = event.raw
            viewer:update_generation(Generation.preview_text(event.raw, opts.kind))
            trace("progress:painted")
        end
        UI:scheduleIn(0.4, poll) -- bounded repaint rate for e-ink
    end
    attempt = function()
        if not valid() then return end
        trace("worker:launch")
        local err
        job, err = require("generation_worker").launch(config, source, opts.kind)
        trace(job and "worker:launched" or "worker:launch-failed")
        if not job then fail(Feedback.classify(err)); return end
        UI:scheduleIn(0.1, poll)
    end
    -- Let the modal paint before forking or initiating any network work.
    UI:scheduleIn(0.05, attempt)
    return session
end

function Generation.preview_text(raw, kind)
    local card, lines = Stream.preview(raw), {}
    local _ = require("gettext")
    -- Learn keeps its answer hidden until the user flips the completed card.
    local fields = kind == "learn" and {{"question", ""}}
        or {{"phrase", ""}, {"ipa", ""}, {"definition", ""}, {"synonyms", _("Sinónimos: ")}, {"text", _("Ejemplo: ")}}
    for _, field in ipairs(fields) do
        local value = card[field[1]]
        if value and value ~= "" then lines[#lines+1] = field[2] .. value:gsub("{{c%d+::(.-)}}", "%1") end
    end
    return table.concat(lines, "\n\n")
end
function Generation.cancel_all()
    local sessions = {}; for session in pairs(active) do sessions[#sessions+1] = session end
    for _, session in ipairs(sessions) do session:cancel(true) end
end
return Generation

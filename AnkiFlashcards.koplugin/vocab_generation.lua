local UI = require("ui/uimanager")
local Viewer = require("card_viewer")
local Feedback = require("generation_feedback")
local Stream = require("text_stream")
local Generation = {}
local active = {}

function Generation.start(config, source, success, options)
    local opts, session = options or {}, {finished = false}
    active[session] = true
    local viewer, job, poll, attempt
    local function close()
        if viewer then viewer._replacing = true; UI:close(viewer); viewer = nil end
    end
    function session:cancel(quiet)
        if self.finished then return end
        self.finished = true; active[self] = nil
        if UI.unschedule then UI:unschedule(poll); UI:unschedule(attempt) end
        if job then job:cancel(UI); job = nil end
        close()
        if not quiet and opts.on_cancel then opts.on_cancel() end
    end
    local label = opts.regenerating and Feedback.REGENERATING or Feedback.GENERATING
    viewer = Viewer:new {card = {}, generating = true, generation_label = label, stream_text = "",
        on_viewer_updated = function(updated) viewer = updated end,
        on_dismiss = function() viewer = nil; session:cancel() end}
    UI:show(viewer)
    local retries, previous = 1, nil
    local function valid()
        if session.finished then return false end
        if opts.is_valid and not opts.is_valid() then session:cancel(); return false end
        return true
    end
    local function fail(info)
        session.finished = true; active[session] = nil
        close()
        if opts.on_failure then opts.on_failure(info) end
        UI:show(require("ui/widget/infomessage"):new {text = info.message})
    end
    poll = function()
        if not valid() then return end
        local event = job:poll()
        if event and event.kind == "complete" then
            job = nil; session.finished = true; active[session] = nil
            close(); success(event.card); return
        elseif event and event.kind == "error" then
            job = nil
            local info = event.info
            local delay = info.retry_after or 3
            if info.retryable and retries > 0 and delay <= 10 then
                retries = retries - 1; previous = nil
                viewer.generation_label, viewer.stream_text = Feedback.RETRYING, ""
                viewer = viewer:update()
                UI:scheduleIn(math.max(1, delay), attempt)
            else fail(info) end
            return
        elseif event and event.kind == "progress" and event.raw ~= previous then
            previous = event.raw
            viewer.stream_text = Generation.preview_text(event.raw)
            viewer = viewer:update()
        end
        UI:scheduleIn(0.4, poll) -- bounded repaint rate for e-ink
    end
    attempt = function()
        if not valid() then return end
        local err
        job, err = require("generation_worker").launch(config, source)
        if not job then fail(Feedback.classify(err)); return end
        UI:scheduleIn(0.1, poll)
    end
    -- Let the modal paint before forking or initiating any network work.
    UI:scheduleIn(0.05, attempt)
    return session
end

function Generation.preview_text(raw)
    local card, lines = Stream.preview(raw), {}
    local _ = require("gettext")
    for _, field in ipairs({{"phrase", ""}, {"ipa", ""}, {"definition", ""}, {"synonyms", _("Sinónimos: ")}, {"text", _("Ejemplo: ")}}) do
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

-- SSE framing is independent of HTTP chunk boundaries (including UTF-8).
local json = require("json")
local Stream = {}
-- SSE repeats an envelope for every token and may carry hidden reasoning.
-- Bound retained text and individual frames separately from total wire bytes.
local MAX_TEXT_BYTES, MAX_FRAME_BYTES, MAX_WIRE_BYTES = 262144, 262144, 8 * 1024 * 1024
function Stream.new(provider, on_text)
    local self = {buffer = "", text = "", bytes = 0, events = false}
    local function event(frame)
        local lines = {}
        for line in (frame .. "\n"):gmatch("(.-)\n") do
            local data = line:match("^data:%s?(.*)")
            if data then lines[#lines+1] = data end
        end
        if #lines == 0 then return end -- comments / keep-alives
        self.events = true
        local payload = table.concat(lines, "\n")
        if payload == "[DONE]" then self.done = true; return end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" then self.error = "Invalid streaming JSON response"; return end
        if data.error then
            local _, err, details = require("generation_feedback").response_error(data, payload, {})
            self.error, self.details = err, details
            return
        end
        local delta = ""
        if provider == "gemini" then
            local candidate = data.candidates and data.candidates[1]
            for _, part in ipairs(candidate and candidate.content and candidate.content.parts or {}) do
                if not part.thought and type(part.text) == "string" then delta = delta .. part.text end
            end
        else
            local choice = data.choices and data.choices[1]
            local content = choice and choice.delta and choice.delta.content
            if type(content) == "string" then delta = content end
        end
        if delta ~= "" and not self.error then
            if #self.text + #delta > MAX_TEXT_BYTES then self.error = "Streaming response text too large"; return end
            self.text = self.text .. delta
            on_text(self.text)
        end
    end
    function self:sink(chunk)
        if self.error then return nil, self.error end
        if not chunk then
            if self.buffer ~= "" then
                event(self.buffer:gsub("\r\n", "\n"))
                self.buffer = ""
            end
            if self.error then return nil, self.error end
            return 1
        end
        self.bytes = self.bytes + #chunk
        if self.bytes > MAX_WIRE_BYTES then self.error = "Streaming response too large"; return nil, self.error end
        self.buffer = self.buffer .. chunk
        while true do
            local a, b = self.buffer:find("\r?\n\r?\n")
            if not a then break end
            if a - 1 > MAX_FRAME_BYTES then self.error = "Streaming response frame too large"; return nil, self.error end
            event(self.buffer:sub(1, a - 1):gsub("\r\n", "\n"))
            self.buffer = self.buffer:sub(b + 1)
            if self.error then return nil, self.error end
        end
        if #self.buffer > MAX_FRAME_BYTES then self.error = "Streaming response frame too large"; return nil, self.error end
        return 1
    end
    return self
end

-- Decode complete fields and the current unfinished JSON string. Never show
-- raw JSON, reasoning tokens, or provider envelopes in the card modal.
function Stream.preview(raw)
    local card, pos = {}, 1
    while true do
        local a, b, key = raw:find('"([%w_]+)"%s*:%s*"', pos)
        if not a then break end
        local i, finish = b + 1, nil
        while i <= #raw do
            local char = raw:sub(i, i)
            if char == '"' then finish = i; break end
            if char == "\\" then i = i + 1 end
            i = i + 1
        end
        local last = finish and finish - 1 or #raw
        local value = raw:sub(b + 1, last)
        if not finish then
            -- An unfinished escape, Unicode surrogate pair or UTF-8 codepoint
            -- is withheld until the next chunk makes it decodable.
            local slash = value:match("()\\[^\\]*$")
            if slash and (#value:sub(slash):match("^\\+") % 2 == 1) then
                local tail = value:sub(slash)
                if tail == "\\" or tail:match("^\\u%x?%x?%x?$") or tail:match("^\\u[dD][89aAbB]%x%x$") then value = value:sub(1, slash - 1) end
            end
            while #value > 0 do
                local ok = pcall(json.decode, '"' .. value .. '"')
                if ok then break end
                value = value:sub(1, -2)
            end
        end
        local ok, decoded = pcall(json.decode, '"' .. value .. '"')
        if ok and type(decoded) == "string" then card[key] = decoded end
        if not finish then break end
        pos = finish + 1
    end
    return card
end
return Stream

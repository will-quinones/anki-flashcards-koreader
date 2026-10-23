local Device = require("device")
local Screen = Device.screen

local function selection_to_text(sel)
  if type(sel) == "string" then return sel end
  if type(sel) ~= "table" then return tostring(sel) end

  -- Some backends give { text="...", ... }
  if sel.text then return sel.text end

  local out = {}

  local function collect(t)
    for _, v in ipairs(t) do
      if type(v) == "string" then
        table.insert(out, v)
      elseif type(v) == "table" then
        -- common field names you’ll see
        if v.text then table.insert(out, v.text) end
        if v.t    then table.insert(out, v.t)    end
        if v.s    then table.insert(out, v.s)    end
        if v.str  then table.insert(out, v.str)  end
        if v.value then table.insert(out, v.value) end
        -- nested containers
        if v.spans    then collect(v.spans)    end
        if v.segments then collect(v.segments) end
        if v.lines    then collect(v.lines)    end
      end
    end
  end

  collect(sel)
  return table.concat(out, "")
end

local function get_page_text(document)
  local ok, result = pcall(function()
    return selection_to_text(document:getTextFromPositions(
      {x = 0, y = 0},
      {x = Screen:getWidth(), y = Screen:getHeight()},
      true))
  end)
  if ok and result then return result end
  return ""
end

local function get_selection_in_context(document, selection, window)
    window = window or 10
    local page_text = get_page_text(document)
    if not page_text or not selection or selection == "" then
        return ""
    end

    -- Plain matching handles punctuation and UTF-8 without Lua-pattern escaping.
    local s_pos, e_pos = page_text:find(selection, 1, true)
    if not s_pos then
        -- Fallback if not found
        return '"' .. selection .. '"'
    end

    local before_text = page_text:sub(1, s_pos - 1)
    local after_text  = page_text:sub(e_pos + 1)

    -- Collect up to N tokens from the end of before_text
    local before_tokens = {}
    for tok in before_text:gmatch("%S+") do
        before_tokens[#before_tokens + 1] = tok
    end
    local before_start = math.max(1, #before_tokens - window + 1)
    local before = table.concat(before_tokens, " ", before_start, #before_tokens)

    -- Collect up to N tokens from the start of after_text
    local after_tokens, count = {}, 0
    for tok in after_text:gmatch("%S+") do
        after_tokens[#after_tokens + 1] = tok
        count = count + 1
        if count >= window then break end
    end
    local after = table.concat(after_tokens, " ")

    return before .. ' {{{ ' .. selection .. ' }}} ' .. after
end

return get_selection_in_context

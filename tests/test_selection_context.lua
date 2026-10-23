-- The vocabulary context extractor is a module, with no obsolete global API.
package.loaded.device = {screen = {getWidth = function() return 800 end, getHeight = function() return 1000 end}}
local context = dofile("AnkiFlashcards.koplugin/selection_context.lua")
assert(_G.get_selection_in_context == nil and _G.get_selection_in_context2 == nil)
local page, calls = "one two three acción rápida four five six", 0
local document = {getTextFromPositions = function(_, first, last, no_selection)
    assert(first.x == 0 and first.y == 0 and last.x == 800 and last.y == 1000 and no_selection)
    calls = calls + 1
    return page
end}
assert(context(document, "acción rápida", 2) == "two three {{{ acción rápida }}} four five")
page = "prefix [100%] {a+b}? suffix"
assert(context(document, "[100%] {a+b}?", 1) == "prefix {{{ [100%] {a+b}? }}} suffix")
page = {text = "before target after"}
assert(context(document, "target", 1) == "before {{{ target }}} after")
page = {{text = "before "}, {segments = {{text = "target"}, {text = " after"}}}}
assert(context(document, "target", 1) == "before {{{ target }}} after")
assert(context(document, "missing", 1) == '"missing"')
assert(context(document, "", 1) == "")
document.getTextFromPositions = function() error("Unsupported extraction") end
assert(context(document, "target", 1) == '"target"')
assert(calls == 6)
print("PASS: native vocabulary context, bounded words, literal punctuation, Unicode, nested text and no global helpers")

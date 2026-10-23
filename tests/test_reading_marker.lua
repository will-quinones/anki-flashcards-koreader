package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local queue, redraws = {}, 0
package.loaded["ui/uimanager"] = {
    scheduleIn=function(_,_,fn) queue[#queue+1]=fn end,
    unschedule=function(_,fn) for i=#queue,1,-1 do if queue[i]==fn then table.remove(queue,i) end end end,
    setDirty=function() redraws=redraws+1 end,
}
package.loaded.annotation_tools = {
    same_book=function(ui,s) return ui.document and not ui.tearing_down and s and ui.document.file==s.book.file end,
    valid_range=function(s) return s and s.pos0 and s.pos1 end,
}
local selected = {text="unrelated selection"}
local ui = {document={file="book.epub",getScreenBoxesFromPositions=function(_,a,b,segments)
    assert(a=="start" and b=="end" and segments); return {{x=10,y=20,w=80,h=12}}
end},highlight={selected_text=selected},annotation={annotations={}},view={state={page=1,pos=20},view_modules={}}}
function ui.view:registerViewModule(name,widget) self.view_modules[name]=widget end
function ui.view:pageToScreenTransform(page,box)
    assert(page==2); return {x=box.x+5,y=box.y+5,w=box.w,h=box.h}
end
local snapshot={book={file="book.epub"},selection={text="word",pos0="start",pos1="end"}}
local Marker=require("reading_marker")
local paints=0
local bb={getWidth=function() return 800 end,getHeight=function() return 1000 end,
    invertRect=function(_,x,y,w,h) paints=paints+1; assert(w>0 and h>0) end}
local function step()
    table.remove(queue,1)()
    local marker=ui.view.view_modules.ankivocab_return
    if marker then marker:paintTo(bb) end
end
Marker.flash(ui,snapshot)
while #queue>0 do step() end
assert(paints==2 and redraws==5 and not ui.view.view_modules.ankivocab_return)
assert(ui.highlight.selected_text==selected and #ui.annotation.annotations==0 and ui.view.state.pos==20)
Marker.flash(ui,snapshot); step()
local before=paints
ui.view.state.page=2
step()
assert(paints==before and not ui.view.view_modules.ankivocab_return)
Marker.flash(ui,snapshot); Marker.clear(ui)
assert(#queue==0)
ui.document.file="another.epub"
Marker.flash(ui,snapshot); assert(#queue==0)
ui.document.file="book.pdf"
snapshot.book.file="book.pdf"
snapshot.selection={pos0={page=2},pos1={page=2},pboxes={{x=10,y=20,w=80,h=12}}}
ui.document.getPageBoxesFromPositions=function(_,page,a,b) assert(page==2 and a.page==2); return snapshot.selection.pboxes end
Marker.flash(ui,snapshot)
while #queue>0 do step() end
assert(paints==before+2 and ui.highlight.selected_text==selected)
ui.tearing_down=true
Marker.flash(ui,snapshot); assert(#queue==0)
Marker.flash(nil,snapshot); Marker.flash(ui,nil)
print("PASS: EPUB/PDF source blinks twice, without annotations/selection/navigation changes; page changes and teardown stop painting")

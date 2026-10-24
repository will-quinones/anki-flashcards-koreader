package.path = "AnkiFlashcards.koplugin/?.lua;" .. package.path
local queue, redraws, requests = {}, 0, {}
local screen_width, screen_height = 800, 1000
package.loaded.device = {screen={getWidth=function() return screen_width end,getHeight=function() return screen_height end}}
package.loaded["ui/geometry"] = {new=function(_,rect) return rect end}
package.loaded["ui/uimanager"] = {
    scheduleIn=function(_,_,fn) queue[#queue+1]=fn end,
    unschedule=function(_,fn) for i=#queue,1,-1 do if queue[i]==fn then table.remove(queue,i) end end end,
    setDirty=function(_,widget,mode,region)
        assert(mode=="ui", "Blink must not advance the reader's full-refresh counter")
        assert(region and region.x>=0 and region.y>=0 and region.w>0 and region.h>0)
        assert(region.x+region.w<=screen_width and region.y+region.h<=screen_height)
        assert(region.w*region.h<screen_width*screen_height, "No full-screen blink refresh")
        requests[#requests+1]={widget=widget,region=region}
        redraws=redraws+1
    end,
}
package.loaded.annotation_tools = {
    same_book=function(ui,s) return ui.document and not ui.tearing_down and s and ui.document.file==s.book.file end,
    valid_range=function(s) return s and s.pos0 and s.pos1 end,
}
local selected = {text="unrelated selection"}
local source_boxes = {{x=10,y=20,w=80,h=12}}
local ui = {document={file="book.epub",getScreenBoxesFromPositions=function(_,a,b,segments)
    assert(a=="start" and b=="end" and segments); return source_boxes
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
assert(paints==2 and redraws==4 and not ui.view.view_modules.ankivocab_return)
for _,request in ipairs(requests) do
    local r=request.region
    assert(request.widget==ui and r.x==10 and r.y==20 and r.w==80 and r.h==12)
end
assert(ui.highlight.selected_text==selected and #ui.annotation.annotations==0 and ui.view.state.pos==20)
Marker.flash(ui,snapshot); step()
local before=paints
ui.view.state.page=2
step()
assert(paints==before and not ui.view.view_modules.ankivocab_return)
local redraw_before=redraws
Marker.flash(ui,snapshot); Marker.clear(ui)
assert(#queue==0 and redraws==redraw_before) -- Never drawn: no cleanup refresh.
Marker.flash(ui,snapshot); step()
redraw_before=redraws
Marker.clear(ui); Marker.clear(ui)
assert(#queue==0 and redraws==redraw_before+1) -- Restore visible text once.
ui.document.file="another.epub"
Marker.flash(ui,snapshot); assert(#queue==0)
ui.document.file="book.pdf"
snapshot.book.file="book.pdf"
snapshot.selection={pos0={page=2},pos1={page=2},pboxes={{x=10,y=20,w=80,h=12}}}
ui.document.getPageBoxesFromPositions=function(_,page,a,b) assert(page==2 and a.page==2); return snapshot.selection.pboxes end
Marker.flash(ui,snapshot)
while #queue>0 do step() end
assert(paints==before+3 and ui.highlight.selected_text==selected)
local r=requests[#requests].region
assert(r.x==15 and r.y==25 and r.w==80 and r.h==12) -- PDF screen transform.

-- Separate lines must remain separate refresh regions; don't repaint the
-- entire rectangle spanning their intervening whitespace. Clip to the screen
-- and cover all edge pixels when native PDF coordinates are fractional.
ui.document.file="book.epub"; snapshot.book.file="book.epub"
snapshot.selection={text="multi-line phrase",pos0="start",pos1="end"}
source_boxes={{x=-4.5,y=18.4,w=40.7,h=12.2},{x=600.6,y=45.2,w=250,h=14.1},
    {x=900,y=200,w=20,h=12},{x=30,y=30,w=0,h=10}}
requests={}; redraw_before=redraws
Marker.flash(ui,snapshot)
while #queue>0 do step() end
assert(#requests==8 and redraws==redraw_before+8)
for i,request in ipairs(requests) do
    local box=request.region
    if i%2==1 then assert(box.x==0 and box.y==18 and box.w==37 and box.h==13)
    else assert(box.x==600 and box.y==45 and box.w==200 and box.h==15) end
end
source_boxes={{x=900,y=200,w=20,h=12}}
Marker.flash(ui,snapshot); assert(#queue==0 and not ui.view.view_modules.ankivocab_return)
source_boxes={{x=10,y=20,w=80,h=12}}
Marker.flash(ui,snapshot); step()
screen_width=400
step(); assert(#queue==0 and not ui.view.view_modules.ankivocab_return)
screen_width=800
ui.tearing_down=true
Marker.flash(ui,snapshot); assert(#queue==0)
Marker.flash(nil,snapshot); Marker.flash(ui,nil)
print("PASS: EPUB/PDF blink refreshes only clipped text segments without full-refresh promotion; cleanup, viewport changes and teardown are safe")

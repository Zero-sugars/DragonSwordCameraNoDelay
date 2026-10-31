package.path='mod/Scripts/?.lua;'..package.path
local Map=require('world_map')
local Navigation=require('menu_navigation')
local function widget(name,kind)
 local w={name=name,kind=kind,shown=true,enabled=true,children={}}
 function w:GetAddress()return self.name end
 return w
end
local panel,layer=widget('map'),widget('layer')
local minus,plus,warp=widget('minus','Button'),widget('plus','Button'),widget('warp','Button')
local text=widget('caption','TextBlock');text.text='워프'
function text:GetText()return {ToString=function()return self.text end}end
local info,wrapper=widget('info'),widget('wrapper')
wrapper.children={warp,text};info.BtnInfoPopupActionSingle=wrapper
panel.InfoPopup=info;panel.LayerMap=layer;panel.BtnMinus=minus;panel.BtnPlus=plus
local function slot()
 local s=widget('slot');s.position={X=-500,Y=-600}
 function s:GetPosition()return {X=self.position.X,Y=self.position.Y}end
 function s:GetSize()return {X=100,Y=30}end
 function s:SetPosition(p)self.position=p end
 return s
end
local inside,outside=slot(),slot();layer.MapOverlaySlot=inside;layer.MapOverlayOutSideSlot=outside
layer.MapOverlay=widget('map-art')
local clicked={}
local geometryReads=0
local function displayed(w)return w~=nil and w.shown and w.enabled end
local function walk(w,callback)
 if not displayed(w)then return end
 callback(w)
 for _,c in ipairs(w.children)do walk(c,callback)end
end
local map=Map.new({valid=function(w)return w~=nil end,read=function(w,k)return w and w[k]end,
 displayed=displayed,isA=function(w,k)return w.kind==k end,walk=walk,
 geometry=function(w)
  geometryReads=geometryReads+1
  if w==layer.MapOverlay then return {w=3000,h=2800,localW=3000,localH=2800}end
  return {w=1000,h=700,localW=1000,localH=700}
 end,
 activate=function(w)clicked[#clicked+1]=w.name end})
local state=map:context(panel)
assert(state.warp==warp and #map:hints(state)==3)
assert(map:zoom(state,-1)and clicked[1]=='minus')
assert(map:zoom(state,1)and clicked[2]=='plus')
assert(map:pan(state,'up')and inside.position.Y==-504 and outside.position.Y==-504)
assert(map:pan(state,'right')and inside.position.X==-596 and outside.position.X==-596)
for _=1,100 do map:pan(state,'right');map:pan(state,'down')end
assert(inside.position.X==-2000 and inside.position.Y==-2100)
assert(outside.position.X==inside.position.X and outside.position.Y==inside.position.Y)
assert(map:warp(state)and clicked[3]=='warp')
text.text='근처로 워프'
local nearby=map:context(panel)
assert(nearby.warp==warp,'Nearby Warp uses the visible native map action')
local hints=map:hints(nearby)
assert(#hints==3 and hints[3].widget==warp and hints[3].key=='F','Nearby Warp also shows F')
assert(map:warp(nearby)and clicked[4]=='warp','F can invoke Nearby Warp')
text.text='<Action>근처로\n 워프</>'
assert(map:context(panel).warp==warp,'Rich-text markup and whitespace do not hide the warp action')
text.text='확인'
assert(not map:warp(nearby)and #clicked==4,'Reused Nearby Warp must not invoke a different action')
for _,caption in ipairs({'워프 취소','근처로 워프 취소','추적 중지'})do
 text.text=caption;assert(not map:context(panel).warp,'Only exact warp actions are eligible')
end
text.text='근처로 워프';wrapper.shown=false
assert(not map:warp(state),'Hidden info action must not execute')
wrapper.shown=true;warp.enabled=false
assert(not map:warp(state),'Disabled warp button must not execute')
warp.enabled=true
local context={scope='map',map=map:context(panel),items={},tabs={}}
local adapter={snapshot=function()return context end,
 panMap=function(_,c,d)return map:pan(c.map,d)end,
 zoomMap=function(_,c,d)return map:zoom(c.map,d)end,
 warpMap=function(_,c)return map:warp(c.map)end}
local n=Navigation.new(adapter)
local before=#clicked
assert(not n:confirm()and #clicked==before,'Space must be inert on the map')
context.secondaryTabs={{active=true},{}}
assert(not n:tab(1,true)and not n:tab(-1,true)and #clicked==before,'1/3 must not zoom or activate tabs on the map')
assert(n:interact()and #clicked==before+1)
n:toggle();assert(not n:interact()and not n:move('up')and not n:tab(1))
n:toggle();context={scope='popup',confirmation=true,items={}}
assert(not n:interact(),'A popup in front of the map must block F')
-- Holding a direction has equal speed across display frame rates, with no
-- per-frame geometry work or larger diagonal movement.
for _,fps in ipairs({30,60,144,240})do
 inside.position={X=-300,Y=-300};outside.position={X=-300,Y=-300}
 local motionState=map:context(panel);assert(map:preparePan(motionState))
 local reads=geometryReads
 for _=1,fps do assert(map:motion(motionState,-1,0,1/fps))end
 assert(math.abs(inside.position.X+1700)<0.001 and inside.position.Y==-300,'Hold speed must be 1400 units/s at every frame rate')
 assert(outside.position.X==inside.position.X and geometryReads==reads,'Both layers move together without frame-time geometry reads')
end
inside.position={X=-300,Y=-300};outside.position={X=-300,Y=-300}
local motionState=map:context(panel);map:preparePan(motionState)
for _=1,120 do map:motion(motionState,-1,-1,1/120)end
local dx,dy=inside.position.X+300,inside.position.Y+300
assert(math.abs(math.sqrt(dx*dx+dy*dy)-1400)<0.001,'Diagonal speed must match straight movement')
local x,y=inside.position.X,inside.position.Y
assert(not map:motion(motionState,0,0,1),'Opposite directions cancel without movement')
assert(inside.position.X==x and inside.position.Y==y)
map:motion(motionState,1,0,10)
assert(math.abs(inside.position.X-x-70)<0.001,'A long hitch is capped instead of causing a jump')
return 'world map: WASD layers/clamps, Q/E zoom, F and hint for Warp/Nearby Warp, rich-text captions, visible/enabled/reused-action gates, no Space action, F7/popup isolation PASS'

package.path='mod/Scripts/?.lua;'..package.path
local serial,hook,focus,clicks=0,nil,0,0
local keys,loops={},{}
local function proxy(value) return {get=function()return value end} end
local function array(values)
    return {ForEach=function(_,cb)for i,v in ipairs(values)do cb(i,proxy(v))end end}
end
local function map(values)
    return {ForEach=function(_,cb)for k,v in pairs(values)do cb(proxy(k),proxy(v))end end}
end
local function object(name,types,bounds)
    serial=serial+1
    local o={name=name,address=serial,types=types or {},bounds=bounds or {x=0,y=0,w=1000,h=700},visibility=0,opacity=1,alive=true,children={}}
    function o:IsValid()return self.alive end
    function o:GetAddress()return self.address end
    function o:GetFullName()return self.name end
    function o:GetFName()return {ToString=function()return self.name end}end
    function o:GetClass()return self end
    function o:IsA(c)return self.types[c.name]==true end
    function o:GetVisibility()return self.visibility end
    function o:GetIsEnabled()return true end
    function o:GetRenderOpacity()return self.opacity end
    function o:SetRenderOpacity(value)self.opacity=value end
    function o:IsInViewport()return self.viewport==true end
    function o:GetParent()return self.parent end
    function o:GetOuter()return self.outer end
    function o:GetChildrenCount()return #self.children end
    function o:GetChildAt(index)return self.children[index+1]end
    function o:GetCachedGeometry()hook(proxy(self),proxy(self.bounds));return {}end
    function o:HasKeyboardFocus()return self.focused==true end
    function o:HasFocusedDescendants()return false end
    function o:CallFunction(fn,...)return fn(self,...)end
    return o
end
local function widget(name,kind,bounds)
    local types={Widget=true,[kind]=true}
    if kind=='Button' or kind=='PanelWidget' then types.PanelWidget=true end
    return object(name,types,bounds)
end
local function delegate(bindings)return {GetBindings=function()return bindings or {}end}end
local target=object('handler');target.Click=function()clicks=clicks+1 end
local function button(name,y)
    local b=widget(name,'Button',{x=20,y=y,w=120,h=40})
    b.OnClicked=delegate({{Object=target,FunctionName={ToString=function()return 'Click'end}}})
    b.OnReleased=delegate();b.OnPressed=delegate();b.OnHovered=delegate();b.OnUnhovered=delegate()
    return b
end
local a,b,offscreen,hidden=button('first',100),button('second',160),button('offscreen',900),button('hidden',220)
local hiddenParent=widget('hidden-parent','PanelWidget');hiddenParent.visibility=1;hiddenParent.children={hidden}
local canvas=widget('canvas','PanelWidget');canvas.children={a,b,offscreen,hiddenParent}
local menu=widget('DPanelOption_C','UserWidget');menu.viewport=true
menu.WidgetTree=object('tree');menu.WidgetTree.RootWidget=canvas
local hud=widget('DPanelMain_PC_C','UserWidget');hud.viewport=true
local root=widget('DRootIngame_C','UserWidget')
local pool={[3]={PanelBase=hud,ZOrder=10,PopupPanelType=0}}
root.PanelPool=map(pool)
local manager=object('manager');manager.CurrentRootPanelInstance=root;manager.PanelUIDefault=array({3})
local controller=object('controller');controller.IsLocalController=function()return true end
local slate=object('slate')
function slate:GetLocalSize(g)return {X=g.w,Y=g.h}end
function slate:LocalToAbsolute(g,p)return {X=g.x+p.X,Y=g.y+p.Y}end
local library=object('library');library.SetFocusToGameViewport=function()focus=focus+1 end
local entryLibrary=object('entry-library');entryLibrary.GetListItemObject=function(_,entry)return entry.data end
local classes={}
StaticFindObject=function(path)
    if path:find('Default__SlateBlueprintLibrary',1,true)then return slate end
    if path:find('Default__WidgetBlueprintLibrary',1,true)then return library end
    if path:find('Default__UserObjectListEntryLibrary',1,true)then return entryLibrary end
    local name=path:match('%.([^%.]+)$')
    if not classes[name]then classes[name]=object(name)end
    return classes[name]
end
local focusedText,mainLayers={},{}
FindAllOf=function(name)
    if name=='PlayerController'then return {controller}end
    if name=='EditableTextBox'then return focusedText end
    if name=='DLayerMainMenu'then return mainLayers end
    return {}
end
FindFirstOf=function(name)assert(name=='DUIManager');return manager end
RegisterHook=function(path,pre,post)assert(path=='/Script/UMG.Widget:GetCachedGeometry');hook=post;return 1,2 end
UnregisterHook=function(path,pre,post)assert(path=='/Script/UMG.Widget:GetCachedGeometry' and pre==1 and post==2);hook=nil end
RegisterKeyBind=function(key,cb)keys[key]=cb end
ExecuteInGameThread=function(cb)cb()end
LoopAsync=function(_,cb)loops[#loops+1]=cb end
Key={F7=7,W=87,A=65,S=83,D=68,SPACE=32,Q=81,E=69,LEFT_MOUSE_BUTTON=1}
local logs={}
local runtime=require('menu_keyboard').start(function(s)logs[#logs+1]=s end)
assert(runtime.adapter:snapshot()==nil,'Gameplay HUD must be excluded')
assert(hook==nil,'Gameplay must not install a geometry hook')
pool[31]={PanelBase=menu,ZOrder=100,PopupPanelType=0}
local context=assert(runtime.adapter:snapshot())
assert(#context.items==2,'Hidden/clipped widgets must be excluded')
assert(hook==nil,'Temporary geometry hook must be removed after scanning')
keys[Key.S]();assert(runtime.navigation.selected.id=='first')
keys[Key.S]();assert(runtime.navigation.selected.id=='second')
keys[Key.SPACE]();assert(clicks==1 and focus==2)
keys[Key.F7]();keys[Key.S]();keys[Key.SPACE]();assert(clicks==1 and not runtime.navigation.enabled)
keys[Key.F7]();keys[Key.S]()
local text=widget('editing','EditableTextBox');text.focused=true;focusedText={text}
keys[Key.SPACE]();assert(clicks==1 and runtime.navigation.selected==nil)
focusedText={}
keys[Key.S]();pool[31]=nil;loops[1]()
assert(runtime.navigation.selected==nil and runtime.adapter:snapshot()==nil)
-- Virtualized rows are identified by their data object as well as the recycled widget.
pool[31]={PanelBase=menu,ZOrder=100,PopupPanelType=0}
local data=object('item-data')
local entry=widget('entry','UserWidget',{x=200,y=100,w=80,h=80});entry.data=data
entry.WidgetTree=object('entry-tree');entry.WidgetTree.RootWidget=widget('image','Widget',entry.bounds)
local list=widget('list','ListViewBase',{x=180,y=80,w=500,h=500})
list.GetDisplayedEntryWidgets=function()return {proxy(entry)}end
list.BP_SetSelectedItem=function(_,value)assert(value==entry.data)end
local itemClicks=0
target.ItemClick=function(_,value)assert(value==entry.data);itemClicks=itemClicks+1 end
list.BP_OnItemClicked=delegate({{Object=target,FunctionName={ToString=function()return 'ItemClick'end}}})
canvas.children={list}
keys[Key.S]();assert(runtime.navigation.selected.kind=='entry')
keys[Key.SPACE]();assert(itemClicks==1)
keys[Key.S]();entry.data=object('recycled-row-data')
keys[Key.SPACE]();assert(itemClicks==1,'Recycled row must not inherit a pending confirmation')
runtime.navigation:clear()
-- Checked tabs can expand visually; vertical order must still follow their centers.
local boxes={}
local tabWidgets={}
for index=1,3 do
    local cb=widget('toggle'..index,'CheckBox',{x=50,y=index*130,w=304,h=100})
    cb.types.DCheckBox=true;cb.GroupType=2;cb.checked=index==1
    cb.IsChecked=function(self)return self.checked end
    cb.SetIsChecked=function(self,value)self.checked=value end
    cb.CheckStateChanged=function(self,value)
        for _,other in ipairs(boxes)do
            other.checked=(other==self and value)
            other.bounds.x=other.checked and 20 or 50
            other.bounds.w=other.checked and 365 or 304
        end
    end
    boxes[index]=cb
    local tab=widget('DGameTab'..index,'UserWidget');tab.parent=canvas
    tab.WidgetTree=object('tab-tree');tab.WidgetTree.RootWidget=cb;tabWidgets[index]=tab
end
boxes[1]:CheckStateChanged(true)
canvas.children=tabWidgets
keys[Key.E]();assert(boxes[2].checked)
keys[Key.E]();assert(boxes[3].checked)
keys[Key.E]();assert(boxes[1].checked)
assert(hook==nil,'Geometry hook must not remain installed after menu operations')
pool[31]=nil
local main=widget('DLayerMainMenu','UserWidget')
main.WidgetTree=object('main-tree');main.WidgetTree.RootWidget=button('main-action',100)
local overlay=widget('menu-overlay','PanelWidget');main.parent=overlay;overlay.parent=hud
mainLayers={main};controller.bShowMouseCursor=true
context=assert(runtime.adapter:snapshot());assert(context.scope=='DLayerMainMenu')
overlay.visibility=1
assert(runtime.adapter:snapshot()==nil,'Collapsed menu ancestor must exclude HUD buttons')
overlay.visibility=0;controller.bShowMouseCursor=false
assert(runtime.adapter:snapshot()==nil,'Normal gameplay must exclude embedded menu')
for _,s in ipairs(logs)do assert(not s:find('ERROR',1,true),s)end
return 'menu runtime: native geometry, HUD/text exclusion, one click, F7, recycled rows, scaled Q/E tabs PASS'

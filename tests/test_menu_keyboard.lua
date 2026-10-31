package.path='mod/Scripts/?.lua;'..package.path
local serial,hook,focus,clicks,hookCount=0,nil,0,0,0
local geometryCalls,globalQueries=0,0
local onInput=false
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
    function o:GetClass()return self.classObject or self end
    function o:IsA(c)return self.types[c.name]==true end
    function o:GetVisibility()return self.visibility end
    function o:GetIsEnabled()return self.enabled~=false end
    function o:GetRenderOpacity()return self.opacity end
    function o:SetRenderOpacity(value)self.opacity=value end
    function o:IsInViewport()return self.viewport==true end
    function o:GetParent()return self.parent end
    function o:GetOuter()return self.outer end
    function o:GetChildrenCount()return #self.children end
    function o:GetChildAt(index)return self.children[index+1]end
    function o:GetCachedGeometry()geometryCalls=geometryCalls+1;hook(proxy(self),proxy(self.bounds));return {}end
    function o:HasKeyboardFocus()return self.focused==true end
    function o:HasFocusedDescendants()return false end
    function o:IsHovered()return self.hovered==true end
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
hud.types.DPanelMain=true
local root=widget('DRootIngame_C','UserWidget')
local pool={[3]={PanelBase=hud,ZOrder=10,PopupPanelType=0}}
root.PanelPool=map(pool)
local manager=object('manager');manager.CurrentRootPanelInstance=root;manager.PanelUIDefault=array({3})
local controller=object('controller');controller.IsLocalController=function()return true end
local slate=object('slate')
function slate:GetLocalSize(g)return {X=g.w,Y=g.h}end
function slate:LocalToAbsolute(g,p)return {X=g.x+p.X,Y=g.y+p.Y}end
local library=object('library');library.SetFocusToGameViewport=function()focus=focus+1 end
local mousePosition={X=0,Y=0}
local layoutLibrary=object('layout-library')
layoutLibrary.GetMousePositionOnPlatform=function()return mousePosition end
local entryLibrary=object('entry-library');entryLibrary.GetListItemObject=function(_,entry)return entry.data end
local classes={}
StaticFindObject=function(path)
    if path:find('Default__SlateBlueprintLibrary',1,true)then return slate end
    if path:find('Default__WidgetBlueprintLibrary',1,true)then return library end
    if path:find('Default__WidgetLayoutLibrary',1,true)then return layoutLibrary end
    if path:find('Default__UserObjectListEntryLibrary',1,true)then return entryLibrary end
    local name=path:match('%.([^%.]+)$')
    if not classes[name]then classes[name]=object(name)end
    return classes[name]
end
local focusedText,mainLayers,blueprintMainLayers,popups={},{},{},{}
local localControllers={controller}
local viewport=object('viewport')
viewport.GetWidgetSlot=function(_,widget)return {ZOrder=widget.viewportZ or 0}end
FindAllOf=function(name)
    globalQueries=globalQueries+1
    if name=='PlayerController'then return localControllers end
    if name=='EditableTextBox'then return focusedText end
    if name=='DLayerMainMenu'then return mainLayers end
    if name=='DLayerMainMenu_C'then return blueprintMainLayers end
    if name=='DPopupBase'then return popups end
    return {}
end
FindFirstOf=function(name)
    if name=='DUIManager'then return manager end
    assert(name=='GameViewportSubsystem');return viewport
end
RegisterHook=function(path,pre,post)
    assert(not onInput and hook==nil and path=='/Script/UMG.Widget:GetCachedGeometry')
    hookCount=hookCount+1;hook=post;return 1,2
end
UnregisterHook=function()error('Geometry hook must not churn during navigation')end
RegisterKeyBind=function(key,cb)
    keys[key]=function() onInput=true;cb();onInput=false;loops[16]() end
end
ExecuteInGameThread=function()error('Input must not schedule native callbacks')end
LoopAsync=function()error('Do not reintroduce cross-thread callback registration')end
LoopInGameThreadWithDelay=function(delay,cb)assert(not onInput);loops[delay]=cb end
LoopInGameThreadAfterFrames=function(delay,cb)assert(not onInput and delay==1);loops.frame=cb end
Key={F7=7,W=87,A=65,S=83,D=68,F=70,SPACE=32,Q=81,E=69,ONE=49,THREE=51,LEFT_MOUSE_BUTTON=1}
local logs={}
local now=0
local runtimeOptions={hints=false,clock=function()return now end}
local runtime=require('menu_keyboard').start(function(s)logs[#logs+1]=s end,runtimeOptions)
assert(runtime.adapter:snapshot()==nil,'Gameplay HUD must be excluded')
assert(hook==nil,'Gameplay must not install a geometry hook')
keys[Key.ONE]();keys[Key.THREE]();assert(hook==nil)
pool[31]={PanelBase=menu,ZOrder=100,PopupPanelType=0}
local context=assert(runtime.adapter:snapshot())
assert(#context.items==2,'Hidden/clipped widgets must be excluded')
assert(hookCount==1,'Menu scanning must reuse one native geometry hook')
keys[Key.S]();assert(runtime.navigation.selected.id=='first')
keys[Key.S]();assert(runtime.navigation.selected.id=='second')
keys[Key.SPACE]();assert(clicks==1 and focus==2)
keys[Key.F7]();keys[Key.S]();keys[Key.SPACE]();assert(clicks==1 and not runtime.navigation.enabled)
keys[Key.F7]();keys[Key.S]()
local text=widget('editing','EditableTextBox');text.parent=menu;text.focused=true;focusedText={text}
keys[Key.SPACE]();assert(clicks==1 and runtime.navigation.selected==nil)
text.visibility=1
keys[Key.S]();assert(runtime.navigation.selected~=nil,'Hidden stale text focus must not block the menu')
text.visibility=0;runtime.navigation:clear()
focusedText={}
keys[Key.S]();pool[31]=nil;loops[250]()
assert(runtime.navigation.selected==nil and runtime.adapter:snapshot()==nil)
-- Virtualized rows are identified by their data object as well as the recycled widget.
pool[31]={PanelBase=menu,ZOrder=100,PopupPanelType=0}
local data=object('item-data')
local entry=widget('entry','UserWidget',{x=200,y=100,w=80,h=80});entry.data=data
entry.WidgetTree=object('entry-tree');entry.WidgetTree.RootWidget=widget('image','Widget',entry.bounds)
local list=widget('list','ListViewBase',{x=180,y=80,w=500,h=500})
list.GetDisplayedEntryWidgets=function()return {proxy(entry)}end
list.BP_SetSelectedItem=function()error('Movement must not dispatch native item selection')end
local itemClicks=0
target.ItemClick=function(_,value)assert(value==entry.data);itemClicks=itemClicks+1 end
list.BP_OnItemClicked=delegate({{Object=target,FunctionName={ToString=function()return 'ItemClick'end}}})
canvas.children={list}
keys[Key.S]();assert(runtime.navigation.selected.kind=='entry' and entry.opacity==0.65)
keys[Key.SPACE]();assert(itemClicks==1 and entry.opacity==1)
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
for _=1,500 do keys[Key.E]();keys[Key.Q]() end
keys[Key.F7]();keys[Key.E]();keys[Key.Q]();assert(boxes[1].checked)
keys[Key.F7]()
assert(hookCount==1,'Rapid navigation must not register or release native hook refs')
-- Equipment adds a nested group; a wider group must not take over Q/E.
local function makeTabs(name,parent,count,levelY,step)
    local group,widgets={},{}
    for index=1,count do
        local cb=widget(name..index,'CheckBox',{x=360+(index-1)*step,y=levelY,w=75,h=48})
        cb.types.DCheckBox=true;cb.GroupType=2;cb.checked=index==1
        cb.IsChecked=function(self)return self.checked end
        cb.SetIsChecked=function(self,value)self.checked=value end
        cb.CheckStateChanged=function(self,value)
            for _,other in ipairs(group)do other.checked=(other==self and value)end
        end
        group[index]=cb
        local tab=widget('D'..name..'Tab'..index,'UserWidget');tab.parent=parent
        tab.WidgetTree=object(name..'-tree');tab.WidgetTree.outer=tab
        tab.WidgetTree.RootWidget=cb;cb.outer=tab.WidgetTree
        widgets[index]=tab
    end
    return group,widgets
end
local gearCanvas=widget('gear-canvas','PanelWidget')
local gear=widget('DEquipmentLayer','UserWidget');gear.parent=canvas
gear.WidgetTree=object('gear-tree');gear.WidgetTree.RootWidget=gearCanvas
local gearBoxes,gearTabs=makeTabs('Gear',gearCanvas,5,80,135)
local tertiaryCanvas=widget('tertiary-canvas','PanelWidget')
local tertiary=widget('DDetailLayer','UserWidget');tertiary.parent=gearCanvas
tertiary.WidgetTree=object('tertiary-tree');tertiary.WidgetTree.RootWidget=tertiaryCanvas
local thirdBoxes,thirdTabs=makeTabs('Third',tertiaryCanvas,3,600,230)
tertiaryCanvas.children=thirdTabs
gearCanvas.children={gearTabs[1],gearTabs[2],gearTabs[3],gearTabs[4],gearTabs[5],tertiary}
canvas.children={tabWidgets[1],tabWidgets[2],tabWidgets[3],gear,a}
context=assert(runtime.adapter:snapshot())
assert(#context.tabs==3 and context.tabs[1].widget==boxes[1])
assert(#context.secondaryTabs==5 and context.secondaryTabs[1].widget==gearBoxes[1])
assert(#context.items==1 and context.items[1].widget==a,'Secondary and third-level tabs must be excluded from WASD items')
assert(#context.hints==2 and context.hints[1].key=='Q/E' and context.hints[2].key=='1/3')
keys[Key.THREE]();assert(gearBoxes[2].checked and boxes[1].checked and thirdBoxes[1].checked)
keys[Key.ONE]();assert(gearBoxes[1].checked)
keys[Key.ONE]();assert(gearBoxes[5].checked)
keys[Key.THREE]();assert(gearBoxes[1].checked)
keys[Key.E]();assert(boxes[2].checked and gearBoxes[1].checked)
keys[Key.Q]();assert(boxes[1].checked)
for _=1,500 do keys[Key.THREE]();keys[Key.ONE]()end
assert(gearBoxes[1].checked and thirdBoxes[1].checked and hookCount==1)
keys[Key.F7]();keys[Key.THREE]();keys[Key.ONE]();assert(gearBoxes[1].checked);keys[Key.F7]()
focusedText={text};keys[Key.THREE]();assert(gearBoxes[1].checked);focusedText={}
-- A newly shown group at the same depth cannot replace the already known primary.
local peerCanvas=widget('peer-canvas','PanelWidget')
local peerBoxes,peerTabs=makeTabs('Peer',peerCanvas,3,500,270)
peerCanvas.children=peerTabs;canvas.children={tabWidgets[1],tabWidgets[2],tabWidgets[3],peerCanvas}
context=assert(runtime.adapter:snapshot())
assert(context.tabs[1].widget==boxes[1] and context.secondaryTabs[1].widget==peerBoxes[1])
-- Hidden groups disappear, and 1/3 never fall through to the main tabs.
peerCanvas.visibility=1
keys[Key.THREE]();keys[Key.ONE]();assert(boxes[1].checked)
context=assert(runtime.adapter:snapshot());assert(#context.secondaryTabs==0 and #context.items==0 and #context.hints==1)
-- A fresh panel with all three groups already open still uses the outer group.
local fresh=widget('DPanelHero_C','UserWidget');fresh.viewport=true
fresh.WidgetTree=object('fresh-tree');fresh.WidgetTree.RootWidget=canvas
canvas.children={gear,tabWidgets[3],tabWidgets[1],tabWidgets[2]}
pool[31].PanelBase=fresh
context=assert(runtime.adapter:snapshot())
assert(context.tabs[1].widget==boxes[1] and context.secondaryTabs[1].widget==gearBoxes[1])
keys[Key.D]();assert(runtime.navigation.selected==nil,'Ignored tab groups must not be selected using WASD')
-- Exercise the real hint adapter/cache on a visible panel, including F7 cleanup.
canvas.types.CanvasPanel=true;canvas.outer=fresh.WidgetTree;fresh.WidgetTree.outer=fresh
gearCanvas.outer=gear.WidgetTree;gear.WidgetTree.outer=gear
tertiaryCanvas.outer=tertiary.WidgetTree;tertiary.WidgetTree.outer=tertiary
for index,tab in ipairs(tabWidgets)do tab.WidgetTree.outer=tab;boxes[index].outer=tab.WidgetTree end
local labels,createdLabels,removedLabels={},0,0
FText=function(value)return value end
StaticConstructObject=function(c,outer)
    assert(c.name=='TextBlock')
    local label=widget('hint-'..tostring(createdLabels),'TextBlock');label.Font={}
    label.SetText=function(self,text)self.text=text end
    label.SetFont=function(self,font)self.Font=font end
    label.SetVisibility=function(self,value)self.visibility=value end
    label.SetShadowOffset=function()end;label.SetShadowColorAndOpacity=function()end
    label.RemoveFromParent=function(self)self.alive=false;removedLabels=removedLabels+1 end
    createdLabels=createdLabels+1;labels[#labels+1]=label
    return label
end
canvas.AddChildToCanvas=function(self,label)
    local slot={}
    slot.SetSize=function(s,size)s.size=size end
    slot.SetZOrder=function(s,z)s.z=z end
    slot.SetPosition=function(s,p)s.position=p end
    label.parent=self;label.Slot=slot;return slot
end
runtimeOptions.hints=true;loops[250]()
assert(createdLabels==2 and labels[1].Font.Size==16 and labels[1].Slot.size.X==38)
assert(labels[1].text=='Q/E' and labels[2].text=='1/3' and labels[2].visibility==3)
keys[Key.THREE]();loops[250]()
assert(gearBoxes[2].checked and createdLabels==2 and removedLabels==0,'Switching tabs reuses both label objects')
gear.visibility=1;loops[250]()
assert(removedLabels==1 and createdLabels==2,'Hidden secondary group removes its label')
gear.visibility=0;keys[Key.E]();loops[250]()
assert(createdLabels==3 and #runtime.adapter:snapshot().hints==2)
keys[Key.F7]();assert(removedLabels==3 and next(runtime.hints.labels)==nil)
runtimeOptions.hints=false;keys[Key.F7]()
pool[31].PanelBase=menu
pool[31]=nil
local main=widget('DLayerMainMenu','UserWidget')
main.WidgetTree=object('main-tree');main.WidgetTree.RootWidget=button('main-action',100)
local overlay=widget('menu-overlay','PanelWidget');main.parent=overlay;overlay.parent=hud
mainLayers={main};controller.bShowMouseCursor=true
context=assert(runtime.adapter:snapshot());assert(context.scope=='DLayerMainMenu')
overlay.visibility=1
assert(runtime.adapter:snapshot()==nil,'Collapsed menu ancestor must exclude HUD buttons')
overlay.visibility=0;controller.bShowMouseCursor=false
context=assert(runtime.adapter:snapshot());assert(context.scope=='DLayerMainMenu','Visible main menu works with hidden mouse cursor')
local mainBefore=clicks
keys[Key.S]();assert(runtime.navigation.selected.widget.opacity==0.65,'Main menu buttons visibly mark keyboard selection')
keys[Key.SPACE]();assert(clicks==mainBefore+1,'Main menu supports WASD selection and Space activation')
manager.alive=false
assert(runtime.adapter:snapshot().scope=='DLayerMainMenu','An already visible menu is independent of manager availability')
manager.alive=true;overlay.visibility=1
assert(runtime.adapter:snapshot()==nil,'Normal gameplay excludes the hidden main menu')
-- The in-game menu is a Blueprint layer embedded in the HUD, above a pooled panel.
overlay.visibility=0;main.name='DLayerMainMenu_C';mainLayers={};hud.DLayerMainMenu=main
pool[31]={PanelBase=menu,ZOrder=300,PopupPanelType=0}
assert(runtime.adapter:snapshot().scope=='DLayerMainMenu_C','Visible HUD-owned main menu covers an older pooled panel')
hud.DLayerMainMenu=nil;blueprintMainLayers={main}
assert(runtime.adapter:snapshot().scope=='DLayerMainMenu_C','Blueprint-only menu class can also be discovered')
overlay.visibility=1;assert(runtime.adapter:snapshot().scope=='DPanelOption_C')
pool[31]=nil;assert(runtime.adapter:snapshot()==nil)
-- Global X controls never enter the selection list; labelled Quit remains an action.
overlay.visibility=0
local mainClose=button('DButton_CloseMainMenu',20)
local mainQuit=button('CloseGame',220)
local quitLabel=widget('QuitCaption','TextBlock',{x=40,y=230,w=80,h=20})
quitLabel.GetText=function()return {ToString=function()return '게임 종료'end}end
mainQuit.children={quitLabel}
main.WidgetTree.RootWidget=widget('main-actions','PanelWidget')
main.WidgetTree.RootWidget.children={mainClose,button('Inventory',100),mainQuit}
main.WidgetTree.outer=main;main.WidgetTree.RootWidget.outer=main.WidgetTree
for _,child in ipairs(main.WidgetTree.RootWidget.children)do child.parent=main.WidgetTree.RootWidget end
context=assert(runtime.adapter:snapshot());assert(#context.items==2)
for _,item in ipairs(context.items)do assert(item.widget~=mainClose)end
keys[Key.S]();assert(runtime.navigation.selected.widget.name=='Inventory')
keys[Key.S]();assert(runtime.navigation.selected.widget==mainQuit)
-- Hover and keyboard share selection, without fighting a stationary pointer.
main.name='DLayerMainMenu';main.classObject=object('DLPAN_LayerPanel_Main_PC_C')
hud.DLayerMainMenu=main
assert(runtime.adapter:snapshot().mouseNavigation,'The real HUD instance name enables mouse selection despite its different Blueprint class')
controller.bShowMouseCursor=true
local inventory=main.WidgetTree.RootWidget.children[2]
local nativeHoverCalls=0
target.Hover=function()nativeHoverCalls=nativeHoverCalls+1 end
inventory.OnHovered=delegate({{Object=target,FunctionName={ToString=function()return 'Hover'end}}})
local function pointAt(widget,x,y)
    -- The game's common-button wrapper can hover while its native Button cannot.
    for _,item in ipairs({inventory,mainQuit,mainClose})do item.hovered=false end
    mousePosition={X=x,Y=y}
end
local hoverBefore=clicks
pointAt(inventory,50,120);loops[50]()
assert(runtime.navigation.selected.widget==inventory and clicks==hoverBefore and nativeHoverCalls==0,
    'Native hover transfers selection without clicking or replaying OnHovered')
local measured,searched=geometryCalls,globalQueries
for i=1,200 do pointAt(inventory,50+i%10,120);loops[50]()end
assert(geometryCalls==measured and globalQueries==searched,
    'Mouse polling must perform ZERO geometry reads and global searches, including while moving')
now=1
runtime.adapter:snapshot()
local iconMeasures=geometryCalls
local oldInventoryGeometry=inventory.GetCachedGeometry
inventory.GetCachedGeometry=function()error('Settled menu must reuse icon geometry')end
for _=1,10 do loops[250]()end
assert(geometryCalls-iconMeasures<=12,'Settled refresh measures only the menu root instead of all icons')
inventory.GetCachedGeometry=oldInventoryGeometry
now=0 -- Other fixture edits exercise fresh menu layouts rather than the settled cache.
local retainedHover=nativeHoverCalls
inventory.opacity=1 -- Simulate the native mouse-leave visual reset.
pointAt(nil,500,600);loops[50]()
assert(runtime.navigation.selected.widget==inventory and inventory.opacity==0.65 and nativeHoverCalls==retainedHover+1,
    'Leaving an icon keeps selection and restores its visible keyboard cursor once')
for _=1,25 do loops[50]()end
assert(nativeHoverCalls==retainedHover+1,'A retained cursor must not replay hover every tick')
pointAt(inventory,50,120);loops[50]()
keys[Key.S]();assert(runtime.navigation.selected.widget==mainQuit,'WASD continues from the mouse-selected item')
for _=1,25 do loops[50]()end
assert(runtime.navigation.selected.widget==mainQuit,'Stationary mouse does not steal keyboard selection')
keys[Key.SPACE]();assert(clicks==hoverBefore+1,'Space executes the keyboard-selected action despite stationary hover')
loops[250]() -- Existing UI refresh rearms mouse selection after an action.
pointAt(inventory,51,120);loops[50]()
assert(runtime.navigation.selected.widget==inventory,'Moving inside the same hovered item resumes mouse selection')
pointAt(mainQuit,50,240);keys[Key.SPACE]()
assert(clicks==hoverBefore+2 and runtime.navigation.selected==nil,'Space reads a newly hovered item even before the poll')
pointAt(inventory,52,120);keys[Key.S]();assert(runtime.navigation.selected.widget==mainQuit)
pointAt(mainClose,50,35);loops[50]()
assert(runtime.navigation.selected.widget==mainQuit,'X remains excluded from mouse/keyboard synchronization')
inventory.enabled=false;pointAt(inventory,52,120);runtime.navigation:clear();loops[50]()
assert(runtime.navigation.selected==nil,'Disabled hover target is excluded')
inventory.enabled=true;inventory.visibility=1;loops[50]()
assert(runtime.navigation.selected==nil,'Hidden hover target is excluded')
inventory.visibility=0
keys[Key.F7]();pointAt(mainQuit,50,241);loops[50]();assert(runtime.navigation.selected==nil,'F7 OFF disables hover synchronization')
keys[Key.F7]();loops[50]();assert(runtime.navigation.selected.widget==mainQuit)
focusedText={text};pointAt(inventory,53,120);keys[Key.SPACE]();loops[50]()
assert(runtime.navigation.selected==nil,'Text entry blocks hover synchronization')
focusedText={};controller.bShowMouseCursor=false;loops[250]();loops[50]()
assert(runtime.navigation.selected.widget==inventory,'Game UI cursor position remains usable when the controller cursor flag is false')
controller.bShowMouseCursor=true
local hoverModal=widget('hover-modal','UserWidget');hoverModal.viewport=true
hoverModal.types.DPopupBase=true;hoverModal.types.DPopupDefault=true
hoverModal.WidgetTree=object('hover-modal-tree');hoverModal.WidgetTree.RootWidget=button('hover-confirm',500)
popups={hoverModal};pointAt(mainQuit,50,242);loops[50]()
keys[Key.SPACE]();assert(clicks==hoverBefore+3 and runtime.navigation.selected==nil,'Front popup receives Space instead of the hovered menu behind it')
loops[50]();assert(runtime.navigation.selected==nil)
popups={};runtime.navigation:clear();pointAt(nil,0,0)
overlay.visibility=1;pool[31]={PanelBase=menu,ZOrder=100,PopupPanelType=0};a.hovered=true
loops[50]();assert(runtime.navigation.selected==nil,'Hover synchronization is limited to the in-game icon menu')
a.hovered=false;pool[31]=nil;overlay.visibility=0
-- A translated/offscreen closed menu must not capture gameplay.
mainQuit.bounds.y=900
main.WidgetTree.RootWidget.children[2].bounds.y=900
assert(runtime.adapter:snapshot()==nil,'A visible but offscreen main-menu shell is excluded')
overlay.visibility=1;blueprintMainLayers={};mainLayers={}
-- Title panels are embedded and do not report IsInViewport themselves.
local titleRoot=widget('DRootLogin_C','UserWidget');titleRoot.viewport=true
local titlePanel=widget('DPanelTitle_C','UserWidget')
local titleButton=button('TitleMenuBtn_PlayGame',160)
titleRoot.WidgetTree=object('title-root-tree');titleRoot.WidgetTree.RootWidget=titlePanel
titlePanel.WidgetTree=object('title-panel-tree');titlePanel.WidgetTree.RootWidget=titleButton
titleRoot.PanelPool=map({});manager.CurrentRootPanelInstance=titleRoot
context=assert(runtime.adapter:snapshot())
assert(context.scope=='DRootLogin_C' and #context.items==1,'Embedded title menu must be scanned through the viewport root')
mainBefore=clicks;keys[Key.S]();keys[Key.SPACE]();assert(clicks==mainBefore+1)
-- A startup confirmation lives outside PanelPool and has no controller/root yet.
controller.alive=false;localControllers={};manager.CurrentRootPanelInstance=nil
local confirm=button('confirm-warning',500)
local popupCanvas=widget('popup-canvas','PanelWidget');popupCanvas.children={confirm}
local popup=widget('DPopupDefault_C','UserWidget');popup.viewport=true;popup.viewportZ=200
popup.types.DPopupBase=true;popup.types.DPopupDefault=true
popup.WidgetTree=object('popup-tree');popup.WidgetTree.RootWidget=popupCanvas
popups={popup}
context=assert(runtime.adapter:snapshot())
assert(context.popup and context.confirmation and #context.items==1)
local before=clicks
keys[Key.SPACE]();assert(clicks==before+1,'Single-button popup needs only one Space')
local cancel=button('cancel-warning',500);cancel.bounds.x=300;confirm.bounds.x=500
target.OnReleasedOkButton=target.Click
local common=object('common-confirm-wrapper')
common.OnButtonReleased=function()target.Click()end
common.OnButtonReleased_0=delegate({{Object=target,FunctionName={ToString=function()return 'OnReleasedOkButton'end}}})
confirm.OnClicked=delegate()
confirm.OnReleased=delegate({{Object=common,FunctionName={ToString=function()return 'OnButtonReleased'end}}})
popupCanvas.children={cancel,confirm}
assert(runtime.adapter:snapshot().confirm.widget==confirm,'Follow the common-button delegate to the affirmative action')
keys[Key.D]();assert(runtime.navigation.selected==nil)
keys[Key.A]();assert(runtime.navigation.selected==nil)
keys[Key.SPACE]();assert(clicks==before+2 and confirm.opacity==1 and cancel.opacity==1)
-- All confirmation popup subclasses use the number of visible action buttons.
local quit=button('DButton_QuitAction',500);quit.bounds.x=500
local quitPopup=widget('DPopupExitGame_C','UserWidget');quitPopup.viewport=true;quitPopup.viewportZ=250
quitPopup.types.DPopupBase=true
quitPopup.WidgetTree=object('quit-tree')
local quitCanvas=widget('quit-canvas','PanelWidget');quitPopup.WidgetTree.RootWidget=quitCanvas
popups={quitPopup}
-- The cancel caption is a sibling inside a common-button wrapper, not a child
-- of the native button. WidgetTree is a UObject without GetParent.
local nativeCancel=button('DButton_1',500)
local cancelCaption=widget('Caption','TextBlock',{x=40,y=510,w=80,h=20});cancelCaption.GetText=function()return {ToString=function()return '취소'end}end
local commonCancel=widget('DCommonButton_C','UserWidget');commonCancel.parent=quitCanvas
local commonCanvas=widget('button-layout','PanelWidget');commonCanvas.children={nativeCancel,cancelCaption}
commonCancel.WidgetTree=object('common-tree');commonCancel.WidgetTree.RootWidget=commonCanvas
commonCancel.WidgetTree.GetParent=nil;commonCancel.WidgetTree.outer=commonCancel
commonCanvas.outer=commonCancel.WidgetTree;nativeCancel.parent=commonCanvas
local close=button('Button_Close',30)
quitCanvas.children={commonCancel,quit,close}
context=assert(runtime.adapter:snapshot())
assert(context.dialog and context.confirmation and #context.items==2 and context.confirm.widget==quit,
    'Exit confirmation selects the opposite of Cancel and ignores the frame close button')
before=clicks
keys[Key.A]();keys[Key.D]();keys[Key.W]();assert(runtime.navigation.selected==nil)
keys[Key.SPACE]();assert(clicks==before+1)
quitCanvas.children={quit}
before=clicks;keys[Key.SPACE]();assert(clicks==before+1,'One-button non-default popup executes on one Space')
quitCanvas.children={close}
before=clicks;keys[Key.SPACE]();assert(clicks==before and #runtime.adapter:snapshot().items==0,'A lone X is never activated by Space')
target.OnCancelButton=target.Click
close.OnClicked=delegate({{Object=target,FunctionName={ToString=function()return 'OnCancelButton'end}}})
keys[Key.SPACE]();assert(clicks==before and #runtime.adapter:snapshot().items==0,'X stays excluded even if its handler is the cancel action')
local labelledClose=button('CloseButton',500)
local closeCaption=widget('CloseCaption','TextBlock',{x=40,y=510,w=80,h=20})
closeCaption.GetText=function()return {ToString=function()return '닫기'end}end
labelledClose.children={closeCaption};quitCanvas.children={labelledClose}
before=clicks;keys[Key.SPACE]();assert(clicks==before+1,'A labelled Close action remains usable, unlike the frame X')
-- Three choices require A/D selection and Space; no fixed affirmative shortcut.
local third=button('third-action',500);third.bounds.x=700
quitCanvas.children={commonCancel,quit,third,close}
context=assert(runtime.adapter:snapshot())
assert(context.dialog and not context.confirmation and #context.items==3 and context.confirm==nil and #context.hints==0)
runtime.navigation:clear();before=clicks
keys[Key.SPACE]();assert(clicks==before and runtime.navigation.selected~=nil,'Unselected three-choice popup is not immediately executed')
keys[Key.D]();assert(runtime.navigation.selected.widget==quit)
keys[Key.D]();assert(runtime.navigation.selected.widget==third)
keys[Key.D]();assert(runtime.navigation.selected.widget==nativeCancel)
keys[Key.A]();assert(runtime.navigation.selected.widget==third)
keys[Key.W]();keys[Key.S]();assert(runtime.navigation.selected.widget==third)
keys[Key.SPACE]();assert(clicks==before+1)
third.visibility=1
context=assert(runtime.adapter:snapshot());assert(context.confirmation and context.confirm.widget==quit)
keys[Key.D]();assert(runtime.navigation.selected==nil)
-- Removing the affirmative button must not reuse an old cached target.
quit.visibility=1
context=assert(runtime.adapter:snapshot());assert(#context.items==1 and context.confirm.widget==nativeCancel)
quitCanvas.children={quit,third};quit.visibility=0;third.visibility=0
context=assert(runtime.adapter:snapshot());assert(context.confirmation and context.confirm==nil)
before=clicks;keys[Key.SPACE]();assert(clicks==before,'Unrecognised two-button popup must not guess a target')
quitCanvas.children={nativeCancel,quit};nativeCancel.enabled=false
context=assert(runtime.adapter:snapshot());assert(#context.items==1 and context.confirm.widget==quit)
nativeCancel.enabled=true
popups={popup}
-- A second visible popup wins by actual viewport order; background buttons are isolated.
local upper=widget('upper-popup','UserWidget');upper.viewport=true;upper.viewportZ=300
upper.types.DPopupBase=true;upper.types.DPopupDefault=true
upper.WidgetTree=object('upper-tree');upper.WidgetTree.RootWidget=button('upper-ok',500)
popups={upper,popup}
context=assert(runtime.adapter:snapshot());assert(context.scope=='upper-popup' and #context.items==1)
upper.visibility=1
context=assert(runtime.adapter:snapshot());assert(context.scope=='DPopupDefault_C')
popup.visibility=1
assert(runtime.adapter:snapshot()==nil,'Hidden popups must not capture gameplay')
upper.visibility=0;popup.visibility=0
keys[Key.F7]();before=clicks
keys[Key.A]();keys[Key.D]();keys[Key.SPACE]();assert(clicks==before and runtime.navigation.selected==nil)
keys[Key.F7]()
-- F is reserved for the visible challenge action on the native dungeon panel.
-- Removed popups remain owned by Root.WidgetTree but cannot block the inventory.
controller.alive=true;localControllers={controller};manager.CurrentRootPanelInstance=root
root.viewport=true;root.WidgetTree=object('live-root-tree');root.WidgetTree.outer=root
local rootCanvas=widget('live-root-canvas','PanelWidget');rootCanvas.types.CanvasPanel=true
root.WidgetTree.RootWidget=rootCanvas;rootCanvas.outer=root.WidgetTree
pool[31]={PanelBase=menu,ZOrder=100,PopupPanelType=0};canvas.children={a,b}
popup.viewport=false;popup.parent=nil;popup.outer=root.WidgetTree
upper.viewport=false;upper.parent=nil;upper.outer=root.WidgetTree
popups={upper,popup}
context=assert(runtime.adapter:snapshot());assert(context.scope==menu.name,
    'A removed popup must not borrow its live owner visibility')
text.parent=nil;text.outer=root.WidgetTree;text.visibility=0;focusedText={text}
keys[Key.S]();assert(runtime.navigation.selected.widget==a,'Detached stale text focus must not block inventory')
focusedText={};text.parent=menu
-- Genuine WidgetTree roots still reach their visible UserWidget owner.
popup.parent=rootCanvas;popupCanvas.outer=popup.WidgetTree;popup.WidgetTree.outer=popup
rootCanvas.children={popup};popups={popup}
context=assert(runtime.adapter:snapshot());assert(context.scope==popup.name)
-- Embedded popup order follows Canvas slot ZOrder, then sibling paint order.
upper.parent=rootCanvas;upper.Slot={ZOrder=2};popup.Slot={ZOrder=1}
rootCanvas.children={upper,popup};popups={popup,upper}
assert(runtime.adapter:snapshot().scope==upper.name)
upper.Slot.ZOrder=0
assert(runtime.adapter:snapshot().scope==popup.name)
upper.Slot.ZOrder=1
assert(runtime.adapter:snapshot().scope==popup.name,'Later sibling wins equal Canvas ZOrder')
rootCanvas.children={popup,upper};assert(runtime.adapter:snapshot().scope==upper.name)
-- A confirmation nested inside a form wins over its owning popup.
upper.parent=popupCanvas;popupCanvas.children={confirm,upper}
assert(runtime.adapter:snapshot().scope==upper.name)
upper.parent=nil;rootCanvas.children={popup};popupCanvas.children={confirm}
-- A buttonless item-use notice is noninteractive; other buttonless modals block.
local notice=widget('DPopupNotice_C','UserWidget');notice.types.DPopupBase=true;notice.types.DPopupNotice=true
notice.parent=rootCanvas;notice.Slot={ZOrder=500};notice.WidgetTree=object('notice-tree')
notice.WidgetTree.RootWidget=widget('notice-text','TextBlock')
rootCanvas.children={notice};popups={notice}
assert(runtime.adapter:snapshot().scope==menu.name,'Use-item notice must not swallow navigation')
notice.types.DPopupNotice=false
context=assert(runtime.adapter:snapshot());assert(context.popup and #context.items==0,
    'Unknown empty modal must still isolate background actions')
notice.parent=nil
-- Quick-slot content selectors are not three extra confirmation actions.
local quick=widget('DPopupQuickSlot_C','UserWidget');quick.types.DPopupBase=true;quick.types.DPopupQuickSlot=true
quick.parent=rootCanvas;quick.outer=root.WidgetTree;rootCanvas.children={quick}
local quickCanvas=widget('quick-layout','PanelWidget');quickCanvas.types.CanvasPanel=true
quick.WidgetTree=object('quick-tree');quick.WidgetTree.outer=quick;quick.WidgetTree.RootWidget=quickCanvas
quickCanvas.outer=quick.WidgetTree;quickCanvas.AddChildToCanvas=canvas.AddChildToCanvas
local slots={}
for i=1,3 do
    slots[i]=button('QuickSlot'..i,250);slots[i].bounds={x=150+(i-1)*180,y=250,w=140,h=140}
    slots[i].parent=quickCanvas
end
local formCancel=button('Cancel',500);formCancel.bounds={x=100,y=500,w=300,h=70};formCancel.parent=quickCanvas
local formOk=button('Register',500);formOk.bounds={x=450,y=500,w=300,h=70};formOk.parent=quickCanvas
local formCaption=widget('RegisterCaption','TextBlock',{x=500,y=520,w=100,h=20})
formCaption.GetText=function()return {ToString=function()return '등록'end}end
formOk.children={formCaption}
quickCanvas.children={slots[1],slots[2],slots[3],formCancel,formOk};popups={quick}
context=assert(runtime.adapter:snapshot())
assert(context.form and not context.dialog and not context.confirmation and #context.items==4
    and #context.formActions==2 and context.formAdvance.widget==formOk)
formOk.enabled=false
context=assert(runtime.adapter:snapshot());assert(#context.items==3 and not context.formAdvance,
    'Disabled registration must not turn Cancel into the form confirmation')
target.SelectSlot=function()clicks=clicks+1;formOk.enabled=true end
slots[2].OnClicked=delegate({{Object=target,FunctionName={ToString=function()return 'SelectSlot'end}}})
before=clicks;keys[Key.F7]();keys[Key.S]();keys[Key.SPACE]();assert(clicks==before)
keys[Key.F7]();focusedText={text};keys[Key.SPACE]();assert(clicks==before);focusedText={}
runtime.navigation:clear();before=clicks
keys[Key.W]();assert(runtime.navigation.selected.widget==slots[1])
keys[Key.D]();assert(runtime.navigation.selected.widget==slots[2])
assert(clicks==before,'Slot movement does not select or register an item')
keys[Key.SPACE]();assert(clicks==before+1 and runtime.navigation.selected.widget==formOk,
    'Space selects one slot, then highlights the separate registration action')
runtimeOptions.hints=true;loops[250]()
local formSpace=false
for _,entry in pairs(runtime.hints.labels)do formSpace=formSpace or entry.label.text=='Space'end
assert(formSpace,'The form Space hint follows the currently selected action')
formOk.OnClicked=delegate({{Object=target,FunctionName={ToString=function()return 'RegisterAndClose'end}}})
target.RegisterAndClose=function()clicks=clicks+1;quick.parent=nil;rootCanvas.children={}end
keys[Key.SPACE]();assert(clicks==before+2 and runtime.navigation.selected==nil)
assert(runtime.adapter:snapshot().scope==menu.name,'Closing registration restores the item menu despite stale owned popup')
keys[Key.S]();keys[Key.SPACE]();assert(clicks==before+3,'Inventory remains usable after registration closes')
-- Closing with the mouse also restores navigation; stale notice objects do not win.
quick.parent=rootCanvas;rootCanvas.children={quick};popups={notice,quick}
keys[Key.S]();quick.parent=nil;rootCanvas.children={};keys[Key.LEFT_MOUSE_BUTTON]()
keys[Key.S]();assert(runtime.navigation.selected.widget==a)
-- A slot action that opens a new confirmation cannot carry the old selection.
quick.parent=rootCanvas;rootCanvas.children={quick};popups={quick}
target.OpenSlotConfirmation=function()clicks=clicks+1;upper.parent=rootCanvas;upper.Slot={ZOrder=50};rootCanvas.children={quick,upper};popups={quick,upper}end
slots[1].OnClicked=delegate({{Object=target,FunctionName={ToString=function()return 'OpenSlotConfirmation'end}}})
runtime.navigation:clear();keys[Key.S]();before=clicks;keys[Key.SPACE]()
assert(clicks==before+1 and runtime.navigation.selected==nil and runtime.adapter:snapshot().scope==upper.name)
keys[Key.SPACE]();assert(clicks==before+2,'New confirmation needs its own Space press')
runtimeOptions.hints=false;runtime.navigation:clear();upper.viewport=true;upper.parent=nil
popup.viewport=true;popup.parent=nil;upper.Slot=nil;popup.Slot=nil;rootCanvas.children={}
-- Three vertically arranged wide actions are a dialog, not a content form.
local verticalActions={button('vertical-one',200),button('vertical-two',300),button('vertical-three',400)}
quitCanvas.children=verticalActions;popups={quitPopup}
context=assert(runtime.adapter:snapshot());assert(context.dialog and not context.form and not context.confirmation)
popups={};controller.alive=true;localControllers={controller};manager.CurrentRootPanelInstance=root
local dungeon=widget('DPanelDungeon_C','UserWidget');dungeon.types.DPanelDungeon=true;dungeon.viewport=true
local dungeonCanvas=widget('dungeon-canvas','PanelWidget');dungeonCanvas.types.CanvasPanel=true
dungeonCanvas.AddChildToCanvas=canvas.AddChildToCanvas
dungeon.WidgetTree=object('dungeon-tree');dungeon.WidgetTree.RootWidget=dungeonCanvas
dungeon.WidgetTree.outer=dungeon;dungeonCanvas.outer=dungeon.WidgetTree
local challenge=button('DButton_Action',500)
local caption=widget('ActionCaption','RichTextBlock',{x=40,y=510,w=80,h=20});caption.caption='<Action>도전</>'
caption.GetText=function(self)return {ToString=function()return self.caption end}end
local challengeWrapper=widget('DCommonActionButton_C','UserWidget');challengeWrapper.parent=dungeonCanvas
local actionLayout=widget('action-layout','PanelWidget');actionLayout.children={challenge,caption}
challengeWrapper.WidgetTree=object('action-tree');challengeWrapper.WidgetTree.GetParent=nil
challengeWrapper.WidgetTree.RootWidget=actionLayout;challengeWrapper.WidgetTree.outer=challengeWrapper
actionLayout.outer=challengeWrapper.WidgetTree;challenge.parent=actionLayout;caption.parent=actionLayout
local closeDungeon=button('Button_CloseDungeon',20)
dungeonCanvas.children={closeDungeon,challengeWrapper}
pool[31]={PanelBase=dungeon,ZOrder=200,PopupPanelType=0}
context=assert(runtime.adapter:snapshot())
assert(context.entryAction.widget==challenge and #context.hints==1 and context.hints[1].key=='F')
before=clicks;keys[Key.F]();assert(clicks==before+1,'F executes Challenge in one press without selecting the close button')
challenge.enabled=false
context=assert(runtime.adapter:snapshot());assert(not context.entryAction and #context.hints==0)
before=clicks;keys[Key.F]();assert(clicks==before,'Disabled challenge cannot run')
challenge.enabled=true;challengeWrapper.visibility=1
keys[Key.F]();assert(clicks==before,'Hidden action ancestor cannot run')
challengeWrapper.visibility=0;caption.caption='취소'
keys[Key.F]();assert(clicks==before,'Reused action must still be labelled Challenge')
caption.caption='도전';local stale=assert(runtime.adapter:snapshot());caption.caption='상세 보기'
assert(not runtime.adapter:enterDungeon(stale) and clicks==before,'Revalidate the action even after a snapshot')
caption.caption='도전';focusedText={text};keys[Key.F]();assert(clicks==before);focusedText={}
keys[Key.F7]();keys[Key.F]();assert(clicks==before);keys[Key.F7]()
-- Identical caption on another menu must not enable F.
dungeon.types.DPanelDungeon=false;keys[Key.F]();assert(clicks==before)
dungeon.types.DPanelDungeon=true
-- Frontmost popups isolate the challenge panel behind them.
upper.visibility=0;popups={upper};keys[Key.F]();assert(clicks==before)
popups={};dungeon.visibility=1;keys[Key.F]();assert(clicks==before);dungeon.visibility=0
runtimeOptions.hints=true;loops[250]()
local fLabel
for _,entry in pairs(runtime.hints.labels)do if entry.label.text=='F'then fLabel=entry.label end end
assert(fLabel and fLabel.Font.Size==16 and fLabel.Slot.size.X==20)
challenge.enabled=false;loops[250]();assert(next(runtime.hints.labels)==nil,'Disabled challenge loses its F label')
challenge.enabled=true;loops[250]();assert(next(runtime.hints.labels)~=nil)
keys[Key.F7]();assert(next(runtime.hints.labels)==nil,'F7 OFF also removes the challenge hint')
runtimeOptions.hints=false;keys[Key.F7]()
-- The second challenge step reuses the team panel, alongside Q/E team presets.
dungeon.types.DPanelDungeon=false;dungeon.types.DPanelTeam=true;dungeon.name='DPanelTeam_C'
for _,tab in ipairs(tabWidgets)do tab.parent=dungeonCanvas end
dungeonCanvas.children={closeDungeon,challengeWrapper,tabWidgets[1],tabWidgets[2],tabWidgets[3]}
context=assert(runtime.adapter:snapshot())
assert(context.entryAction.widget==challenge and #context.tabs==3 and #context.hints==2)
before=clicks;keys[Key.F]();assert(clicks==before+1,'F also executes Challenge on the team-selection step')
context=assert(runtime.adapter:snapshot())
local active=1
for index,tab in ipairs(context.tabs)do if tab.active then active=index;break end end
local nextTeam=context.tabs[active%#context.tabs+1].widget
keys[Key.E]();assert(nextTeam.checked and clicks==before+1,'Q/E changes the team without starting Challenge')
-- An ordinary team editing action has no F binding or F hint.
caption.caption='편성 완료';before=clicks
keys[Key.F]();assert(clicks==before and not runtime.adapter:snapshot().entryAction)
caption.caption='도전';challenge.enabled=false
keys[Key.F]();assert(clicks==before,'Disabled team challenge cannot run')
challenge.enabled=true;challengeWrapper.visibility=1
keys[Key.F]();assert(clicks==before,'Hidden team challenge cannot run')
challengeWrapper.visibility=0;upper.visibility=0;popups={upper}
keys[Key.F]();assert(clicks==before,'Team challenge cannot run behind a popup')
popups={};focusedText={text};keys[Key.F]();assert(clicks==before);focusedText={}
keys[Key.F7]();keys[Key.F]();assert(clicks==before);keys[Key.F7]()
-- Real team layouts can place the caption beside the Button in a shared layer.
-- Every native button then has the same first UserWidget owner: that must not
-- make all portrait buttons inherit the Challenge caption or hide the F binding.
local teamLayer=widget('DLayerTeamSet_C','UserWidget');teamLayer.parent=dungeonCanvas
local teamLayout=widget('team-layout','PanelWidget')
teamLayer.WidgetTree=object('team-layer-tree');teamLayer.WidgetTree.RootWidget=teamLayout
teamLayer.WidgetTree.outer=teamLayer;teamLayer.WidgetTree.GetParent=nil;teamLayout.outer=teamLayer.WidgetTree
local portrait=button('CharacterSlot1',100);portrait.parent=teamLayout
local nativeX=button('DButton_UnknownIcon',20);nativeX.bounds.x=900;nativeX.parent=teamLayout
target.OnReleasedCloseMainMenuButton=target.Click
nativeX.OnClicked=delegate({{Object=target,FunctionName={ToString=function()return 'OnReleasedCloseMainMenuButton'end}}})
challenge.parent=teamLayout;caption.parent=teamLayout;teamLayout.children={portrait,nativeX,caption,challenge}
dungeonCanvas.children={teamLayer,tabWidgets[1],tabWidgets[2],tabWidgets[3]}
context=assert(runtime.adapter:snapshot())
assert(context.entryAction.widget==challenge and #context.items==2,'Only the button under the Challenge caption is bound; X is excluded')
before=clicks;keys[Key.F]();assert(clicks==before+1)
caption.bounds.y=300
context=assert(runtime.adapter:snapshot());assert(not context.entryAction,'An unrelated Challenge caption cannot bind another button')
caption.bounds.y=510
-- Return to the compact wrapper fixture for duplicate-action and hint checks.
challenge.parent=actionLayout;caption.parent=actionLayout
dungeonCanvas.children={closeDungeon,challengeWrapper,tabWidgets[1],tabWidgets[2],tabWidgets[3]}
before=clicks
-- Reused team panels must resolve a unique currently visible Challenge action.
local duplicate=button('DuplicateChallenge',500);duplicate.parent=actionLayout
actionLayout.children={challenge,caption,duplicate}
context=assert(runtime.adapter:snapshot());assert(not context.entryAction)
keys[Key.F]();assert(clicks==before,'Ambiguous challenge buttons must not execute')
actionLayout.children={challenge,caption}
runtimeOptions.hints=true;loops[250]()
local hasTeamF,hasTeamTabs=false,false
for _,entry in pairs(runtime.hints.labels)do
    hasTeamF=hasTeamF or entry.label.text=='F'
    hasTeamTabs=hasTeamTabs or entry.label.text=='Q/E'
end
assert(hasTeamF and hasTeamTabs,'Team challenge hint and Q/E hint must coexist')
caption.caption='편성 완료';loops[250]()
for _,entry in pairs(runtime.hints.labels)do assert(entry.label.text~='F','Normal team editing has no F hint')end
caption.caption='도전';keys[Key.F7]();assert(next(runtime.hints.labels)==nil)
runtimeOptions.hints=false;keys[Key.F7]()
-- The map updates on engine frames, with no hold delay, UI searches or geometry
-- reads in the frame callback. Releasing keys and foreground modals stop motion.
popups={};focusedText={};overlay.visibility=1
local worldPanel=widget('DPanelWorldMap_C','UserWidget');worldPanel.viewport=true;worldPanel.types.DPanelWorldMap=true
local worldCanvas=widget('world-canvas','PanelWidget')
worldPanel.WidgetTree=object('world-tree');worldPanel.WidgetTree.RootWidget=worldCanvas
local mapLayer=object('map-layer');worldPanel.LayerMap=mapLayer
local artwork=widget('map-artwork','Widget',{x=0,y=0,w=3000,h=2800});artwork.parent=worldCanvas;mapLayer.MapOverlay=artwork
local function panSlot()
 local slot=object('pan-slot');slot.position={X=-1700,Y=-1800}
 function slot:GetPosition()return {X=self.position.X,Y=self.position.Y}end
 function slot:SetPosition(value)self.position=value end
 return slot
end
local mapInside,mapOutside=panSlot(),panSlot();mapLayer.MapOverlaySlot=mapInside;mapLayer.MapOverlayOutSideSlot=mapOutside
pool[31]={PanelBase=worldPanel,ZOrder=300,PopupPanelType=0}
local mapNow=0
runtimeOptions.mapClock=function()return mapNow end
local down={W=true}
FName=function(name)return name end
controller.IsInputKeyDown=function(_,key)return down[key.KeyName]==true end
worldPanel.GetOwningPlayer=function()return controller end
loops[250]();keys[Key.W]()
local start=mapInside.position.Y
local mapMeasures,mapSearches=geometryCalls,globalQueries
for _=1,120 do mapNow=mapNow+1/120;loops.frame()end
assert(math.abs(mapInside.position.Y-start-1400)<0.001,'Held map key moves immediately at the same speed on every engine frame')
assert(mapInside.position.Y==mapOutside.position.Y and geometryCalls==mapMeasures and globalQueries==mapSearches,
 'Map frame updates do not measure geometry or search global UI objects')
down.W=false;local stopped=mapInside.position.Y;mapNow=mapNow+1/120;loops.frame()
assert(mapInside.position.Y==stopped,'Releasing the key stops movement on the next frame')
-- The global key callback may precede PlayerInput's down flag by one frame.
down.W=false;keys[Key.W]();local pendingY=mapInside.position.Y
mapNow=mapNow+1/240;loops.frame()
assert(mapInside.position.Y==pendingY)
down.W=true;mapNow=mapNow+1/240;loops.frame()
assert(mapInside.position.Y>pendingY,'An early false PlayerInput flag must not permanently discard the held key')
down.W=false;mapNow=mapNow+1/240;loops.frame()
-- Recover a held direction even when its edge callback was missed or flushed.
down.A=true;local recoveredX=mapInside.position.X;loops[50]()
mapNow=mapNow+1/240;loops.frame()
assert(mapInside.position.X>recoveredX,'Periodic key sampling recovers a held key without a new key-down callback')
down.A=false;mapNow=mapNow+1/240;loops.frame()
-- A still-valid controller from the previous world must not own current input.
local currentOwner=object('current-map-controller');currentOwner.IsLocalController=function()return true end
currentOwner.IsInputKeyDown=function(_,key)return down[key.KeyName]==true end
worldPanel.GetOwningPlayer=function()return currentOwner end
local oldInput=controller.IsInputKeyDown;controller.IsInputKeyDown=function()return false end
down.W=true;keys[Key.W]();local ownerY=mapInside.position.Y
mapNow=mapNow+1/240;loops.frame()
assert(mapInside.position.Y>ownerY,'The current map owner replaces a stale but valid input controller')
controller.IsInputKeyDown=oldInput;worldPanel.GetOwningPlayer=function()return controller end
down.W=false;runtime.adapter:snapshot();mapNow=mapNow+1/240;loops.frame()
down.D=true;keys[Key.D]();popups={upper};keys[Key.SPACE]()
local popupX=mapInside.position.X;mapNow=mapNow+1/120;loops.frame()
assert(mapInside.position.X==popupX,'Popup input cancels held map motion')
popups={};down.D=false;loops[250]();down.W=true;keys[Key.W]();keys[Key.F7]()
stopped=mapInside.position.Y;mapNow=mapNow+1/120;loops.frame()
assert(mapInside.position.Y==stopped,'F7 OFF stops map movement immediately')
keys[Key.F7]();loops.frame();assert(mapInside.position.Y==stopped,'Re-enabling F7 does not replay a stale held key')
-- The real public popup is shared by dungeon exits and ordinary confirmations.
local exitPopup=widget('DPublicPopup_DefVertical_C','UserWidget');exitPopup.viewport=true;exitPopup.types.DPopupBase=true
local exitCanvas=widget('exit-popup-canvas','PanelWidget');exitCanvas.types.CanvasPanel=true
exitCanvas.AddChildToCanvas=canvas.AddChildToCanvas
exitPopup.WidgetTree=object('exit-popup-tree');exitPopup.WidgetTree.outer=exitPopup;exitPopup.WidgetTree.RootWidget=exitCanvas
exitCanvas.outer=exitPopup.WidgetTree
local exitQuestion=widget('ExitDescription','RichTextBlock',{x=100,y=230,w=750,h=100})
exitQuestion.text='<Orange>용의 제단</> 나가시겠습니까?'
exitQuestion.GetText=function(self)return {ToString=function()return self.text end}end
local exitCancel=button('cancel-dungeon',500);exitCancel.bounds={x=100,y=500,w=300,h=70};exitCancel.parent=exitCanvas
local exitConfirm=button('confirm-dungeon',500);exitConfirm.bounds={x=500,y=500,w=300,h=70};exitConfirm.parent=exitCanvas
local exitCaption=widget('ExitButtonText','TextBlock',{x=550,y=520,w=100,h=20})
exitCaption.text='나가기';exitCaption.GetText=exitQuestion.GetText;exitCaption.parent=exitConfirm
exitConfirm.children={exitCaption};exitCanvas.children={exitQuestion,exitCancel,exitConfirm};popups={exitPopup}
context=assert(runtime.adapter:snapshot())
assert(context.confirmation and context.confirmKey=='F' and context.entryAction.widget==exitConfirm)
before=clicks;keys[Key.SPACE]();assert(clicks==before,'Space cannot approve dungeon exit')
keys[Key.F]();assert(clicks==before+1,'F approves the actual shared dungeon-exit popup')
runtimeOptions.hints=true;loops[250]()
local exitF=false
for _,entry in pairs(runtime.hints.labels)do
 assert(entry.label.text~='Space','Dungeon-exit popup must not show Space')
 exitF=exitF or entry.label.text=='F'
end
assert(exitF,'Dungeon exit displays the small F hint')
exitQuestion.text='용의 제단에 입장하시겠습니까?'
context=assert(runtime.adapter:snapshot())
assert(context.confirmKey=='Space' and not context.entryAction,'Button labels cannot turn a dungeon-entry question into an exit')
exitQuestion.text='게임을 종료하시겠습니까?';exitCaption.text='종료'
before=clicks;keys[Key.F]();assert(clicks==before)
keys[Key.SPACE]();assert(clicks==before+1,'Ordinary game-exit confirmation keeps Space')
exitQuestion.text='용의 제단 나가시겠습니까?';exitCaption.text='나가기'
exitConfirm.enabled=false
context=assert(runtime.adapter:snapshot());assert(context.confirmKey=='Space' and not context.entryAction,'Cancel alone must never become an F approval')
before=clicks;keys[Key.F]();assert(clicks==before)
exitConfirm.enabled=true;keys[Key.F7]();keys[Key.F]();assert(clicks==before,'F7 OFF also disables exit approval')
keys[Key.F7]();focusedText={text};keys[Key.F]();assert(clicks==before,'Text entry blocks exit approval');focusedText={}
-- Direct exit actions also reserve F, and revalidation rejects a reused button.
popups={};runtimeOptions.hints=false
local exitPanel=widget('DPanelDungeonActions_C','UserWidget');exitPanel.viewport=true
exitPanel.WidgetTree=object('exit-panel-tree');exitPanel.WidgetTree.RootWidget=exitConfirm
exitConfirm.parent=nil;exitConfirm.outer=exitPanel.WidgetTree;exitPanel.WidgetTree.outer=exitPanel
exitCaption.text='제단에서 나가기';pool[31]={PanelBase=exitPanel,ZOrder=500,PopupPanelType=0}
context=assert(runtime.adapter:snapshot());assert(context.entryAction.widget==exitConfirm)
runtime.navigation:clear();keys[Key.S]();before=clicks;keys[Key.SPACE]();assert(clicks==before)
keys[Key.F]();assert(clicks==before+1,'Direct dungeon-exit action uses F instead of Space')
local staleExit=assert(runtime.adapter:snapshot());exitCaption.text='제단 정보'
assert(not runtime.adapter:enterDungeon(staleExit),'A reused action must be revalidated before F activation')
-- The real HUD instance survives while its expanded menu is closed. Its bag
-- shortcut cannot become an eligible menu, even after a settled menu was cached.
popups={};focusedText={};pool[31]=nil;overlay.visibility=0
local combatRoot=widget('combat-and-menu-root','PanelWidget');combatRoot.outer=main.WidgetTree
main.WidgetTree.RootWidget=combatRoot;main.WidgetTree.outer=main;hud.DLayerMainMenu=main
local combatBag=button('InventoryButton02',20);combatBag.parent=combatRoot
local expanded=widget('expanded-menu-group','PanelWidget');expanded.parent=combatRoot;expanded.visibility=1
local heroAction,teamAction=button('hero-menu',180),button('team-menu',260)
heroAction.parent=expanded;teamAction.parent=expanded;expanded.children={heroAction,teamAction}
combatRoot.children={combatBag,expanded};controller.bShowMouseCursor=false
runtime.navigation:clear();before=clicks
assert(runtime.adapter:snapshot()==nil,'Combat HUD bag alone is not an open menu')
manager.PanelUIDefault=array({})
assert(runtime.adapter:snapshot()==nil,'Native HUD panels are excluded even when the default-panel list is unavailable')
manager.PanelUIDefault=array({3})
for _=1,20 do keys[Key.SPACE]();keys[Key.W]();keys[Key.SPACE]()end
assert(clicks==before and runtime.navigation.selected==nil,'Combat Space/WASD must never invoke the bag shortcut')
expanded.visibility=0;context=assert(runtime.adapter:snapshot());assert(context.mouseNavigation)
keys[Key.S]();assert(runtime.navigation.selected.widget==heroAction,'Expanded menu still supports keyboard navigation')
now=2;runtime.adapter:snapshot();expanded.visibility=1
keys[Key.SPACE]();assert(clicks==before and runtime.navigation.selected==nil,
 'Closing only the menu ancestor invalidates cached controls while the HUD layer stays visible')
mousePosition={X=50,Y=35};loops[250]();loops[50]()
assert(runtime.navigation.selected==nil,'Hovering the combat bag cannot arm menu confirmation')
expanded.visibility=0
assert(runtime.adapter:snapshot()~=nil,'Reopening the expanded menu restores keyboard controls')
expanded.visibility=1
local inventoryOpen=button('explicit-inventory-open',180)
menu.WidgetTree.RootWidget=inventoryOpen;pool[31]={PanelBase=menu,ZOrder=600,PopupPanelType=0}
keys[Key.S]();keys[Key.SPACE]();assert(clicks==before+1,'An explicitly opened inventory remains keyboard-accessible above the combat HUD')
for _,s in ipairs(logs)do assert(not s:find('ERROR',1,true),s)end
return 'menu runtime: HUD/Blueprint main menus, visible keyboard selection, global X exclusion with labelled Close/Quit preserved, shared-layer Challenge captions, F gates, Q/E/menu/popup regressions PASS'

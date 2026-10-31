local Navigation = require("menu_navigation")
local WorldMap = require("world_map")
local HotkeyHints = require("hotkey_hints")
local Module = {}

local function valid(object)
    local ok, value = pcall(function() return object and object:IsValid() end)
    return ok and value == true
end

local function read(object, key)
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
end

local function unwrap(value)
    local ok, result = pcall(function() return value:get() end)
    return ok and result or value
end

local function visible(widget)
    if not valid(widget) then return false end
    local visibility = widget:GetVisibility()
    return visibility ~= 1 and visibility ~= 2 and widget:GetIsEnabled() and widget:GetRenderOpacity() > 0.01
end

local function intersect(a, b)
    local x, y = math.max(a.x, b.x), math.max(a.y, b.y)
    local right, bottom = math.min(a.x+a.w, b.x+b.w), math.min(a.y+a.h, b.y+b.h)
    if right <= x or bottom <= y then return nil end
    return { x=x, y=y, w=right-x, h=bottom-y }
end

local function centerInside(outer, inner)
    if not outer or not inner then return false end
    local x,y=inner.x+inner.w/2,inner.y+inner.h/2
    return x>=outer.x and x<=outer.x+outer.w and y>=outer.y and y<=outer.y+outer.h
end

local function caption(widget)
    local ok,text=pcall(function()return widget:GetText():ToString()end)
    if ok then return text:gsub("<[^>]+>",""):gsub("%s",""):lower() end
end

local function dungeonExitText(text)
    local location=false
    for _,word in ipairs({"던전","제단","토벌","레이드","균열","시련의탑","dungeon","altar","raid"}) do
        if text:find(word,1,true) then location=true;break end
    end
    if not location or text:find("퇴장취소",1,true) or text:find("나가기취소",1,true) then return false end
    for _,word in ipairs({"나가","퇴장","떠나","leave","exit"}) do
        if text:find(word,1,true) then return true end
    end
    return false
end

local function fire(widget, event, ...)
    -- Invoke a snapshot of the dynamic delegate's targets. The pinned UE4SS build
    -- exposes bindings reliably, but its Broadcast helper misses game UI handlers.
    local bindings = widget[event]:GetBindings() or {}
    for _, binding in ipairs(bindings) do
        local object = binding.Object
        if valid(object) then
            local fn = object[binding.FunctionName:ToString()]
            object:CallFunction(fn, ...)
        end
    end
end

local function handlerMatches(widget, pattern, depth, seen)
    depth, seen = depth or 0, seen or {}
    if not valid(widget) or depth > 2 or seen[widget:GetAddress()] then return false end
    seen[widget:GetAddress()] = true
    for _, event in ipairs({"OnClicked", "OnReleased", "OnPressed", "OnButtonReleased_0"}) do
        local delegate = read(widget, event)
        if delegate then
            local ok, bindings = pcall(function() return delegate:GetBindings() end)
            for _, binding in ipairs(ok and bindings or {}) do
                local name = binding.FunctionName:ToString():lower()
                if name:match(pattern) then return true end
                if handlerMatches(binding.Object, pattern, depth+1, seen) then return true end
            end
        end
    end
    return false
end

function Module.start(log, options)
    options = options or {}
    local adapter = { types = {}, highlights = {} }
    local navigation = Navigation.new(adapter)
    local manager, controller, slate, viewport, geometryHook, layoutLibrary
    local wantedGeometry, geometryResult
    local lastError
    local activeMap, held, keyNames = nil, {}, {}
    local mapState,mapTime,gameplayStatics,clockFallback
    local directionKeys={up="W",down="S",left="A",right="D"}
    local function stopMap() held={};mapState=nil;mapTime=nil end
    local mouseContext,refreshedScope,mainCache
    local clock=options.clock or os.clock
    local tabScope, primaryGroup, secondaryGroup, tabHintContext, tabHintStamp, tabHintTime
    local thread = options.thread or require("game_thread").new(log)

    local function class(name)
        if not valid(adapter.types[name]) then adapter.types[name] = StaticFindObject("/Script/UMG." .. name) end
        return adapter.types[name]
    end

    local function isA(object, name)
        local c = class(name)
        return valid(c) and object:IsA(c)
    end

    local function gameIsA(object, name)
        local key = "DSClient." .. name
        if not valid(adapter.types[key]) then adapter.types[key] = StaticFindObject("/Script/" .. key) end
        local c = adapter.types[key]
        return valid(c) and object:IsA(c)
    end

    local function challengePanel(scope)
        return gameIsA(scope,"DPanelDungeon") or gameIsA(scope,"DPanelTeam")
    end

    local function mainMenu(scope)
        if not valid(scope) then return false end
        -- The HUD property/instance is DLayerMainMenu, but its shipped Blueprint
        -- class is DLPAN_LayerPanel_Main_PC_C, not DLayerMainMenu_C.
        if scope:GetFName():ToString()=="DLayerMainMenu" then return true end
        local name=scope:GetClass():GetFName():ToString()
        return name=="DLayerMainMenu_C" or name=="DLayerMainMenu"
    end

    local function hudShortcut(widget)
        local name=widget:GetFName():ToString():lower()
        return name:match("^inventorybutton%d*$")~=nil or name=="goodsbutton"
    end

    local function menuAnchor(context)
        for _,item in ipairs(context.items) do
            if not hudShortcut(item.widget) then return item.widget end
        end
    end

    local function attachedParent(widget)
        local parent=widget:GetParent()
        if valid(parent) then return parent end
        local outer=widget:GetOuter()
        for _=1,8 do
            if not valid(outer) or isA(outer,"UserWidget") then break end
            outer=outer:GetOuter()
        end
        -- Outer records ownership, not attachment. Removed popups remain owned
        -- by the live root's WidgetTree until GC, but are no longer on screen.
        local tree=valid(outer) and read(outer,"WidgetTree")
        local root=valid(tree) and unwrap(read(tree,"RootWidget"))
        if valid(root) and root:GetAddress()==widget:GetAddress() then return outer end
    end

    local function displayed(widget)
        local seen = {}
        for _=1,64 do
            if not valid(widget) or not visible(widget) then return false end
            local address=widget:GetAddress()
            if seen[address] then return false end
            seen[address]=true
            if isA(widget,"UserWidget") and widget:IsInViewport() then return true end
            local parent=attachedParent(widget)
            if valid(parent) and isA(parent,"WidgetSwitcher") then
                local active=parent:GetActiveWidget()
                if not valid(active) or active:GetAddress()~=widget:GetAddress() then return false end
            end
            if not valid(parent) or not isA(parent,"Widget") then return false end
            widget=parent
        end
        return false
    end

    local function walkUI(root, callback)
        local seen, count = {}, 0
        local function walk(widget, depth)
            if not valid(widget) or not visible(widget) or depth>24 or count>512 then return end
            local address=widget:GetAddress()
            if seen[address] then return end
            seen[address],count=true,count+1
            callback(widget)
            if isA(widget,"UserWidget") then
                local tree=read(widget,"WidgetTree")
                if valid(tree) then walk(tree.RootWidget,depth+1) end
            elseif isA(widget,"WidgetSwitcher") then walk(widget:GetActiveWidget(),depth+1)
            elseif isA(widget,"PanelWidget") then
                for index=0,widget:GetChildrenCount()-1 do walk(widget:GetChildAt(index),depth+1) end
            end
        end
        walk(root,0)
    end

    local map = WorldMap.new({valid=valid,read=read,displayed=displayed,isA=isA,walk=walkUI,
        parent=function(widget)return widget:GetParent()end,
        geometry=function(widget)return adapter:geometry(widget)end,
        activate=function(widget)adapter:activate({widget=widget,kind="button"})end})

    local function mapContext(scope,state)
        -- Travel can leave an old controller valid until garbage collection.
        -- The visible map's owning player is the authoritative input source.
        local ok,owner=pcall(function()return scope:GetOwningPlayer()end)
        if ok and valid(owner) then
            local localOk,isLocal=pcall(function()return owner:IsLocalController()end)
            if localOk and isLocal then controller=owner end
        end
        state=state or map:context(scope)
        return {scope=scope:GetFullName(),scopeWidget=scope,items={},tabs={},map=state,hints=map:hints(state)}
    end

    function adapter:mapClock()
        if options.mapClock then return options.mapClock() end
        if not clockFallback then
            if not valid(gameplayStatics) then gameplayStatics=StaticFindObject("/Script/Engine.Default__GameplayStatics") end
            local ok,value=pcall(function()return gameplayStatics:GetRealTimeSeconds(controller)end)
            if ok and type(value)=="number" then return value end
            clockFallback=true
        end
        return os.clock()
    end

    function adapter:panMap(context,direction,step)
        local key=directionKeys[direction]
        if not key or held[key] then return key~=nil end
        if not keyNames[key] then keyNames[key]=FName(key) end
        activeMap,mapState=context.scopeWidget,context.map
        mapTime=self:mapClock();held[key]={started=mapTime,seen=false}
        -- An opening map can lack geometry for its first frame. Keep the hold
        -- armed so the frame callback can start as soon as layout is ready.
        if not map:preparePan(mapState) then return true end
        return map:pan(mapState,direction,step or 24)
    end
    function adapter:zoomMap(context,direction)
        local result=map:zoom(context.map,direction)
        if result then mapState=context.map end
        return result
    end
    function adapter:warpMap(context)stopMap();return map:warp(context.map)end

    local function initialize()
        if not valid(controller) then
            controller = nil
            for _, candidate in ipairs(FindAllOf("PlayerController") or {}) do
                if candidate:IsLocalController() then controller = candidate; break end
            end
        end
        if not valid(manager) then manager = FindFirstOf("DUIManager") end
        if not valid(slate) then slate = StaticFindObject("/Script/UMG.Default__SlateBlueprintLibrary") end
        -- Startup warnings can appear before a local controller or root panel exists.
        return valid(slate)
    end

    local function popupOrder(widget)
        local reverse,seen={},{}
        for _=1,64 do
            if not valid(widget) or seen[widget:GetAddress()] then break end
            seen[widget:GetAddress()]=true
            if isA(widget,"UserWidget") and widget:IsInViewport() then
                if not valid(viewport) then viewport=FindFirstOf("GameViewportSubsystem") end
                local ok,z=pcall(function()return viewport:GetWidgetSlot(widget).ZOrder end)
                reverse[#reverse+1]={ok and type(z)=="number" and z or 0,0}
                break
            end
            local parent=attachedParent(widget)
            if not valid(parent) then break end
            local slot=read(widget,"Slot")
            local z=slot and read(slot,"ZOrder")
            local index=0
            if isA(parent,"PanelWidget") then
                for i=0,parent:GetChildrenCount()-1 do
                    local child=parent:GetChildAt(i)
                    if valid(child) and child:GetAddress()==widget:GetAddress() then index=i;break end
                end
            end
            reverse[#reverse+1]={type(z)=="number" and z or 0,index}
            widget=parent
        end
        local path={}
        for i=#reverse,1,-1 do
            path[#path+1]=reverse[i][1];path[#path+1]=reverse[i][2]
        end
        return path
    end

    local function compareOrder(a,b)
        for i=1,math.min(#a,#b) do
            if a[i]~=b[i] then return a[i]>b[i] and 1 or -1 end
        end
        return #a==#b and 0 or (#a>#b and 1 or -1)
    end

    local previousPopup
    function adapter:popup()
        local top, topOrder, topFocused
        for _, popup in ipairs(FindAllOf("DPopupBase") or {}) do
            if displayed(popup) then
                -- Item-use notices auto-close and have no actions. They must not
                -- capture navigation intended for the item menu beneath them.
                local content=gameIsA(popup,"DPopupNotice") and self:collect(popup)
                if not (content and #content.items==0) then
                    local order=popupOrder(popup)
                    local focused=popup:HasKeyboardFocus() or popup:HasFocusedDescendants()
                    local comparison=top and compareOrder(order,topOrder) or 1
                    if comparison>0 or (comparison==0 and
                        ((focused and not topFocused) or (focused==topFocused and previousPopup==popup:GetAddress()))) then
                        top,topOrder,topFocused=popup,order,focused
                    end
                end
            end
        end
        previousPopup=top and top:GetAddress()
        return top
    end

    local function installGeometryHook()
        if not geometryHook then
            -- FGeometry has no reflected fields. Normal Lua return conversion loses its
            -- contents; read the native return parameter while its storage is still alive.
            local pre, post = RegisterHook("/Script/UMG.Widget:GetCachedGeometry", function() end, function(context, result)
                if not wantedGeometry then return end
                local widget = context:get()
                if widget:GetAddress() ~= wantedGeometry then return end
                local g = result:get()
                local size = slate:GetLocalSize(g)
                local origin = slate:LocalToAbsolute(g, { X=0, Y=0 })
                local corner = slate:LocalToAbsolute(g, { X=size.X, Y=size.Y })
                geometryResult = { x=origin.X, y=origin.Y, w=corner.X-origin.X, h=corner.Y-origin.Y,
                    localW=size.X,localH=size.Y }
            end)
            geometryHook = {pre, post}
        end
    end

    function adapter:geometry(widget)
        if not initialize() then return nil end
        -- One hook for this mod's lifetime. Repeated deferred unregister/register
        -- cycles caused native callback/ref churn during rapid inventory movement.
        installGeometryHook()
        wantedGeometry, geometryResult = widget:GetAddress(), nil
        local ok, err = pcall(function() widget:GetCachedGeometry() end)
        wantedGeometry = nil
        if not ok then error(err) end
        local result = geometryResult
        geometryResult = nil
        if result and result.w > 1 and result.h > 1 then return result end
    end

    function adapter:scope()
        if not initialize() then return nil end
        -- DPopupBase widgets are not in the root's PanelPool. Never let a
        -- modal's input reach the menu behind it, including on the login screen.
        local popup = self:popup()
        if popup then return popup end
        local root = valid(manager) and read(manager, "CurrentRootPanelInstance")
        local title = valid(root) and root:GetClass():GetFName():ToString():find("RootLogin",1,true)
        local defaults = {}
        local defaultPanels=valid(manager) and read(manager,"PanelUIDefault")
        if defaultPanels then defaultPanels:ForEach(function(_, value) defaults[unwrap(value)] = true end) end
        local top, topZ
        local embeddedMenus={}
        -- Panels are added directly to the viewport, outside RootCanvas's child
        -- list. The game's own pool supplies their actual display order.
        local pool=valid(root) and read(root,"PanelPool")
        if pool then pool:ForEach(function(key, value)
            local unit = unwrap(value)
            local panel = unit.PanelBase
            if valid(panel) and visible(panel) and panel:IsInViewport() then
                local mainMenu=read(panel,"DLayerMainMenu")
                if valid(mainMenu) then embeddedMenus[#embeddedMenus+1]=mainMenu end
                local eligible = not gameIsA(panel,"DPanelMain") and (title or not defaults[unwrap(key)] or unit.PopupPanelType ~= 0)
                if eligible and (not topZ or unit.ZOrder > topZ) then top, topZ = panel, unit.ZOrder end
            end
        end) end
        -- Menu visibility is authoritative even when the game hides the cursor
        -- for keyboard/controller input. Hidden ancestors still exclude gameplay.
        local function menuScope(layer)
            if not displayed(layer) then
                if mainCache and mainCache.widget:GetAddress()==layer:GetAddress() then mainCache,mouseContext=nil,nil end
                return nil
            end
            local content
            local same=mainCache and valid(mainCache.widget) and mainCache.widget:GetAddress()==layer:GetAddress()
            local now=clock()
            if same and now>=mainCache.settled and valid(mainCache.anchor) and displayed(mainCache.anchor) then
                local bounds=self:geometry(layer)
                local old=mainCache.bounds
                if bounds and old and bounds.x==old.x and bounds.y==old.y and bounds.w==old.w and bounds.h==old.h then
                    -- This menu has a fixed set of icons. Keep live enabled/visible
                    -- checks, without re-walking captions or measuring every icon.
                    content={}
                    for key,value in pairs(mainCache.context) do content[key]=value end
                    content.items={}
                    for _,item in ipairs(mainCache.context.items) do
                        if visible(item.widget) then content.items[#content.items+1]=item end
                    end
                    mouseContext=content
                end
            end
            if not content then
                content=self:collect(layer)
                local anchor=content and menuAnchor(content)
                if anchor and mainMenu(layer) then
                    mainCache={widget=layer,context=content,bounds=content.bounds,anchor=anchor,
                        settled=same and mainCache.settled or now+0.5}
                end
            end
            if content and menuAnchor(content) then return layer end
            -- The same HUD layer keeps InventoryButton02 alive during combat.
            -- A visible shortcut alone does not mean the expanded menu is open.
            mainCache,mouseContext=nil,nil
        end
        -- The HUD owns this layer; its Blueprint class has no native class with
        -- the same name. It can also cover a panel still present in PanelPool.
        for _,layer in ipairs(embeddedMenus) do
            local menu=menuScope(layer);if menu then return menu end
        end
        for _,name in ipairs({"DLayerMainMenu_C","DLayerMainMenu"}) do
            for _,layer in ipairs(FindAllOf(name) or {}) do
                local menu=menuScope(layer);if menu then return menu end
            end
        end
        if top then return top end
        -- The title menu is embedded in RootLogin rather than added separately
        -- to the viewport or PanelPool. Traverse that visible root as a fallback.
        if title and displayed(root) then return root end
        return nil
    end

    local function editingText()
        for _, name in ipairs({"EditableText", "EditableTextBox", "MultiLineEditableText", "MultiLineEditableTextBox"}) do
            for _, widget in ipairs(FindAllOf(name) or {}) do
                if displayed(widget) and (widget:HasKeyboardFocus() or widget:HasFocusedDescendants()) then return true end
            end
        end
        return false
    end

    local function buttonRole(widget,scope,bounds)
        local role={cancel=handlerMatches(widget,"cancel") or handlerMatches(widget,"on.*nobutton"),
            positive=handlerMatches(widget,"on.*okbutton") or handlerMatches(widget,"on.*confirmbutton")
                or handlerMatches(widget,"on.*buttonconfirm") or handlerMatches(widget,"on.*yesbutton"),
            dismiss=handlerMatches(widget,"closebutton") or handlerMatches(widget,"backbutton"),
            closeControl=handlerMatches(widget,"close")}
        role.dungeonExit=handlerMatches(widget,"dungeon.*leave") or handlerMatches(widget,"leave.*dungeon")
            or handlerMatches(widget,"dungeon.*exit") or handlerMatches(widget,"emergencyescape")
            or (gameIsA(scope,"DPopupDungeonResult") and handlerMatches(widget,"onreleasedleavebutton"))
        local captions={cancel=true,no=true,["취소"]=true,["아니오"]=true,["아니요"]=true}
        local positive={ok=true,yes=true,confirm=true,["확인"]=true,["예"]=true}
        local dismiss={close=true,back=true,["닫기"]=true,["뒤로"]=true}
        local function inspect(root)
            local name=root:GetFName():ToString():lower()
            role.namedCancel=role.namedCancel or name:find("cancel",1,true)~=nil or name:find("nobutton",1,true)~=nil
                or name:find("button_no",1,true)~=nil
            role.cancel=role.cancel or role.namedCancel
            role.namedBack=role.namedBack or name=="back" or name:find("backbutton",1,true)~=nil
                or name:find("button_back",1,true)~=nil
            role.dismiss=role.dismiss or name:find("close",1,true)~=nil or name:find("back",1,true)~=nil
            role.closeControl=role.closeControl or name:find("close",1,true)~=nil
            walkUI(root,function(child)
                if isA(child,"TextBlock") or isA(child,"RichTextBlock") then
                    local text=caption(child)
                    if text and centerInside(bounds,adapter:geometry(child)) then
                        role.cancel=role.cancel or captions[text] or false
                        role.positive=role.positive or positive[text] or false
                        role.dismiss=role.dismiss or dismiss[text] or false
                        local x=text=="x" or text=="×" or text=="✕"
                        role.labelledAction=role.labelledAction or (text~="" and not x)
                        role.closeControl=role.closeControl or x
                        role.dungeonExit=role.dungeonExit or dungeonExitText(text)
                    end
                end
            end)
        end
        inspect(widget)
        -- Captions can be siblings of the native Button inside its common-button
        -- UserWidget. Inspect only that wrapper, never the whole popup's captions.
        local owner=widget
        for _=1,16 do
            local ok,parent=pcall(function()return owner:GetParent()end)
            if not ok or not valid(parent) then parent=owner:GetOuter() end
            if not valid(parent) or parent:GetAddress()==scope:GetAddress() then break end
            owner=parent
            if isA(owner,"UserWidget") then inspect(owner);break end
        end
        role.frameClose=role.closeControl and not (role.namedCancel or role.namedBack or role.labelledAction)
        return role
    end

    function adapter:collect(scope, tabsOnly)
        local scopeBounds = self:geometry(scope)
        if not scopeBounds then return nil end
        local items, tabs, visited, count = {}, {}, {}, 0
        local popupTexts={}
        local challengeCaptions={}
        local challengeScreen=challengePanel(scope) and not tabsOnly
        local popup = gameIsA(scope, "DPopupBase")
        local function walk(widget, clip, depth, tabOwner, userDepth)
            widget = unwrap(widget)
            if not valid(widget) or depth > 48 or count > 4000 then return end
            local address = widget:GetAddress()
            if visited[address] or not visible(widget) then return end
            visited[address], count = true, count+1
            if popup and (isA(widget,"TextBlock") or isA(widget,"RichTextBlock")) then
                local text=caption(widget)
                if text and text~="" then popupTexts[#popupTexts+1]={text=text,bounds=self:geometry(widget)} end
            end
            if challengeScreen and (isA(widget,"TextBlock") or isA(widget,"RichTextBlock")) then
                local text=caption(widget)
                if text=="도전" or text=="challenge" then
                    local bounds=self:geometry(widget)
                    if bounds and intersect(bounds,clip) then challengeCaptions[#challengeCaptions+1]=bounds end
                end
            end
            if isA(widget,"UserWidget") then
                userDepth=userDepth+1
                local name=widget:GetClass():GetFName():ToString()
                if name:find("Tab",1,true) and not name:find("Table",1,true) then
                    local parent=widget:GetParent()
                    tabOwner={id=valid(parent) and parent:GetAddress() or name,level=userDepth}
                end
            end
            local button, checkbox = isA(widget, "Button"), isA(widget, "CheckBox")
            if (button or checkbox) and (not tabsOnly or (checkbox and tabOwner)) then
                local bounds = self:geometry(widget)
                if bounds and intersect(bounds, clip) and not (bounds.w > scopeBounds.w*0.8 and bounds.h > scopeBounds.h*0.8) then
                    local actionable = checkbox
                    if button then
                        actionable = #(widget.OnClicked:GetBindings() or {}) > 0 or #(widget.OnReleased:GetBindings() or {}) > 0
                            or #(widget.OnPressed:GetBindings() or {}) > 0
                        if actionable then
                            bounds.role=buttonRole(widget,scope,bounds)
                            actionable=not bounds.role.frameClose
                        end
                    end
                    if actionable then
                        bounds.id, bounds.widget = widget:GetFullName(), widget
                        bounds.kind = checkbox and "checkbox" or "button"
                        bounds.popup = popup
                        local name=widget:GetFName():ToString():lower()
                        bounds.preferInitial = not (name:find("close",1,true) or name:find("back",1,true) or name:find("goods",1,true)
                            or (mainMenu(scope) and hudShortcut(widget)))
                        if checkbox and tabOwner then
                            bounds.active=widget:IsChecked()
                            bounds.tabGroup=tostring(tabOwner.id)..":"..tostring(read(widget,"GroupType"))
                            bounds.tabLevel=tabOwner.level
                            tabs[#tabs+1]=bounds
                        else items[#items+1] = bounds end
                    end
                end
            end
            local list = isA(widget, "ListViewBase")
            if isA(widget, "ScrollBox") or list then
                local bounds = self:geometry(widget)
                clip = bounds and intersect(clip, bounds)
                if not clip then return end
            end
            if isA(widget, "UserWidget") then
                local tree = read(widget,"WidgetTree")
                if valid(tree) then walk(tree.RootWidget, clip, depth+1, tabOwner, userDepth) end
            elseif isA(widget, "WidgetSwitcher") then
                walk(widget:GetActiveWidget(), clip, depth+1, tabOwner, userDepth)
            elseif isA(widget, "PanelWidget") then
                for index=0,widget:GetChildrenCount()-1 do walk(widget:GetChildAt(index), clip, depth+1, tabOwner, userDepth) end
            elseif list then
                local entries = widget:GetDisplayedEntryWidgets()
                local objects = {}
                for _, entry in ipairs(entries) do objects[#objects+1] = unwrap(entry) end
                for _, entry in ipairs(objects) do
                    local before, beforeTabs = #items, #tabs
                    local library=StaticFindObject("/Script/UMG.Default__UserObjectListEntryLibrary")
                    local ok, object=pcall(function() return library:GetListItemObject(entry) end)
                    walk(entry, clip, depth+1, tabOwner, userDepth)
                    if ok and valid(object) then
                        for index=before+1,#items do items[index].id=items[index].id..":"..tostring(object:GetAddress()) end
                    end
                    if not tabsOnly and #items == before and #tabs == beforeTabs and valid(entry) and visible(entry) then
                        if ok and valid(object) then
                            local bounds=self:geometry(entry)
                            local event=read(widget,"BP_OnItemClicked")
                            if bounds and intersect(bounds,clip) and event and #(event:GetBindings() or {}) > 0 then
                                bounds.id=entry:GetFullName()..":"..tostring(object:GetAddress())
                                bounds.kind, bounds.widget, bounds.list, bounds.item="entry", entry, widget, object
                                items[#items+1]=bounds
                            end
                        end
                    end
                end
            end
        end
        walk(scope, scopeBounds, 0, nil, 0)
        table.sort(items, function(a,b)
            local ay, by = math.floor(a.y/4), math.floor(b.y/4)
            if ay ~= by then return ay < by end
            if a.x ~= b.x then return a.x < b.x end
            return a.id < b.id
        end)
        local groups={}
        for _,tab in ipairs(tabs) do
            local group=groups[tab.tabGroup] or {id=tab.tabGroup,level=tab.tabLevel,
                items={},left=math.huge,right=-math.huge,top=math.huge,bottom=-math.huge}
            groups[tab.tabGroup]=group
            group.level=math.min(group.level,tab.tabLevel)
            group.items[#group.items+1]=tab
            local x,y=tab.x+tab.w/2,tab.y+tab.h/2
            group.left,group.right=math.min(group.left,x),math.max(group.right,x)
            group.top,group.bottom=math.min(group.top,y),math.max(group.bottom,y)
        end
        if tabScope~=scope:GetAddress() then
            tabScope,primaryGroup,secondaryGroup=scope:GetAddress(),nil,nil
        end
        local function choose(exclude, previous)
            local candidates,level={},math.huge
            for _,group in pairs(groups) do
                if group~=exclude then
                    if group.level<level then candidates,level={},group.level end
                    if group.level==level then candidates[#candidates+1]=group end
                end
            end
            -- Keep the same group when checked tabs resize or another group grows.
            for _,group in ipairs(candidates) do if group.id==previous then return group end end
            table.sort(candidates,function(a,b)
                local aspan=math.max(a.right-a.left,a.bottom-a.top)
                local bspan=math.max(b.right-b.left,b.bottom-b.top)
                if aspan~=bspan then return aspan>bspan end
                if a.top~=b.top then return a.top<b.top end
                return a.id<b.id
            end)
            return candidates[1]
        end
        local primary=choose(nil,primaryGroup)
        local secondary=choose(primary,secondaryGroup)
        primaryGroup,secondaryGroup=primary and primary.id,secondary and secondary.id
        local function sorted(group)
            if not group then return {} end
            local vertical=group.bottom-group.top>group.right-group.left
            table.sort(group.items,function(a,b)
                local av=vertical and a.y+a.h/2 or a.x+a.w/2
                local bv=vertical and b.y+b.h/2 or b.x+b.w/2
                return av==bv and a.id<b.id or av<bv
            end)
            return group.items
        end
        tabs=sorted(primary)
        local secondaryTabs=sorted(secondary)
        -- Tab controls never enter WASD navigation. Third and deeper groups are ignored.
        local tabHints={}
        for _,entry in ipairs({{primary,"Q/E"},{secondary,"1/3"}}) do
            local group,key=entry[1],entry[2]
            if group and #group.items>1 then
                local active=group.items[1]
                for _,item in ipairs(group.items) do if item.active then active=item;break end end
                tabHints[#tabHints+1]={id="tabs:"..group.id..":"..key,widget=active.widget,key=key}
            end
        end
        local dialog,confirmation,confirm,form=false,false,nil,false
        local formActions,formAdvance
        if popup then
            local choices,allButtons,hasEntries={},{},false
            for _,item in ipairs(items) do
                if item.kind=="entry" then hasEntries=true end
                if item.kind=="button" then
                    item.role=item.role or buttonRole(item.widget,scope,item)
                    allButtons[#allButtons+1]=item
                    if not item.role.dismiss or item.role.cancel or item.role.positive then choices[#choices+1]=item end
                end
            end
            if #choices==0 and #allButtons==1 then choices=allButtons end
            -- Square quick-slot selectors belong to the form, not its footer's
            -- confirmation choices. Pure three-way action dialogs still use A/D.
            local bottom=-math.huge
            for _,item in ipairs(choices) do
                if item.w>=item.h*1.6 then bottom=math.max(bottom,item.y+item.h/2) end
            end
            local footer,body={},{}
            for _,item in ipairs(items) do
                if item.kind=="button" and item.w>=item.h*1.6
                    and math.abs(item.y+item.h/2-bottom)<=math.max(8,math.min(32,item.h*0.4)) then
                    footer[#footer+1]=item
                else body[#body+1]=item end
            end
            local quickSlot=gameIsA(scope,"DPopupQuickSlot")
            form=hasEntries or #tabs>0 or #secondaryTabs>0
            for _,item in ipairs(body) do
                if item.y+item.h/2<bottom and (item.kind~="button" or item.w<item.h*1.6) then form=true end
            end
            form=form or quickSlot
            dialog=not form
            if form then
                formActions=footer
                local positive,cancel
                for _,item in ipairs(footer) do
                    if item.role.positive and not item.role.cancel then positive=item end
                    if item.role.cancel then cancel=item end
                end
                if #footer==1 and not footer[1].role.cancel then confirm=footer[1]
                elseif #footer==2 then confirm=positive or (cancel and (footer[1]==cancel and footer[2] or footer[1])) end
                items={}
                for _,item in ipairs(body) do items[#items+1]=item end
                for _,item in ipairs(footer) do
                    if #footer>2 or not item.role.cancel then items[#items+1]=item end
                end
                formAdvance=quickSlot and confirm or nil
            end
            if dialog then
                items=choices
                confirmation=#choices<=2
                if #choices==1 then confirm=choices[1]
                elseif #choices==2 then
                    -- A known affirmative action wins. Otherwise use the sole
                    -- button opposite a recognised cancel/close action.
                    local a,b=choices[1],choices[2]
                    if a.role.positive and not a.role.cancel then confirm=a
                    elseif b.role.positive and not b.role.cancel then confirm=b
                    elseif a.role.cancel~=b.role.cancel then confirm=a.role.cancel and b or a end
                end
            end
        end
        local entryAction
        if challengeScreen then
            for _,item in ipairs(items) do
                local challenge=false
                for _,label in ipairs(challengeCaptions) do
                    if centerInside(item,label) then challenge=true;break end
                end
                if item.kind=="button" and challenge then
                    -- Duplicate captions are ambiguous; do not choose an arbitrary button.
                    if entryAction then entryAction=nil;break end
                    entryAction=item
                end
            end
        end
        local exitAction,ambiguousExit
        for _,item in ipairs(items) do
            if item.role and item.role.dungeonExit and not item.role.cancel then
                item.fixedKey="F"
                if exitAction then ambiguousExit=true end
                exitAction=item
            end
        end
        local body={}
        for _,label in ipairs(popupTexts) do
            local actionCaption=false
            for _,item in ipairs(items) do
                if centerInside(item,label.bounds) then actionCaption=true;break end
            end
            if not actionCaption then body[#body+1]=label.text end
        end
        local confirmKey="Space"
        if confirmation and confirm and not (confirm.role and confirm.role.cancel)
            and (dungeonExitText(table.concat(body,"")) or (confirm.role and confirm.role.dungeonExit)) then
            confirmKey="F";confirm.fixedKey="F";entryAction=confirm
        elseif not confirmation and exitAction and not ambiguousExit then
            entryAction=exitAction
        end
        local keyHints=confirmation and (confirm and {{widget=confirm.widget,key=confirmKey}} or {}) or tabHints
        if entryAction and not confirmation then keyHints[#keyHints+1]={widget=entryAction.widget,key="F"} end
        local context={ scope=scope:GetFullName(), scopeWidget=scope,bounds=scopeBounds,items=items, tabs=tabs, secondaryTabs=secondaryTabs,
            popup=popup, dialog=dialog, confirmation=confirmation, confirm=confirm,confirmKey=confirmKey,
            form=form, formActions=formActions, formAdvance=formAdvance,
            mouseNavigation=mainMenu(scope),
            entryAction=entryAction, hints=keyHints }
        if context.mouseNavigation and not tabsOnly then mouseContext=context end
        return context
    end

    function adapter:mousePosition()
        if not valid(layoutLibrary) then layoutLibrary=StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary") end
        local ok,value=pcall(function()return layoutLibrary:GetMousePositionOnPlatform()end)
        if ok and value and type(value.X)=="number" and type(value.Y)=="number" then return {x=value.X,y=value.Y} end
    end

    function adapter:hovered(context)
        if not context.mouseNavigation then return nil end
        local position=self:mousePosition()
        if not position then return nil end
        local hovered
        for _,item in ipairs(context.items) do
            -- Button wrappers do not reliably expose native IsHovered. These
            -- rectangles already use the same desktop coordinates as Slate's cursor.
            if item.kind=="button" and position.x>=item.x and position.x<item.x+item.w
                and position.y>=item.y and position.y<item.y+item.h and visible(item.widget) then
                if hovered then return nil,position end
                hovered=item
            end
        end
        return hovered,position
    end

    function adapter:pollMouse()
        if not navigation.enabled then navigation.mouse=nil;return end
        -- Never search global objects, traverse menus, or measure geometry here.
        -- Existing 250ms UI refresh and real key input supply the cached context.
        local context=mouseContext
        if not context then navigation.mouse=nil;return end
        local position=self:mousePosition()
        local previous=navigation.mouse
        if position and previous and previous.scope==context.scope
            and previous.x==position.x and previous.y==position.y then return end
        if not displayed(context.scopeWidget) then
            mouseContext=nil;navigation:clear();navigation.mouse=nil;return
        end
        navigation:context(context)
    end

    function adapter:enterDungeon(context)
        local scope=self:scope()
        if not scope or scope:GetAddress()~=context.scopeWidget:GetAddress() or editingText() then return false end
        -- Re-read the caption and enabled/visible state instead of trusting a cached hint.
        local current=self:collect(scope)
        local item=current and current.entryAction
        if not item or not displayed(item.widget) then return false end
        self:activate(item)
        return true
    end

    local function tabStamp(context)
        local parts={}
        for _,tabs in ipairs({context.tabs or {},context.secondaryTabs or {}}) do
            for _,item in ipairs(tabs) do
                local widget=item.widget
                parts[#parts+1]=item.id..":"..tostring(displayed(widget))..":"..tostring(valid(widget) and widget:IsChecked())
            end
        end
        return table.concat(parts,"|")
    end

    local function rememberTabs(context)
        tabHintContext=context
        tabHintStamp=context and tabStamp(context)
        tabHintTime=os.clock()
    end

    function adapter:snapshot()
        local scope=self:scope()
        if not scope or editingText() then mouseContext=nil;stopMap();return nil end
        if not gameIsA(scope,"DPanelWorldMap") then stopMap() end
        if not mainMenu(scope) then mouseContext=nil end
        if gameIsA(scope,"DPanelWorldMap") then return mapContext(scope) end
        installGeometryHook()
        local ok,result=pcall(function()
            -- Main-menu discovery has already collected this exact visible layer.
            if mainMenu(scope) and mouseContext and mouseContext.scopeWidget:GetAddress()==scope:GetAddress() then return mouseContext end
            return self:collect(scope)
        end)
        wantedGeometry = nil
        geometryResult = nil
        if not ok then error(result) end
        if result and not result.popup then rememberTabs(result) end
        return result
    end

    local function hintCanvas(context)
        local canvas
        walkUI(context.scopeWidget,function(widget)
            if not canvas and isA(widget,"CanvasPanel") then canvas=widget end
        end)
        return canvas
    end

    local hints=HotkeyHints.new({valid=valid,displayed=displayed,
        remove=function(label)if valid(label) then label:RemoveFromParent() end end,
        create=function(context,button,key)
            local canvas=hintCanvas(context)
            local tree=read(context.scopeWidget,"WidgetTree")
            if not valid(canvas) or not valid(tree) then return nil end
            local text=StaticConstructObject(class("TextBlock"),tree)
            if not valid(text) then return nil end
            text:SetText(FText(key))
            local font=text.Font
            font.Size=16
            text:SetFont(font)
            text:SetVisibility(3) -- HitTestInvisible: hints never intercept the mouse.
            text:SetRenderOpacity(0.85)
            text:SetShadowOffset({X=1,Y=1})
            text:SetShadowColorAndOpacity({R=0,G=0,B=0,A=1})
            local slot=canvas:AddChildToCanvas(text)
            slot:SetSize({X=key=="Space" and 58 or (#key>1 and 38 or 20),Y=26})
            slot:SetZOrder(10000)
            return text
        end,
        place=function(context,label,button,key)
            local canvas=label:GetParent()
            local c,b=adapter:geometry(canvas),adapter:geometry(button)
            if not c or not b then label:SetVisibility(1);return end
            local sx,sy=c.w/c.localW,c.h/c.localH
            local width=key=="Space" and 58 or (#key>1 and 38 or 20)
            local x=(b.x+b.w-c.x)/sx+7
            if x+width>c.localW-4 then x=(b.x+b.w-c.x)/sx-width-10 end
            local y=(b.y+b.h/2-c.y)/sy-13
            label.Slot:SetPosition({X=x,Y=y})
            label:SetVisibility(3)
        end})

    function adapter:refreshHints()
        activeMap=nil
        mapState=nil
        refreshedScope=nil
        if not navigation.enabled then stopMap();mouseContext=nil;tabHintContext=nil;hints:clear();return end
        local scope=self:scope()
        if not scope or editingText() then stopMap();mouseContext=nil;tabHintContext=nil;hints:clear();return end
        refreshedScope=scope
        if not mainMenu(scope) then mouseContext=nil end
        if gameIsA(scope,"DPanelWorldMap") then
            activeMap=scope;mapState=map:context(scope)
            if next(held) then map:preparePan(mapState) end
        else stopMap() end
        if options.hints==false then tabHintContext=nil;hints:clear();return end
        -- This fixed icon menu has no Q/E tab groups; avoid traversing its tree
        -- again just to rediscover an empty hint set.
        if mainMenu(scope) then tabHintContext=nil;hints:clear();return end
        if gameIsA(scope,"DPanelWorldMap") then
            tabHintContext=nil;hints:update(mapContext(scope,mapState))
        elseif gameIsA(scope,"DPopupBase") or challengePanel(scope) then
            tabHintContext=nil
            local context=self:collect(scope)
            if context and context.form and navigation.scope==context.scope and navigation.selected then
                for _,item in ipairs(context.items) do
                    if item.id==navigation.selected.id then
                        context.hints[#context.hints+1]={widget=item.widget,key="Space"};break
                    end
                end
            end
            hints:update(context)
        else
            -- Scan tab widgets on transitions; periodically discover asynchronously
            -- added groups without measuring every inventory button each refresh.
            if not tabHintContext or not valid(tabHintContext.scopeWidget)
                or tabHintContext.scopeWidget:GetAddress()~=scope:GetAddress()
                or os.clock()-tabHintTime>=1 or tabHintStamp~=tabStamp(tabHintContext) then
                rememberTabs(self:collect(scope,true))
            end
            hints:update(tabHintContext)
        end
    end

    function adapter:highlight(item, on, source)
        local widget = item.widget
        if not valid(widget) then return end
        if on then
            self.highlights[item.id] = self.highlights[item.id] or { widget=widget, original=widget:GetRenderOpacity() }
            -- Native mouse hover already fired this delegate. Replaying it can
            -- repeat game UI handlers; keyboard selection still needs it.
            if item.kind == "button" and source~="mouse" then fire(widget,"OnHovered") end
            widget:SetRenderOpacity(0.65)
            -- Keep Slate's focused-button Space handler from duplicating our own
            -- confirmation. This changes focus only; it does not change input mode.
            if source~="retain" then
                local library=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
                library:SetFocusToGameViewport()
            end
        else
            local entry = self.highlights[item.id]
            if entry then
                if math.abs(widget:GetRenderOpacity()-0.65) < 0.001 then widget:SetRenderOpacity(entry.original) end
                self.highlights[item.id] = nil
            end
            if item.kind == "button" then fire(widget,"OnUnhovered") end
        end
    end

    function adapter:activate(item)
        mouseContext=nil
        local widget = item.widget
        if not valid(widget) or not visible(widget) then return end
        if item.kind == "entry" then
            if valid(item.list) and valid(item.item) then fire(item.list,"BP_OnItemClicked",item.item) end
            return
        end
        if item.kind == "checkbox" then
            local group=read(widget,"GroupType")
            local checked = (type(group)=="number" and group~=0) or not widget:IsChecked()
            widget:SetIsChecked(checked)
            local gameCheckbox=StaticFindObject("/Script/DSClient.DCheckBox")
            if valid(gameCheckbox) and widget:IsA(gameCheckbox) then widget:CheckStateChanged(checked)
            else fire(widget,"OnCheckStateChanged",checked) end
            return
        end
        fire(widget,"OnPressed")
        if valid(widget) then fire(widget,"OnReleased") end
        if valid(widget) then fire(widget,"OnClicked") end
    end

    function adapter:activateTab(item)
        local widget=item.widget
        if not valid(widget) or not visible(widget) then return end
        widget:SetIsChecked(true)
        local gameCheckbox=StaticFindObject("/Script/DSClient.DCheckBox")
        if valid(gameCheckbox) and widget:IsA(gameCheckbox) then widget:CheckStateChanged(true)
        else fire(widget,"OnCheckStateChanged",true) end
    end

    local function run(callback)
        local ok, err = pcall(callback)
        if not ok then
            wantedGeometry = nil
            if tostring(err) ~= lastError then lastError=tostring(err); log("MENU ERROR "..lastError) end
            pcall(function() navigation:clear() end)
        end
    end

    local function bind(key, callback)
        if options.bindKeys == false then return end
        thread:bind(key, function() run(callback) end)
    end
    bind(Key.F7, function()
        stopMap()
        log("MENU " .. (navigation:toggle() and "ON" or "OFF") .. " - WASD / Space")
        adapter:refreshHints()
    end)
    for _, entry in ipairs({{Key.W,"up"},{Key.S,"down"},{Key.A,"left"},{Key.D,"right"}}) do
        local direction = entry[2]
        bind(entry[1], function() navigation:move(direction) end)
    end
    bind(Key.SPACE, function() navigation:confirm() end)
    bind(Key.Q, function() navigation:tab(-1) end)
    bind(Key.E, function() navigation:tab(1) end)
    bind(Key.ONE, function() navigation:tab(-1,true) end)
    bind(Key.THREE, function() navigation:tab(1,true) end)
    bind(Key.F, function() navigation:interact() end)
    bind(Key.LEFT_MOUSE_BUTTON, function() mouseContext=nil;stopMap();navigation:clear() end)
    thread:loop(50,function()
        if options.bindKeys~=false then adapter:pollMouse() end
        if options.bindKeys==false or not navigation.enabled or not mapState or not valid(controller) then return end
        -- Key-down callbacks and PlayerInput can arrive in different engine
        -- ticks, and UI focus changes can flush PlayerInput. Recover a currently
        -- pressed direction without requiring a fresh key-down callback.
        local wasIdle=not next(held)
        local now=adapter:mapClock()
        for _,key in ipairs({"W","A","S","D"}) do
            if not keyNames[key] then keyNames[key]=FName(key) end
            local ok,down=pcall(function()return controller:IsInputKeyDown({KeyName=keyNames[key]})end)
            if ok and down and not held[key] then held[key]={started=now,seen=true} end
        end
        if wasIdle and next(held) then mapTime=now end
    end)
    local motionDriver=thread:frames(1,function()
        if options.bindKeys==false or not navigation.enabled or not mapState or not next(held) then return end
        if not valid(activeMap) or not valid(controller) then stopMap();return end
        local visibility=activeMap:GetVisibility()
        if visibility==1 or visibility==2 then stopMap();return end
        local now=adapter:mapClock()
        local seconds=mapTime and now-mapTime or 0
        mapTime=now
        local x,y=0,0
        for key,state in pairs(held) do
            local ok,down=pcall(function()return controller:IsInputKeyDown({KeyName=keyNames[key]})end)
            if ok and down then
                state.seen=true
                if key=="W" then y=y+1 elseif key=="S" then y=y-1
                elseif key=="A" then x=x+1 elseif key=="D" then x=x-1 end
            elseif state.seen or now-state.started>=0.12 then held[key]=nil end
        end
        if not map:motion(mapState,x,y,seconds) and not next(held) then mapTime=nil end
    end)
    log("MAP motion driver="..motionDriver.." speed=1400; no hold delay")
    thread:loop(250, function()
            run(function()
                adapter:refreshHints()
                local selected=navigation.selected
                if not selected then return end
                local scope = refreshedScope
                if not scope or scope:GetFullName() ~= navigation.scope or not valid(selected.widget) then navigation:clear() end
            end)
    end)
    log("MENU loaded - F7 toggle; WASD select, Space confirm, Q/E primary tabs, 1/3 secondary tabs, F warp/challenge; native Esc goes back")
    return { navigation=navigation, adapter=adapter, hints=hints, reportStatus=function()
        local context=adapter:snapshot()
        if not context then
            log("STATUS MENU scope=none")
            local root=valid(manager) and read(manager,"CurrentRootPanelInstance")
            local pool=valid(root) and read(root,"PanelPool")
            if pool then pool:ForEach(function(_,value)
                local unit=unwrap(value)
                local panel=read(unit,"PanelBase")
                if valid(panel) then
                    local menu=read(panel,"DLayerMainMenu")
                    log(string.format("STATUS PANEL %s visible=%s viewport=%s embeddedMenu=%s displayed=%s",
                        panel:GetFName():ToString(),tostring(visible(panel)),tostring(panel:IsInViewport()),
                        valid(menu) and menu:GetFName():ToString() or "none",tostring(valid(menu) and displayed(menu))))
                end
            end) end
            return
        end
        log(string.format("STATUS MENU scope=%s items=%d popup=%s dialog=%s immediate=%s form=%s confirm=%s selected=%s actionF=%s",
            context.scope,#context.items,tostring(context.popup),tostring(context.dialog),tostring(context.confirmation),tostring(context.form),
            context.confirm and context.confirm.widget:GetFName():ToString() or "none",
            navigation.selected and navigation.selected.widget:GetFName():ToString() or "none",
            context.entryAction and context.entryAction.widget:GetFName():ToString() or "none"))
        for index,item in ipairs(context.items) do
            if index>16 then break end
            log(string.format("STATUS ITEM %s kind=%s rect=%.1f,%.1f,%.1f,%.1f",
                item.widget:GetFName():ToString(),item.kind,item.x,item.y,item.w,item.h))
        end
        if context.mouseNavigation then
            local hovered,position=adapter:hovered(context)
            log(string.format("STATUS MOUSE cursor=%s position=%s hovered=%s",
                tostring(valid(controller) and read(controller,"bShowMouseCursor")),
                position and string.format("%.1f,%.1f",position.x,position.y) or "unavailable",
                hovered and hovered.widget:GetFName():ToString() or "none"))
        end
        if context.map then
            local keys={}
            for _,key in ipairs({"W","A","S","D"}) do
                if not keyNames[key] then keyNames[key]=FName(key) end
                local ok,down=pcall(function()return controller:IsInputKeyDown({KeyName=keyNames[key]})end)
                keys[#keys+1]=key..":"..tostring(ok and down).."/"..tostring(held[key]~=nil)
            end
            log("STATUS MAP driver="..motionDriver.." down/armed="..table.concat(keys,",").." ready="..tostring(mapState and mapState.panBounds~=nil))
        end
    end }
end

return Module

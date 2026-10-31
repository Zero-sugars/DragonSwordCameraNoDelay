local Navigation = require("menu_navigation")
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

function Module.start(log, options)
    options = options or {}
    local adapter = { types = {}, highlights = {} }
    local navigation = Navigation.new(adapter)
    local manager, controller, slate, geometryHook
    local wantedGeometry, geometryResult
    local lastError, pending

    local function class(name)
        if not valid(adapter.types[name]) then adapter.types[name] = StaticFindObject("/Script/UMG." .. name) end
        return adapter.types[name]
    end

    local function isA(object, name)
        local c = class(name)
        return valid(c) and object:IsA(c)
    end

    local function displayed(widget)
        local seen = {}
        for _=1,64 do
            if not valid(widget) or not visible(widget) then return false end
            local address=widget:GetAddress()
            if seen[address] then return false end
            seen[address]=true
            if isA(widget,"UserWidget") and widget:IsInViewport() then return true end
            local parent=widget:GetParent()
            if not valid(parent) then
                local outer=widget:GetOuter()
                for _=1,8 do
                    if not valid(outer) or isA(outer,"UserWidget") then break end
                    outer=outer:GetOuter()
                end
                parent=outer
            end
            if not valid(parent) or not isA(parent,"Widget") then return false end
            widget=parent
        end
        return false
    end

    local function initialize()
        if not valid(controller) then
            controller = nil
            for _, candidate in ipairs(FindAllOf("PlayerController") or {}) do
                if candidate:IsLocalController() then controller = candidate; break end
            end
        end
        if not valid(manager) then manager = FindFirstOf("DUIManager") end
        if not valid(slate) then slate = StaticFindObject("/Script/UMG.Default__SlateBlueprintLibrary") end
        if not valid(controller) or not valid(manager) or not valid(slate) then return false end
        return true
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
                geometryResult = { x=origin.X, y=origin.Y, w=corner.X-origin.X, h=corner.Y-origin.Y }
            end)
            geometryHook = {pre, post}
        end
    end

    local function releaseGeometryHook()
        wantedGeometry = nil
        if geometryHook then
            UnregisterHook("/Script/UMG.Widget:GetCachedGeometry", geometryHook[1], geometryHook[2])
            geometryHook = nil
        end
    end

    function adapter:geometry(widget)
        local temporary = not geometryHook
        if temporary then
            if not initialize() then return nil end
            installGeometryHook()
        end
        wantedGeometry, geometryResult = widget:GetAddress(), nil
        local ok, err = pcall(function() widget:GetCachedGeometry() end)
        wantedGeometry = nil
        if temporary then releaseGeometryHook() end
        if not ok then error(err) end
        local result = geometryResult
        geometryResult = nil
        if result and result.w > 1 and result.h > 1 then return result end
    end

    function adapter:scope()
        if not initialize() then return nil end
        local root = read(manager, "CurrentRootPanelInstance")
        if not valid(root) then return nil end
        local title = root:GetClass():GetFName():ToString():find("RootLogin",1,true)
        local defaults = {}
        manager.PanelUIDefault:ForEach(function(_, value) defaults[unwrap(value)] = true end)
        local top, topZ
        -- Panels are added directly to the viewport, outside RootCanvas's child
        -- list. The game's own pool supplies their actual display order.
        root.PanelPool:ForEach(function(key, value)
            local unit = unwrap(value)
            local panel = unit.PanelBase
            if valid(panel) and visible(panel) and panel:IsInViewport() then
                local eligible = title or not defaults[unwrap(key)] or unit.PopupPanelType ~= 0
                if eligible and (not topZ or unit.ZOrder > topZ) then top, topZ = panel, unit.ZOrder end
            end
        end)
        if top then return top end
        if controller.bShowMouseCursor then
            for _, layer in ipairs(FindAllOf("DLayerMainMenu") or {}) do
                if displayed(layer) then return layer end
            end
        end
        return nil
    end

    local function editingText()
        for _, name in ipairs({"EditableText", "EditableTextBox", "MultiLineEditableText", "MultiLineEditableTextBox"}) do
            for _, widget in ipairs(FindAllOf(name) or {}) do
                if widget:HasKeyboardFocus() or widget:HasFocusedDescendants() then return true end
            end
        end
        return false
    end

    function adapter:collect(scope)
        local scopeBounds = self:geometry(scope)
        if not scopeBounds then return nil end
        local items, tabs, visited, count = {}, {}, {}, 0
        local function walk(widget, clip, depth, tabOwner)
            widget = unwrap(widget)
            if not valid(widget) or depth > 48 or count > 4000 then return end
            local address = widget:GetAddress()
            if visited[address] or not visible(widget) then return end
            visited[address], count = true, count+1
            if isA(widget,"UserWidget") then
                local name=widget:GetClass():GetFName():ToString()
                if name:find("Tab",1,true) and not name:find("Table",1,true) then
                    local parent=widget:GetParent()
                    tabOwner=valid(parent) and parent:GetAddress() or name
                end
            end
            local button, checkbox = isA(widget, "Button"), isA(widget, "CheckBox")
            if button or checkbox then
                local bounds = self:geometry(widget)
                if bounds and intersect(bounds, clip) and not (bounds.w > scopeBounds.w*0.8 and bounds.h > scopeBounds.h*0.8) then
                    local actionable = checkbox
                    if button then
                        actionable = #(widget.OnClicked:GetBindings() or {}) > 0 or #(widget.OnReleased:GetBindings() or {}) > 0
                    end
                    if actionable then
                        bounds.id, bounds.widget = widget:GetFullName(), widget
                        bounds.kind = checkbox and "checkbox" or "button"
                        local name=widget:GetFName():ToString():lower()
                        bounds.preferInitial = not (name:find("close",1,true) or name:find("back",1,true) or name:find("goods",1,true))
                        if checkbox and tabOwner then
                            bounds.active=widget:IsChecked()
                            bounds.tabGroup=tostring(tabOwner)..":"..tostring(read(widget,"GroupType"))
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
                if valid(tree) then walk(tree.RootWidget, clip, depth+1, tabOwner) end
            elseif isA(widget, "WidgetSwitcher") then
                walk(widget:GetActiveWidget(), clip, depth+1, tabOwner)
            elseif isA(widget, "PanelWidget") then
                for index=0,widget:GetChildrenCount()-1 do walk(widget:GetChildAt(index), clip, depth+1, tabOwner) end
            elseif list then
                local entries = widget:GetDisplayedEntryWidgets()
                local objects = {}
                for _, entry in ipairs(entries) do objects[#objects+1] = unwrap(entry) end
                for _, entry in ipairs(objects) do
                    local before, beforeTabs = #items, #tabs
                    local library=StaticFindObject("/Script/UMG.Default__UserObjectListEntryLibrary")
                    local ok, object=pcall(function() return library:GetListItemObject(entry) end)
                    walk(entry, clip, depth+1, tabOwner)
                    if ok and valid(object) then
                        for index=before+1,#items do items[index].id=items[index].id..":"..tostring(object:GetAddress()) end
                    end
                    if #items == before and #tabs == beforeTabs and valid(entry) and visible(entry) then
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
        walk(scope, scopeBounds, 0)
        table.sort(items, function(a,b)
            local ay, by = math.floor(a.y/4), math.floor(b.y/4)
            if ay ~= by then return ay < by end
            if a.x ~= b.x then return a.x < b.x end
            return a.id < b.id
        end)
        local groups={}
        for _,tab in ipairs(tabs) do
            local group=groups[tab.tabGroup] or {items={},left=math.huge,right=-math.huge,top=math.huge,bottom=-math.huge}
            groups[tab.tabGroup]=group
            group.items[#group.items+1]=tab
            local x,y=tab.x+tab.w/2,tab.y+tab.h/2
            group.left,group.right=math.min(group.left,x),math.max(group.right,x)
            group.top,group.bottom=math.min(group.top,y),math.max(group.bottom,y)
        end
        local primary,span
        for _,group in pairs(groups) do
            local extent=math.max(group.right-group.left,group.bottom-group.top)
            if #group.items>1 and (not span or extent>span or (extent==span and group.top<primary.top)) then primary,span=group,extent end
        end
        tabs=primary and primary.items or {}
        for _,group in pairs(groups) do
            if group~=primary then for _,tab in ipairs(group.items)do items[#items+1]=tab end end
        end
        local vertical=primary and primary.bottom-primary.top>primary.right-primary.left
        table.sort(tabs, function(a,b)
            local av=vertical and a.y+a.h/2 or a.x+a.w/2
            local bv=vertical and b.y+b.h/2 or b.x+b.w/2
            return av==bv and a.id<b.id or av<bv
        end)
        return { scope=scope:GetFullName(), items=items, tabs=tabs }
    end

    function adapter:snapshot()
        local scope=self:scope()
        if not scope or editingText() then return nil end
        installGeometryHook()
        local ok,result=pcall(function() return self:collect(scope) end)
        releaseGeometryHook()
        if not ok then error(result) end
        return result
    end

    function adapter:highlight(item, on)
        local widget = item.widget
        if not valid(widget) then return end
        if on then
            if item.kind == "entry" then
                item.list:BP_SetSelectedItem(item.item)
            elseif item.kind == "checkbox" then
                self.highlights[item.id] = { widget=widget, original=widget:GetRenderOpacity() }
                widget:SetRenderOpacity(0.65)
            else fire(widget,"OnHovered") end
            -- Keep Slate's focused-button Space handler from duplicating our own
            -- confirmation. This changes focus only; it does not change input mode.
            local library=StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
            library:SetFocusToGameViewport()
        else
            local entry = self.highlights[item.id]
            if entry then
                if math.abs(widget:GetRenderOpacity()-0.65) < 0.001 then widget:SetRenderOpacity(entry.original) end
                self.highlights[item.id] = nil
            elseif item.kind == "button" then fire(widget,"OnUnhovered") end
        end
    end

    function adapter:activate(item)
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
        RegisterKeyBind(key, function() ExecuteInGameThread(function() run(callback) end) end)
    end
    bind(Key.F7, function() log("MENU " .. (navigation:toggle() and "ON" or "OFF") .. " - WASD / Space") end)
    for _, entry in ipairs({{Key.W,"up"},{Key.S,"down"},{Key.A,"left"},{Key.D,"right"}}) do
        local direction = entry[2]
        bind(entry[1], function() navigation:move(direction) end)
    end
    bind(Key.SPACE, function() navigation:confirm() end)
    bind(Key.Q, function() navigation:tab(-1) end)
    bind(Key.E, function() navigation:tab(1) end)
    bind(Key.LEFT_MOUSE_BUTTON, function() navigation:clear() end)
    LoopAsync(250, function()
        if pending or not navigation.selected then return false end
        pending = true
        ExecuteInGameThread(function()
            run(function()
                local selected=navigation.selected
                if not selected then return end
                local scope = adapter:scope()
                if not scope or scope:GetFullName() ~= navigation.scope or not valid(selected.widget) then navigation:clear() end
            end)
            pending = false
        end)
        return false
    end)
    log("MENU loaded - F7 toggle; WASD select, Space confirm, Q/E tabs; native Esc goes back")
    return { navigation=navigation, adapter=adapter }
end

return Module

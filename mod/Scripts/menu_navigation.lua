-- Selection rules are independent of Unreal objects so menu transitions can be tested.
local Navigation = {}
Navigation.__index = Navigation

local function firstItem(items)
    for _, item in ipairs(items) do if item.kind == "entry" then return item end end
    for _, item in ipairs(items) do if item.preferInitial ~= false then return item end end
    return items[1]
end

function Navigation.new(adapter)
    return setmetatable({ adapter = adapter, enabled = true }, Navigation)
end

function Navigation:clear()
    if self.selected then self.adapter:highlight(self.selected, false) end
    self.selected, self.scope = nil, nil
end

function Navigation:toggle()
    self:clear()
    self.mouse = nil
    self.enabled = not self.enabled
    return self.enabled
end

function Navigation:context(context)
    if not self.enabled then return nil end
    context = context or self.adapter:snapshot()
    if not context or context.blocked then self:clear(); self.mouse=nil; return nil end
    if self.scope ~= context.scope then self:clear() end
    local found
    for _, item in ipairs(context.items) do
        if self.selected and item.id == self.selected.id then found = item; break end
    end
    if self.selected and not found then self:clear() end
    self.scope = context.scope
    if found then self.selected = found end
    self:syncMouse(context)
    return context
end

function Navigation:select(item, source)
    if not item then return end
    if self.selected and self.selected.id == item.id then return end
    if self.selected then self.adapter:highlight(self.selected, false) end
    self.selected = item
    self.adapter:highlight(item, true, source)
end

function Navigation:syncMouse(context)
    if not context.mouseNavigation or context.popup or context.map then self.mouse=nil;return end
    local item,position=self.adapter:hovered(context)
    local id=item and item.id
    local previous=self.mouse
    local moved=position and previous and previous.x and
        (math.abs(position.x-previous.x)>=1 or math.abs(position.y-previous.y)>=1)
    local changed=not previous or previous.scope~=context.scope or previous.id~=id or moved
    self.mouse={scope=context.scope,id=id,x=position and position.x,y=position and position.y}
    -- A stationary pointer must not pull selection back after a WASD move.
    -- Selection alone never clicks a button, even when Space is held elsewhere.
    if changed and item then self:select(item,"mouse")
    elseif changed and not item and previous and previous.id and self.selected and self.selected.id==previous.id then
        -- Native mouse-leave animations can erase the visible cursor even though
        -- selection remains. Restore it once, without a per-frame hover replay.
        self.adapter:highlight(self.selected,true,"retain")
    end
end

function Navigation.neighbor(items, current, direction)
    local horizontal = direction == "left" or direction == "right"
    local sign = (direction == "left" or direction == "up") and -1 or 1
    local cx, cy = current.x + current.w / 2, current.y + current.h / 2
    local best, bestScore
    for _, item in ipairs(items) do
        if item.id ~= current.id then
            local dx, dy = item.x + item.w / 2 - cx, item.y + item.h / 2 - cy
            local along = (horizontal and dx or dy) * sign
            local across = math.abs(horizontal and dy or dx)
            if along > 1 then
                local overlap = horizontal
                    and math.min(current.y + current.h, item.y + item.h) - math.max(current.y, item.y)
                    or math.min(current.x + current.w, item.x + item.w) - math.max(current.x, item.x)
                local score = along + across * 3 + (overlap < 0 and across * 4 or 0)
                if not bestScore or score < bestScore then best, bestScore = item, score end
            end
        end
    end
    return best
end

function Navigation:move(direction)
    local context = self:context()
    if context and context.map then self:clear();return self.adapter:panMap(context,direction) end
    if context and context.confirmation then self:clear(); return false end
    if not context or #context.items == 0 then return false end
    if context.dialog then
        if direction~="left" and direction~="right" then return false end
        local index
        for i,item in ipairs(context.items) do if self.selected and self.selected.id==item.id then index=i;break end end
        local step=direction=="left" and -1 or 1
        if index then index=(index-1+step)%#context.items+1
        else index=step==1 and 1 or #context.items end
        self:select(context.items[index])
        return true
    end
    local target
    if self.selected then
        target = Navigation.neighbor(context.items, self.selected, direction)
    else
        target = firstItem(context.items)
    end
    self:select(target)
    return target ~= nil
end

function Navigation:tab(direction, secondary)
    local context = self:context()
    if not context or context.dialog or context.confirmation then return false end
    if context.map then
        if secondary then return false end
        self:clear();return self.adapter:zoomMap(context,direction)
    end
    local tabs = context.tabs
    if secondary then tabs = context.secondaryTabs end
    if not tabs or #tabs < 2 then return false end
    local current = 1
    for index, item in ipairs(tabs) do if item.active then current=index; break end end
    local target = tabs[(current-1+direction) % #tabs + 1]
    self:clear()
    self.adapter:activateTab(target)
    return true
end

function Navigation:confirm()
    local context = self:context()
    if context and context.map then self:clear();return false end
    if not context or #context.items == 0 then return false end
    if context.confirmation then
        if context.confirmKey=="F" then return false end
        -- Small dialogs reserve Escape for the game's cancel action and Space
        -- for the affirmative action, even if A/D last highlighted Cancel.
        local item = context.confirm
        if not item then return false end
        self:clear()
        self.adapter:activate(item)
        return true
    end
    if not self.selected then
        local first = firstItem(context.items)
        self:select(first)
        return false -- Multi-choice popups still require an explicit selection.
    end
    local item = self.selected
    if item.fixedKey=="F" then return false end
    self:clear()
    self.adapter:activate(item)
    if context.form then
        -- Native selection can open a new popup or recycle the current one.
        -- Re-read before selecting anything; never confirm two actions at once.
        local current=self:context()
        if current and current.scope==context.scope and current.form then
            local target=current.formAdvance and item.id~=current.formAdvance.id and current.formAdvance
            if not target then
                for _,candidate in ipairs(current.items) do
                    if candidate.id==item.id then target=candidate;break end
                end
            end
            self:select(target)
        end
    end
    return true
end

function Navigation:interact()
    local context=self:context()
    if not context then return false end
    if context.map then self:clear();return self.adapter:warpMap(context) end
    if context.entryAction then self:clear();return self.adapter:enterDungeon(context) end
    return false
end

return Navigation

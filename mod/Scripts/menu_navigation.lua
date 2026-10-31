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
    self.enabled = not self.enabled
    return self.enabled
end

function Navigation:context()
    if not self.enabled then return nil end
    local context = self.adapter:snapshot()
    if not context or context.blocked then self:clear(); return nil end
    if self.scope ~= context.scope then self:clear() end
    local found
    for _, item in ipairs(context.items) do
        if self.selected and item.id == self.selected.id then found = item; break end
    end
    if self.selected and not found then self:clear() end
    self.scope = context.scope
    if found then self.selected = found end
    return context
end

function Navigation:select(item)
    if not item then return end
    if self.selected and self.selected.id == item.id then return end
    if self.selected then self.adapter:highlight(self.selected, false) end
    self.selected = item
    self.adapter:highlight(item, true)
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
    if not context or #context.items == 0 then return false end
    local target
    if self.selected then
        target = Navigation.neighbor(context.items, self.selected, direction)
    else
        target = firstItem(context.items)
    end
    self:select(target)
    return target ~= nil
end

function Navigation:tab(direction)
    local context = self:context()
    if not context or not context.tabs or #context.tabs < 2 then return false end
    local current = 1
    for index, item in ipairs(context.tabs) do if item.active then current=index; break end end
    local target = context.tabs[(current-1+direction) % #context.tabs + 1]
    self:clear()
    self.adapter:activateTab(target)
    return true
end

function Navigation:confirm()
    local context = self:context()
    if not context or #context.items == 0 then return false end
    if not self.selected then
        self:select(firstItem(context.items))
        return false -- A newly opened menu never receives an inherited confirmation.
    end
    local item = self.selected
    self:clear()
    self.adapter:activate(item)
    return true
end

return Navigation

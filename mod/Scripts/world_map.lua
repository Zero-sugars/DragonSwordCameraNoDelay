local Map = {}
Map.__index = Map

function Map.new(api) return setmetatable({ api=api },Map) end

function Map:context(panel)
    local api=self.api
    local state={panel=panel,layer=api.read(panel,'LayerMap'),
        minus=api.read(panel,'BtnMinus'),plus=api.read(panel,'BtnPlus')}
    local info=api.read(panel,'InfoPopup')
    if api.displayed(info) then
        for _,name in ipairs({'BtnInfoPopupActionSingle','BtnInfoPopupActionDouble01','BtnInfoPopupActionDouble02'})do
            local wrapper=api.read(info,name)
            if api.displayed(wrapper) then
                local warp,button=false,nil
                api.walk(wrapper,function(widget)
                    if api.isA(widget,'Button') then button=button or widget end
                    if api.isA(widget,'TextBlock') or api.isA(widget,'RichTextBlock') then
                        local ok,text=pcall(function()return widget:GetText():ToString()end)
                        if ok then
                            text=text:gsub('<[^>]+>',''):gsub('%s',''):lower()
                            if text=='워프' or text=='근처로워프' or text=='warp' or text=='fasttravel' or text=='teleport' then warp=true end
                        end
                    end
                end)
                if warp and button and api.displayed(button) then state.warp=button;break end
            end
        end
    end
    return state
end

function Map:preparePan(state)
    local api=self.api
    if not api.displayed(state.panel) or not api.valid(state.layer) then return false end
    local inside=api.read(state.layer,'MapOverlaySlot')
    local outside=api.read(state.layer,'MapOverlayOutSideSlot')
    if not api.valid(inside) or not api.valid(outside) then return false end
    -- Stretched Canvas slots report design-time offsets (e.g. 100x30), not
    -- the map's rendered dimensions. Cached geometry tracks the actual zoom.
    local overlay=api.read(state.layer,'MapOverlay')
    local drawn=api.geometry(overlay)
    if not drawn then return false end
    local parent=api.parent and api.parent(overlay)
    local bounds=api.geometry(api.valid(parent) and parent or state.panel)
    local width=bounds and (bounds.localW or bounds.w)or 1920
    local height=bounds and (bounds.localH or bounds.h)or 1080
    local scaleX=bounds and bounds.w/width or 1
    local scaleY=bounds and bounds.h/height or 1
    local size={X=drawn.w/scaleX,Y=drawn.h/scaleY}
    state.panBounds={inside=inside,outside=outside,width=width,height=height,size=size}
    return true
end

function Map:panVector(state,x,y)
    if x==0 and y==0 then return false end
    if not state.panBounds and not self:preparePan(state) then return false end
    local b=state.panBounds
    if not self.api.valid(state.panel) or not self.api.valid(b.inside) or not self.api.valid(b.outside) then return false end
    local p=b.inside:GetPosition()
    local nextX=b.size.X<=b.width and p.X or math.max(b.width-b.size.X,math.min(0,p.X+x))
    local nextY=b.size.Y<=b.height and p.Y or math.max(b.height-b.size.Y,math.min(0,p.Y+y))
    local dx,dy=nextX-p.X,nextY-p.Y
    if dx==0 and dy==0 then return true end
    local other=b.outside:GetPosition()
    b.inside:SetPosition({X=nextX,Y=nextY})
    b.outside:SetPosition({X=other.X+dx,Y=other.Y+dy})
    return true
end

function Map:pan(state,direction,step)
    if not self.api.displayed(state.panel) then return false end
    step=step or 96
    if direction=='up' then return self:panVector(state,0,step)
    elseif direction=='down' then return self:panVector(state,0,-step)
    elseif direction=='left' then return self:panVector(state,step,0)
    elseif direction=='right' then return self:panVector(state,-step,0) end
    return false
end

function Map:motion(state,x,y,seconds)
    local length=math.sqrt(x*x+y*y)
    if length==0 or seconds<=0 then return false end
    -- Distance follows real elapsed time, with equal diagonal speed. Cap stalls
    -- so returning from a hitch never flings the map across the screen.
    local distance=1400*math.min(seconds,0.05)
    return self:panVector(state,x/length*distance,y/length*distance)
end

function Map:zoom(state,direction)
    local button=direction<0 and state.minus or state.plus
    if not self.api.displayed(state.panel) or not self.api.displayed(button)then return false end
    self.api.activate(button)
    state.panBounds=nil
    return true
end

function Map:warp(state)
    if not self.api.displayed(state.panel)then return false end
    -- Re-read the active info action; a reused button may now mean something else.
    local current=self:context(state.panel)
    if not current.warp or not self.api.displayed(current.warp)then return false end
    self.api.activate(current.warp)
    return true
end

function Map:hints(state)
    local hints={}
    for _,pair in ipairs({{state.minus,'Q'},{state.plus,'E'},{state.warp,'F'}})do
        if self.api.displayed(pair[1])then hints[#hints+1]={widget=pair[1],key=pair[2]}end
    end
    return hints
end

return Map

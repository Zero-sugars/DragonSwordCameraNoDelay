local Hints={}
Hints.__index=Hints

function Hints.new(api)return setmetatable({api=api,labels={}},Hints)end

function Hints:clear()
    for _,entry in pairs(self.labels)do self.api.remove(entry.label)end
    self.labels={};self.scope=nil
end

function Hints:update(context)
    if not context then self:clear();return end
    if self.scope~=context.scope then self:clear();self.scope=context.scope end
    local wanted={}
    for _,binding in ipairs(context.hints or{})do
        if self.api.displayed(binding.widget)then
            local id=binding.id or tostring(binding.widget:GetAddress())..':'..binding.key
            local entry=self.labels[id]
            if not entry or not self.api.valid(entry.label)then
                local label=self.api.create(context,binding.widget,binding.key)
                if self.api.valid(label)then entry={label=label};self.labels[id]=entry end
            end
            if entry then self.api.place(context,entry.label,binding.widget,binding.key);wanted[id]=true end
        end
    end
    for id,entry in pairs(self.labels)do
        if not wanted[id]then self.api.remove(entry.label);self.labels[id]=nil end
    end
end

return Hints

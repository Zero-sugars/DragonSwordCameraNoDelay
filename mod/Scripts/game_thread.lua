-- Key callbacks run on the input thread. Queue plain Lua values there and keep
-- native callback registrations fixed instead of creating a registry ref per key.
local Thread = {}
Thread.__index = Thread

function Thread.new(log)
    local self = setmetatable({ queue = {}, log = log, lastError = nil }, Thread)
    LoopInGameThreadWithDelay(16, function()
        local batch = self.queue
        self.queue = {}
        for _, callback in ipairs(batch) do self:run(callback) end
    end)
    return self
end

function Thread:run(callback)
    local ok, err = pcall(callback)
    if not ok and tostring(err) ~= self.lastError then
        self.lastError = tostring(err)
        self.log("ERROR " .. self.lastError)
    end
end

function Thread:bind(key, callback)
    RegisterKeyBind(key, function()
        if #self.queue < 64 then self.queue[#self.queue + 1] = callback end
    end)
end

function Thread:loop(delay, callback)
    LoopInGameThreadWithDelay(delay, function() self:run(callback) end)
end

function Thread:frames(count, callback)
    local run=function() self:run(callback) end
    if type(LoopInGameThreadAfterFrames)=="function" then
        local ok=pcall(LoopInGameThreadAfterFrames,count,run)
        if ok then return "frames" end
    end
    -- Older loaders without EngineTick frame callbacks still get short updates.
    LoopInGameThreadWithDelay(8,run)
    return "8ms"
end

return Thread

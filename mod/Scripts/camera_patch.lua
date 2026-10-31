-- UE4SS supplies reflected UObjects; no hard-coded memory offsets are used.
local Patch = {}
Patch.__index = Patch

function Patch.new()
    return setmetatable({ entries = {} }, Patch)
end

local desired = { bEnableCameraRotationLag = false, CameraRotationLagSpeed = 0.0 }

local function valid(object)
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function identity(object)
    if not valid(object) then return nil end
    local ok, result = pcall(function() return object:GetFullName() end)
    return ok and result or nil
end

function Patch:apply(object)
    local name = identity(object)
    if not name then return false, "invalid object" end
    local ok, flag, speed = pcall(function()
        return object.bEnableCameraRotationLag, object.CameraRotationLagSpeed
    end)
    if not ok or type(flag) ~= "boolean" or type(speed) ~= "number" then
        return false, "rotation lag properties unavailable"
    end
    local entry = self.entries[name]
    if not entry then
        entry = { object = object, original = {
            bEnableCameraRotationLag = flag, CameraRotationLagSpeed = speed,
        } }
        self.entries[name] = entry
    end
    local changed = false
    for key, value in pairs(desired) do
        if object[key] ~= value then
            object[key] = value
            changed = true
        end
    end
    if object.bEnableCameraRotationLag ~= false or object.CameraRotationLagSpeed ~= 0 then
        return false, "rotation lag write verification failed"
    end
    return true, changed
end

function Patch:restore()
    local restored = 0
    for name, entry in pairs(self.entries) do
        if identity(entry.object) == name then
            local ok = pcall(function()
                for key, value in pairs(desired) do
                    -- Do not overwrite a newer value supplied by the game.
                    if entry.object[key] == value then entry.object[key] = entry.original[key] end
                end
            end)
            if ok then restored = restored + 1 end
        end
    end
    self.entries = {}
    return restored
end

function Patch:prune()
    for name, entry in pairs(self.entries) do
        if identity(entry.object) ~= name then self.entries[name] = nil end
    end
end

return Patch

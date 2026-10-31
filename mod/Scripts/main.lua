local components = require("components")
local patch = components.camera and require("camera_patch").new() or nil
local enabled = components.camera
local controller = nil
local announced = {}
local lastError = nil
local menu = nil

local function log(message)
    print("[DragonSwordCameraNoDelay] " .. message .. "\n")
end

local function valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return ok and result == true
end

local function read(object, key)
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function findController()
    if valid(controller) then return controller end
    for _, candidate in ipairs(FindAllOf("DsCameraControllerComponent") or {}) do
        local ok, isLocal = pcall(function() return candidate:GetOwner():IsLocalController() end)
        if ok and isLocal then controller = candidate; return controller end
    end
    return nil
end

local function cameras()
    local result = {}
    if not components.camera then return result end
    local seen = {}
    local currentController = findController()
    if not currentController then return result end
    for _, key in ipairs({ "PCPlayerCharacter", "CurrentCharacter" }) do
        local character = read(currentController, key)
        if valid(character) then
            for _, field in ipairs({ "SpringArmComponent", "VehicleSpringArmComponent" }) do
                local arm = read(character, field)
                if valid(arm) then
                    local name = arm:GetFullName()
                    if not seen[name] then result[#result + 1] = arm; seen[name] = true end
                end
            end
        end
    end
    return result
end

local function update()
    patch:prune()
    if not enabled then return end
    for _, arm in ipairs(cameras()) do
        local name = arm:GetFullName()
        local beforeFlag = arm.bEnableCameraRotationLag
        local beforeSpeed = arm.CameraRotationLagSpeed
        local ok, changed = patch:apply(arm)
        if not ok then error(changed) end
        if not announced[name] then
            log(string.format("ACTIVE %s | rotation lag %s -> false, speed %s -> 0", name, tostring(beforeFlag), tostring(beforeSpeed)))
            announced[name] = true
        end
    end
end

local function run(callback)
    local ok, err = pcall(callback)
    if not ok and tostring(err) ~= lastError then
        lastError = tostring(err)
        log("ERROR " .. lastError)
    end
end

local thread = require("game_thread").new(log)

if components.camera then thread:bind(Key.F8, function()
        run(function()
            enabled = not enabled
            if enabled then
                announced = {}
                update()
                log("ON - instant camera rotation")
            else
                log(string.format("OFF - restored %d camera(s)", patch:restore()))
            end
        end)
end) end

thread:bind(Key.F9, function()
        run(function()
            local arms = cameras()
            log(string.format("STATUS enabled=%s localCameras=%d", tostring(enabled), #arms))
            if menu then
                log("STATUS menuKeyboard=" .. tostring(menu.navigation.enabled))
                if menu.reportStatus then menu.reportStatus() end
            end
            for _, arm in ipairs(arms) do
                log(string.format("STATUS %s | rotationLag=%s rotationSpeed=%s locationLag=%s collision=%s",
                    arm:GetFullName(), tostring(arm.bEnableCameraRotationLag), tostring(arm.CameraRotationLagSpeed),
                    tostring(arm.bEnableCameraLag), tostring(arm.bDoCollisionTest)))
            end
        end)
end)

if components.camera then thread:loop(100, function() run(update) end) end

if components.menu then menu = require("menu_keyboard").start(log, { thread=thread }) end
log("v0.4.0 loaded - F7 menu, F8 camera, F9 status; waiting for the local player camera")

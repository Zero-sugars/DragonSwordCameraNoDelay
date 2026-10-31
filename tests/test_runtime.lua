package.path = 'mod/Scripts/?.lua;' .. package.path
local callbacks, keys, logs = {}, {}, {}
local function obj(name)
    return { alive=true, IsValid=function(self) return self.alive end, GetFullName=function() return name end }
end
local function arm(name)
    local value=obj(name)
    value.bEnableCameraRotationLag=true; value.CameraRotationLagSpeed=10
    value.bEnableCameraLag=true; value.bDoCollisionTest=true
    return value
end
local remoteArm, localArm, swapArm = arm('remote'), arm('local'), arm('swap')
local function ctrl(localPlayer, camera)
    local owner={IsLocalController=function() return localPlayer end}
    local value=obj('controller')
    value.PCPlayerCharacter=obj('character')
    value.PCPlayerCharacter.SpringArmComponent=camera
    value.CurrentCharacter=value.PCPlayerCharacter
    value.GetOwner=function() return owner end
    return value
end
local remote, localController=ctrl(false,remoteArm), ctrl(true,localArm)
local list={remote}
Key={F8=119,F9=120}
RegisterKeyBind=function(key,callback) keys[key]=callback end
ExecuteInGameThread=function(callback) callback() end
LoopAsync=function(_,callback) callbacks[#callbacks+1]=callback end
FindAllOf=function(name) assert(name=='DsCameraControllerComponent'); return list end
print=function(message) logs[#logs+1]=message end
package.loaded.menu_keyboard={start=function()return {navigation={enabled=true}}end}
dofile('mod/Scripts/main.lua')
local tick=callbacks[1]
tick()
assert(remoteArm.bEnableCameraRotationLag==true)
list={remote,localController}
tick()
assert(localArm.bEnableCameraRotationLag==false and localArm.CameraRotationLagSpeed==0)
assert(remoteArm.bEnableCameraRotationLag==true)
keys[Key.F8]()
assert(localArm.bEnableCameraRotationLag==true and localArm.CameraRotationLagSpeed==10)
tick()
assert(localArm.bEnableCameraRotationLag==true)
keys[Key.F8]()
assert(localArm.bEnableCameraRotationLag==false)
localController.CurrentCharacter=obj('newCharacter')
localController.CurrentCharacter.SpringArmComponent=swapArm
tick()
assert(swapArm.bEnableCameraRotationLag==false)
keys[Key.F9]()
keys[Key.F8]()
assert(localArm.bEnableCameraRotationLag==true and swapArm.bEnableCameraRotationLag==true)
assert(localArm.bEnableCameraLag==true and localArm.bDoCollisionTest==true)
for _,message in ipairs(logs) do assert(not message:find('ERROR')) end
return 'runtime: local-only scope, F8 restore, character switch, F9 PASS'

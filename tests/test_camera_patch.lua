local Patch = dofile("mod/Scripts/camera_patch.lua")
local function camera(name)
    return {
        name=name, alive=true,
        bEnableCameraRotationLag=true, CameraRotationLagSpeed=8.5,
        bEnableCameraLag=true, CameraLagSpeed=7, bDoCollisionTest=true,
        CameraRotationLagMaxSpeed=360,
        IsValid=function(self) return self.alive end,
        GetFullName=function(self) return self.name end,
    }
end

local patch=Patch.new()
local first=camera("Camera1")
assert(patch:apply(first))
assert(first.bEnableCameraRotationLag==false and first.CameraRotationLagSpeed==0)
assert(first.bEnableCameraLag==true and first.CameraLagSpeed==7)
assert(first.bDoCollisionTest==true and first.CameraRotationLagMaxSpeed==360)
assert(patch:apply(first))
assert(patch:restore()==1)
assert(first.bEnableCameraRotationLag==true and first.CameraRotationLagSpeed==8.5)

assert(patch:apply(first))
first.CameraRotationLagSpeed=17 -- game changed it after our last write
patch:restore()
assert(first.CameraRotationLagSpeed==17)

local gone=camera("Gone")
assert(patch:apply(gone))
gone.alive=false
assert(patch:restore()==0)

local incomplete=camera("Incomplete")
incomplete.CameraRotationLagSpeed=nil
assert(not patch:apply(incomplete))
assert(incomplete.bEnableCameraRotationLag==true)

local reused=camera("Reused")
assert(patch:apply(reused))
reused.name="DifferentObject"
assert(patch:restore()==0)
assert(reused.bEnableCameraRotationLag==false)

local replaced=camera("Replaced")
assert(patch:apply(replaced))
replaced.alive=false
patch:prune()
assert(next(patch.entries)==nil)
print("camera_patch: apply, restore, external changes, invalidation, property checks PASS")

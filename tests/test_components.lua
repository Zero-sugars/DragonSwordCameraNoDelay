package.path='mod/Scripts/?.lua;'..package.path
for _,mode in ipairs({'camera','menu'}) do
    local keys,loops={},{}
    package.loaded.components={camera=mode=='camera',menu=mode=='menu'}
    package.loaded.game_thread=nil
    package.loaded.camera_patch=mode=='camera' and {new=function()return {prune=function()end}end} or nil
    package.preload.camera_patch=mode=='menu' and function()error('Menu-only must not load camera module')end or nil
    package.loaded.menu_keyboard=mode=='menu' and {start=function()return {navigation={enabled=true}}end} or nil
    package.preload.menu_keyboard=mode=='camera' and function()error('Camera-only must not load menu module')end or nil
    Key={F8=8,F9=9}
    RegisterKeyBind=function(key,callback)keys[key]=callback end
    LoopInGameThreadWithDelay=function(delay,callback)loops[delay]=callback end
    FindAllOf=function(name)assert(mode=='camera' and name=='DsCameraControllerComponent');return {}end
    print=function()end
    dofile('mod/Scripts/main.lua')
    assert(keys[Key.F9] and loops[16])
    assert((keys[Key.F8]~=nil)==(mode=='camera') and (loops[100]~=nil)==(mode=='camera'))
    keys[Key.F9]();loops[16]()
    if loops[100]then loops[100]()end
end
return 'components: camera-only/menu-only exclude uninstalled module loading, F8 binding and camera scanning PASS'

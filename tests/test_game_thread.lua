package.path='mod/Scripts/?.lua;'..package.path
local keys,loops,logs={},{},{}
local registrations,inInput=0,false
LoopInGameThreadWithDelay=function(delay,cb)
    assert(not inInput,'Native callback registration on input thread')
    registrations=registrations+1;loops[delay]=cb
end
RegisterKeyBind=function(key,cb)keys[key]=cb end
local thread=require('game_thread').new(function(s)logs[#logs+1]=s end)
local count,updates=0,0
thread:bind(1,function()count=count+1 end)
thread:loop(100,function()updates=updates+1 end)
for _=1,1000 do
    inInput=true
    for _=1,30 do keys[1]() end
    inInput=false
    loops[100]();loops[16]()
end
assert(count==30000 and updates==1000 and registrations==2)
for _=1,1000 do keys[1]() end
loops[16]();assert(count==30064,'Backlog must stay bounded')
thread:bind(2,function()error('expected failure')end)
keys[2]();keys[1]();loops[16]()
assert(count==30065 and #logs==1,'A failed command must not stop the queue')
local frameCallback,frames= nil,0
LoopInGameThreadAfterFrames=function(delay,cb)
 assert(not inInput and delay==1);registrations=registrations+1;frameCallback=cb
end
assert(thread:frames(1,function()frames=frames+1 end)=='frames')
for _=1,1000 do frameCallback()end
assert(frames==1000 and registrations==3,'Frame updates use one fixed native registration')
LoopInGameThreadAfterFrames=function()error('EngineTick unavailable')end
assert(thread:frames(1,function()frames=frames+1 end)=='8ms')
loops[8]();assert(frames==1001 and registrations==4,'Unsupported loaders use one bounded fallback loop')
return 'game thread: 30,000 queued keys, bounded backlog, fixed native registrations, error isolation PASS'

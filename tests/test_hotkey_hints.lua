package.path='mod/Scripts/?.lua;'..package.path
local Hints=require('hotkey_hints')
local created,removed,placed=0,0,0
local function object(id)return {id=id,alive=true,shown=true,GetAddress=function(self)return self.id end}end
local a,b=object('a'),object('b')
local h=Hints.new({valid=function(w)return w and w.alive end,displayed=function(w)return w and w.shown end,
 create=function(_,button,key)created=created+1;return object(button.id..key)end,
 place=function()placed=placed+1 end,remove=function(label)label.alive=false;removed=removed+1 end})
local c={scope='map',hints={{widget=a,key='Q'},{widget=b,key='F'}}}
h:update(c);assert(created==2 and removed==0)
for _=1,1000 do h:update(c)end
assert(created==2,'Refreshing hint positions must not create more UObjects')
b.shown=false;h:update(c);assert(removed==1)
c={scope='popup',hints={{widget=a,key='Space'}}};h:update(c)
assert(created==3 and removed==2)
h:clear();assert(removed==3 and next(h.labels)==nil)
h:update(nil);assert(removed==3)
local positions={}
h.api.place=function(_,label,button,key)positions[key]={label=label,button=button}end
c={scope='tabs',hints={{id='primary',widget=a,key='Q/E'},{id='secondary',widget=a,key='1/3'}}}
h:update(c)
local primary,secondary=positions['Q/E'].label,positions['1/3'].label
b.shown=true
for index=1,1000 do
    c.hints[2].widget=index%2==0 and a or b
    h:update(c)
end
assert(created==5 and positions['Q/E'].label==primary and positions['1/3'].label==secondary,
    'Tab switching must reposition existing labels instead of creating UObjects per key press')
c.hints[2]=nil;h:update(c);assert(removed==4,'Hidden secondary group loses its hint')
h:clear();assert(removed==5)
return 'hotkey hints: 1000 refreshes and tab switches reuse labels, hidden/scope/OFF cleanup PASS'

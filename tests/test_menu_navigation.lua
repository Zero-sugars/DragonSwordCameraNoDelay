package.path = 'mod/Scripts/?.lua;' .. package.path
local Navigation = require('menu_navigation')
local function item(id,x,y) return { id=id,x=x,y=y,w=80,h=40 } end
local a,b,c,d = item('a',0,0),item('b',100,0),item('c',0,60),item('d',100,60)
local context = { scope='menu', items={a,b,c,d} }
local highlights, activations = {}, {}
local adapter = {
    snapshot=function() return context end,
    highlight=function(_,value,on) highlights[value.id]=on end,
    activate=function(_,value) activations[#activations+1]=value.id end,
    activateTab=function(_,value)
        for _,tab in ipairs(context.tabs) do tab.active=(tab==value) end
    end,
}
local n=Navigation.new(adapter)
assert(n:move('down') and n.selected==a)
assert(n:move('right') and n.selected==b and highlights.a==false and highlights.b==true)
assert(n:move('down') and n.selected==d)
assert(n:move('left') and n.selected==c)
assert(n:move('up') and n.selected==a)
assert(not n:move('up') and n.selected==a)
assert(n:confirm() and activations[1]=='a' and n.selected==nil)
assert(not n:confirm() and n.selected==a and #activations==1)
-- A popup cannot inherit the old menu's selected button or a pending confirmation.
context={scope='popup',items={b,d}}
assert(not n:confirm() and n.selected==b and #activations==1)
assert(n:confirm() and activations[2]=='b')
n:move('down')
context={scope='popup',items={d}}
assert(not n:confirm() and n.selected==d and #activations==2)
-- Focused text and gameplay return no eligible context.
context={scope='popup',items={d},blocked=true}
assert(not n:confirm() and n.selected==nil and highlights.d==false)
context=nil
assert(not n:move('down'))
context={scope='menu',items={a,b}}
n:move('right')
assert(n:toggle()==false and n.selected==nil and highlights.a==false)
assert(not n:move('right') and not n:confirm() and #activations==2)
assert(n:toggle()==true)
-- Prefer an aligned button over a nearby diagonal button in another row.
local diagonal=item('diagonal',85,45)
assert(Navigation.neighbor({a,b,diagonal},a,'right')==b)
local t1,t2,t3 = {active=true},{},{}
context={scope='tabs',items={},tabs={t1,t2,t3}}
assert(n:tab(1) and t2.active)
assert(n:tab(-1) and t1.active)
assert(n:tab(-1) and t3.active)
assert(n:tab(1) and t1.active)
n:toggle()
assert(not n:tab(1) and t1.active)
n:toggle()
local close=item('close',300,0); close.preferInitial=false
context={scope='menu',items={close,a,b}}
assert(n:move('down') and n.selected==a)
return 'menu: spatial selection, popup isolation, text/gameplay exclusion, toggle, Q/E wrap PASS'

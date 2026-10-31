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
    enterDungeon=function(_,value)activations[#activations+1]=value.entryAction.id;return true end,
    activateTab=function(_,value)
        for _,tabs in ipairs({context.tabs or {},context.secondaryTabs or {}}) do
            for _,tab in ipairs(tabs) do
                if tab==value then
                    for _,other in ipairs(tabs) do other.active=(other==value) end
                    return
                end
            end
        end
        error('Only the first two groups may be activated')
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
assert(not n:tab(1,true) and t1.active,'Missing secondary tabs must not fall back to primary tabs')
local s1,s2,s3={active=true},{},{}
context.secondaryTabs={s1,s2,s3}
context.tertiaryTabs={{active=true},{}}
assert(n:tab(1,true) and s2.active and t1.active)
assert(n:tab(-1,true) and s1.active and t1.active)
assert(n:tab(-1,true) and s3.active and t1.active)
assert(n:tab(1,true) and s1.active)
n:toggle()
assert(not n:tab(1) and t1.active)
assert(not n:tab(1,true) and s1.active)
n:toggle()
context.secondaryTabs={s1}
assert(not n:tab(1,true),'One secondary tab has no next tab')
context=nil
assert(not n:tab(1,true),'Gameplay cannot switch secondary tabs')
context={scope='text',blocked=true,items={},tabs={t1,t2},secondaryTabs={s1,s2}}
assert(not n:tab(1,true) and s1.active,'Focused text blocks number shortcuts')
local close=item('close',300,0); close.preferInitial=false
context={scope='menu',items={close,a,b}}
assert(n:move('down') and n.selected==a)
-- Generic confirmation popups support immediate acknowledgement with one button.
local ok=item('ok',100,0);ok.kind='button'
local cancel=item('cancel',0,0);cancel.kind='button'
context={scope='single-confirm',popup=true,confirmation=true,confirm=ok,items={ok}}
local before=#activations
assert(n:confirm() and activations[#activations]=='ok' and #activations==before+1)
context={scope='two-buttons',popup=true,confirmation=true,confirm=ok,items={cancel,ok}}
context.tabs={t1,t2};context.secondaryTabs={s1,s2}
assert(not n:tab(1) and not n:tab(1,true),'Confirmation popups cannot forward tab keys')
assert(not n:move('right') and n.selected==nil,'Small dialogs no longer use A/D selection')
assert(not n:move('left') and n.selected==nil)
assert(n:confirm() and activations[#activations]=='ok')
local other=item('third',200,0);other.kind='button'
context={scope='three-buttons',popup=true,dialog=true,confirmation=false,items={cancel,ok,other}}
before=#activations
assert(not n:confirm() and n.selected==cancel and #activations==before)
assert(n:move('right') and n.selected==ok)
assert(n:move('right') and n.selected==other)
assert(n:move('right') and n.selected==cancel)
assert(n:move('left') and n.selected==other)
assert(not n:move('up') and not n:move('down') and n.selected==other)
assert(n:confirm() and activations[#activations]=='third')
context={scope='two-buttons',popup=true,dialog=true,confirmation=true,items={cancel,ok}}
context.confirm=nil;before=#activations
assert(not n:confirm() and #activations==before,'Never substitute a cancel button for missing confirmation')
n:toggle();before=#activations
context={scope='single-confirm',popup=true,confirmation=true,confirm=ok,items={ok}}
assert(not n:confirm() and #activations==before,'F7 OFF must block immediate popup confirmation')
n:toggle()
context={scope='dungeon',items={ok},entryAction=ok}
before=#activations
assert(n:interact() and #activations==before+1 and activations[#activations]=='ok')
n:toggle();assert(not n:interact() and #activations==before+1);n:toggle()
context={scope='popup',items={ok},popup=true,confirmation=true,confirm=ok}
assert(not n:interact(),'F cannot execute confirmation popups')
context={scope='text',items={ok},entryAction=ok,blocked=true}
assert(not n:interact(),'Focused text blocks the challenge shortcut')
context=nil;assert(not n:interact(),'Normal gameplay cannot use the challenge shortcut')
context={scope='dungeon-exit',items={ok,cancel},confirmation=true,confirm=ok,confirmKey='F',entryAction=ok}
before=#activations
assert(not n:confirm() and #activations==before,'Dungeon exit cannot be approved using Space')
assert(n:interact() and #activations==before+1 and activations[#activations]=='ok','Dungeon exit approval uses F')
context={scope='exit-menu',items={ok},entryAction=ok};ok.fixedKey='F'
n:move('down');before=#activations
assert(not n:confirm() and #activations==before,'F-only exit button is not executed by Space after selection')
assert(n:interact() and #activations==before+1);ok.fixedKey=nil
return 'menu: 1/2-button immediate Space, 3-button A/D wrap and Space selection, unknown-confirm isolation, F7/text/gameplay gates, Q/E/1/3 PASS'

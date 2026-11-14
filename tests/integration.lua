local A={}; local now=100; local calls=0; local timers={}; local created={}
local base=os.getenv("CLEARLOOT_ADDON") or "ClearLoot"
local nativeSchema=assert(loadfile("tests/fixtures/forever_loot_template.lua"))()
local frameMethods={}
function frameMethods:SetScript(k,v) self.scripts[k]=v end
function frameMethods:GetScript(k) return self.scripts[k] end
function frameMethods:HookScript(k,v)
    local old=self.hooks[k]
    self.hooks[k]=function(...) if old then old(...) end; v(...) end
end
function frameMethods:GetChildren() return (table.unpack or unpack)(self.children) end
function frameMethods:CreateFontString() return setmetatable({children={},scripts={},hooks={}}, {__index=frameMethods}) end
frameMethods.CreateTexture=frameMethods.CreateFontString
function frameMethods:SetSize(w,h) self.width=w; self.height=h end
function frameMethods:SetWidth(w) self.width=w end
function frameMethods:SetHeight(h) self.height=h end
function frameMethods:GetWidth() return self.width or 300 end
function frameMethods:GetHeight() return self.height or 80 end
function frameMethods:SetText(s) self.text=s end
function frameMethods:GetText() return self.text end
function frameMethods:SetShown(v) self.shown=not not v end
function frameMethods:Show() self.shown=true end
function frameMethods:Hide() self.shown=false end
function frameMethods:IsShown() return self.shown end
function frameMethods:IsMouseOver() return false end
function frameMethods:IsMouseEnabled() return self.mouse~=false end
function frameMethods:EnableMouse(v) self.mouse=v end
function frameMethods:GetAlpha() return self.alpha or 1 end
function frameMethods:SetAlpha(v) self.alpha=v end
function frameMethods:GetFrameLevel() return 1 end
function frameMethods:GetCenter() return self.centerX or 500,self.centerY or 400 end
function frameMethods:GetEffectiveScale() return 1 end
function frameMethods:SetChecked(v) self.checked=v end
function frameMethods:GetChecked() return self.checked end
function frameMethods:SetEnabled(v) self.enabled=v end
function frameMethods:SetPoint(...) self.point={...} end
local harmless={"SetFont","SetJustifyH","SetJustifyV","SetBackdrop","SetBackdropColor","SetBackdropBorderColor",
    "SetAllPoints","SetTexture","SetStatusBarTexture","SetStatusBarColor","SetMinMaxValues","SetValue",
    "SetFrameLevel","SetMovable","SetClampedToScreen","RegisterForDrag","StartMoving","StopMovingOrSizing","SetFrameStrata",
    "SetScrollChild","SetScale","ClearAllPoints","SetTextColor","SetAutoFocus","SetMaxLetters","ClearFocus",
    "RegisterEvent","UnregisterAllEvents","SetColorTexture","SetMultiLine","HighlightText","SetFocus"}
for _,name in ipairs(harmless) do frameMethods[name]=function() end end
function frameMethods:SetValue(v) self.value=v end
function frameMethods:SetMinMaxValues(a,b) self.minimum=a; self.maximum=b end
function frameMethods:SetStatusBarColor(r,g,b) self.color={r,g,b} end
function CreateFrame(kind,name,parent,template)
    local f=setmetatable({children={},scripts={},hooks={},shown=true},{__index=frameMethods})
    f.template=template; f.frameName=name
    if template=="ClearLootDemoLootFrameTemplate" then
        local xml=assert(io.open(base.."/Demo.xml")):read("*a")
        assert(xml:find('inherits="'..nativeSchema.template..'"',1,true))
        assert(xml:find("<OnLoad>self.clearLootDemo = true;</OnLoad>",1,true))
        for _,script in ipairs({"OnShow","OnHide","OnEvent","OnUpdate"}) do
            assert(xml:find("<"..script..">return;</"..script..">",1,true))
            f.scripts[script]=function() error("inherited live loot script must not run") end
        end
        f:SetSize(nativeSchema.width,nativeSchema.height)
        f.Name=f:CreateFontString(); f.Timer=CreateFrame("StatusBar",nil,f)
        f.IconFrame=CreateFrame("Button",nil,f); f.IconFrame.Icon=f:CreateTexture()
        f.IconFrame.Count=f:CreateFontString()
        f.IconFrame:SetScript("OnClick",function() error("real icon click") end)
        f.IconFrame:SetScript("OnUpdate",function() error("real icon update") end)
        f[nativeSchema.buttonParent]=CreateFrame("Frame",nil,f)
        for key in pairs(nativeSchema.buttons) do
            f[nativeSchema.buttonParent][key]=CreateFrame("Button",nil,f[nativeSchema.buttonParent])
            f[nativeSchema.buttonParent][key]:SetScript("OnClick",function() RollOnLoot(999,1) end)
        end
        f.NeedRollAnim=CreateFrame("Frame",nil,f)
    end
    if parent then table.insert(parent.children,f) end
    created[#created+1]=f; return f
end
local registered,opened
Settings={RegisterCanvasLayoutCategory=function(panel,name)
    registered={panel=panel,name=name,GetID=function() return 42 end}; return registered
end,RegisterAddOnCategory=function(category) assert(category==registered) end,
OpenToCategory=function(id) opened=id end}
GroupLootContainer=CreateFrame("Frame"); GroupLootContainer.reservedSize=100
local nativeLayouts=0
function GroupLootContainer_Update(c)
    nativeLayouts=nativeLayouts+1
    if c.rollFrames then
        for i=1,c.maxIndex do
            local f=c.rollFrames[i]
            if f then f:ClearAllPoints(); f:SetPoint("CENTER",c,"BOTTOM",0,c.reservedSize*(i-0.5)) end
        end
        c:SetHeight(c.reservedSize*c.maxIndex); c:SetShown(c.maxIndex>0)
        if c.maxIndex>0 then c.layoutParent:Layout() end
    end
end
local nativeAdds=0
function GroupLootContainer_AddFrame(c,f)
    assert(c~=GroupLootContainer,"demo must not enter the real loot container")
    nativeAdds=nativeAdds+1; c.maxIndex=c.maxIndex+1; c.rollFrames[c.maxIndex]=f
    GroupLootContainer_Update(c); f:Show()
end
-- Optional verification against downloaded, pinned Blizzard Forever Lua source.
-- The regular suite is self contained; this path exercises the actual native
-- layout implementation rather than just our small frame API mock.
if os.getenv("CLEARLOOT_NATIVE_SOURCE") then
    InputUtil={IsGamepadUIEnabled=function() return false end}
    max=math.max
    GroupLootContainer.rollFrames={}; GroupLootContainer.maxIndex=0
    GroupLootContainer.layoutParent={Layout=function() end}
    assert(loadfile(os.getenv("CLEARLOOT_NATIVE_SOURCE")))()
    local nativeUpdate=GroupLootContainer_Update
    local nativeAdd=GroupLootContainer_AddFrame
    GroupLootContainer_Update=function(c) nativeLayouts=nativeLayouts+1; nativeUpdate(c) end
    GroupLootContainer_AddFrame=function(c,f)
        assert(c~=GroupLootContainer,"demo must not enter real loot container")
        nativeAdds=nativeAdds+1; nativeAdd(c,f)
    end
end
UIParent=CreateFrame("Frame"); STANDARD_TEXT_FONT="mock.ttf"; RAID_CLASS_COLORS={}; SlashCmdList={}
UIParent:SetSize(1920,1080)
GameTooltip=CreateFrame("Frame"); C_Timer={After=function(delay,fn) timers[#timers+1]=fn end}
function GetTime() return now end
function GetLootRollItemInfo() return "icon","Sword",1,3,false,true,true,false,nil,nil,nil,nil,false end
function GetLootRollItemLink() return "item:mock" end
function GetLootRollTimeLeft() return 60000 end
function RollOnLoot() calls=calls+1 end
function ConfirmLootRoll() end
function hooksecurefunc(name,fn)
    local original=_G[name]; _G[name]=function(...) original(...); fn(...) end
end
local history={}
C_LootHistory={GetLootHistoryTime=function() return now end,GetAllEncounterInfos=function() return {{encounterID=1}} end,
    GetSortedDropsForEncounter=function() return history end,GetSortedInfoForDrop=function() return history[1] end}
for i=1,4 do _G["GroupLootFrame"..i]=CreateFrame("Frame",nil,UIParent) end
assert(loadfile(base.."/Model.lua"))("ClearLoot",A)
assert(loadfile(base.."/History.lua"))("ClearLoot",A)
assert(loadfile(base.."/UI.lua"))("ClearLoot",A)
assert(loadfile(base.."/StatsUI.lua"))("ClearLoot",A)
assert(loadfile(base.."/NativeUI.lua"))("ClearLoot",A)
assert(loadfile(base.."/Core.lua"))("ClearLoot",A)
local eventFrame=created[#created]
eventFrame.scripts.OnEvent(eventFrame,"ADDON_LOADED","ClearLoot")
assert(registered.name=="ClearLoot" and A.settings,"settings must register at addon load")
A.OpenSettings(); assert(opened==42,"slash settings must open the registered category")
GroupLootFrame1.rollID=10
eventFrame.scripts.OnEvent(eventFrame,"START_LOOT_ROLL",10,60000)
local nativeRoll=A.rolls[1]
assert(A.db.presentation=="native" and nativeRoll.nativeAttached)
assert(nativeRoll.nativeCard.point[2]==GroupLootFrame1,"table must anchor to matching native frame")
assert(GroupLootFrame1:GetAlpha()==1 and GroupLootFrame1:IsMouseEnabled(),"native controls must remain usable")
assert(not nativeRoll.nativeCard.buttons[1]:IsShown(),"attached table must not duplicate roll buttons")
assert(not A.window:IsShown(),"native rolls must not also open a standalone window")
assert(GroupLootContainer.reservedSize>100 and nativeLayouts>0,"native slots need room for tables")
A.db.presentation="custom"; A.Render()
assert(GroupLootContainer.reservedSize==100,"leaving native mode must restore spacing")
assert(#A.rolls==1 and A.cards[1].roll.id==10)
A.Choose(A.rolls[1],1); assert(calls==1)
history={{lootListKey=2,itemHyperlink="item:mock",startTime=100,rollInfos={
    {playerName="You",isSelf=true,state=0,roll=44},{playerName="Friend",state=3,roll=99}}}}
A.RefreshHistory(); assert(A.rolls[1].key=="1:2" and A.rolls[1].choice==1)
A.Render()
local card=A.cards[1]
assert(card.timer.value==2 and card.timer.maximum==2 and card.timer.color[2]==0.85)
assert(card.rows[2].separator:IsShown(),"Need and Greed must have a group separator")
local short=A.UpdateCard(card,A.rolls[1]); A.db.compact=false
local large=A.UpdateCard(card,A.rolls[1]); assert(short<large,"compact cards must be shorter")
A.db.compact=true
A.rolls[1].rows[2].state=4; A.UpdateCard(card,A.rolls[1])
assert(card.timer.value==1 and card.timer.maximum==2 and card.timer.color[1]==1,"waiting choices must stay yellow")
A.RefreshHistory()
A.Choose(A.rolls[1],2); assert(calls==1,"must not submit a second choice")
for _,layout in ipairs({"stack","tabs","windows"}) do
    A.db.layout=layout; A.Render(); A.OpenSettings(); A.settings:Hide()
end
A.db.replaceNative=false; A.ApplyNative(); assert(GroupLootFrame1:GetAlpha()==1 and GroupLootFrame1:IsMouseEnabled())
A.db.replaceNative=true; A.ApplyNative(); assert(GroupLootFrame1:GetAlpha()==0 and not GroupLootFrame1:IsMouseEnabled())
assert(GroupLootFrame2:GetAlpha()==1,"untracked native rolls must remain visible")
A.db.presentation="native"; A.ApplyNative(); A.Render()
assert(GroupLootFrame1:GetAlpha()==1 and GroupLootFrame1:IsMouseEnabled())
-- A leader is not a winner. A confirmed result highlights the full row.
assert(not nativeRoll.nativeCard.rows[1].winner:IsShown())
A.ApplyDrop(nativeRoll,{rollInfos={{playerName="You",isSelf=true,state=0,roll=44,isWinner=true},
    {playerName="Friend",state=3,roll=99}}},now)
A.Render(); assert(nativeRoll.nativeCard.rows[1].winner:IsShown())
assert(nativeRoll.nativeCard.rows[1].name.text:find("Winner:"))
A.db.layout="stack"; GroupLootFrame1:Hide(); A.Render()
assert(not nativeRoll.nativeAttached and A.window:IsShown(),"result must survive native frame hiding")
assert(A.cards[1].tableOnly and A.cards[1].rows[1].winner:IsShown())
GroupLootFrame1.rollID=999; GroupLootFrame1:Show(); A.Render()
assert(not nativeRoll.nativeAttached,"recycled native frame must not inherit the old table")
GroupLootFrame1.rollID=10; A.Render()
A.db.presentation="none"; A.ApplyNative(); A.Render()
assert(not nativeRoll.nativeCard:IsShown() and not A.window:IsShown())
A.db.presentation="native"
-- A second result must clear the old highlight when pooled rows are reused.
A.ApplyDrop(nativeRoll,{allPassed=true,rollInfos={{playerName="You",isSelf=true,state=5},
    {playerName="Friend",state=5}}},now)
A.Render(); assert(not nativeRoll.nativeCard.rows[1].winner:IsShown())
nativeRoll.finished=nil; nativeRoll.resultConfirmed=nil
-- A late identical roll invalidates an early history association.
eventFrame.scripts.OnEvent(eventFrame,"START_LOOT_ROLL",11,60000)
A.RefreshHistory(); assert(not A.rolls[1].key and not A.rolls[2].key)
assert(A.rolls[1].ambiguous and #A.rolls[1].rows==0)
GroupLootFrame1.rollID=11; A.Render()
assert(A.rolls[2].nativeAttached and not A.rolls[1].nativeAttached)
assert(A.rolls[2].nativeCard==nativeRoll.nativeCard and #A.nativeCards==1,"native tables must be pooled per slot")
assert(A.rolls[2].nativeCard.roll==A.rolls[2] and not A.rolls[2].nativeCard.rows[1]:IsShown())
-- Combat defers spacing writes; the next render after combat applies them.
local oldSpacing=GroupLootContainer.reservedSize
InCombatLockdown=function() return true end
A.db.presentation="none"; A.Render(); assert(GroupLootContainer.reservedSize==oldSpacing)
InCombatLockdown=function() return false end
A.Render(); assert(GroupLootContainer.reservedSize==100)
A.db.presentation="native"
now=180; eventFrame.scripts.OnUpdate(eventFrame,1)
assert(A.rolls[1].status=="Outcome unconfirmed")
SlashCmdList.CLEARLOOT("native"); assert(GroupLootFrame1:GetAlpha()==1)
local before=calls
local recordedBefore=#A.db.lootArchive.records
local liveID=GroupLootFrame1.rollID
local liveSpacing=GroupLootContainer.reservedSize
A.Demo()
assert(nativeAdds>=3 and A.demoContainer.maxIndex==3)
assert(#A.demoFrames==3 and not A.window:IsShown(),"demo must use native previews, not standalone cards")
local stale=A.demoFrames[1].roll
A.Demo()
assert(#A.demoFrames==3 and A.demoFrames[1].roll~=stale,"reopening must reuse frames with fresh rolls")
for i,f in ipairs(A.demoFrames) do
    assert(f.template=="ClearLootDemoLootFrameTemplate" and f.roll.demo and not f.rollID)
    assert(f.card.attached and f.card.tableOnly and f.card.point[2]==f)
    assert(f.card:GetWidth()==f:GetWidth(),"preview table must use native width")
    assert(f.point[1]=="CENTER" and f.point[2]==A.demoContainer,"preview must use native container layout")
    assert(not f.NeedButton,"Forever buttons are nested, not retail-style root fields")
    assert(f.scripts.OnShow==nil and f.scripts.OnUpdate==nil and f.scripts.OnEvent==nil)
    assert(f.IconFrame.scripts.OnClick==nil and f.IconFrame.scripts.OnUpdate==nil)
    assert(not f.LootButtonContainer.TransmogButton:IsShown() and not f.card.buttons[1]:IsShown())
end
-- Dragging must survive refreshes and move the native header/table together.
local dragged=A.demoFrames[1]; local handle=dragged.card.dragHandle
assert(handle and handle.owner==dragged and not dragged.card.pin)
local originalAnchor=dragged.point
handle.scripts.OnDragStart(handle)
assert(dragged.clearLootDragging)
A.Render(); assert(dragged.clearLootDragging and dragged.point==originalAnchor,"refresh must not interrupt dragging")
dragged.centerX=800; dragged.centerY=500
handle.scripts.OnDragStop(handle)
assert(not dragged.clearLootDragging)
assert(A.db.lootPositions[1].x==300 and A.db.lootPositions[1].y==100)
assert(dragged.point[1]=="CENTER" and dragged.point[2]==UIParent)
A.Render(); assert(dragged.point[4]==300 and dragged.point[5]==100,"native layout must preserve dragged location")
assert(dragged.card.point[2]==dragged,"table must continue following the dragged header")
A.db.locked=true; handle.scripts.OnDragStart(handle)
assert(not dragged.clearLootDragging,"locked windows must not drag")
A.db.locked=false
for _,surface in ipairs({dragged,dragged.IconFrame}) do
    surface.hooks.OnDragStart(surface); assert(dragged.clearLootDragging)
    surface.hooks.OnDragStop(surface); assert(not dragged.clearLootDragging)
end
dragged.card.scripts.OnDragStart(dragged.card); assert(dragged.clearLootDragging)
dragged.card.scripts.OnDragStop(dragged.card); assert(not dragged.clearLootDragging)
assert(dragged.LootButtonContainer.PassButton.scripts.OnClick,"native button click must remain intact")
A.demoFrames[1].LootButtonContainer.PassButton.scripts.OnClick()
A.demoFrames[2].LootButtonContainer.NeedButton.scripts.OnClick()
A.demoFrames[3].LootButtonContainer.GreedButton.scripts.OnClick()
assert(A.demoFrames[1].roll.rows[1].state==5 and not A.demoFrames[1].roll.rows[1].roll)
assert(A.demoFrames[2].roll.choice==1 and A.demoFrames[3].roll.choice==2)
A.demoFrames[2].LootButtonContainer.PassButton.scripts.OnClick()
assert(A.demoFrames[2].roll.choice==1,"demo choice must not submit twice")
assert(calls==before,"native preview buttons must never submit loot")
for _,fn in ipairs(timers) do fn() end
A.Render()
assert(not stale.finished,"callbacks from a replaced demo must be ignored")
assert(A.demoFrames[2].roll.status=="You won")
assert(A.demoFrames[2].card.rows[1].winner:IsShown(),"native preview must show confirmed winner highlight")
assert(not A.demoFrames[2].LootButtonContainer.NeedButton.enabled,"finished demo controls must be disabled")
local winGlow=A.demoFrames[2].card.resultGlow
local lossGlow=A.demoFrames[3].card.resultGlow
assert(winGlow and winGlow:IsShown() and winGlow.outcome=="win")
assert(lossGlow and lossGlow:IsShown() and lossGlow.outcome=="loss")
assert(not A.demoFrames[1].card.resultGlow,"passing must not trigger a loss animation")
assert(not winGlow:IsMouseEnabled(),"glow must not block native controls or dragging")
local started=winGlow.roll.glowStarted
A.Render(); assert(winGlow.roll.glowStarted==started,"refresh must not restart pulses")
now=started+0.4; winGlow.scripts.OnUpdate(winGlow)
assert(winGlow:GetAlpha()>0.9,"win should visibly pulse")
now=started+3; winGlow.scripts.OnUpdate(winGlow)
assert(winGlow:GetAlpha()==0.55,"pulses should settle to a retained outline")
local pending=A.NewRoll(-99,nil,now,60,nil)
pending.status="Outcome unconfirmed"
A.UpdateCard(A.demoFrames[3].card,pending)
assert(not lossGlow:IsShown(),"reused cards must clear previous result glows")

assert(GroupLootFrame1.rollID==liveID and GroupLootFrame1:GetAlpha()==1 and GroupLootFrame1:IsMouseEnabled())
assert(GroupLootContainer.reservedSize==liveSpacing,"preview must not resize the live loot container")
assert(#A.db.lootArchive.records==recordedBefore,"demo rows must not enter persistent history")
for _,f in ipairs(A.demoFrames) do f.roll.dismissed=true end
A.Render()
for _,f in ipairs(A.demoFrames) do assert(not f:IsShown() and not f.card:IsShown()) end
A.OpenHistory("players"); A.OpenHistory("drops"); A.RefreshStatsIfVisible(); A.OpenExport()
assert(A.db.lootArchive and A.statsWindow and A.exportFrame)
-- Unknown/missing native templates must not silently pass as a native demo.
A.demoFrames={}; A.demoTemplateWarning=nil; A.historyView=false
local create=CreateFrame
CreateFrame=function(kind,name,parent,template)
    if template=="ClearLootDemoLootFrameTemplate" then error("missing native template") end
    return create(kind,name,parent,template)
end
A.Demo()
assert(A.demoTemplateWarning and not A.window:IsShown(),"failed native demo must report failure, never fall back")
CreateFrame=create
print("PASS integration: load, controls, all layouts, settings registration, native attachments/spacing/reuse, winner highlighting, native restoration, duplicates, unknown outcomes, demo isolation")

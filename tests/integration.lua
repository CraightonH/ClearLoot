local A={}; local now=100; local calls=0; local timers={}; local created={}
local base=os.getenv("CLEARLOOT_ADDON") or "ClearLoot"
local frameMethods={}
function frameMethods:SetScript(k,v) self.scripts[k]=v end
function frameMethods:HookScript(k,v) self.hooks[k]=v end
function frameMethods:GetChildren() return (table.unpack or unpack)(self.children) end
function frameMethods:CreateFontString() return setmetatable({children={},scripts={},hooks={}}, {__index=frameMethods}) end
frameMethods.CreateTexture=frameMethods.CreateFontString
function frameMethods:SetSize(w,h) self.width=w; self.height=h end
function frameMethods:SetWidth(w) self.width=w end
function frameMethods:SetHeight(h) self.height=h end
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
function frameMethods:GetCenter() return 500,400 end
function frameMethods:GetEffectiveScale() return 1 end
function frameMethods:SetChecked(v) self.checked=v end
function frameMethods:GetChecked() return self.checked end
function frameMethods:SetEnabled(v) self.enabled=v end
function frameMethods:SetPoint(...) self.point={...} end
local harmless={"SetFont","SetJustifyH","SetJustifyV","SetBackdrop","SetBackdropColor","SetBackdropBorderColor",
    "SetAllPoints","SetTexture","SetStatusBarTexture","SetStatusBarColor","SetMinMaxValues","SetValue",
    "SetMovable","SetClampedToScreen","RegisterForDrag","StartMoving","StopMovingOrSizing","SetFrameStrata",
    "SetScrollChild","SetScale","ClearAllPoints","SetTextColor","SetAutoFocus","SetMaxLetters","ClearFocus",
    "RegisterEvent","SetColorTexture","SetMultiLine","HighlightText","SetFocus"}
for _,name in ipairs(harmless) do frameMethods[name]=function() end end
function frameMethods:SetValue(v) self.value=v end
function frameMethods:SetMinMaxValues(a,b) self.minimum=a; self.maximum=b end
function frameMethods:SetStatusBarColor(r,g,b) self.color={r,g,b} end
function CreateFrame(kind,name,parent)
    local f=setmetatable({children={},scripts={},hooks={},shown=true},{__index=frameMethods})
    if parent then table.insert(parent.children,f) end
    created[#created+1]=f; return f
end
UIParent=CreateFrame("Frame"); STANDARD_TEXT_FONT="mock.ttf"; RAID_CLASS_COLORS={}; SlashCmdList={}
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
assert(loadfile(base.."/Core.lua"))("ClearLoot",A)
local eventFrame=created[#created]
eventFrame.scripts.OnEvent(eventFrame,"ADDON_LOADED","ClearLoot")
eventFrame.scripts.OnEvent(eventFrame,"START_LOOT_ROLL",10,60000)
GroupLootFrame1.rollID=10
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
-- A late identical roll invalidates an early history association.
eventFrame.scripts.OnEvent(eventFrame,"START_LOOT_ROLL",11,60000)
A.RefreshHistory(); assert(not A.rolls[1].key and not A.rolls[2].key)
assert(A.rolls[1].ambiguous and #A.rolls[1].rows==0)
now=180; eventFrame.scripts.OnUpdate(eventFrame,1)
assert(A.rolls[1].status=="Outcome unconfirmed")
SlashCmdList.CLEARLOOT("native"); assert(GroupLootFrame1:GetAlpha()==1)
A.Demo(); local before=calls
local recordedBefore=#A.db.lootArchive.records
for _,r in ipairs(A.rolls) do if r.demo then
    A.Choose(r,0); assert(r.rows[1].state==5 and r.rows[1].roll==nil)
end end
assert(calls==before,"preview must never submit loot")
for _,fn in ipairs(timers) do fn() end
A.Render()
assert(#A.db.lootArchive.records==recordedBefore,"demo rows must not enter persistent history")
A.OpenHistory("players"); A.OpenHistory("drops"); A.RefreshStatsIfVisible(); A.OpenExport()
assert(A.db.lootArchive and A.statsWindow and A.exportFrame)
print("PASS integration: load, controls, all layouts, native restoration, duplicates, unknown outcomes, demo isolation")

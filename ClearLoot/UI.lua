local _, A = ...
local function text(parent,size)
    local t=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    t:SetFont(STANDARD_TEXT_FONT,size or 12,""); t:SetJustifyH("LEFT")
    return t
end
local function panel(parent)
    local f=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    f:SetBackdrop({bgFile="Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(0.12,0.11,0.09,0.97); f:SetBackdropBorderColor(1,1,1,1)
    return f
end
local function button(parent,label,w,callback)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(w or 80,22); b:SetText(label); b:SetScript("OnClick",callback)
    return b
end
local function tooltip(widget,fn)
    widget:EnableMouse(true)
    widget:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); fn(self); GameTooltip:Show()
    end)
    widget:SetScript("OnLeave",function() GameTooltip:Hide() end)
end
local function movable(f,save)
    f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self) if not A.db.locked then self.dragging=true; self:StartMoving() end end)
    f:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing(); self.dragging=false
        if save then
            local x,y=self:GetCenter(); local px,py=UIParent:GetCenter()
            local ratio=self:GetEffectiveScale()/UIParent:GetEffectiveScale()
            A.db.x=x*ratio-px; A.db.y=y*ratio-py
            -- Anchor uses UIParent-relative pixels at the child's scale.
            A.db.x=A.db.x/A.db.scale; A.db.y=A.db.y/A.db.scale
        end
    end)
end
function A.MakeCard(parent)
    local f=panel(parent); f.rows={}; f.buttons={}
    f.icon=CreateFrame("Button",nil,f); f.icon:SetSize(38,38); f.icon:SetPoint("TOPLEFT",12,-12)
    f.icon.texture=f.icon:CreateTexture(nil,"ARTWORK"); f.icon.texture:SetAllPoints()
    tooltip(f.icon,function() if f.roll.link then GameTooltip:SetHyperlink(f.roll.link) end end)
    f.title=text(f,13); f.title:SetPoint("TOPLEFT",58,-12); f.title:SetPoint("RIGHT",-75,0)
    f.title:SetHeight(30)
    f.close=button(f,"×",25,function()
        if f.roll.finished then f.roll.dismissed=true; A.Render() end
    end); f.close:SetPoint("TOPRIGHT",-8,-36)
    f.bet=button(f,"Bet",35,function() A.OpenBets(f.roll) end)
    f.meta=text(f,11); f.meta:SetPoint("TOPLEFT",12,-56)
    f.timer=CreateFrame("StatusBar",nil,f); f.timer:SetPoint("TOPLEFT",12,-76)
    f.timer:SetPoint("TOPRIGHT",-12,-76); f.timer:SetHeight(3)
    f.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8"); f.timer:SetStatusBarColor(0.35,0.65,0.95)
    local actions={{"Need",1},{"Greed",2},{"Pass",0},{"Transmog",4},{"DE",3}}
    for i,action in ipairs(actions) do
        local kind=action[2]
        local b=button(f,action[1],68,function() A.Choose(f.roll,kind) end)
        b:SetPoint("TOPLEFT",12+(i-1)*73,-88); f.buttons[kind]=b
        tooltip(b,function(self)
            GameTooltip:SetText(action[1]);
            if self.reason then GameTooltip:AddLine(self.reason,1,0.4,0.4,true) end
        end)
    end
    f.heading=text(f,10); f.heading:SetPoint("TOPLEFT",12,-119)
    f.heading:SetText("PLAYER                                  CHOICE                 ROLL")
    f.choiceHeading=text(f,10); f.choiceHeading:SetText("CHOICE")
    f.rollHeading=text(f,10); f.rollHeading:SetText("ROLL"); f.rollHeading:SetJustifyH("RIGHT")
    f.notice=text(f,11); f.notice:SetPoint("TOPLEFT",12,-141); f.notice:SetPoint("RIGHT",-12,0)
    f.notice:SetJustifyV("TOP")
    f.result=text(f,13); f.result:SetPoint("BOTTOMLEFT",12,13); f.result:SetPoint("RIGHT",-12,0)
    f.result:SetHeight(34)
    return f
end
local function positionCard(f,db)
    local compact=db.compact
    f.icon:ClearAllPoints(); f.icon:SetSize(compact and 32 or 38,compact and 32 or 38)
    f.icon:SetPoint("TOPLEFT",compact and 8 or 12,compact and -7 or -12)
    f.title:ClearAllPoints(); f.title:SetPoint("TOPLEFT",compact and 48 or 58,compact and -7 or -12)
    f.title:SetPoint("RIGHT",compact and -110 or -75,0); f.title:SetHeight(compact and 17 or 30)
    f.title:SetFont(STANDARD_TEXT_FONT,compact and 12 or 13,"")
    f.meta:ClearAllPoints(); f.meta:SetPoint("TOPLEFT",compact and 48 or 12,compact and -28 or -56)
    f.timer:ClearAllPoints(); f.timer:SetPoint("TOPLEFT",compact and 8 or 12,compact and -50 or -76)
    f.timer:SetPoint("TOPRIGHT",compact and -8 or -12,compact and -50 or -76)
    for kind,b in pairs(f.buttons) do
        b:ClearAllPoints(); b:SetSize(compact and 45 or 68,compact and 20 or 22)
        b:SetText(({[0]="Pass",[1]="Need",[2]="Greed",[3]="DE",[4]=compact and "Mog" or "Transmog"})[kind])
        if compact then
            local right=(kind==0 or kind==3) and -8 or -57
            b:SetPoint("TOPRIGHT",right,(kind==0 or kind==1) and -5 or -27)
        else
            local x=({[1]=12,[2]=85,[0]=158,[3]=231,[4]=85})[kind]
            b:SetPoint("TOPLEFT",x,-88)
        end
    end
    f.close:ClearAllPoints()
    f.close:SetSize(compact and 22 or 25,compact and 18 or 22)
    f.close:SetPoint(compact and "BOTTOMRIGHT" or "TOPRIGHT",-8,compact and 5 or -36)
    f.heading:ClearAllPoints(); f.heading:SetPoint("TOPLEFT",compact and 8 or 12,compact and -60 or -119)
    f.heading:SetText(compact and "PLAYER" or "PLAYER                                  CHOICE                 ROLL")
    f.choiceHeading:SetShown(compact); f.rollHeading:SetShown(compact)
    f.choiceHeading:ClearAllPoints(); f.choiceHeading:SetPoint("TOPLEFT",12+(db.width-50)*0.48+4,compact and -60 or -119)
    f.rollHeading:ClearAllPoints(); f.rollHeading:SetPoint("TOPRIGHT",compact and -8 or -12,compact and -60 or -119)
    f.notice:ClearAllPoints(); f.notice:SetPoint("TOPLEFT",compact and 8 or 12,compact and -78 or -141)
    f.notice:SetPoint("RIGHT",-12,0)
    f.result:ClearAllPoints(); f.result:SetPoint("BOTTOMLEFT",compact and 8 or 12,compact and 6 or 13)
    f.result:SetPoint("RIGHT",compact and -38 or -12,0); f.result:SetHeight(compact and 18 or 34)
    f.result:SetFont(STANDARD_TEXT_FONT,compact and 11 or 13,"")
end
-- Three gentle pulses, followed by a quieter outline for the retained result.
-- The effect is its own mouse-transparent frame, so loot controls stay clickable.
function A.UpdateResultGlow(card,r)
    local outcome=r.resultConfirmed and not r.ambiguous and
        ((r.status=="You won" and "win") or (r.status=="You lost" and "loss"))
    if not outcome then
        if card.resultGlow then card.resultGlow:Hide() end
        return
    end
    if r.glowOutcome~=outcome then r.glowOutcome=outcome; r.glowStarted=GetTime() end
    local glow=card.resultGlow
    if not glow then
        glow=CreateFrame("Frame",nil,card,"BackdropTemplate"); card.resultGlow=glow
        glow:EnableMouse(false)
        glow:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=24,
            insets={left=8,right=8,top=8,bottom=8}})
        glow:SetScript("OnUpdate",function(self)
            local age=math.max(0,GetTime()-self.roll.glowStarted)
            if age<2.4 then self:SetAlpha(0.35+0.6*(0.5-0.5*math.cos(age/2.4*math.pi*6)))
            else self:SetAlpha(0.55) end
        end)
    end
    glow.roll=r; glow.outcome=outcome
    local top=card.attached and r.nativeFrame or card
    glow:ClearAllPoints(); glow:SetPoint("TOPLEFT",top,"TOPLEFT",-9,9)
    glow:SetPoint("BOTTOMRIGHT",card,"BOTTOMRIGHT",9,-9)
    glow:SetFrameLevel(math.max(card:GetFrameLevel(),top:GetFrameLevel())+3)
    local red,green,blue=outcome=="win" and 0.2 or 1,outcome=="win" and 1 or 0.2,0.2
    glow:SetBackdropColor(red,green,blue,0.06)
    glow:SetBackdropBorderColor(red,green,blue,1)
    glow:Show(); glow:GetScript("OnUpdate")(glow)
end
function A.UpdateCard(f,r)
    local db=A.db; f.roll=r
    positionCard(f,db)
    local width=f.tableOnly and (f.tableWidth or db.width-26) or db.width-26
    local rowWidth=width-24
    if f.tableOnly then
        for _,widget in ipairs({f.icon,f.meta}) do widget:Hide() end
        for _,widget in pairs(f.buttons) do widget:Hide() end
        f.title:SetShown(not f.attached)
        f.title:ClearAllPoints(); f.title:SetPoint("TOPLEFT",12,-10)
        f.title:SetPoint("RIGHT",-12,0); f.title:SetHeight(18)
        local y=f.attached and 11 or 35
        f.heading:ClearAllPoints(); f.heading:SetPoint("TOPLEFT",12,-y); f.heading:SetText("PLAYER")
        f.choiceHeading:Show(); f.choiceHeading:ClearAllPoints()
        f.choiceHeading:SetPoint("TOPLEFT",12+rowWidth*0.48+4,-y)
        f.rollHeading:Show(); f.rollHeading:ClearAllPoints(); f.rollHeading:SetPoint("TOPRIGHT",-12,-y)
        f.timer:ClearAllPoints(); f.timer:SetPoint("TOPLEFT",12,-y-17)
        f.timer:SetPoint("TOPRIGHT",-12,-y-17)
        f.notice:ClearAllPoints(); f.notice:SetPoint("TOPLEFT",12,-y-24); f.notice:SetPoint("RIGHT",-12,0)
        f.close:ClearAllPoints(); f.close:SetPoint("BOTTOMRIGHT",-10,7)
        f.result:ClearAllPoints(); f.result:SetPoint("BOTTOMLEFT",12,8)
        f.result:SetPoint("RIGHT",-40,0); f.result:SetHeight(18)
    else
        f.icon:Show(); f.meta:Show(); f.title:Show()
    end
    f:SetWidth(width); f:SetAlpha(db.opacity)
    f.icon.texture:SetTexture(r.texture or "Interface\\Icons\\INV_Misc_Dice_02")
    f.title:SetText(r.link or r.name or "Loading item…")
    f.close:SetEnabled(not not r.finished)
    local left=math.max(0,(r.started+r.duration)-GetTime())
    local chosen,total,complete=A.Completion(r)
    local count=total>0 and string.format("%d/%d chosen",chosen,total) or "Choices unavailable"
    f.meta:SetText(db.compact and (count..(r.finished and "" or string.format(" · %.0fs",left))) or
        (r.status.." · "..count..string.format(" · %.0fs",left)))
    f.timer:SetMinMaxValues(0,math.max(1,total)); f.timer:SetValue(chosen)
    if complete then f.timer:SetStatusBarColor(0.3,0.85,0.4)
    else f.timer:SetStatusBarColor(1,0.78,0.15) end
    for kind,b in pairs(f.buttons) do
        local allowed=(kind==0) or (r.allowed and r.allowed[kind])
        local show=(kind~=3 and kind~=4) or (r.allowed and r.allowed[kind])
        b:SetShown(not f.tableOnly and not not show)
        b:SetEnabled(not r.finished and not r.closed and not r.choice and left>0 and not not allowed)
        b.reason=r.reasons and r.reasons[kind] or nil
    end
    -- Transmog takes Greed's slot; disenchant occupies a fourth slot when offered.
    f.buttons[2]:SetShown(not f.tableOnly and not (r.allowed and r.allowed[4]))
    local rows=A.SortedRows(r,db)
    f.notice:SetText(#rows==0 and (r.match or "Player details unavailable for this drop") or "")
    f.notice:SetHeight(38)
    local rowY=f.tableOnly and (f.attached and 35 or 59) or (db.compact and 77 or 139)
    local firstRowY=rowY; local previousGroup
    for i,p in ipairs(rows) do
        local group=A.RollGroup(p.state)
        local boundary=db.groupSeparators and previousGroup and group~=previousGroup
        if boundary then rowY=rowY+6 end
        local row=f.rows[i]
        if not row then
            row=CreateFrame("Frame",nil,f); row.name=text(row); row.choice=text(row); row.roll=text(row)
            row.name:SetPoint("LEFT",0,0); row.name:SetWidth(rowWidth*0.48)
            row.choice:SetPoint("LEFT",row.name,"RIGHT",4,0); row.choice:SetWidth(rowWidth*0.33)
            row.roll:SetPoint("RIGHT"); row.roll:SetJustifyH("RIGHT"); row.roll:SetWidth(45)
            row.winner=row:CreateTexture(nil,"BACKGROUND")
            row.winner:SetAllPoints(); row.winner:SetColorTexture(1,0.82,0,0.22)
            row.separator=row:CreateTexture(nil,"ARTWORK")
            row.separator:SetColorTexture(0.42,0.47,0.53,0.8)
            row.separator:SetHeight(1); row.separator:SetPoint("TOPLEFT",0,4); row.separator:SetPoint("TOPRIGHT",0,4)
            f.rows[i]=row
        end
        row:Show(); row:SetSize(rowWidth,db.rowHeight); row:ClearAllPoints()
        row:SetPoint("TOPLEFT",12,-rowY); row.separator:SetShown(not not boundary)
        rowY=rowY+db.rowHeight; previousGroup=group
        row.name:SetWidth(rowWidth*0.48); row.choice:SetWidth(rowWidth*0.33)
        for _,t in ipairs({row.name,row.choice,row.roll}) do t:SetFont(STANDARD_TEXT_FONT,db.fontSize,"") end
        local won=r.resultConfirmed and p.isWinner and not r.ambiguous
        row.winner:SetShown(not not won)
        local name=(won and "|cffffd100Winner:|r " or "")..(p.playerName or "Unknown")
        if p.isSelf then name=name.." (you)" end
        local color=db.classColors and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.playerClass]
        row.name:SetText(name); row.name:SetTextColor(color and color.r or 0.85,color and color.g or 0.88,color and color.b or 0.94)
        row.choice:SetText("|cff"..(A.colors[p.state] or "929eaf")..(A.labels[p.state] or "Waiting").."|r")
        row.roll:SetText(won and ("|cffffd100"..tostring(p.roll or "—").." *|r") or tostring(p.roll or "—"))
    end
    for i=#rows+1,#f.rows do f.rows[i]:Hide() end
    local result
    if r.finished then
        result=r.status
        if r.winner then result=result.." · "..(r.winner.playerName or "Unknown").." · "..(A.labels[r.winner.state] or "Roll").." "..tostring(r.winner.roll or "—") end
    elseif r.closed or left==0 then result=db.compact and "Awaiting server result" or "Awaiting server result · outcome unconfirmed"
    elseif r.choice then result="Your choice: "..({[0]="Pass",[1]="Need",[2]="Greed",[3]="Disenchant",[4]="Transmog"})[r.choice]
    else result=db.compact and "Choose above" or "Choose above · results stay visible after you roll" end
    f.result:SetText(result)
    if r.resultConfirmed and r.status=="You won" then f.result:SetTextColor(0.2,1,0.3)
    elseif r.resultConfirmed and r.status=="You lost" then f.result:SetTextColor(1,0.25,0.2)
    else f.result:SetTextColor(0.85,0.88,0.8) end
    f.bet:ClearAllPoints(); f.bet:SetPoint("BOTTOMRIGHT",-36,7); f.bet:SetSize(35,18)
    local showBet=A.bettingAvailable and not r.demo
    f.bet:SetShown(not not showBet)
    if showBet then f.result:SetPoint("RIGHT",-80,0) end
    local height=math.max(rowY,firstRowY+2*db.rowHeight)+(f.tableOnly and 34 or (db.compact and 28 or 64))
    f:SetHeight(height); A.UpdateResultGlow(f,r); return height
end
function A.BuildUI()
    local f=panel(UIParent); A.window=f; f:SetFrameStrata("DIALOG"); movable(f,true)
    f.title=text(f,14); f.title:SetPoint("TOPLEFT",13,-14); f.title:SetText("CLEARLOOT")
    local settings=button(f,"Settings",75,function() A.OpenSettings() end); settings:SetPoint("TOPRIGHT",-12,-9)
    local history=button(f,"History",70,function() A.OpenHistory("drops") end)
    history:SetPoint("RIGHT",settings,"LEFT",-5,0)
    f.context=text(f,11); f.context:SetPoint("TOPLEFT",13,-41)
    f.tabs=CreateFrame("Frame",nil,f); f.tabs:SetPoint("TOPLEFT",12,-61); f.tabs:SetPoint("TOPRIGHT",-12,-61); f.tabs:SetHeight(26)
    f.tabButtons={}
    f.scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT",5,-93); f.scroll:SetPoint("BOTTOMRIGHT",-27,10)
    f.content=CreateFrame("Frame",nil,f.scroll); f.content:SetSize(400,1); f.scroll:SetScrollChild(f.content)
    A.cards={}; A.floaters={}; A.Render()
end
function A.Render()
    if not A.window then return end
    local db=A.db; local f=A.window; local visible={}
    if A.RenderAttachments then A.RenderAttachments() end
    for _,r in ipairs(A.rolls) do
        if A.historyView or (not r.nativeDemo and not r.dismissed and (r.demo or db.presentation~="none") and not r.nativeAttached and
            (db.presentation~="native" or r.demo or r.finished or r.closed or r.nativeSeen)) then
            visible[#visible+1]=r
        end
    end
    if A.historyView then
        table.sort(visible,function(a,b) return a.started>b.started end)
    end
    f:SetScale(db.scale); f:SetWidth(db.width)
    if not f.dragging then
        f:ClearAllPoints(); f:SetPoint("CENTER",UIParent,"CENTER",db.x,db.y)
    end
    f.context:SetShown(not db.compact)
    f.title:SetText(db.compact and ((A.historyView and "HISTORY" or "CLEARLOOT").." · "..#visible) or "CLEARLOOT")
    f.title:SetFont(STANDARD_TEXT_FONT,db.compact and 12 or 14,"")
    f.context:SetText((A.historyView and "SESSION HISTORY" or "GROUP LOOT").."  ·  "..#visible.." item(s)")
    f.content:SetWidth(db.width-32)
    for _,card in ipairs(A.cards) do card:Hide() end
    for _,floater in ipairs(A.floaters) do floater:Hide() end
    for _,b in ipairs(f.tabButtons) do b:Hide() end
    local layout=A.historyView and "stack" or db.layout
    local tabs=layout=="tabs"
    f.tabs:SetShown(tabs)
    f.tabs:ClearAllPoints(); f.tabs:SetPoint("TOPLEFT",12,db.compact and -38 or -61)
    f.tabs:SetPoint("TOPRIGHT",-12,db.compact and -38 or -61)
    f.scroll:ClearAllPoints(); f.scroll:SetPoint("TOPLEFT",5,db.compact and (tabs and -69 or -38) or (tabs and -93 or -62))
    f.scroll:SetPoint("BOTTOMRIGHT",-27,10)
    if tabs and #visible>0 then
        local selected=1
        for i,r in ipairs(visible) do if r==A.selected then selected=i end end
        A.selected=visible[selected]
        -- Paginated tab strip: unlimited drops without shrinking labels to nothing.
        local first=math.floor((selected-1)/3)*3+1
        for slot=1,3 do
            local r=visible[first+slot-1]
            local b=f.tabButtons[slot]
            if not b then b=button(f.tabs,"",90,function() end); f.tabButtons[slot]=b end
            if r then
                b:SetWidth((db.width-100)/3); b:ClearAllPoints(); b:SetPoint("LEFT",(slot-1)*(db.width-100)/3,0)
                local label=r.name or "Item"
                b:SetText((r==A.selected and "> " or "")..label:sub(1,13))
                b:SetScript("OnClick",function() A.selected=r; A.Render() end); b:Show()
            end
        end
        for slot,offset in pairs({[4]=-1,[5]=1}) do
            local b=f.tabButtons[slot]
            if not b then b=button(f.tabs,offset<0 and "<" or ">",28,function() end); f.tabButtons[slot]=b end
            b:ClearAllPoints(); b:SetPoint("RIGHT",slot==4 and -32 or 0,0); b:Show()
            b:SetEnabled(selected+offset>=1 and selected+offset<=#visible)
            b:SetScript("OnClick",function() A.selected=visible[selected+offset]; A.Render() end)
        end
        visible={A.selected}
    end
    local y=0
    for i,r in ipairs(visible) do
        local card
        if layout=="windows" then
            card=A.floaters[i]
            if not card then card=A.MakeCard(UIParent); A.floaters[i]=card; movable(card,false); card:SetFrameStrata("DIALOG") end
            card:SetScale(db.scale)
            if card.lastRoll~=r then
                card:ClearAllPoints(); card:SetPoint("TOPLEFT",UIParent,"TOPLEFT",40+((i-1)%3)*(db.width+8),-70-math.floor((i-1)/3)*90)
                card.lastRoll=r
            end
            card.tableOnly=db.presentation=="native" and not r.demo; card.attached=false; card.tableWidth=nil
            A.UpdateCard(card,r)
        else
            card=A.cards[i]
            if not card then card=A.MakeCard(f.content); A.cards[i]=card end
            card:ClearAllPoints(); card:SetPoint("TOPLEFT",0,-y)
            card.tableOnly=db.presentation=="native" and not r.demo; card.attached=false; card.tableWidth=nil
            y=y+A.UpdateCard(card,r)+8
        end
        card:Show(); r.frame=card
    end
    f.content:SetHeight(math.max(1,y)); f:SetHeight(math.min(db.maxHeight,math.max(80,y+(db.compact and (tabs and 80 or 49) or (tabs and 104 or 73)))))
    f:Show()
    if #visible==0 and not A.historyView then f:Hide() end
end
function A.BuildSettings(parent)
    if A.settings then return A.settings end
    local f=parent or panel(UIParent); A.settings=f
    if not parent then
        f:SetSize(480,640); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); movable(f,false)
    end
    local title=text(f,16); title:SetPoint("TOPLEFT",18,-18); title:SetText("ClearLoot settings")
    if not parent then local close=button(f,"Close",65,function() f:Hide() end); close:SetPoint("TOPRIGHT",-14,-14) end
    local common=CreateFrame("Frame",nil,f); common:SetAllPoints(); local advanced=CreateFrame("Frame",nil,f); advanced:SetAllPoints(); advanced:Hide()
    local toggle=button(f,"Advanced",100,function()
        local show=not advanced:IsShown(); common:SetShown(not show); advanced:SetShown(show)
    end); toggle:SetPoint("TOPLEFT",18,-51)
    local basic=button(f,"Common",90,function() common:Show(); advanced:Hide() end); basic:SetPoint("LEFT",toggle,"RIGHT",8,0)
    local function label(parent,title,y)
        local t=text(parent,12); t:SetPoint("TOPLEFT",20,-y); t:SetText(title); return t
    end
    local function check(parent,key,title,y)
        local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate"); b:SetPoint("TOPLEFT",16,-y); b:SetSize(28,28)
        local t=text(parent,12); t:SetPoint("LEFT",b,"RIGHT",5,0); t:SetText(title)
        b:SetScript("OnShow",function() b:SetChecked(A.db[key]) end)
        b:SetChecked(A.db[key]); b:SetScript("OnClick",function()
            if key=="betsEnabled" and A.betClient then A.betClient:SetEnabled(not not b:GetChecked())
            else A.db[key]=not not b:GetChecked() end
            if A.ApplyNative then A.ApplyNative() end; A.Render()
        end)
    end
    local function number(parent,key,title,y,min,max)
        label(parent,title,y+5)
        local box=CreateFrame("EditBox",nil,parent,"InputBoxTemplate"); box:SetSize(76,25); box:SetPoint("TOPRIGHT",-22,-y)
        box:SetAutoFocus(false); box:SetMaxLetters(8); box:SetText(tostring(A.db[key]))
        local function commit()
            local v=tonumber(box:GetText())
            if v and v==v then A.db[key]=math.max(min,math.min(max,v)) end
            if key=="archiveLimit" then A.PruneArchive(A.db) end
            box:SetText(tostring(A.db[key])); A.Render()
        end
        box:SetScript("OnEnterPressed",function() commit(); box:ClearFocus() end)
        box:SetScript("OnEditFocusLost",commit)
    end
    local cycle
    cycle=button(common,"",190,function()
        local nextLayout={stack="tabs",tabs="windows",windows="stack"}
        A.db.layout=nextLayout[A.db.layout]; A.Render()
        cycle:SetText(({stack="Stacked panels",tabs="Tabbed window",windows="Separate windows"})[A.db.layout])
    end); cycle:SetPoint("TOPRIGHT",-20,-100); cycle:SetText(({stack="Stacked panels",tabs="Tabbed window",windows="Separate windows"})[A.db.layout])
    label(common,"Multiple items",105)
    number(common,"closeAfter","Close result after seconds (0 = keep)",147,0,300)
    number(common,"scale","UI scale (0.65–1.6)",190,0.65,1.6)
    check(common,"pauseHover","Pause closing while hovered",235)
    check(common,"locked","Lock window position",275)
    local modes={native="Extend Blizzard loot frames",custom="Standalone ClearLoot panels",none="Blizzard UI only"}
    local mode=button(common,modes[A.db.presentation],240,function(self)
        A.db.presentation=({native="custom",custom="none",none="native"})[A.db.presentation]
        A.db.replaceNative=A.db.presentation=="custom"
        self:SetText(modes[A.db.presentation]); A.ApplyNative(); A.Render()
    end); mode:SetPoint("TOPLEFT",20,-315)
    mode:SetScript("OnShow",function(self) self:SetText(modes[A.db.presentation]) end)
    check(common,"compact","Compact panels (turn off for larger headers)",352)
    local preview=button(common,"Preview rolls",125,function() A.Demo() end); preview:SetPoint("TOPLEFT",20,-400)
    local history=button(common,"History / stats",125,function() A.OpenHistory("players") end); history:SetPoint("LEFT",preview,"RIGHT",10,0)
    check(common,"betsEnabled","Show friends' side bets (honor ledger)",438)
    local bets=button(common,"Side bets / ledger",160,function() A.OpenBets() end); bets:SetPoint("TOPLEFT",20,-478)
    local tip=label(common,"Drag the item header, icon, or table to move a panel.\nYellow bar: players still choosing. Green: everyone chose.\nThe server may still be resolving the winner.\nPreview rolls never send real loot choices.",520); tip:SetWidth(440); tip:SetHeight(90)
    number(advanced,"width","Window width",100,380,650)
    number(advanced,"rowHeight","Player row height",142,18,32)
    number(advanced,"fontSize","Player font size",184,10,18)
    number(advanced,"opacity","Panel opacity (0.4–1)",226,0.4,1)
    number(advanced,"maxHeight","Maximum stack height (scrolls)",268,300,900)
    number(advanced,"historyLimit","Completed items kept this session",310,10,200)
    check(advanced,"showPassed","Show players who passed",353)
    check(advanced,"classColors","Use class colors for player names",390)
    check(advanced,"sound","Play a sound on confirmed results",427)
    check(advanced,"groupSeparators","Separate Need / Greed / Pass groups",464)
    local sort=button(advanced,"Toggle player sorting",180,function()
        A.db.sort=A.db.sort=="name" and "priority" or "name"; A.Render()
        print("ClearLoot: within each choice group, sort by "..(A.db.sort=="name" and "name" or "roll"))
    end); sort:SetPoint("TOPLEFT",20,-506)
    local reset=button(advanced,"Reset position",130,function() A.db.x=0; A.db.y=180; A.db.lootPositions={}; A.Render() end); reset:SetPoint("TOPLEFT",20,-545)
    number(advanced,"archiveLimit","Persistent history: maximum drops",585,100,50000)
    return f
end

function A.RegisterSettings()
    local f=CreateFrame("Frame", "ClearLootSettingsPanel", UIParent); f.name="ClearLoot"; f:Hide()
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        A.settingsCategory=Settings.RegisterCanvasLayoutCategory(f,"ClearLoot")
        Settings.RegisterAddOnCategory(A.settingsCategory)
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",0,-8); scroll:SetPoint("BOTTOMRIGHT",-30,8)
        local content=CreateFrame("Frame",nil,scroll); content:SetSize(480,640)
        scroll:SetScrollChild(content); A.BuildSettings(content)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(f); A.legacySettings=f; A.BuildSettings(f)
    end
end
function A.OpenSettings()
    if A.settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(A.settingsCategory:GetID())
    elseif A.legacySettings and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(A.legacySettings)
    else
        A.BuildSettings():Show()
    end
end

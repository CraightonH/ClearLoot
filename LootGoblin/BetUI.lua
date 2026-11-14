local _,A=...
local M=A.BetModel
local function panel()
    local f=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    f:SetBackdrop({bgFile="Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=24,
        insets={left=6,right=6,top=6,bottom=6}})
    f:SetBackdropColor(0.12,0.11,0.09,1); f:SetBackdropBorderColor(1,1,1,1)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart",function() f:StartMoving() end)
    f:SetScript("OnDragStop",function() f:StopMovingOrSizing() end); f:SetPoint("CENTER")
    return f
end
local function text(parent,size,x,y,width)
    local t=parent:CreateFontString(nil,"OVERLAY"); t:SetFont(STANDARD_TEXT_FONT,size or 12,"")
    t:SetJustifyH("LEFT"); t:SetPoint("TOPLEFT",x,y); if width then t:SetWidth(width) end; return t
end
local function button(parent,title,width,x,y,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate"); b:SetSize(width,24); b:SetText(title)
    b:SetPoint("TOPLEFT",x,y); b:SetScript("OnClick",fn); return b
end
local function message(reason) return M.reasons[reason] or reason or "" end
local function name(round,guid) return round.participants[guid] or guid or "—" end
function A.OpenBetRecord(round)
    local f=A.betDetail
    if not f then
        f=panel(); A.betDetail=f; f:SetSize(740,580); f.rows={}
        f.title=text(f,14,16,-16,620)
        button(f,"Close",60,660,-12,function() f:Hide() end)
        local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-50); scroll:SetPoint("BOTTOMRIGHT",-34,46)
        f.content=CreateFrame("Frame",nil,scroll); f.content:SetWidth(670); scroll:SetScrollChild(f.content)
        f.text=text(f.content,12,0,0,655)
        text(f,11,16,-542,700):SetText("Payment marks are local notes, not proof of a transfer. LootGoblin never opens trades or moves money.")
    end
    f.title:SetText("Side-bet ledger · "..(M.states[round.state] or round.state))
    local content=f.content
    local lines={A.RecordDate(round.timestamp).." UTC",round.itemLink or round.itemName or "Unknown item",
        "Allowed selected: <= "..round.percent.."%; cutoff: "..round.cutoff.." seconds",
        round.state=="VOID" and ("VOID · "..message(round.reason)) or (round.state=="SETTLED" and "Honor-system settlement; no gold moved by LootGoblin" or "Waiting for friends' bets and the loot result"),"","Bets:"}
    for _,e in ipairs(round.entries) do lines[#lines+1]=name(round,e.bettor).." → "..name(round,e.target).." · "..M.Money(e.stake) end
    if #round.entries==0 then lines[#lines+1]="None" end
    if round.pool then lines[#lines+1]=""; lines[#lines+1]="Pledged pool: "..M.Money(round.pool) end
    if round.winner then lines[#lines+1]="Loot winner: "..name(round,round.winner) end
    if round.reconcile then
        lines[#lines+1]="This round was voided after local paid notes. Reconcile any actual payments manually:"
        for i,p in ipairs(round.priorPayments or {}) do
            if (round.priorPaidLocally or round.paidLocally)[i] then lines[#lines+1]=name(round,p.from).." → "..name(round,p.to).." · "..M.Money(p.amount).." (previously marked paid locally)" end
        end
    end
    f.text:SetText(table.concat(lines,"\n")); local y=#lines*20+12; f.text:SetHeight(y)
    for _,row in ipairs(f.rows) do row:Hide() end
    for i,p in ipairs(round.payments or {}) do
        local row=f.rows[i]
        if not row then
            row=CreateFrame("Frame",nil,content); row:SetSize(670,42)
            row.text=text(row,12,0,0,510); row.text:SetHeight(36)
            row.mark=button(row,"",140,520,0,function() end); f.rows[i]=row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-y); row:Show()
        row.text:SetText(name(round,p.from).." owes "..name(round,p.to).." · "..M.Money(p.amount))
        row.mark:SetText(round.paidLocally[i] and "Locally paid" or "Mark paid locally")
        row.mark:SetScript("OnClick",function()
            round.paidLocally[i]=not round.paidLocally[i]; A.OpenBetRecord(round)
        end)
        y=y+44
    end
    content:SetHeight(math.max(y,100))
    f:Show()
end
function A.InlineBetState(r)
    local state={visible=r.demo or A.bettingAvailable,pool=0}
    if not state.visible then return state end
    if r.demo then
        state.mine=r.demoTotal and {stake=r.demoTotal,targets=r.demoBets} or nil
        state.canBet=not r.finished and not r.dismissed and GetTime()<r.started+r.duration-10
        state.pool=r.demoTotal or 0
        state.reason=not state.canBet and "finished" or nil
        return state
    end
    local context=A.betClient and A.betClient.byRoll[r]
    state.record=context and context.record
    state.pool=state.record and state.record.pool or 0
    local guid=UnitGUID and UnitGUID("player")
    local mine={stake=0,targets={}}
    for _,entry in ipairs(state.record and state.record.entries or {}) do
        if entry.bettor==guid then
            mine.stake=mine.stake+entry.stake
            mine.targets[entry.target]=(mine.targets[entry.target] or 0)+entry.stake
        end
    end
    state.mine=mine.stake>0 and mine or nil
    local snapshot=A.BetSnapshot(r); state.snapshot=snapshot
    if not snapshot then state.reason="data"
    else
        state.canBet,state.reason=M.CanBet({state=state.record and state.record.state or "OPEN",
            percent=math.min(A.db.betPercent,M.PERCENT),cutoff=math.max(A.db.betCutoff,M.CUTOFF),
            closed=r.betClosedReason or (state.record and state.record.closed),closedReason=r.betClosedReason or (state.record and state.record.closedReason),
            rosterKey=state.record and state.record.rosterKey or snapshot.rosterKey},snapshot)
        if state.reason=="threshold" or state.reason=="timer" then r.betClosedReason=state.reason end
        if not snapshot.participants[guid] then state.canBet=false; state.reason="target" end
    end
    return state
end
function A.PlaceInlineBet(r,player,stake)
    if type(stake)~="number" or stake~=stake or stake<1 or stake>M.MAX_MONEY or stake~=math.floor(stake) then
        r.inlineBetError=message("stake"); A.Render(); return false
    end
    local state=A.InlineBetState(r)
    if not state.canBet then r.inlineBetError=message(state.reason); A.Render(); return false end
    local target=player.playerGUID or (r.demo and player.playerName)
    local ok,reason
    if r.demo and target then
        if stake>M.MAX_MONEY-(r.demoTotal or 0) then reason="stake"
        else
            r.demoBets=r.demoBets or {}
            r.demoBets[target]=(r.demoBets[target] or 0)+stake
            r.demoTotal=(r.demoTotal or 0)+stake; ok=true
        end
    elseif A.bettingAvailable and target then ok,reason=A.betClient:Submit(r,target,stake)
    else reason="target" end
    r.inlineBetError=not ok and message(reason) or nil
    A.Render(); return not not ok
end
function A.OpenBets()
    if not A.betWindow then
        local f=panel(); A.betWindow=f; f:SetSize(760,650); f.page=1; f.view="ledger"; f.rows={}
        text(f,15,16,-16,600):SetText("LootGoblin · side-bet ledger")
        button(f,"Close",65,680,-12,function() f:Hide() end)
        text(f,12,16,-53,430):SetText("Place bets directly beside players in the loot table.")
        button(f,"Ledger",75,546,-48,function() f.view="ledger"; A.RenderBets() end)
        button(f,"Rules",75,626,-48,function() f.view="rules"; A.RenderBets() end)
        f.rules=CreateFrame("Frame",nil,f); f.rules:SetAllPoints()
        f.ledger=CreateFrame("Frame",nil,f); f.ledger:SetAllPoints()
        local fields={{"betPercent","My maximum selected percentage (inclusive)",100,0,20},
            {"betCutoff","My minimum remaining seconds",145,10,30}}
        for _,field in ipairs(fields) do
            local key,title,y,min,max=(table.unpack or unpack)(field)
            text(f.rules,12,20,-y,530):SetText(title)
            local box=CreateFrame("EditBox",nil,f.rules,"InputBoxTemplate"); box:SetSize(100,26); box:SetPoint("TOPLEFT",590,-y+5)
            box:SetAutoFocus(false); box:SetMaxLetters(10); box:SetText(tostring(A.db[key]))
            local function save()
                local value=tonumber(box:GetText())
                if value and value==value then
                    value=math.max(min,math.min(max,value)); value=math.floor(value); A.db[key]=value
                end
                box:SetText(tostring(A.db[key])); box:ClearFocus(); A.RenderBets()
            end
            box:SetScript("OnEnterPressed",save); box:SetScript("OnEditFocusLost",function()
                local value=tonumber(box:GetText()); if value and value==value then
                    value=math.max(min,math.min(max,value)); A.db[key]=math.floor(value)
                end
                box:SetText(tostring(A.db[key]))
            end)
        end
        local help=text(f.rules,12,20,-345,690); help:SetHeight(220)
        help:SetText("Shared rules: <=20% selected and more than 10 seconds remaining when a bet is placed. Each client validates its own bet before recording it.\n\nThere is no manual hosting, timed host window, or confirmation step. Bets are shared automatically, and a bettor is selected to resolve the pool in the background. Friends need the same addon version.\n\nClick 1c, 1s, or 1g repeatedly to add stakes to any players until betting closes. Correct bettors split the pledged pool in proportion to their stakes. No correct predictions means pledges are cancelled.\n\nYou may set stricter personal percentage/time limits. Friends do not need matching settings. Loot choices are never held.")
        f.pageText=text(f.ledger,12,20,-100,600)
        button(f.ledger,"<",30,650,-94,function() f.page=math.max(1,f.page-1); A.RenderBets() end)
        button(f.ledger,">",30,688,-94,function() f.page=f.page+1; A.RenderBets() end)
        f.scroll=CreateFrame("ScrollFrame",nil,f.ledger,"UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT",16,-135); f.scroll:SetPoint("BOTTOMRIGHT",-34,70)
        f.content=CreateFrame("Frame",nil,f.scroll); f.content:SetWidth(700); f.scroll:SetScrollChild(f.content)
    end
    A.betWindow:Show(); A.RenderBets()
end
function A.RenderBets()
    local f=A.betWindow; if not f then return end
    f.rules:SetShown(f.view=="rules"); f.ledger:SetShown(f.view=="ledger")
    if f.view=="rules" then return end
    local records=A.db.betLedger.records; local pages=math.max(1,math.ceil(#records/40)); f.page=math.min(pages,f.page)
    f.pageText:SetText(#records.." saved rounds · page "..f.page.."/"..pages.." · click for bets and honor payments")
    for _,row in ipairs(f.rows) do row:Hide() end
    local first=#records-(f.page-1)*40; local shown=0
    for index=first,math.max(1,first-39),-1 do
        local record=records[index]; if record then
            shown=shown+1; local row=f.rows[shown]
            if not row then row=CreateFrame("Button",nil,f.content); row.label=text(row,11,4,-5,680); row.label:SetHeight(35); f.rows[shown]=row end
            row:Show(); row:SetSize(695,42); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(shown-1)*42)
            row.label:SetText(A.RecordDate(record.timestamp).." · "..(record.itemName or "Item").." · "..(M.states[record.state] or record.state).."\n"..#record.entries.." stake positions"..(record.reason and (" · "..message(record.reason)) or ""))
            row:SetScript("OnClick",function() A.OpenBetRecord(record) end)
        end
    end
    f.content:SetHeight(math.max(1,shown*42)); return
end

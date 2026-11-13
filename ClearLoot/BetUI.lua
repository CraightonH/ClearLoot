local _,A=...
local M=A.BetModel
local function panel()
    local f=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    f:SetBackdropColor(0.045,0.06,0.085,1); f:SetBackdropBorderColor(0.3,0.35,0.4,1)
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
        text(f,11,16,-542,700):SetText("Payment marks are local notes, not proof of a transfer. ClearLoot never opens trades or moves money.")
    end
    f.title:SetText("Side-bet ledger · "..(M.states[round.state] or round.state))
    local content=f.content
    local lines={A.RecordDate(round.timestamp).." UTC",round.itemLink or round.itemName or "Unknown item",
        "Coordinator: "..name(round,round.host),"Allowed selected: <= "..round.percent.."%; cutoff: "..round.cutoff.." seconds",
        round.state=="VOID" and ("VOID · "..message(round.reason)) or (round.state=="SETTLED" and "Honor-system settlement; no gold moved by ClearLoot" or "Awaiting a locked book and verified loot result"),"","Accepted bets:"}
    for _,e in ipairs(round.entries) do lines[#lines+1]=name(round,e.bettor).." → "..name(round,e.target).." · "..M.Money(e.stake) end
    if #round.entries==0 then lines[#lines+1]="None" end
    if round.pool then lines[#lines+1]=""; lines[#lines+1]="Pledged pool: "..M.Money(round.pool) end
    if round.winner then lines[#lines+1]="Loot winner: "..name(round,round.winner) end
    if round.reconcile then
        lines[#lines+1]="This round was voided after local paid notes. Reconcile any actual payments manually:"
        for i,p in ipairs(round.priorPayments or {}) do
            if round.paidLocally[i] then lines[#lines+1]=name(round,p.from).." → "..name(round,p.to).." · "..M.Money(p.amount).." (previously marked paid locally)" end
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
function A.OpenBets(roll)
    if not A.betWindow then
        local f=panel(); A.betWindow=f; f:SetSize(760,650); f.page=1; f.view="live"; f.rows={}
        text(f,15,16,-16,600):SetText("ClearLoot · optional side bets")
        button(f,"Close",65,680,-12,function() f:Hide() end)
        f.enable=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate"); f.enable:SetSize(28,28); f.enable:SetPoint("TOPLEFT",14,-47)
        f.enable:SetScript("OnClick",function() A.betClient:SetEnabled(not not f.enable:GetChecked()); A.RenderBets(); A.Render() end)
        text(f,12,46,-53,390):SetText("Enable side bets · honor ledger only")
        button(f,"Live rolls",85,456,-48,function() f.view="live"; A.RenderBets() end)
        button(f,"Ledger",75,546,-48,function() f.view="ledger"; A.RenderBets() end)
        button(f,"Rules",75,626,-48,function() f.view=f.view=="rules" and "live" or "rules"; A.RenderBets() end)
        f.live=CreateFrame("Frame",nil,f); f.live:SetAllPoints(); f.rules=CreateFrame("Frame",nil,f); f.rules:SetAllPoints()
        f.ledger=CreateFrame("Frame",nil,f); f.ledger:SetAllPoints()
        f.item=text(f.live,13,48,-94,630); f.item:SetHeight(32)
        local function move(offset)
            local rolls={}; for _,r in ipairs(A.rolls) do if not r.demo then rolls[#rolls+1]=r end end
            for i,r in ipairs(rolls) do if r==f.roll then f.roll=rolls[math.max(1,math.min(#rolls,i+offset))]; break end end
            A.RenderBets()
        end
        button(f.live,"<",28,14,-92,function() move(-1) end); button(f.live,">",28,714,-92,function() move(1) end)
        f.info=text(f.live,11,16,-133,720); f.info:SetHeight(46)
        f.host=button(f.live,"Host betting window",170,16,-185,function()
            if f.roll then local _,reason=A.betClient:Start(f.roll); f.error=message(reason); A.RenderBets() end
        end)
        f.void=button(f.live,"Void round",110,194,-185,function()
            local c=A.betClient.byRoll[f.roll]; if c and c.record.host==UnitGUID("player") then A.betClient:Void(c,"cancel",true); A.RenderBets() end
        end)
        text(f.live,12,16,-230,130):SetText("Predict loot winner:")
        f.target=button(f.live,"Choose player",310,145,-224,function()
            local targets=f.targets or {}; local index=1
            for i,guid in ipairs(targets) do if guid==f.targetGUID then index=i%#targets+1; break end end
            f.targetGUID=targets[index]; A.RenderBets()
        end)
        text(f.live,12,16,-270,130):SetText("Stake in gold:")
        f.stake=CreateFrame("EditBox",nil,f.live,"InputBoxTemplate"); f.stake:SetSize(110,24); f.stake:SetPoint("TOPLEFT",150,-264)
        f.stake:SetAutoFocus(false); f.stake:SetMaxLetters(12); f.stake:SetText(tostring(A.db.betDefaultGold))
        f.submit=button(f.live,"Place / retry bet",160,280,-264,function()
            local stake=M.ParseGold(f.stake:GetText())
            if not stake then f.error="Enter a positive stake, up to four decimal gold places."
            else local _,reason=A.betClient:Submit(f.roll,f.targetGUID,stake); f.error=message(reason) end
            A.RenderBets()
        end)
        f.status=text(f.live,12,16,-306,720); f.status:SetHeight(42)
        f.book=text(f.live,11,16,-359,710); f.book:SetHeight(225)
        f.book:SetJustifyV("TOP")
        f.note=text(f,11,16,-601,720); f.note:SetHeight(38)
        f.note:SetText("Bets are pledges. Payments are on your honor. No trades, gold collection, balance checks, or auto-payments. Only this addon's loot buttons can be held during the short window.")
        local fields={{"betPercent","Maximum selected percentage (inclusive)",100,0,100},
            {"betCutoff","Stop accepting bets at remaining seconds",145,10,30},
            {"betWindow","Betting window length (seconds)",190,2,20},
            {"betMaxGold","Maximum gold pledged per character",235,1,1000},
            {"betDefaultGold","Default stake in gold",280,0.0001,1000}}
        for _,field in ipairs(fields) do
            local key,title,y,min,max=(table.unpack or unpack)(field)
            text(f.rules,12,20,-y,530):SetText(title)
            local box=CreateFrame("EditBox",nil,f.rules,"InputBoxTemplate"); box:SetSize(100,26); box:SetPoint("TOPLEFT",590,-y+5)
            box:SetAutoFocus(false); box:SetMaxLetters(10); box:SetText(tostring(A.db[key]))
            local function save()
                local value=tonumber(box:GetText())
                if value and value==value then
                    value=math.max(min,math.min(max,value)); if key~="betDefaultGold" then value=math.floor(value) end; A.db[key]=value
                end
                box:SetText(tostring(A.db[key])); box:ClearFocus(); A.RenderBets()
            end
            box:SetScript("OnEnterPressed",save); box:SetScript("OnEditFocusLost",function()
                local value=tonumber(box:GetText()); if value and value==value then
                    value=math.max(min,math.min(max,value)); A.db[key]=key=="betDefaultGold" and value or math.floor(value)
                end
                box:SetText(tostring(A.db[key]))
            end)
        end
        local help=text(f.rules,12,20,-345,690); help:SetHeight(220)
        help:SetText("Defaults: <=20% selected, more than 10 seconds remaining, five-second betting window.\n\nThe coordinator and bettors must enable this module and match percentage, cutoff, and window settings. A new window needs at least window + cutoff + 1 seconds remaining.\n\nOne accepted prediction per character per round. Correct bettors split the pledged pool in proportion to their stakes. No correct predictions means all pledges are cancelled.\n\nRules are frozen per round. Other UI, macros, and non-addon players can still roll early; too many choices during an open window void it.")
        f.pageText=text(f.ledger,12,20,-100,600)
        button(f.ledger,"<",30,650,-94,function() f.page=math.max(1,f.page-1); A.RenderBets() end)
        button(f.ledger,">",30,688,-94,function() f.page=f.page+1; A.RenderBets() end)
        f.scroll=CreateFrame("ScrollFrame",nil,f.ledger,"UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT",16,-135); f.scroll:SetPoint("BOTTOMRIGHT",-34,70)
        f.content=CreateFrame("Frame",nil,f.scroll); f.content:SetWidth(700); f.scroll:SetScrollChild(f.content)
    end
    local f=A.betWindow
    if roll then f.roll=roll; f.view="live" end
    if not f.roll then for _,r in ipairs(A.rolls) do if not r.demo and not r.finished then f.roll=r; break end end end
    f:Show(); A.RenderBets()
end
function A.RenderBets()
    local f=A.betWindow; if not f then return end
    f.enable:SetChecked(A.db.betsEnabled); f.live:SetShown(f.view=="live"); f.rules:SetShown(f.view=="rules"); f.ledger:SetShown(f.view=="ledger")
    if f.view=="rules" then return end
    if f.view=="ledger" then
        local records=A.db.betLedger.records; local pages=math.max(1,math.ceil(#records/40)); f.page=math.min(pages,f.page)
        f.pageText:SetText(#records.." saved rounds · page "..f.page.."/"..pages.." · click for bets and honor payments")
        for _,row in ipairs(f.rows) do row:Hide() end
        local first=#records-(f.page-1)*40; local shown=0
        for index=first,math.max(1,first-39),-1 do
            local record=records[index]; if record then
                shown=shown+1; local row=f.rows[shown]
                if not row then row=CreateFrame("Button",nil,f.content); row.label=text(row,11,4,-5,680); row.label:SetHeight(35); f.rows[shown]=row end
                row:Show(); row:SetSize(695,42); row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(shown-1)*42)
                row.label:SetText(A.RecordDate(record.timestamp).." · "..(record.itemName or "Item").." · "..(M.states[record.state] or record.state).."\n"..#record.entries.." accepted bets"..(record.reason and (" · "..message(record.reason)) or ""))
                row:SetScript("OnClick",function() A.OpenBetRecord(record) end)
            end
        end
        f.content:SetHeight(math.max(1,shown*42)); return
    end
    local r=f.roll; local context=r and A.betClient.byRoll[r]; local round=context and context.record
    local snapshot=r and A.BetSnapshot(r)
    f.item:SetText(r and (r.link or r.name or "Loading item") or "No current real loot roll. Demo rolls never accept side bets.")
    f.info:SetText(not A.bettingAvailable and "This client does not expose the required group addon messaging API." or
        (snapshot and string.format("Selected %d/%d (%.1f%%) · live timer %.1fs\nAllowed <= %d%%; cutoff %ds; window %ds. Other bettors must also enable ClearLoot side bets.",
            snapshot.selected,snapshot.total,100*snapshot.selected/snapshot.total,(snapshot.leftMs or 0)/1000,
            round and round.percent or A.db.betPercent,round and round.cutoff or A.db.betCutoff,A.db.betWindow) or message(r and r.betBlockedReason or "data")))
    f.host:SetEnabled(A.bettingAvailable and A.db.betsEnabled and r~=nil and context==nil and snapshot~=nil and not r.betBlockedReason)
    f.void:SetEnabled(round~=nil and round.host==(UnitGUID and UnitGUID("player")) and (round.state=="OPEN" or round.state=="LOCKED" or round.state=="AWAITING_LOCK"))
    local participants=round and round.participants or snapshot and snapshot.participants or {}
    f.targets={}; for guid in pairs(participants) do f.targets[#f.targets+1]=guid end; table.sort(f.targets)
    if not participants[f.targetGUID] then f.targetGUID=f.targets[1] end
    f.target:SetText(participants[f.targetGUID] or "No eligible targets")
    local can=round and M.CanBet(round,snapshot); f.submit:SetEnabled(A.db.betsEnabled and not not can)
    local status=round and ((M.states[round.state] or round.state).." · "..#round.entries.." accepted · coordinator "..name(round,round.host)) or "No round hosted for this item."
    if round and round.reason then status=status.." · "..message(round.reason) end
    local pending=context and context.pending[UnitGUID and UnitGUID("player")]
    if pending then status=status..(pending.error and (" · "..message(pending.error)) or " · awaiting host acceptance") end
    if f.error and f.error~="" then status=status.."\n"..f.error end
    f.status:SetText(status)
    local lines={"Accepted predictions (one per character; accepted bets cannot be edited):"}
    for i,e in ipairs(round and round.entries or {}) do
        if i<=9 then lines[#lines+1]=name(round,e.bettor).." → "..name(round,e.target).." · "..M.Money(e.stake) end
    end
    if round and #round.entries>9 then lines[#lines+1]="More predictions are available in Ledger → round details." end
    if round and (round.state=="SETTLED" or round.state=="VOID") then lines[#lines+1]="Open Ledger → this round for the saved outcome and honor-payment notes." end
    f.book:SetText(table.concat(lines,"\n"))
end

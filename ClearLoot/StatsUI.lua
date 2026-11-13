local _,A=...
local function label(parent,size)
    local t=parent:CreateFontString(nil,"OVERLAY")
    t:SetFont(STANDARD_TEXT_FONT,size or 12,""); t:SetJustifyH("LEFT"); return t
end
local function panel(parent)
    local f=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1})
    f:SetBackdropColor(0.045,0.06,0.085,1); f:SetBackdropBorderColor(0.3,0.35,0.4,1)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetClampedToScreen(true); return f
end
local function button(parent,text,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate"); b:SetText(text); b:SetSize(width,24)
    b:SetScript("OnClick",fn); return b
end
local function movable(f)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function() f:StartMoving() end)
    f:SetScript("OnDragStop",function() f:StopMovingOrSizing() end)
end
function A.OpenExport(filter)
    if A.exportFrame then A.exportFrame:Hide() end
    local f=panel(UIParent); A.exportFrame=f; f:SetSize(720,500); f:SetPoint("CENTER"); movable(f)
    local title=label(f,14); title:SetPoint("TOPLEFT",16,-16); title:SetText("ClearLoot · copy CSV (Ctrl+A, Ctrl+C)")
    local close=button(f,"Close",65,function() f:Hide() end); close:SetPoint("TOPRIGHT",-12,-12)
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",16,-54); scroll:SetPoint("BOTTOMRIGHT",-34,16)
    local box=CreateFrame("EditBox",nil,scroll); box:SetMultiLine(true); box:SetAutoFocus(false)
    box:SetFont(STANDARD_TEXT_FONT,11,""); box:SetWidth(660); box:SetHeight(400)
    box:SetScript("OnEscapePressed",function() box:ClearFocus() end)
    box:SetScript("OnTextChanged",function(self)
        local lines=0
        for line in ((self:GetText() or "").."\n"):gmatch("(.-)\n") do
            lines=lines+math.max(1,math.ceil(#line/90))
        end
        self:SetHeight(math.max(400,(lines+1)*14))
    end)
    scroll:SetScrollChild(box); box:SetText(A.ExportCSV(A.db,filter)); box:HighlightText(); box:SetFocus()
end
local function detail(record)
    local f=A.detailFrame
    if not f then
        f=panel(UIParent); A.detailFrame=f; f:SetSize(620,500); f:SetPoint("CENTER"); movable(f)
        local close=button(f,"Close",65,function() f:Hide() end); close:SetPoint("TOPRIGHT",-12,-12)
        f.scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT",16,-48); f.scroll:SetPoint("BOTTOMRIGHT",-34,16)
        f.content=CreateFrame("Frame",nil,f.scroll); f.content:SetWidth(560); f.scroll:SetScrollChild(f.content)
        f.text=label(f.content,12); f.text:SetPoint("TOPLEFT"); f.text:SetWidth(550)
    end
    local lines={A.RecordDate(record.timestamp).." UTC",record.itemLink or record.itemName or "Unknown item",
        record.source.name or "Unknown source",record.outcome or "Unconfirmed",""}
    if not record.confirmed then lines[#lines+1]="Excluded from win-rate statistics: outcome/association unconfirmed." end
    for _,p in ipairs(record.participants) do
        lines[#lines+1]=p.name.."  ·  "..(A.labels[p.state] or "Waiting").."  ·  "..tostring(p.roll or "—")..(p.key==record.winnerKey and "  WINNER" or "")
    end
    f.text:SetText(table.concat(lines,"\n")); local height=math.max(80,#lines*20)
    f.text:SetHeight(height); f.content:SetHeight(height); f:Show()
end
function A.OpenHistory(view)
    if not A.statsWindow then
        local f=panel(UIParent); A.statsWindow=f; f:SetSize(820,570); f:SetPoint("CENTER"); movable(f)
        f.view="players"; f.days=0; f.choice="All"; f.groupAliases=false; f.query=""; f.rows={}
        f.title=label(f,15); f.title:SetPoint("TOPLEFT",16,-16); f.title:SetText("ClearLoot · history and roll statistics")
        local close=button(f,"Close",65,function() f:Hide() end); close:SetPoint("TOPRIGHT",-12,-12)
        local players=button(f,"Players",85,function() f.view="players"; f.page=1; A.RenderStats() end); players:SetPoint("TOPLEFT",16,-50)
        local drops=button(f,"Drops",75,function() f.view="drops"; f.page=1; A.RenderStats() end); drops:SetPoint("LEFT",players,"RIGHT",6,0)
        local period
        period=button(f,"All dates",100,function()
            f.days=({[0]=7,[7]=30,[30]=0})[f.days]; f.page=1; period:SetText(f.days==0 and "All dates" or (f.days.." days")); A.RenderStats()
        end); period:SetPoint("LEFT",drops,"RIGHT",12,0)
        local choice
        choice=button(f,"All choices",105,function()
            f.choice=({All="Need",Need="Greed",Greed="Transmog",Transmog="All"})[f.choice]
            f.page=1; choice:SetText(f.choice=="All" and "All choices" or f.choice); A.RenderStats()
        end); choice:SetPoint("LEFT",period,"RIGHT",6,0)
        local grouping
        grouping=button(f,"Characters",120,function()
            f.groupAliases=not f.groupAliases; f.page=1; grouping:SetText(f.groupAliases and "Manual aliases" or "Characters"); A.RenderStats()
        end); grouping:SetPoint("LEFT",choice,"RIGHT",6,0)
        local export=button(f,"Copy CSV",90,function() A.OpenExport({days=f.days,query=f.query}) end)
        export:SetPoint("TOPRIGHT",-16,-50)
        local searchLabel=label(f,11); searchLabel:SetText("Find drops by item / player / source:"); searchLabel:SetPoint("TOPLEFT",16,-90)
        f.search=CreateFrame("EditBox",nil,f,"InputBoxTemplate"); f.search:SetSize(300,24); f.search:SetPoint("TOPLEFT",200,-84)
        f.search:SetAutoFocus(false); f.search:SetMaxLetters(100)
        f.search:SetScript("OnEnterPressed",function(self) f.query=self:GetText(); f.page=1; self:ClearFocus(); A.RenderStats() end)
        local nextPage=button(f,">",28,function() f.page=(f.page or 1)+1; A.RenderStats() end); nextPage:SetPoint("TOPRIGHT",-16,-84)
        local previousPage=button(f,"<",28,function() f.page=(f.page or 1)-1; A.RenderStats() end); previousPage:SetPoint("RIGHT",nextPage,"LEFT",-78,0)
        f.pageText=label(f,11); f.pageText:SetWidth(72); f.pageText:SetPoint("RIGHT",nextPage,"LEFT",-4,0)
        f.coverage=label(f,11); f.coverage:SetPoint("TOPLEFT",16,-121); f.coverage:SetWidth(780); f.coverage:SetHeight(30)
        f.heading=label(f,11); f.heading:SetPoint("TOPLEFT",16,-158); f.heading:SetWidth(780)
        f.scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
        f.scroll:SetPoint("TOPLEFT",12,-182); f.scroll:SetPoint("BOTTOMRIGHT",-32,134)
        f.content=CreateFrame("Frame",nil,f.scroll); f.content:SetWidth(770); f.scroll:SetScrollChild(f.content)
        f.aliasLabel=label(f,11); f.aliasLabel:SetPoint("BOTTOMLEFT",16,102); f.aliasLabel:SetText("Select a character row to assign a shared alt/account label.")
        f.alias=CreateFrame("EditBox",nil,f,"InputBoxTemplate"); f.alias:SetSize(300,24); f.alias:SetPoint("BOTTOMLEFT",20,68)
        f.alias:SetAutoFocus(false); f.alias:SetMaxLetters(64)
        local saveAlias=function()
            if f.selectedCharacter then A.SetAlias(A.db,f.selectedCharacter,f.alias:GetText()); f.alias:ClearFocus(); A.RenderStats() end
        end
        f.alias:SetScript("OnEnterPressed",saveAlias)
        local save=button(f,"Save alias",85,saveAlias); save:SetPoint("LEFT",f.alias,"RIGHT",8,0)
        local remove=button(f,"Remove alias",100,function()
            if f.selectedCharacter then f.alias:SetText(""); saveAlias() end
        end); remove:SetPoint("LEFT",save,"RIGHT",6,0)
        local note=label(f,11); note:SetPoint("BOTTOMLEFT",16,12); note:SetWidth(780); note:SetHeight(43)
        note:SetText("Win rate uses confirmed, contested rolls in the highest eligible choice tier. Passes and lower-priority choices are excluded. Expected wins assumes equal chances within that tier; it is not evidence of bias. Aliases are manual labels, not verified account names.")
    end
    A.statsWindow.view=view or "players"; A.statsWindow.page=1; A.statsWindow:Show(); A.RenderStats()
end
function A.RenderStats()
    local f=A.statsWindow; if not f then return end
    local filter={days=f.days,choice=f.choice,groupAliases=f.groupAliases,query=f.query}
    local list,coverage
    if f.view=="players" then list,coverage=A.ComputeStats(A.db,filter)
    else
        list=A.FilterRecords(A.db,filter)
        local reversed={}; for i=#list,1,-1 do reversed[#reversed+1]=list[i] end; list=reversed
    end
    for _,row in ipairs(f.rows) do row:Hide() end
    f.revision=A.db.lootArchive.revision
    f.coverage:SetText(coverage and string.format("%d recorded drops · %d confirmed · %d unknown · %d incomplete/inconsistent excluded | %s tier filter",
        coverage.records,coverage.confirmed,coverage.unknown,coverage.excluded,f.choice) or
        (#list.." recorded drops · click a row for player choices and rolls · UTC dates · tier filter applies to Players"))
    f.heading:SetText(f.view=="players" and "CHARACTER / ALIAS                  WINS / TRIES       RATE      EXPECTED     SOLO WINS    BEST W / L      ITEMS" or
        "UTC DATE                     ITEM                                             WINNER / OUTCOME")
    local pages=math.max(1,math.ceil(#list/50)); f.page=math.max(1,math.min(pages,f.page or 1))
    f.pageText:SetText(f.page.." / "..pages)
    local first=(f.page-1)*50+1; local last=math.min(#list,first+49)
    for index=first,last do
        local i=index-first+1; local data=list[index]
        local row=f.rows[i]
        if not row then
            row=CreateFrame("Button",nil,f.content); row.cells={}
            local offsets={0,245,335,400,490,580,690}
            for j,x in ipairs(offsets) do
                local t=label(row,11); t:SetPoint("TOPLEFT",x,-5); t:SetWidth(j==1 and 235 or 85); t:SetHeight(22); row.cells[j]=t
            end
            f.rows[i]=row
        end
        row:SetSize(766,30); row:ClearAllPoints(); row:SetPoint("TOPLEFT",4,-(i-1)*30); row:Show()
        for _,t in ipairs(row.cells) do t:SetText("") end
        if f.view=="players" then
            row.cells[1]:SetText(data.name); row.cells[2]:SetText(data.wins.." / "..data.opportunities)
            row.cells[3]:SetText(data.rate and string.format("%.1f%%",data.rate*100) or "—")
            row.cells[4]:SetText(string.format("%.1f",data.expected)); row.cells[5]:SetText(tostring(data.uncontested))
            row.cells[6]:SetText(data.longestWin.." / "..data.longestLoss); row.cells[7]:SetText(tostring(data.items))
            row:SetScript("OnClick",function()
                if f.groupAliases then f.aliasLabel:SetText("Switch to Characters to assign aliases."); return end
                f.selectedCharacter=data.key; f.aliasLabel:SetText("Alias for "..data.name.." (shared label merges alts):")
                f.alias:SetText(A.db.lootArchive.aliases[data.key] or "")
            end)
        else
            row.cells[1]:SetText(A.RecordDate(data.timestamp).."  ·  "..(data.itemName or "Unknown item"))
            row.cells[2]:SetText(data.winnerName or "—"); row.cells[4]:SetText(data.outcome or "Unknown")
            row:SetScript("OnClick",function() detail(data) end)
        end
    end
    f.content:SetHeight(math.max(1,(last-first+1)*30))
end
function A.RefreshStatsIfVisible()
    local f=A.statsWindow
    if f and f:IsShown() and f.revision~=A.db.lootArchive.revision then A.RenderStats() end
end

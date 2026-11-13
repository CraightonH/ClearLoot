local _,A=...
local function epoch() return time and time() or 0 end
local function realmName()
    return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "UnknownRealm"
end
function A.InitHistory(db)
    if type(db.lootArchive)~="table" then db.lootArchive={} end
    local h=db.lootArchive
    h.version=1
    if type(h.records)~="table" then h.records={} end
    if type(h.nextID)~="number" then h.nextID=1 end
    if type(h.aliases)~="table" then h.aliases={} end
    if type(db.archiveLimit)~="number" then db.archiveLimit=5000 end
    db.archiveLimit=math.floor(math.max(100,math.min(50000,db.archiveLimit)))
    h.revision=h.revision or 0
    A.PruneArchive(db)
    return h
end
function A.PruneArchive(db)
    local h=db.lootArchive
    db.archiveLimit=math.floor(db.archiveLimit)
    local excess=#h.records-db.archiveLimit
    if excess>0 then
        local keep={}
        for i=math.floor(excess)+1,#h.records do keep[#keep+1]=h.records[i] end
        h.records=keep; h.revision=h.revision+1
    end
end
function A.CharacterIdentity(p,realm)
    local full=p.playerName or "Unknown"
    local name,fromRealm=full:match("^([^%-]+)%-(.+)$")
    name=name or full; fromRealm=fromRealm or realm or realmName()
    local display=name.."-"..fromRealm
    local key=p.playerGUID or ("name:"..display:lower():gsub("[%s']",""))
    return key,display
end
function A.StartRecord(r)
    r.wallStarted=epoch(); r.realm=realmName()
    if GetInstanceInfo then
        local name,kind,difficulty,_,_,_,_,instanceID=GetInstanceInfo()
        r.source={name=name or "Unknown",kind=kind,difficultyID=difficulty,instanceID=instanceID}
    else r.source={name="Unknown"} end
    if UnitGUID then r.observerGUID=UnitGUID("player") end
end
function A.RecordRoll(db,r,forceUncertain)
    if r.demo or (not r.finished and not forceUncertain) then return end
    local h=db.lootArchive; if not h then return end
    local record={id=r.archiveID,timestamp=r.wallStarted or epoch(),itemLink=r.link,itemName=r.name,
        source=A.Copy(r.source or {}),observerGUID=r.observerGUID,rollID=r.id,
        encounterID=r.encounterID,dropKey=r.lootListKey,outcome=r.status,
        confirmed=not forceUncertain and r.resultConfirmed==true and not r.ambiguous,
        allPassed=r.status=="Everyone passed",uncertainty=r.match,participants={}}
    if forceUncertain then record.outcome="Association uncertain" end
    local signature={tostring(record.outcome),tostring(record.confirmed),tostring(record.itemLink),tostring(record.itemName)}
    if not forceUncertain then
        for _,p in ipairs(r.rows) do
            local key,name=A.CharacterIdentity(p,r.realm)
            local row={key=key,name=name,playerClass=p.playerClass,state=p.state,roll=p.roll,isSelf=p.isSelf,
                isWinner=p.isWinner or (r.winner and ((r.winner.playerGUID and r.winner.playerGUID==p.playerGUID) or
                    (not r.winner.playerGUID and r.winner.playerName==p.playerName)))}
            record.participants[#record.participants+1]=row
            if row.isWinner then record.winnerKey=key; record.winnerName=name end
            signature[#signature+1]=table.concat({key,tostring(p.state),tostring(p.roll),tostring(row.isWinner)},"|")
        end
    end
    signature=table.concat(signature,";")
    if signature==r.archiveSignature then return r.archiveID end
    r.archiveSignature=signature
    local found
    if r.archiveID then
        for i,old in ipairs(h.records) do if old.id==r.archiveID then found=i; break end end
        -- The user may have pruned this record already; don't resurrect it.
        if not found then return end
    else
        record.id=h.nextID; h.nextID=h.nextID+1; r.archiveID=record.id
    end
    if found then h.records[found]=record else h.records[#h.records+1]=record end
    h.revision=h.revision+1; A.PruneArchive(db)
    return record.id
end
function A.SetAlias(db,key,label)
    label=(label or ""):match("^%s*(.-)%s*$"):sub(1,64)
    db.lootArchive.aliases[key]=label~="" and label or nil
    db.lootArchive.revision=db.lootArchive.revision+1
end
local tiers={[0]=1,[1]=2,[2]=3,[3]=4}
local function choiceIncluded(state,filter)
    return not filter or filter=="All" or (filter=="Need" and (state==0 or state==1)) or
        (filter=="Greed" and state==3) or (filter=="Transmog" and state==2)
end
function A.FilterRecords(db,filter)
    filter=filter or {}; local rows={}; local now=filter.now or epoch()
    local cutoff=filter.days and filter.days>0 and now-filter.days*86400 or 0
    local query=(filter.query or ""):lower()
    for _,record in ipairs(db.lootArchive.records) do
        if (record.timestamp or 0)>=cutoff then
            local match=query==""
            local haystack=(record.itemName or "").." "..(record.itemLink or "").." "..(record.winnerName or "").." "..(record.source.name or "")
            for _,p in ipairs(record.participants) do
                haystack=haystack.." "..p.name.." "..(db.lootArchive.aliases[p.key] or "")
            end
            if haystack:lower():find(query,1,true) then match=true end
            if match then rows[#rows+1]=record end
        end
    end
    table.sort(rows,function(a,b) if a.timestamp==b.timestamp then return a.id<b.id end; return a.timestamp<b.timestamp end)
    return rows
end
function A.ComputeStats(db,filter)
    filter=filter or {}; local byKey={}; local coverage={records=0,confirmed=0,unknown=0,excluded=0}
    local function identity(p)
        local alias=filter.groupAliases and db.lootArchive.aliases[p.key]
        return alias and ("alias:"..alias:lower()) or p.key,alias or p.name
    end
    local function get(p)
        local key,name=identity(p); local s=byKey[key]
        if not s then
            s={key=key,name=name,wins=0,opportunities=0,expected=0,uncontested=0,items=0,passes=0,
                appearances=0,winStreak=0,lossStreak=0,longestWin=0,longestLoss=0,characters={}}
            byKey[key]=s
        end
        s.characters[p.key]=p.name; return s
    end
    for _,r in ipairs(A.FilterRecords(db,filter)) do
        coverage.records=coverage.records+1
        if not r.confirmed then coverage.unknown=coverage.unknown+1
        else
            coverage.confirmed=coverage.confirmed+1
            local best=99; local winner; local complete=#r.participants>0
            for _,p in ipairs(r.participants) do
                if (tiers[p.state] or 99)<best then best=tiers[p.state] end
                if p.key==r.winnerKey then winner=p end
                if p.state==nil or p.state==4 then complete=false end
            end
            local pool={}
            for _,p in ipairs(r.participants) do if best<99 and tiers[p.state]==best then pool[#pool+1]=p end end
            local valid=complete and winner and tiers[winner.state]==best
            local groups={}
            for _,p in ipairs(r.participants) do
                local s=get(p)
                local g=groups[s.key] or {s=s,eligible=0,win=false,passed=false}
                groups[s.key]=g
                if p.state==5 then g.passed=true end
                if r.winnerKey==p.key then s.items=s.items+1 end
                if valid and tiers[p.state]==best then g.eligible=g.eligible+1 end
                if r.winnerKey==p.key then g.win=true end
            end
            for _,g in pairs(groups) do
                g.s.appearances=g.s.appearances+1
                if g.passed then g.s.passes=g.s.passes+1 end
            end
            if valid and choiceIncluded(winner.state,filter.choice) then
                for _,g in pairs(groups) do
                    local s=g.s
                    if g.eligible>0 then
                        if #pool==1 then if g.win then s.uncontested=s.uncontested+1 end
                        else
                            s.opportunities=s.opportunities+1
                            s.expected=s.expected+g.eligible/#pool
                            if g.win then
                                s.wins=s.wins+1; s.winStreak=s.winStreak+1; s.lossStreak=0
                                s.longestWin=math.max(s.longestWin,s.winStreak)
                            else
                                s.lossStreak=s.lossStreak+1; s.winStreak=0
                                s.longestLoss=math.max(s.longestLoss,s.lossStreak)
                            end
                        end
                    end
                end
            elseif not r.allPassed and not valid then coverage.excluded=coverage.excluded+1 end
        end
    end
    local rows={}
    for _,s in pairs(byKey) do
        s.rate=s.opportunities>0 and s.wins/s.opportunities or nil
        s.delta=s.wins-s.expected; rows[#rows+1]=s
    end
    table.sort(rows,function(a,b)
        if a.opportunities~=b.opportunities then return a.opportunities>b.opportunities end
        return a.name<b.name
    end)
    return rows,coverage
end
function A.RecordDate(timestamp)
    return date and date("!%Y-%m-%d %H:%M",timestamp) or tostring(timestamp)
end
function A.ExportCSV(db,filter)
    local function cell(value)
        local s=tostring(value or "")
        if type(value)=="string" and s:find("^[=+@%-]") then s="'"..s end
        return '"'..s:gsub('"','""')..'"'
    end
    local output={"record_id,utc,item,item_link,source,difficulty,confirmed,outcome,character_key,character,alias,choice,roll,winner"}
    for _,r in ipairs(A.FilterRecords(db,filter)) do
        local participants=#r.participants>0 and r.participants or {{}}
        for _,p in ipairs(participants) do
            local fields={r.id,A.RecordDate(r.timestamp),r.itemName or "",r.itemLink or "",r.source.name or "",r.source.difficultyID or "",
                tostring(r.confirmed),r.outcome or "",p.key or "",p.name or "",db.lootArchive.aliases[p.key] or "",
                A.labels[p.state] or "Unknown",p.roll or "",tostring(p.key~=nil and p.key==r.winnerKey)}
            for i,v in ipairs(fields) do fields[i]=cell(v) end
            output[#output+1]=table.concat(fields,",")
        end
    end
    return table.concat(output,"\n")
end

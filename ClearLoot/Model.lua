local _, A = ...
A.defaults = {layout="stack", closeAfter=20, scale=1, width=400, rowHeight=18,
    opacity=0.96, locked=false, pauseHover=true, showPassed=true, classColors=true,
    sort="priority", replaceNative=true, historyLimit=60, x=0, y=180,
    maxHeight=650, sound=false, fontSize=11, compact=true, groupSeparators=true}
A.labels = {[0]="Need", [1]="Need (off spec)", [2]="Transmog", [3]="Greed",
    [4]="Waiting", [5]="Pass"}
A.colors = {[0]="73c7ff", [1]="73c7ff", [2]="d6a2ff", [3]="ffce70",
    [4]="929eaf", [5]="929eaf"}
local priority = {[0]=1,[1]=2,[2]=3,[3]=4,[5]=5,[4]=6}
function A.RollGroup(state)
    if state==0 or state==1 then return "Need" end
    return ({[2]="Transmog",[3]="Greed",[5]="Pass"})[state] or "Waiting"
end
function A.Completion(r)
    local chosen,total=0,#r.rows
    for _,p in ipairs(r.rows) do
        if p.state==0 or p.state==1 or p.state==2 or p.state==3 or p.state==5 then chosen=chosen+1 end
    end
    return chosen,total,total>0 and chosen==total
end
function A.Copy(t)
    local out = {}
    for k,v in pairs(t or {}) do out[k] = type(v)=="table" and A.Copy(v) or v end
    return out
end
function A.InitDB(db)
    db = type(db)=="table" and db or {}
    for k,v in pairs(A.defaults) do
        if type(db[k])~=type(v) then db[k]=v end
    end
    if db.layout~="stack" and db.layout~="tabs" and db.layout~="windows" then db.layout="stack" end
    local ranges={closeAfter={0,300},scale={0.65,1.6},width={380,650},rowHeight={18,32},
        opacity={0.4,1},historyLimit={10,200},maxHeight={300,900},fontSize={10,18},x={-4000,4000},y={-4000,4000}}
    for k,r in pairs(ranges) do
        if db[k]~=db[k] then db[k]=A.defaults[k] end
        db[k]=math.max(r[1],math.min(r[2],db[k]))
    end
    return db
end
function A.NewRoll(id, link, now, duration, historyNow)
    return {id=id,link=link,started=now,historyStarted=historyNow,duration=duration,
        rows={},status="Rolling",match="Waiting for loot history",choice=nil}
end
-- Only a unique pair is safe. Never match two identical copies by arrival order.
-- A previous drop with the same hyperlink must not be reused for a new roll.
function A.Match(rolls, drops)
    local claimed={}
    for _,r in ipairs(rolls) do if r.key then claimed[r.key]=true end end
    local candidates, counts = {}, {}
    for _,r in ipairs(rolls) do
        if not r.key and not r.demo and not r.finished and not r.ambiguous then
            local list={}
            for _,d in ipairs(drops) do
                local key=tostring(d.encounterID)..":"..tostring(d.lootListKey or d.lootListID)
                if not claimed[key] and r.link and d.itemHyperlink==r.link
                    and type(d.startTime)=="number" and r.historyStarted
                    and math.abs(d.startTime-r.historyStarted)<=4 then
                    list[#list+1]={key=key,drop=d}
                    counts[key]=(counts[key] or 0)+1
                end
            end
            candidates[r]=list
        end
    end
    for r,list in pairs(candidates) do
        if #list==1 and counts[list[1].key]==1 then
            r.key=list[1].key; r.encounterID=list[1].drop.encounterID
            r.lootListKey=list[1].drop.lootListKey or list[1].drop.lootListID; r.match=nil
        elseif #list>0 then
            r.match="Identical drops: history association uncertain"
        end
    end
end
function A.ApplyDrop(r,d,now)
    r.rows=A.Copy(d.rollInfos or {})
    r.waiting=0
    local winner, own = d.winner, nil
    for _,p in ipairs(r.rows) do
        if p.state==4 or p.state==nil then r.waiting=r.waiting+1 end
        if p.isWinner then winner=p end
        if p.isSelf then own=p end
    end
    if own then r.choice=({[0]=1,[1]=1,[2]=4,[3]=2,[5]=0})[own.state] end
    -- The winner flag on a player is authoritative. Never infer from the highest
    -- visible roll, from currentLeader, a zero timer, or a missing win toast.
    if winner or d.allPassed then
        if not r.resultConfirmed then r.finished=now; r.dismissed=false end
        r.resultConfirmed=true
        r.winner=winner
        if d.allPassed then r.status="Everyone passed"
        elseif winner.isSelf then r.status="You won"
        elseif own and own.state==5 then r.status="You passed"
        elseif own then r.status="You lost"
        else r.status="Roll complete" end
    elseif not r.finished then
        r.status=r.waiting>0 and "Rolling" or "Resolving"
    end
end
function A.SortedRows(r,db)
    local rows={}
    for _,p in ipairs(r.rows) do
        if db.showPassed or p.state~=5 then rows[#rows+1]=p end
    end
    table.sort(rows,function(a,b)
        if db.sort=="name" then return (a.playerName or "")<(b.playerName or "") end
        local ap,bp=priority[a.state] or 6,priority[b.state] or 6
        if ap~=bp then return ap<bp end
        if (a.roll or -1)~=(b.roll or -1) then return (a.roll or -1)>(b.roll or -1) end
        if (not not a.isWinner)~=(not not b.isWinner) then return not not a.isWinner end
        return (a.playerName or "")<(b.playerName or "")
    end)
    return rows
end
function A.ShouldClose(r,db,now,hovered)
    if r.pinned or not r.finished or db.closeAfter==0 then return false end
    if db.pauseHover and hovered then r.lastHover=now; return false end
    return now-math.max(r.finished,r.lastHover or 0)>=db.closeAfter
end

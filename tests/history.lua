local base=os.getenv("CLEARLOOT_ADDON") or "ClearLoot"
local A={}
assert(loadfile(base.."/Model.lua"))("ClearLoot",A)
assert(loadfile(base.."/History.lua"))("ClearLoot",A)
local now=1800000000
function time() return now end
function date(fmt,n) return os.date(fmt,n) end
function GetNormalizedRealmName() return "TestRealm" end
local count=0
local function test(name,fn) fn(); count=count+1; print("PASS "..name) end
local function db() local d=A.InitDB({}); A.InitHistory(d); return d end
local function row(name,state,roll,winner) return {playerGUID="Player-1-"..name,playerName=name,playerClass="MAGE",state=state,roll=roll,isWinner=winner} end
local function record(d,rows,allPassed)
    local r=A.NewRoll(d.lootArchive.nextID,"item:a",100,60,100)
    r.name="Sword"; A.StartRecord(r)
    A.ApplyDrop(r,{rollInfos=rows,allPassed=allPassed},150); A.RecordRoll(d,r); return r
end
local function stats(d,filter)
    local list,coverage=A.ComputeStats(d,filter); local out={}
    for _,s in ipairs(list) do out[s.name]=s end
    return out,coverage
end
test("persistent archive survives initialization and contains source identities",function()
    local d=db(); record(d,{row("A",0,90,true),row("B",0,10)})
    A.InitHistory(d); assert(#d.lootArchive.records==1)
    assert(d.lootArchive.records[1].participants[1].name=="A-TestRealm")
    assert(d.lootArchive.records[1].participants[1].key=="Player-1-A")
end)
test("Need against Greed is uncontested; greed never counts as a loss",function()
    local d=db(); record(d,{row("A",0,1,true),row("B",3,99)})
    local s=stats(d)
    assert(s["A-TestRealm"].uncontested==1 and s["A-TestRealm"].opportunities==0)
    assert(s["B-TestRealm"].opportunities==0 and s["B-TestRealm"].lossStreak==0)
end)
test("contested rates, expected wins and streaks use eligible outcomes only",function()
    local d=db()
    for i=1,3 do
        now=now+1; record(d,{row("A",0,20),row("B",0,90,true),row("C",3,100),row("D",5)})
    end
    local s=stats(d)
    assert(s["A-TestRealm"].opportunities==3 and s["A-TestRealm"].wins==0)
    assert(s["A-TestRealm"].longestLoss==3 and s["A-TestRealm"].expected==1.5)
    assert(s["B-TestRealm"].wins==3 and s["B-TestRealm"].longestWin==3)
    assert(s["C-TestRealm"].opportunities==0 and s["D-TestRealm"].passes==3)
end)
test("unknown and contradictory results never pollute win rates",function()
    local d=db(); local r=A.NewRoll(1,"item:x",100,60,100); r.finished=180; r.status="Outcome unconfirmed"
    A.RecordRoll(d,r)
    record(d,{row("A",0,99),row("B",3,1,true)})
    local s,c=stats(d)
    assert(c.unknown==1 and c.excluded==1)
    assert(s["A-TestRealm"].opportunities==0 and s["B-TestRealm"].opportunities==0)
end)
test("late winner updates a record in place instead of double counting",function()
    local d=db(); local r=A.NewRoll(1,"item:x",100,60,100); r.finished=180; r.status="Outcome unconfirmed"
    A.RecordRoll(d,r); A.RecordRoll(d,r); assert(#d.lootArchive.records==1)
    A.ApplyDrop(r,{rollInfos={row("A",0,90,true),row("B",0,20)}},200)
    A.RecordRoll(d,r); A.RecordRoll(d,r)
    assert(#d.lootArchive.records==1 and d.lootArchive.records[1].confirmed)
    local s=stats(d); assert(s["A-TestRealm"].wins==1)
end)
test("duplicate-item ambiguity invalidates a previous statistical win",function()
    local d=db(); local r=record(d,{row("A",0,90,true),row("B",0,10)})
    A.RecordRoll(d,r,true)
    local s,c=stats(d); assert(next(s)==nil and c.unknown==1 and #d.lootArchive.records==1)
end)
test("aliases group alts while retaining character identities",function()
    local d=db()
    record(d,{row("A",0,90,true),row("B",0,10)})
    record(d,{row("AltA",3,90,true),row("B",3,10)})
    A.SetAlias(d,"Player-1-A","Alex"); A.SetAlias(d,"Player-1-AltA","Alex")
    local s=stats(d,{groupAliases=true}); assert(s.Alex.wins==2 and s.Alex.opportunities==2 and s.Alex.expected==1)
    s=stats(d); assert(s["A-TestRealm"].wins==1 and s["AltA-TestRealm"].wins==1)
    assert(d.lootArchive.records[1].participants[1].key=="Player-1-A")
end)
test("Need and Greed date filters produce independent samples",function()
    local d=db(); record(d,{row("A",0,90,true),row("B",0,10)})
    now=now+31*86400; record(d,{row("A",3,90,true),row("B",3,10)})
    local s=stats(d,{choice="Need"}); assert(s["A-TestRealm"].wins==1)
    s=stats(d,{choice="Greed"}); assert(s["A-TestRealm"].wins==1)
    s=stats(d,{days=7,now=now}); assert(s["A-TestRealm"].wins==1 and s["A-TestRealm"].opportunities==1)
end)
test("all-pass and previews never become wins or losses",function()
    local d=db(); record(d,{row("A",5),row("B",5)},true)
    local r=record(d,{row("C",0,90,true),row("D",0,10)}); local n=#d.lootArchive.records
    r.archiveID=nil; r.archiveSignature=nil; r.demo=true; A.RecordRoll(d,r)
    assert(#d.lootArchive.records==n)
    local s=stats(d); assert(s["A-TestRealm"].passes==1 and s["A-TestRealm"].opportunities==0)
end)
test("CSV preserves participant rows and neutralizes spreadsheet formulas",function()
    local d=db(); record(d,{row("A",0,90,true),row("B",0,10)})
    A.SetAlias(d,"Player-1-A","=SUM(1,2)")
    local csv=A.ExportCSV(d)
    assert(csv:find("record_id",1,true) and csv:find("'=SUM(1,2)",1,true))
    local n=0; for _ in csv:gmatch("\n") do n=n+1 end; assert(n==2)
end)
test("retention is independent of session frames and removes oldest records",function()
    local d=db(); d.archiveLimit=2
    for i=1,4 do now=now+1; record(d,{row("A",0,i,true),row("B",0,0)}) end
    assert(#d.lootArchive.records==2 and d.lootArchive.records[1].id==3 and d.lootArchive.nextID==5)
end)
test("same names on different realms stay distinct without a GUID",function()
    local a=A.CharacterIdentity({playerName="Alex-One"}); local b=A.CharacterIdentity({playerName="Alex-Two"})
    assert(a~=b)
end)
print(count.." persistent-history scenarios passed")

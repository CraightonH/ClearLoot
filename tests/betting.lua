local base=os.getenv("CLEARLOOT_ADDON") or "ClearLoot"
local A={}
assert(loadfile(base.."/Model.lua"))("ClearLoot",A)
assert(loadfile(base.."/BetModel.lua"))("ClearLoot",A)
assert(loadfile(base.."/BetComms.lua"))("ClearLoot",A)
local M=A.BetModel; local count=0
local function test(name,fn) fn(); count=count+1; print("PASS "..name) end
local function snapshot(n,selected,left)
    local participants={}; for i=1,n do participants["P"..i]="Player"..i end
    return {total=n,selected=selected or 0,leftMs=left or 60000,participants=participants,
        rosterKey=M.RosterKey(participants),itemKey="42"}
end
local function new(n)
    local s=snapshot(n or 5)
    return assert(M.New("round","P1",s,{percent=20,cutoff=10,window=5,maxStake=10000000},1)),s
end
test("inclusive 20% thresholds apply to 5, 10, 20, and 40 eligible rollers",function()
    for _,n in ipairs({5,10,20,40}) do
        assert(M.Available(snapshot(n,n/5),20))
        local ok,reason=M.Available(snapshot(n,n/5+1),20); assert(not ok and reason=="threshold")
    end
    assert(not M.Available(snapshot(4,1),20)); assert(M.Available(snapshot(4,0),20))
end)
test("missing data, unknown counts and short time windows fail closed",function()
    assert(not M.Available(nil,20)); assert(not M.Available(snapshot(0),20))
    local s=snapshot(5); s.selected=nil; assert(not M.Available(s,20))
    local _,reason=M.New("r","P1",snapshot(5,0,16000),{percent=20,cutoff=10,window=5,maxStake=100},1)
    assert(reason=="short")
end)
test("the receipt-side server cutoff rejects at exactly ten seconds",function()
    local r,s=new(); s.leftMs=10000
    local e,reason=M.Accept(r,s,"P1","P2",100,"n1"); assert(not e and reason=="timer" and #r.entries==0)
end)
test("bets are acknowledged once, with replay protection and immutable amounts",function()
    local r,s=new()
    assert(M.Accept(r,s,"P1","P2",100,"n1"))
    assert(M.Accept(r,s,"P1","P2",100,"n1")); assert(#r.entries==1)
    local e,reason=M.Accept(r,s,"P1","P3",200,"n2"); assert(not e and reason=="duplicate")
    assert(not M.Accept(r,s,"P2","outsider",100,"n3"))
    assert(not M.Accept(r,s,"P2","P3",100.5,"n4"))
end)
test("a locked book cannot receive additional entries",function()
    local r,s=new(); assert(M.Accept(r,s,"P1","P2",100,"n1"))
    assert(M.Lock(r,1,M.Digest(r)))
    assert(not M.ApplyEntry(r,{seq=2,bettor="P2",target="P2",stake=100,nonce="n2"}))
    s.selected=5; assert(not M.Accept(r,s,"P2","P2",100,"n2"))
    assert(r.state=="LOCKED")
end)
test("proportional winnings and copper rounding conserve every pledged coin",function()
    local r,s=new()
    M.Accept(r,s,"P1","P5",1,"1"); M.Accept(r,s,"P2","P5",2,"2"); M.Accept(r,s,"P3","P4",7,"3")
    assert(M.Lock(r,3,M.Digest(r))); assert(M.Settle(r,"P5"))
    assert(r.pool==10 and r.balances.P1==2 and r.balances.P2==5 and r.balances.P3==-7)
    local total,paid=0,0
    for _,v in pairs(r.balances) do total=total+v end
    for _,p in ipairs(r.payments) do paid=paid+p.amount end
    assert(total==0 and paid==7)
end)
test("nobody correct and single-bettor pools cancel all pledges",function()
    local r,s=new(); M.Accept(r,s,"P1","P2",100,"1"); M.Accept(r,s,"P2","P3",100,"2")
    M.Lock(r,2,M.Digest(r)); local _,reason=M.Settle(r,"P4"); assert(reason=="none" and r.state=="VOID" and #r.payments==0)
    r,s=new(); M.Accept(r,s,"P1","P2",100,"1"); M.Lock(r,1,M.Digest(r)); _,reason=M.Settle(r,"P2"); assert(reason=="few")
end)
test("gold parsing is exact to copper and rejects malformed or excessive stakes",function()
    assert(M.ParseGold("5.0001")==50001 and M.ParseGold("0.0001")==1)
    assert(not M.ParseGold("0") and not M.ParseGold("-1") and not M.ParseGold("nan") and not M.ParseGold("1e3"))
    assert(not M.ParseGold("1001") and not M.ParseGold("0.00001"))
end)
test("maximum-size raid pools settle deterministically without precision loss",function()
    local r,s=new(40)
    for i=1,40 do M.Accept(r,s,"P"..i,i<=13 and "P40" or "P39",10000000-i,tostring(i)) end
    M.Lock(r,40,M.Digest(r)); assert(M.Settle(r,"P40"))
    local sum=0; for _,v in pairs(r.balances) do assert(v==math.floor(v)); sum=sum+v end; assert(sum==0)
end)

local function network(size)
    local N={clock=0,members={},nodes={},bus={},selected=0,disconnected={},winner=nil}
    N.total=math.max(5,size)
    for i=1,N.total do N.members["P"..i]="Player"..i end
    for i=1,size do
        local key="P"..i; local db=A.InitDB({betsEnabled=true}); local roll={id=i,name="Sword",link="item:42",key="matched"}
        local env={now=function() return N.clock end,wall=function() return 1800000000 end,selfGUID=function() return key end,
            members=function() return N.members end,rolls=function() return {roll} end,
            snapshot=function()
                if N.missing or roll.ambiguous then return nil end
                local s=snapshot(N.total,N.selected,N.left or (60000-N.clock*1000))
                s.itemKey=M.ItemKey(roll.link)
                s.finished=N.finished or N.winner~=nil; s.confirmed=N.winner~=nil; s.winner=N.winner; s.allPassed=N.allPassed
                return s
            end,
            send=function(message)
                N.bus[#N.bus+1]={sender=key,message=message}; return true
            end}
        local client=A.NewBetClient(db,env)
        N.nodes[key]={client=client,db=db,roll=roll}; client:Hello(true)
    end
    function N:step(dt)
        self.clock=self.clock+dt
        for key,node in pairs(self.nodes) do if not self.disconnected[key] then node.client:Tick() end end
        local bus=self.bus; self.bus={}
        for _,packet in ipairs(bus) do
            for key,node in pairs(self.nodes) do
                if not self.disconnected[key] and (not self.drop or not self.drop(packet,key)) then node.client:Receive(packet.sender,packet.message) end
            end
        end
    end
    function N:advance(seconds) for i=1,math.ceil(seconds/0.1) do self:step(0.1) end end
    N:advance(0.5)
    return N
end
local function host(n)
    local a=n.nodes.P1; local r,reason=a.client:Start(a.roll); assert(r,reason)
    n:advance(0.3); return r
end
local function place(n,bettor,target,amount)
    local node=n.nodes[bettor]; local ok,reason=node.client:Submit(node.roll,target,amount); assert(ok,reason)
end
test("two addon peers share bets, lock a complete book, and settle identical honor debts",function()
    local n=network(2); local r=host(n)
    place(n,"P1","P3",50000); place(n,"P2","P4",50000); n:advance(0.5)
    assert(#r.entries==2)
    n:advance(5); assert(r.state=="LOCKED")
    n.selected=5; n.winner="P3"; n:advance(1)
    local other=n.nodes.P2.client.byRoll[n.nodes.P2.roll].record
    assert(r.state=="SETTLED" and other.state=="SETTLED")
    assert(r.digest==other.digest and r.payments[1].amount==50000 and r.payments[1].from=="P2")
end)
test("one of five choosing is allowed; two of five void an open round",function()
    local n=network(2); n.selected=1; local r=host(n)
    place(n,"P1","P3",100); n:advance(0.2); n.selected=2; n:advance(0.5)
    assert(r.state=="VOID" and r.reason=="threshold")
    assert(n.nodes.P2.client.byRoll[n.nodes.P2.roll].record.state=="VOID")
    local ok=n.nodes.P2.client:Submit(n.nodes.P2.roll,"P3",100); assert(not ok)
end)
test("a message received after the server cutoff cannot sneak into the book",function()
    local n=network(2); local r=host(n)
    local request="BET|1|"..r.id.."|late|P3|100"
    n.left=10000
    n.nodes.P1.client:Receive("P2",request)
    assert(#r.entries==0)
end)
test("a late request cannot void an already expired betting window using later loot choices",function()
    local n=network(2); local r=host(n)
    place(n,"P1","P3",100); place(n,"P2","P4",100); n:advance(0.5)
    n.left=10000; n.selected=5
    n.nodes.P1.client:Receive("P2","BET|1|"..r.id.."|late|P3|200")
    assert(r.state=="LOCKED" and #r.entries==2)
end)
test("an instant loot result cannot disguise an invalid open window as a timer cutoff",function()
    local n=network(2); local r=host(n)
    place(n,"P1","P3",100); place(n,"P2","P4",100); n:advance(0.5)
    n.left=0; n.selected=5; n.winner="P3"; n:advance(0.5)
    assert(r.state=="VOID" and #r.payments==0)
end)
test("normal results after the betting deadline do not void a client whose next tick is delayed",function()
    local n=network(2); local r=host(n)
    place(n,"P1","P3",100); place(n,"P2","P4",100); n:advance(0.5)
    n.clock=n.clock+6; n.left=0; n.selected=5; n.winner="P3"; n:advance(2)
    assert(r.state=="SETTLED" and n.nodes.P2.client.byRoll[n.nodes.P2.roll].record.state=="SETTLED")
end)
test("lost entry delivery is recovered before the locked book can settle",function()
    local n=network(2); local r=host(n); local dropped=false
    n.drop=function(packet,key)
        if key=="P2" and packet.message:match("^ENTRY|") and not dropped then dropped=true; return true end
    end
    place(n,"P1","P3",100); place(n,"P2","P4",100); n:advance(1)
    n:advance(5); n.winner="P3"; n.selected=5; n:advance(2)
    local other=n.nodes.P2.client.byRoll[n.nodes.P2.roll].record
    assert(dropped and r.state=="SETTLED" and other.state=="SETTLED" and #other.entries==2)
end)
test("unknown senders, unsupported schemas, and non-host book entries are ignored",function()
    local n=network(3); local r=host(n); local c=n.nodes.P2.client
    c:Receive("outsider","VOID|1|"..r.id.."|cancel")
    c:Receive("P1","VOID|2|"..r.id.."|cancel")
    c:Receive("P3","ENTRY|1|"..r.id.."|1|P3|P4|100|fake")
    assert(c.byRoll[n.nodes.P2.roll].record.state=="OPEN" and #r.entries==0)
end)
test("a coordinator cannot invent a local player's pledge without their submission",function()
    local n=network(2); local r=host(n); local peer=n.nodes.P2
    peer.client:Receive("P1","ENTRY|1|"..r.id.."|1|P2|P3|100|invented")
    assert(peer.client.byRoll[peer.roll].record.state=="VOID")
    n:advance(0.5); assert(r.state=="VOID")
end)
test("unacknowledged books never produce honor debts, even after a winner appears",function()
    local n=network(2); local r=host(n)
    n.drop=function(packet,key) return key=="P1" and packet.sender=="P2" and packet.message:match("^ACK|") end
    place(n,"P1","P3",100); place(n,"P2","P4",100); n:advance(6)
    n.selected=5; n.winner="P3"; n:advance(2)
    local other=n.nodes.P2.client.byRoll[n.nodes.P2.roll].record
    assert(r.state=="LOCKED" and other.state=="LOCKED" and not r.payments and not other.payments)
end)
test("a lost final-result message is recovered from the coordinating client",function()
    local n=network(2); local r=host(n); local dropped=false
    n.drop=function(packet,key)
        if key=="P2" and packet.message:match("^RESULT|") and not dropped then dropped=true; return true end
    end
    place(n,"P1","P3",100); place(n,"P2","P4",100); n:advance(6)
    n.selected=5; n.winner="P3"; n:advance(3)
    assert(dropped and r.state=="SETTLED" and n.nodes.P2.client.byRoll[n.nodes.P2.roll].record.state=="SETTLED")
end)
test("changing local rules or enabling/disabling cannot weaken a frozen round",function()
    local n=network(2); local r=host(n)
    n.nodes.P1.db.betPercent=100; n.selected=2; n:advance(0.5)
    assert(r.state=="VOID" and r.reason=="threshold")
    n=network(2); r=host(n); n.nodes.P1.client:SetEnabled(false); n:advance(0.5)
    assert(r.state=="VOID" and n.nodes.P2.client.byRoll[n.nodes.P2.roll].record.state=="VOID")
end)
test("a detected duplicate after settlement voids debts and preserves paid notes for reconciliation",function()
    local n=network(2); local r=host(n)
    place(n,"P1","P3",100); place(n,"P2","P4",100); n:advance(6)
    n.selected=5; n.winner="P3"; n:advance(1); assert(r.state=="SETTLED")
    r.paidLocally[1]=true; n.nodes.P1.roll.ambiguous=true; n:advance(0.5)
    assert(r.state=="VOID" and #r.payments==0 and r.reconcile and #r.priorPayments==1)
    assert(n.nodes.P2.client.byRoll[n.nodes.P2.roll].record.state=="VOID")
end)
test("missing history and membership changes void instead of paying a guessed winner",function()
    local n=network(2); local r=host(n); n.missing=true; n:advance(0.5); assert(r.state=="VOID")
    n=network(2); r=host(n); n.members.P5=nil; n:advance(0.5); assert(r.state=="VOID")
end)
test("host disconnects release local loot controls and leave no payable balances",function()
    local n=network(2); local r=host(n); n.disconnected.P1=true; n:advance(9)
    local other=n.nodes.P2.client.byRoll[n.nodes.P2.roll].record
    assert(other.state=="VOID" and other.reason=="host" and #other.payments==0)
end)
test("active records are voided on reload while settled ledgers are retained",function()
    local n=network(2); local r=host(n); local db=n.nodes.P2.db
    local old=db.betLedger.records[1]; assert(old.state=="OPEN")
    A.NewBetClient(db,{now=function() return 0 end,wall=function() return 1 end})
    assert(old.state=="VOID" and old.reason=="interrupted" and #db.betLedger.records==1)
end)
test("default-off clients neither advertise nor open betting rounds",function()
    local db=A.InitDB({}); local sent=0
    local c=A.NewBetClient(db,{now=function() return 0 end,wall=function() return 1 end,selfGUID=function() return "P1" end,
        members=function() return {P1="One"} end,rolls=function() return {} end,send=function() sent=sent+1; return true end})
    c:Hello(true); c:Tick(); assert(sent==0); assert(not c:Start({}))
end)
test("forty peers converge on one locked raid book despite a lost early entry",function()
    local n=network(40); local r=host(n); local dropped=false
    n.drop=function(packet,key)
        if key=="P40" and packet.message:match("^ENTRY|") and not dropped then dropped=true; return true end
    end
    for i=1,40 do place(n,"P"..i,i<=10 and "P40" or "P39",100) end
    n:advance(15)
    assert(#r.entries==40 and r.state=="LOCKED")
    n.selected=40; n.winner="P40"; n:advance(5)
    assert(dropped and r.state=="SETTLED")
    for _,node in pairs(n.nodes) do
        local peer=node.client.byRoll[node.roll].record
        assert(peer.state=="SETTLED" and #peer.entries==40 and peer.digest==r.digest)
    end
end)
print(count.." side-betting scenarios passed")

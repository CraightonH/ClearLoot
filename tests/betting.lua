local base=os.getenv("LOOTGOBLIN_ADDON") or "LootGoblin"
local A={}
for _,file in ipairs({"Model.lua","BetModel.lua","BetComms.lua"}) do assert(loadfile(base.."/"..file))("LootGoblin",A) end
local M=A.BetModel; local count=0
local function test(name,fn) fn(); count=count+1; print("PASS "..name) end
local function snapshot(n,selected,left)
    local participants={}; for i=1,n do participants["P"..i]="Player"..i end
    return {total=n,selected=selected or 0,leftMs=left or 60000,participants=participants,
        rosterKey=M.RosterKey(participants),itemKey=M.ItemKey("item:42"),deadline=1800000060}
end
local function new(n)
    local s=snapshot(n or 5)
    return assert(M.New("local-id",nil,s,{percent=20,cutoff=10,maxStake=10000000},1)),s
end
local function entry(bettor,target,stake,nonce)
    return {bettor=bettor,target=target,stake=stake,nonce=nonce or bettor,selected=0,remaining=50000}
end
local function network(size)
    local N={clock=0,total=math.max(5,size),nodes={},members={},bus={},selected=0,offline={}}
    for i=1,N.total do N.members["P"..i]="Player"..i end
    for i=1,size do
        local key="P"..i; local db=A.InitDB({}); local roll={id=i,name="Sword",link="item:42",key="matched"}
        local env={now=function() return N.clock end,wall=function() return math.floor(1800000000+N.clock) end,
            selfGUID=function() return key end,members=function() return N.members end,rolls=function() return {roll} end,
            snapshot=function()
                if N.missing or roll.ambiguous then return nil end
                local s=snapshot(N.total,N.selected,N.left or math.max(0,math.floor(60000-N.clock*1000)))
                s.finished=N.winner~=nil or N.allPassed; s.confirmed=N.winner~=nil; s.winner=N.winner; s.allPassed=N.allPassed
                return s
            end,
            send=function(message) N.bus[#N.bus+1]={sender=key,message=message}; return true end}
        N.nodes[key]={client=A.NewBetClient(db,env),db=db,roll=roll}
    end
    function N:step(dt)
        self.clock=self.clock+dt
        for key,node in pairs(self.nodes) do if not self.offline[key] then node.client:Tick() end end
        local bus=self.bus; self.bus={}
        if self.reverse then local reversed={}; for i=#bus,1,-1 do reversed[#reversed+1]=bus[i] end; bus=reversed end
        for _,p in ipairs(bus) do for key,node in pairs(self.nodes) do
            if not self.offline[key] and (not self.drop or not self.drop(p,key)) then node.client:Receive(p.sender,p.message) end
        end end
    end
    function N:advance(seconds) for i=1,math.ceil(seconds/0.1) do self:step(0.1) end end
    function N:place(who,target,stake)
        local node=self.nodes[who]; local ok,reason=node.client:Submit(node.roll,target,stake or 100); assert(ok,reason)
        return node.client.byRoll[node.roll].record
    end
    function N:round(who) local node=self.nodes[who]; return node.client.byRoll[node.roll].record end
    return N
end
test("inclusive 20% thresholds work for parties and raids",function()
    for _,n in ipairs({5,10,20,40}) do assert(M.Available(snapshot(n,n/5),20)); assert(not M.Available(snapshot(n,n/5+1),20)) end
end)
test("a local bet is valid at 10.001s and rejected at exactly 10s",function()
    local n=network(1); n.left=10001; local r=n:place("P1","P3",50000); assert(r.pool==50000)
    n=network(1); n.left=10000; assert(not n.nodes.P1.client:Submit(n.nodes.P1.roll,"P3",50000))
end)
test("the first click records a bet without discovering peers or creating a host",function()
    local n=network(1); assert(not n.nodes.P1.db.betsEnabled)
    local r=n:place("P1","P3",50000)
    assert(#r.entries==1 and r.pool==50000 and n.nodes.P1.db.betsEnabled and r.host==nil)
end)
test("digests depend on bets rather than local ids, hosts, or arrival order",function()
    local a,s=new(); local b=new(); b.id="different"; b.host="P5"
    M.Merge(a,entry("P1","P3",100)); M.Merge(a,entry("P2","P4",200))
    M.Merge(b,entry("P2","P4",200)); M.Merge(b,entry("P1","P3",100))
    assert(M.Digest(a)==M.Digest(b))
end)
test("repeat notifications are idempotent and conflicting edits are rejected",function()
    local r=new(); assert(M.Merge(r,entry("P1","P3",100)))
    assert(M.Merge(r,entry("P1","P3",100))); assert(#r.entries==1 and r.pool==100)
    assert(not M.Merge(r,entry("P1","P3",200)))
    assert(M.Merge(r,entry("P1","P4",200)))
end)
test("original submission facts are validated even when a notification arrives late",function()
    local r=new(); assert(not M.Merge(r,{bettor="P1",target="P3",stake=100,nonce="x",selected=2,remaining=50000}))
    assert(not M.Merge(r,{bettor="P1",target="P3",stake=100,nonce="x",selected=0,remaining=10000}))
    assert(M.Merge(r,entry("P1","P3",100)))
end)
test("proportional settlements conserve the pool down to a copper",function()
    local r=new(); M.Merge(r,entry("P1","P5",1)); M.Merge(r,entry("P2","P5",2)); M.Merge(r,entry("P3","P4",7))
    M.Lock(r,3,M.Digest(r)); assert(M.Settle(r,"P5"))
    assert(r.pool==10 and r.balances.P1==2 and r.balances.P2==5 and r.balances.P3==-7)
    r=new(40)
    for i=1,40 do assert(M.Merge(r,entry("P"..i,i<=13 and "P40" or "P39",10000000-i))) end
    M.Lock(r,40,M.Digest(r)); assert(M.Settle(r,"P40"))
    local total=0; for _,balance in pairs(r.balances) do assert(balance==math.floor(balance)); total=total+balance end
    assert(total==0)
end)
test("stakes are exact positive copper amounts without the old personal cap",function()
    assert(M.ParseGold("0.0001")==1 and M.ParseGold("5.0001")==50001)
    assert(not M.ParseGold("1e2") and not M.ParseGold("-1") and not M.ParseGold("0.00001"))
    local n=network(1); n.nodes.P1.db.betMaxGold=1
    assert(n.nodes.P1.client:Submit(n.nodes.P1.roll,"P3",20000))
end)
test("stricter personal settings do not require friends to match settings",function()
    local n=network(2)
    n.nodes.P1.db.betPercent=0; n.nodes.P1.db.betCutoff=20; n.nodes.P1.db.betMaxGold=1
    n.nodes.P2.db.betPercent=20; n.nodes.P2.db.betCutoff=10; n.nodes.P2.db.betMaxGold=500
    n:place("P1","P3"); n:place("P2","P4",20000); n:advance(3)
    assert(M.Digest(n:round("P1"))==M.Digest(n:round("P2")) and n:round("P1").pool==20100)
end)
test("two simultaneous first bets merge and elect a resolver automatically",function()
    local n=network(2); n:place("P1","P3",50000); n:place("P2","P4",50000); n:advance(2)
    local a,b=n:round("P1"),n:round("P2")
    assert(#a.entries==2 and #b.entries==2 and a.pool==100000 and M.Digest(a)==M.Digest(b) and a.host=="P1")
    n.winner="P3"; n.selected=5; n:advance(2)
    assert(a.state=="SETTLED" and b.state=="SETTLED" and a.payments[1].amount==50000)
end)
test("a third bettor can join asynchronously without reopening or hosting anything",function()
    local n=network(3); n:place("P1","P3"); n:place("P2","P4"); n:advance(3)
    assert(n:round("P1").state=="LOCKED")
    n:place("P3","P3",200); n:advance(3)
    for _,node in pairs(n.nodes) do local r=node.client.byRoll[node.roll].record; assert(#r.entries==3 and r.pool==400) end
    n.winner="P3"; n.selected=5; n:advance(2)
    assert(n:round("P1").state=="SETTLED" and n:round("P3").state=="SETTLED")
end)
test("a valid notification arriving after the cutoff still joins the shared pool",function()
    local n=network(2); n:place("P1","P3"); n:place("P2","P4")
    -- Submit was valid on both clients. Transport is delayed until 10s remain.
    n.left=10000; n:advance(3)
    assert(#n:round("P1").entries==2 and #n:round("P2").entries==2)
    assert(not n.nodes.P1.client:Submit(n.nodes.P1.roll,"P4",100))
end)
test("watching friends is not participation and does not elect the watcher",function()
    local n=network(3); n.nodes.P1.client:Watch(n.nodes.P1.roll)
    n:place("P2","P4"); n:place("P3","P5"); n:advance(3)
    local r=n:round("P1"); assert(#r.entries==2 and r.host=="P2")
end)
test("lost notifications recover from their original authors",function()
    local n=network(2); local dropped=false
    n.drop=function(p,key) if key=="P2" and p.sender=="P1" and p.message:match("^BET|") and not dropped then dropped=true; return true end end
    n:place("P1","P3"); n:place("P2","P4"); n:advance(4)
    assert(dropped and M.Digest(n:round("P1"))==M.Digest(n:round("P2")))
end)
test("reordered book and bet notices converge without manual retries",function()
    local n=network(3); n.reverse=true
    for i=1,3 do n:place("P"..i,"P4",i*100) end; n:advance(4)
    assert(#n:round("P1").entries==3 and M.Digest(n:round("P1"))==M.Digest(n:round("P3")))
end)
test("every entry belongs to the actual message sender",function()
    local n=network(2); n:place("P1","P3"); n.nodes.P2.client:Watch(n.nodes.P2.roll)
    n:advance(2)
    local r=n:round("P2"); local old=r.entries[1].stake
    local message=table.concat({"BET","3",r.itemKey,r.rosterKey,r.deadline,"fake","P3",999,0,50000,20,10,1},"|")
    n.nodes.P2.client:Receive("outsider",message)
    assert(#r.entries==1 and r.entries[1].stake==old)
end)
test("no payment result is fabricated before the clients agree on the pool",function()
    local n=network(2)
    n.drop=function(p,key) return key=="P1" and p.sender=="P2" and p.message:match("^BOOK|") end
    n:place("P1","P3"); n:place("P2","P4"); n:advance(2); n.winner="P3"; n.selected=5; n:advance(3)
    assert(n:round("P1").state~="SETTLED" and n:round("P2").state~="SETTLED")
end)
test("a missing resolution message is replayed automatically",function()
    local n=network(2); local dropped=false
    n.drop=function(p,key) if key=="P2" and p.message:match("^RESULT|") and not dropped then dropped=true; return true end end
    n:place("P1","P3"); n:place("P2","P4"); n:advance(2); n.winner="P3"; n.selected=5; n:advance(4)
    assert(dropped and n:round("P2").state=="SETTLED")
end)
test("resolver failover uses another connected bettor rather than cancelling pledges",function()
    local n=network(3); for i=1,3 do n:place("P"..i,"P4",100) end; n:advance(3)
    n.offline.P1=true; n.members.P1=nil; n.winner="P4"; n.selected=5; n:advance(3)
    assert(n:round("P2").host=="P2" and n:round("P2").state=="SETTLED" and n:round("P3").state=="SETTLED")
end)
test("crossing the selection cutoff closes betting and retains accepted stakes",function()
    local n=network(1); n:place("P1","P3"); n.selected=2; n:advance(0.5)
    assert(n:round("P1").state=="LOCKED" and n:round("P1").closed)
end)
test("close-only threshold policy retains earlier valid bets",function()
    local n=network(1); n.nodes.P1.db.betBreachAction="close"; n:place("P1","P3"); n.selected=2; n:advance(0.5)
    assert(n:round("P1").state=="LOCKED" and #n:round("P1").entries==1)
end)
test("notifications cannot reopen betting after local timer or choice limits fail",function()
    local n=network(2); n:place("P1","P3"); n:place("P2","P4"); n:advance(2)
    n.left=10000; assert(not n.nodes.P1.client:Submit(n.nodes.P1.roll,"P3",200))
    n.left=50000; n.selected=2; assert(not n.nodes.P2.client:Submit(n.nodes.P2.roll,"P3",200))
end)
test("a later valid notice can revise a result after the shared book grows",function()
    local n=network(3); n:place("P1","P4"); n:place("P2","P3"); n:advance(2)
    local third=n.nodes.P3
    n.drop=function(p,key) return p.sender=="P3" and key~="P3" end
    n:place("P3","P4",200); n.winner="P4"; n.selected=5; n:advance(2)
    assert(n:round("P1").state=="SETTLED")
    n:round("P1").paidLocally[1]=true
    n.drop=nil; n:advance(4)
    assert(#n:round("P1").entries==3 and n:round("P1").state=="SETTLED" and n:round("P3").state=="SETTLED")
    assert(n:round("P1").priorPaidLocally[1] and not n:round("P1").paidLocally[1])
end)
test("all-pass and unknown outcomes never invent an honor payment",function()
    local n=network(2); n:place("P1","P3"); n:place("P2","P4"); n:advance(2); n.allPassed=true; n:advance(1)
    assert(n:round("P1").state=="VOID")
    n=network(2); n:place("P1","P3"); n:place("P2","P4"); n:advance(2); n.missing=true; n:advance(90)
    assert(n:round("P1").state=="UNRESOLVED" and not n:round("P1").payments)
end)
test("a friend's ambiguous item invalidates calculated payments and retains paid notes",function()
    local n=network(2); n:place("P1","P3"); n:place("P2","P4"); n:advance(2)
    n.winner="P3"; n.selected=5; n:advance(2)
    local r=n:round("P1"); assert(r.state=="SETTLED"); r.paidLocally[1]=true
    n.nodes.P2.roll.ambiguous=true; n:advance(3)
    assert(r.state=="VOID" and r.reason=="ambiguous" and #r.payments==0 and r.priorPaidLocally[1])
end)
test("interrupted pools retain their bets as unresolved records",function()
    local n=network(1); local r=n:place("P1","P3")
    A.NewBetClient(n.nodes.P1.db,{now=function() return 0 end,wall=function() return 1 end})
    assert(r.state=="UNRESOLVED" and #r.entries==1 and not r.payments)
end)
test("turning notifications off cannot withdraw an already placed bet",function()
    local n=network(2); n:place("P1","P3"); n:place("P2","P4"); n:advance(2)
    n.nodes.P1.client:SetEnabled(false); n.winner="P3"; n.selected=5; n:advance(3)
    assert(n:round("P1").state=="SETTLED" and n:round("P2").state=="SETTLED")
end)
test("forty asynchronous bettors share one pool and one outcome",function()
    local n=network(40)
    for i=1,40 do n:place("P"..i,"P40",100); n:place("P"..i,"P39",100) end; n:advance(10)
    n.winner="P40"; n.selected=40; n:advance(5)
    for _,node in pairs(n.nodes) do
        local r=node.client.byRoll[node.roll].record
        assert(#r.entries==80 and r.pool==8000 and r.state=="SETTLED")
    end
end)
test("repeated denomination clicks accumulate and allow multiple targets",function()
    local n=network(2)
    n:place("P1","P3",1); n:place("P1","P3",100); n:place("P1","P3",10000)
    n:place("P1","P4",100); n:place("P2","P4",10000); n:advance(4)
    for _,who in ipairs({"P1","P2"}) do
        local r=n:round(who)
        assert(#r.entries==3 and r.pool==20201)
        local mine=0; for _,e in ipairs(r.entries) do if e.bettor=="P1" then mine=mine+e.stake end end
        assert(mine==10201)
    end
    n.winner="P3"; n.selected=5; n:advance(3)
    assert(n:round("P1").balances.P1==10000 and n:round("P1").balances.P2==-10000)
end)
test("older cumulative revisions cannot double count or undo a newer stake",function()
    local r=new(); local e=entry("P1","P3",101); e.revision=2
    assert(M.Merge(r,e)); assert(M.Merge(r,entry("P1","P3",1)))
    assert(r.pool==101 and #r.entries==1)
    assert(M.Merge(r,e)); assert(r.pool==101)
    local bad=entry("P1","P3",100); bad.revision=3
    assert(not M.Merge(r,bad) and r.pool==101)
end)
test("rapid clicks coalesce transport without losing cumulative stakes",function()
    local n=network(2); n.reverse=true
    for i=1,500 do n:place("P1","P3",1) end
    n:place("P1","P4",10000); n:place("P2","P3",100)
    assert(#n.nodes.P1.client.queue<=4)
    n:advance(4)
    assert(n:round("P1").pool==10600 and n:round("P2").pool==10600)
end)
test("one bettor backing multiple players cannot create a payable pool alone",function()
    local r=new(); M.Merge(r,entry("P1","P3",1)); M.Merge(r,entry("P1","P4",10000))
    M.Lock(r,2,M.Digest(r)); assert(not M.Settle(r,"P3") and r.reason=="few")
end)
test("closing a pool does not remove earlier repeated stakes",function()
    local n=network(2); n:place("P1","P3",1); n:place("P1","P4",100); n:place("P2","P3",10000)
    n:advance(3); n.selected=2; n:advance(0.2)
    assert(not n.nodes.P1.client:Submit(n.nodes.P1.roll,"P3",1))
    assert(n:round("P1").pool==10101 and n:round("P1").state~="VOID")
    n.selected=0
    assert(not n.nodes.P1.client:Submit(n.nodes.P1.roll,"P3",1),"a closed window must not reopen")
end)
test("large multi-target pools settle to independently calculated exact copper balances",function()
    -- Reference balances generated with Python arbitrary-precision integers.
    local cases={
        {2148517947882405,706859763755724,646946017355229,632632537223415,4872242988524218,3871208503219960,1001034485304258,-4872242988524218},
        {53974429336482,1050556364159637,1013894754630610,3616434968030495,287684459588368,-709373520014738,997057979603106,-287684459588368},
        {1893823546275203,205407994725495,119352210778209,14860586518267,1972262891545419,1957560302766816,14702588778603,-1972262891545419},
        {642531911882979,690307841593306,241637218767148,120657778673446,221000842900643,182596318905294,38404523995349,-221000842900643},
        {236599495212868,811307252665187,530206976820384,662006937973265,408284117845529,44939686465277,363344431380252,-408284117845529},
        {1085887306431132,1575299357633862,228427215169183,1889496731467863,967316404567872,470829731075140,496486673492732,-967316404567872},
        {1003353790867417,2339192260029392,758817903479694,836656918907351,994138449745254,643204773619689,350933676125565,-994138449745254},
        {2010638213433482,1286792270212251,295695028867980,2286750227247069,827669686568812,367646157370432,460023529198380,-827669686568812},
        {85883811885674,41453310027318,11628933116625,5526182062672,8060125347809,7241198537612,818926810197,-8060125347809},
        {1937248263921482,1820503143961798,2265115741720582,110966497542527,1689281549187539,1575857508461201,113424040726338,-1689281549187539},
        {768126854481670,1193741137312481,425150173019300,912092307360047,900106186637173,479517171792958,420589014844215,-900106186637173},
        {46333774603221,3456403728226,81745571073034,419377607349043,280401961572837,-43312859401284,323714820974121,-280401961572837},
        {1725615494645513,975106203692512,178674378166295,522910855170962,2645399257233552,2187301525795382,458097731438170,-2645399257233552},
        {1110337434285524,2107518148558241,1869909387673680,2836827438513873,672236941059549,-518846131766726,1191083072826275,-672236941059549},
        {13544982816571,4869272291613,23825427932288,16565538148660,5581147955404,-8345056556789,13926204512193,-5581147955404},
        {797176486766743,321401877519704,700553381213059,1951771236566326,672426283777127,-200354528471104,872780812248231,-672426283777127},
        {171762120413997,668917685449840,120707358449152,1109976242100133,124290980344698,-15119724940335,139410705285033,-124290980344698},
        {22535735706694,187700429230974,49275480157618,224337903921234,184794660909053,63961853384834,120832807524219,-184794660909053},
        {71183457628740,11532811718519,21998803521148,27425913579565,165541744187937,118843279372228,46698464815709,-165541744187937},
        {147128811862830,194357496407486,594077710754569,237324926560978,1175683015584479,450043447563071,725639568021408,-1175683015584479},
    }
    for _,c in ipairs(cases) do
        local r=new()
        local bettors={"P1","P1","P1","P2","P3"}
        local targets={"P5","P5","P4","P5","P4"}
        for i=1,5 do assert(M.Merge(r,entry(bettors[i],targets[i],c[i],"ticket"..i))) end
        assert(M.Lock(r,5,M.Digest(r))); assert(M.Settle(r,"P5"))
        assert(r.balances.P1==c[6] and r.balances.P2==c[7] and r.balances.P3==c[8])
        assert(r.balances.P1+r.balances.P2+r.balances.P3==0)
    end
end)
test("large cumulative stakes round-trip without scientific-notation precision loss",function()
    local n=network(2); local stake=4503599627370401
    n:place("P1","P3",stake); n:place("P2","P4",1); n:advance(3)
    assert(n:round("P2").pool==stake+1 and M.Digest(n:round("P1"))==M.Digest(n:round("P2")))
end)
test("a late valid stake can reconcile a pool with no earlier winning predictions",function()
    local n=network(3); n:place("P1","P4"); n:place("P2","P4"); n:advance(2)
    n.drop=function(p,key) return p.sender=="P3" and key~="P3" end
    n:place("P3","P3",200); n.winner="P3"; n.selected=5; n:advance(2)
    assert(n:round("P1").state=="VOID" and n:round("P1").reason=="none")
    n.drop=nil; n:advance(5)
    assert(n:round("P1").state=="SETTLED" and n:round("P1").pool==400)
    assert(n:round("P1").balances.P3==200)
end)
print(count.." asynchronous betting scenarios passed")

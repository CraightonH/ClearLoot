local _,A=...
local M={}; A.BetModel=M
M.PERCENT=20; M.CUTOFF=10
M.states={OPEN="Bets arriving",LOCKED="Bets shared",UNRESOLVED="Waiting to reconcile",SETTLED="Payments calculated",VOID="Voided"}
M.reasons={data="Timer or eligible-player history unavailable",threshold="More than the allowed percentage have chosen",
    timer="Server-time cutoff reached",window="Betting window closed",short="Too little time for a betting window",
    roster="Eligible players changed",finished="Loot roll already finished",duplicate="One accepted bet per character",
    target="Unknown prediction target",stake="Stake is outside this round's limit",peers="Another enabled ClearLoot player is needed",
    rules="Friends are using different betting rules",host="Waiting for another bettor to resolve",
    sync="Bet book could not be synchronized",ambiguous="Loot association is uncertain",interrupted="Interrupted by reload",
    few="Fewer than two accepted bettors",none="Nobody predicted the winner; pledges cancelled",allpass="Everyone passed",
    conflict="Conflicting predictions from one character",disabled="Betting is disabled",cancel="Voided"}
local function integer(n,max)
    return type(n)=="number" and n==n and n>=0 and n<=max and n==math.floor(n)
end
function M.Hash(s)
    local n=5381
    for i=1,#s do n=(n*33+s:byte(i))%4294967291 end
    return string.format("%.0f",n)
end
function M.ItemKey(link) return M.Hash(link:match("|H(.-)|h") or link) end
function M.RosterKey(participants)
    local ids={}; for guid in pairs(participants) do ids[#ids+1]=guid end
    table.sort(ids); return M.Hash(table.concat(ids,","))
end
function M.Available(snapshot,percent)
    if not snapshot or not integer(snapshot.total,40) or snapshot.total<2 or
        not integer(snapshot.selected,snapshot.total) or not integer(percent,100) then return false,"data" end
    -- Integer comparison makes exactly 20% inclusive at every party/raid size.
    if snapshot.selected*100>snapshot.total*percent then return false,"threshold" end
    return true
end
function M.CanBet(round,snapshot)
    if round.state=="VOID" or round.state=="SETTLED" then return false,"window" end
    local ok,reason=M.Available(snapshot,round.percent); if not ok then return false,reason end
    if snapshot.rosterKey~=round.rosterKey then return false,"roster" end
    if snapshot.finished then return false,"finished" end
    if not integer(snapshot.leftMs,3600000) then return false,"data" end
    if snapshot.leftMs<=round.cutoff*1000 then return false,"timer" end
    return true
end
function M.New(id,host,snapshot,rules,timestamp)
    local ok,reason=M.Available(snapshot,rules.percent); if not ok then return nil,reason end
    if snapshot.finished then return nil,"finished" end
    if not integer(rules.cutoff,30) or rules.cutoff<10 or
        not integer(rules.maxStake,10000000) or rules.maxStake<1 then return nil,"rules" end
    if not integer(snapshot.leftMs,3600000) or snapshot.leftMs<=rules.cutoff*1000 then return nil,"timer" end
    return {id=id,host=host,state="OPEN",percent=rules.percent,cutoff=rules.cutoff,maxStake=rules.maxStake,
        closeRemaining=rules.cutoff*1000,rosterKey=snapshot.rosterKey,itemKey=snapshot.itemKey,
        participants=A.Copy(snapshot.participants),entries={},timestamp=timestamp,paidLocally={}}
end
function M.Accept(round,snapshot,bettor,target,stake,nonce)
    local ok,reason=M.CanBet(round,snapshot); if not ok then return nil,reason end
    if not round.participants[bettor] or not round.participants[target] then return nil,"target" end
    if not integer(stake,round.maxStake) or stake<1 then return nil,"stake" end
    local e={bettor=bettor,target=target,stake=stake,nonce=nonce,selected=snapshot.selected,remaining=snapshot.leftMs}
    local merged,why=M.Merge(round,e)
    if not merged then return nil,why end
    for _,entry in ipairs(round.entries) do if entry.bettor==bettor then return entry end end
end
function M.Digest(round)
    local lines={"2",round.rosterKey,round.itemKey,tostring(round.percent),tostring(round.cutoff)}
    local entries={}; for _,e in ipairs(round.entries) do entries[#entries+1]=e end
    table.sort(entries,function(a,b) return a.bettor<b.bettor end)
    for _,e in ipairs(entries) do
        lines[#lines+1]=table.concat({e.bettor,e.target,e.stake,e.nonce,e.selected,e.remaining},",")
    end
    return M.Hash(table.concat(lines,";"))
end
function M.Merge(round,e)
    if not round.participants[e.bettor] or not round.participants[e.target] or
        not integer(e.stake,10000000) or e.stake<1 or type(e.nonce)~="string" or #e.nonce>64 then return false,"data" end
    local allowed,reason=M.Available({total=#M.ParticipantIDs(round),selected=e.selected},round.percent)
    if not allowed then return false,reason end
    if not integer(e.remaining,3600000) or e.remaining<=round.cutoff*1000 then return false,"timer" end
    for _,old in ipairs(round.entries) do
        if old.bettor==e.bettor then
            if old.target==e.target and old.stake==e.stake and old.nonce==e.nonce and old.selected==e.selected and old.remaining==e.remaining then return true,"duplicate" end
            return false,"conflict"
        end
    end
    if round.state=="VOID" then return false,"window" end
    if round.state=="SETTLED" then
        if next(round.paidLocally or {}) then
            round.priorPayments=A.Copy(round.payments or {}); round.priorPaidLocally=A.Copy(round.paidLocally); round.reconcile=true
        end
        round.paidLocally={}
        round.state="LOCKED"
    end
    round.entries[#round.entries+1]=A.Copy(e)
    table.sort(round.entries,function(a,b) return a.bettor<b.bettor end)
    round.pool=0
    for i,entry in ipairs(round.entries) do entry.seq=i; round.pool=round.pool+entry.stake end
    round.digest=nil; round.payments=nil; round.balances=nil; round.winner=nil
    return true
end
function M.ParticipantIDs(round)
    local ids={}; for guid in pairs(round.participants) do ids[#ids+1]=guid end; table.sort(ids); return ids
end
function M.Resolver(round,connected)
    local candidates={}
    for _,e in ipairs(round.entries) do if connected[e.bettor] then candidates[#candidates+1]=e.bettor end end
    table.sort(candidates); return candidates[1]
end
function M.Lock(round,count,digest)
    if round.state=="VOID" or round.state=="SETTLED" then return false,"window" end
    if not integer(count,40) or count~=#round.entries or digest~=M.Digest(round) then return false,"sync" end
    round.state="LOCKED"; round.digest=digest; return true
end
function M.Void(round,reason)
    if round.payments and #round.payments>0 and round.paidLocally and next(round.paidLocally) then
        round.priorPayments=A.Copy(round.payments); round.priorPaidLocally=A.Copy(round.paidLocally); round.reconcile=true
    end
    round.state="VOID"; round.reason=reason; round.payments={}; round.balances={}
end
local function divmod(n,d)
    local q=math.floor(n/d)
    -- Products are bounded below 2^53, so correct possible floating division rounding.
    if q*d>n then q=q-1 elseif (q+1)*d<=n then q=q+1 end
    return q,n-q*d
end
function M.Settle(round,winner)
    if round.state=="SETTLED" then return true end
    if round.state~="LOCKED" then return false,"window" end
    if not round.participants[winner] then return false,"target" end
    if #round.entries<2 then M.Void(round,"few"); return false,"few" end
    local pool,winningStake=0,0; local winning={}; local balances={}
    for _,e in ipairs(round.entries) do
        pool=pool+e.stake; balances[e.bettor]=-e.stake
        if e.target==winner then winningStake=winningStake+e.stake; winning[#winning+1]=e end
    end
    if winningStake==0 then M.Void(round,"none"); return false,"none" end
    local credited=0; local fractions={}
    for _,e in ipairs(winning) do
        local amount,remainder=divmod(pool*e.stake,winningStake)
        balances[e.bettor]=balances[e.bettor]+amount; credited=credited+amount
        fractions[#fractions+1]={key=e.bettor,remainder=remainder}
    end
    table.sort(fractions,function(a,b) if a.remainder~=b.remainder then return a.remainder>b.remainder end; return a.key<b.key end)
    for i=1,pool-credited do local key=fractions[i].key; balances[key]=balances[key]+1 end
    local debtors,creditors={},{}
    for key,amount in pairs(balances) do
        if amount<0 then debtors[#debtors+1]={key=key,left=-amount}
        elseif amount>0 then creditors[#creditors+1]={key=key,left=amount} end
    end
    table.sort(debtors,function(a,b) return a.key<b.key end); table.sort(creditors,function(a,b) return a.key<b.key end)
    local payments={}; local i,j=1,1
    while debtors[i] and creditors[j] do
        local amount=math.min(debtors[i].left,creditors[j].left)
        payments[#payments+1]={from=debtors[i].key,to=creditors[j].key,amount=amount}
        debtors[i].left=debtors[i].left-amount; creditors[j].left=creditors[j].left-amount
        if debtors[i].left==0 then i=i+1 end; if creditors[j].left==0 then j=j+1 end
    end
    round.pool=pool; round.winner=winner; round.balances=balances; round.payments=payments; round.state="SETTLED"
    return true
end
function M.ParseGold(text)
    local whole,fraction=tostring(text or ""):match("^(%d+)%.?(%d*)$")
    if not whole or #fraction>4 or #whole>4 then return nil end
    local amount=tonumber(whole)*10000+tonumber(fraction..string.rep("0",4-#fraction))
    if not integer(amount,10000000) or amount<1 then return nil end
    return amount
end
function M.Money(copper)
    return string.format("%dg %ds %dc",math.floor(copper/10000),math.floor(copper/100)%100,copper%100)
end

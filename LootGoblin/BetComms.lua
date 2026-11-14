local _,A=...
local M=A.BetModel
local function number(s,max)
    local n=tonumber(s); if not n or n~=n or n<0 or n>max or n~=math.floor(n) then return nil end; return math.floor(n)
end
local function encode(op,...)
    local fields={op,"3",...}
    for i,v in ipairs(fields) do
        v=type(v)=="number" and string.format("%.0f",v) or tostring(v); if #v>96 or v:find("[|%c]") then return nil end; fields[i]=v
    end
    local message=table.concat(fields,"|"); return #message<=255 and message or nil
end
local function decode(message)
    if type(message)~="string" or #message>255 or message:find("%c") then return nil end
    local fields={}; for part in (message.."|"):gmatch("(.-)|") do fields[#fields+1]=part end
    if fields[2]~="3" or #fields>13 then return nil end; return fields
end
function A.NewBetClient(db,env)
    db.betLedger=type(db.betLedger)=="table" and db.betLedger or {}
    local ledger=db.betLedger
    ledger.records=type(ledger.records)=="table" and ledger.records or {}
    ledger.nextID=tonumber(ledger.nextID) or 1; ledger.sessions=(tonumber(ledger.sessions) or 0)+1
    for _,r in ipairs(ledger.records) do
        if r.state=="OPEN" or r.state=="LOCKED" or r.state=="AWAITING_LOCK" then
            r.state="UNRESOLVED"; r.reason="interrupted"; r.payments=nil
        end
    end
    local C={contexts={},byRoll={},queue={},credits=800,lastPump=env.now(),revision=0,
        nonce=tostring(env.wall()).."."..ledger.sessions,serial=0}
    local function changed() C.revision=C.revision+1 end
    local function deadline(roll,snapshot)
        if not roll.betDeadline then roll.betDeadline=snapshot.deadline or math.floor(env.wall()+(snapshot.leftMs or 0)/1000+0.5) end
        return roll.betDeadline
    end
    function C:Send(op,...)
        local message=encode(op,...); if not message then return false end
        local args={...}
        local key=(op=="BET" and table.concat({op,args[1],args[2],args[3],args[4],args[5]},"|")) or
            (op=="BOOK" and table.concat({op,args[1],args[2],args[3]},"|"))
        for _,packet in ipairs(self.queue) do
            if packet.text==message then return true end
            if key and packet.key==key then packet.text=message; packet.at=env.now(); return true end
        end
        if #self.queue>=240 then return false end
        self.queue[#self.queue+1]={text=message,at=env.now(),key=key}; return true
    end
    function C:Pump()
        local now=env.now(); self.credits=math.min(800,self.credits+math.max(0,now-self.lastPump)*800); self.lastPump=now
        local sent=0
        while self.queue[1] and sent<8 do
            local p=self.queue[1]; local cost=#p.text+16
            if now-p.at>15 then table.remove(self.queue,1)
            elseif cost>self.credits then break
            elseif env.send(p.text) then table.remove(self.queue,1); self.credits=self.credits-cost; sent=sent+1
            else break end
        end
    end
    function C:SetEnabled(enabled) db.betsEnabled=not not enabled; changed() end
    function C:Find(item,roster,untilTime)
        local found,roll,snapshot
        for _,context in pairs(self.contexts) do
            local r=context.record
            if r.itemKey==item and r.rosterKey==roster and math.abs(r.deadline-untilTime)<=2 then
                if found then return nil end; found=context
            end
        end
        if found then return found,found.roll,env.snapshot(found.roll) end
        for _,candidate in ipairs(env.rolls()) do
            if not candidate.demo and not candidate.ambiguous and candidate.link and M.ItemKey(candidate.link)==item then
                local s=env.snapshot(candidate)
                if s and s.rosterKey==roster and math.abs(deadline(candidate,s)-untilTime)<=2 then
                    if roll then return nil end; roll=candidate; snapshot=s
                end
            end
        end
        return nil,roll,snapshot
    end
    function C:Ensure(roll,snapshot,proof,percent,cutoff)
        if self.byRoll[roll] then return self.byRoll[roll] end
        local view=A.Copy(snapshot)
        if proof then view.selected=proof.selected; view.leftMs=proof.remaining; view.finished=false end
        local id=tostring(env.selfGUID())..":"..ledger.sessions..":"..ledger.nextID
        local round,reason=M.New(id,nil,view,{percent=M.PERCENT,cutoff=M.CUTOFF,maxStake=M.MAX_MONEY},env.wall())
        if not round then return nil,reason end
        ledger.nextID=ledger.nextID+1
        round.protocol=3; round.deadline=deadline(roll,snapshot); round.itemName=roll.name; round.itemLink=roll.link
        local c={record=round,roll=roll,agreements={},lastChange=env.now(),lastPublish=-100,lastSync=-100,
            expires=env.now()+math.max(0,round.deadline-env.wall())+30}
        self.contexts[id]=c; self.byRoll[roll]=c; ledger.records[#ledger.records+1]=round
        if #ledger.records>1000 then
            for i,r in ipairs(ledger.records) do
                if r.state=="SETTLED" or r.state=="VOID" or r.state=="UNRESOLVED" then
                    local old=self.contexts[r.id]; if old then self.byRoll[old.roll]=nil; self.contexts[r.id]=nil end
                    table.remove(ledger.records,i); break
                end
            end
        end
        changed(); return c
    end
    local function ownEntry(context)
        for _,e in ipairs(context.record.entries) do if e.bettor==env.selfGUID() then return e end end
    end
    function C:Publish(context)
        local r=context.record; local e=ownEntry(context); if not e then return end
        for _,mine in ipairs(r.entries) do
            if mine.bettor==env.selfGUID() then
                self:Send("BET",r.itemKey,r.rosterKey,r.deadline,mine.nonce,mine.target,mine.stake,mine.selected,mine.remaining,r.percent,r.cutoff,mine.revision or 1)
            end
        end
        self:Send("BOOK",r.itemKey,r.rosterKey,r.deadline,e.nonce,M.Digest(r),#r.entries,r.state=="VOID" and ("V:"..(r.reason or "data")) or "Y")
        context.lastPublish=env.now()
    end
    function C:RequestSync(context)
        if env.now()-context.lastSync<1 then return end
        context.lastSync=env.now(); local r=context.record
        self:Send("SYNC",r.itemKey,r.rosterKey,r.deadline)
    end
    function C:Notice(context,e)
        local ok,reason=M.Merge(context.record,e)
        if not ok then return false,reason end
        if reason~="duplicate" then
            context.lastChange=env.now(); context.agreements={}; context.result=nil
            context.record.reason=nil
            context.expires=math.max(context.expires,env.now()+10)
            local mine=ownEntry(context)
            if mine then context.agreements[mine.bettor]=M.Digest(context.record) end
            self:Publish(context); changed()
        end
        return true
    end
    function C:Submit(roll,target,stake)
        if roll.betClosedReason then return false,roll.betClosedReason end
        local snapshot=env.snapshot(roll)
        if not snapshot then return false,"data" end
        local context=self.byRoll[roll]
        local rules={state=context and context.record.state or "OPEN",percent=math.min(db.betPercent,M.PERCENT),
            cutoff=math.max(db.betCutoff,M.CUTOFF),closed=context and context.record.closed,closedReason=context and context.record.closedReason,rosterKey=context and context.record.rosterKey or snapshot.rosterKey}
        local valid,reason=M.CanBet(rules,snapshot)
        if not valid then
            if reason=="threshold" or reason=="timer" then roll.betClosedReason=reason end
            return false,reason
        end
        if not number(tostring(stake),M.MAX_MONEY) or stake<1 then return false,"stake" end
        if not snapshot.participants[target] or not snapshot.participants[env.selfGUID()] then return false,"target" end
        if not context then context,reason=self:Ensure(roll,snapshot); if not context then return false,reason end end
        self.serial=self.serial+1
        local previous=0
        for _,entry in ipairs(context.record.entries) do
            if entry.bettor==env.selfGUID() and entry.target==target and entry.nonce==self.nonce then previous=entry.stake end
        end
        if stake>M.MAX_MONEY-previous then return false,"stake" end
        local e={bettor=env.selfGUID(),target=target,stake=previous+stake,nonce=self.nonce,revision=self.serial,
            selected=snapshot.selected,remaining=snapshot.leftMs}
        local ok,why=self:Notice(context,e); if not ok then return false,why end
        -- The click is consent to participate; no discovery/host/acceptance action is required.
        db.betsEnabled=true; self:Publish(context); self:RequestSync(context)
        return true
    end
    function C:Watch(roll)
        db.betsEnabled=true
        if self.byRoll[roll] then self.byRoll[roll].expires=math.max(self.byRoll[roll].expires,env.now()+10) end
        local s=roll and env.snapshot(roll)
        if s then self:Send("SYNC",s.itemKey,s.rosterKey,deadline(roll,s)) end
    end
    function C:Receive(sender,message)
        if sender==env.selfGUID() or not env.members()[sender] then return end
        local f=decode(message); if not f then return end
        local untilTime=number(f[5],10000000000); if not untilTime then return end
        local context,roll,snapshot=self:Find(f[3],f[4],untilTime)
        if not db.betsEnabled and not (context and ownEntry(context)) then return end
        if f[1]=="BET" and #f==13 then
            local stake=number(f[8],M.MAX_MONEY); local selected=number(f[9],40); local remaining=number(f[10],3600000)
            local percent=number(f[11],100); local cutoff=number(f[12],30)
            local revision=number(f[13],M.MAX_MONEY)
            if not stake or not selected or not remaining or not percent or not cutoff or not revision or revision<1 or #f[6]>64 or not snapshot then return end
            if percent~=M.PERCENT or cutoff~=M.CUTOFF then
                if context then context.error="rules" end; return
            end
            local e={bettor=sender,target=f[7],stake=stake,nonce=f[6],revision=revision,selected=selected,remaining=remaining}
            if not context then
                if not roll or env.wall()>untilTime+30 then return end
                -- Validate the originating client's immutable submission facts, not arrival-time loot choices.
                context=self:Ensure(roll,snapshot,e,percent,cutoff)
            end
            if context then
                local ok,reason=self:Notice(context,e); if not ok then context.error=reason end
            end
        elseif context and f[1]=="BOOK" and #f==9 then
            local entry
            for _,e in ipairs(context.record.entries) do if e.bettor==sender and e.nonce==f[6] then entry=e; break end end
            if entry and number(f[8],M.MAX_MONEY)==#context.record.entries and f[7]==M.Digest(context.record) then
                context.agreements[sender]=f[7]
                local reason=f[9]:match("^V:(.+)$")
                if reason and M.reasons[reason] then
                    if reason~="threshold" then
                        M.Void(context.record,reason); changed()
                    end
                end
            else self:RequestSync(context) end
        elseif context and f[1]=="SYNC" and #f==5 then
            if env.now()-(context.lastReply or -100)>=0.5 then
                context.lastReply=env.now(); self:Publish(context)
                if context.record.state=="SETTLED" and context.record.host==env.selfGUID() then
                    local r=context.record; self:Send("RESULT",r.itemKey,r.rosterKey,r.deadline,M.Digest(r),r.winner)
                end
            end
        elseif context and f[1]=="RESULT" and #f==7 then
            if sender==M.Resolver(context.record,env.members()) and f[6]==M.Digest(context.record) and context.record.participants[f[7]] then
                context.result={sender=sender,digest=f[6],winner=f[7]}; changed()
            else self:RequestSync(context) end
        elseif not context and roll and f[1]=="BOOK" then
            self:Send("SYNC",f[3],f[4],untilTime)
        end
    end
    function C:Agreed(context)
        if M.BettorCount(context.record)<2 then return false end
        local digest=M.Digest(context.record)
        for _,e in ipairs(context.record.entries) do if context.agreements[e.bettor]~=digest then return false end end
        return true
    end
    function C:Tick()
        local now=env.now(); local me=env.selfGUID()
        for _,c in pairs(self.contexts) do
            local r=c.record; local s=env.snapshot(c.roll)
            if r.state~="VOID" and (now<=c.expires or r.state=="SETTLED") then
                if c.roll.ambiguous then M.Void(r,"ambiguous"); changed()
                elseif s and s.rosterKey==r.rosterKey then
                    local agreed=self:Agreed(c)
                    if agreed then r.state=r.state=="SETTLED" and "SETTLED" or "LOCKED"; r.digest=M.Digest(r) end
                    if not s.finished then
                        local allowed,reason=M.Available(s,r.percent)
                        if not allowed or (s.leftMs and s.leftMs<=r.cutoff*1000) then
                            r.closed=true; r.closedReason=not allowed and reason or "timer"
                        end
                    end
                    if r.state=="OPEN" and not s.finished then
                        local allowed,reason=M.Available(s,r.percent)
                        if not allowed then
                            r.state="LOCKED"; r.closed=true; r.closedReason=reason
                            self:Publish(c); changed()
                        elseif s.leftMs and s.leftMs<=r.cutoff*1000 then r.state="LOCKED"; r.closed=true; r.closedReason="timer"; changed() end
                    end
                    r.host=M.Resolver(r,env.members())
                    if s.confirmed and s.winner and now-c.lastChange>=1 and r.state~="SETTLED" and r.state~="VOID" then
                        c.resultSeen=c.resultSeen or now
                        if r.host==me and agreed then
                            r.state="LOCKED"; r.digest=M.Digest(r)
                            local ok,reason=M.Settle(r,s.winner)
                            if ok then self:Send("RESULT",r.itemKey,r.rosterKey,r.deadline,r.digest,r.winner); c.settledAt=now
                            else c.error=reason end
                            changed()
                        elseif c.result and c.result.sender==r.host and c.result.digest==M.Digest(r) then
                            if c.result.winner~=s.winner then M.Void(r,"data")
                            else r.state="LOCKED"; r.digest=M.Digest(r); M.Settle(r,s.winner); c.settledAt=now end
                            changed()
                        else self:RequestSync(c) end
                        if M.BettorCount(r)<2 and now-(c.resultSeen or now)>=3 then r.state="UNRESOLVED"; r.reason="few"; changed() end
                    elseif s.allPassed then M.Void(r,"allpass"); changed() end
                end
            end
            if now>c.expires and r.state~="SETTLED" and r.state~="VOID" then
                if M.BettorCount(r)<2 then M.Void(r,"few") else r.state="UNRESOLVED"; r.reason="sync" end
            end
            if now<=c.expires+10 and (db.betsEnabled or ownEntry(c)) and now-c.lastPublish>=1.5 and (r.state~="SETTLED" or now-(c.settledAt or now)<10) then
                self:Publish(c)
                if r.state=="SETTLED" and r.host==me then self:Send("RESULT",r.itemKey,r.rosterKey,r.deadline,M.Digest(r),r.winner) end
            end
        end
        self:Pump()
    end
    return C
end

local function normalized(name) return name and name:lower():gsub("[%s']","") end
function A.BetMembers()
    local members,names={},{}
    local function add(unit)
        if UnitIsConnected and not UnitIsConnected(unit) then return end
        local guid=UnitGUID and UnitGUID(unit); if not guid then return end
        local name,realm
        if UnitFullName then name,realm=UnitFullName(unit) elseif UnitName then name=UnitName(unit) end
        if not name then return end
        local _,full=A.CharacterIdentity({playerName=name..(realm and realm~="" and ("-"..realm) or "")})
        members[guid]=full; names[normalized(full)]=guid
    end
    add("player")
    if IsInRaid and IsInRaid() then for i=1,(GetNumGroupMembers and GetNumGroupMembers() or 0) do add("raid"..i) end
    else for i=1,(GetNumSubgroupMembers and GetNumSubgroupMembers() or 0) do add("party"..i) end end
    return members,names
end
function A.BetSnapshot(roll)
    if roll.demo or roll.ambiguous or not roll.key or not C_LootHistory or not GetLootRollTimeLeft then return nil end
    local d=C_LootHistory.GetSortedInfoForDrop(roll.encounterID,roll.lootListKey)
    if not d or not d.rollInfos then return nil end
    local members=A.BetMembers(); local participants={}; local total,selected=0,0; local winner=d.winner and d.winner.playerGUID
    for _,p in ipairs(d.rollInfos) do
        if not p.playerGUID or participants[p.playerGUID] or not number(tostring(p.state),5) then return nil end
        local _,full=A.CharacterIdentity(p,roll.realm)
        total=total+1; participants[p.playerGUID]=members[p.playerGUID] or full
        if p.state~=4 then selected=selected+1 end
        if p.isWinner then winner=p.playerGUID end
    end
    if total<2 or total>40 then return nil end
    local left=GetLootRollTimeLeft(roll.id)
    if type(left)=="number" and left==left and left>=0 and left<=3600000 then left=math.floor(left) else left=nil end
    if not roll.betDeadline and left and left>0 then
        local serverNow=(GetServerTime and GetServerTime()) or (time and time()) or 0
        roll.betDeadline=math.floor(serverNow+left/1000+0.5)
    end
    return {participants=participants,total=total,selected=selected,rosterKey=M.RosterKey(participants),
        deadline=roll.betDeadline or (roll.wallStarted and roll.wallStarted+(roll.duration or 0)),
        leftMs=left,itemKey=M.ItemKey(roll.link),finished=not not roll.finished or not not winner or d.allPassed,
        confirmed=not not winner,allPassed=d.allPassed,winner=winner}
end
function A.InitBetting()
    local function distribution()
        if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid and IsInRaid() then return "RAID" end
        if IsInGroup and IsInGroup() then return "PARTY" end
    end
    local api=C_ChatInfo
    A.bettingAvailable=not not (api and api.RegisterAddonMessagePrefix and api.SendAddonMessage and UnitGUID)
    local env={now=GetTime,wall=function() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end,
        selfGUID=function() return UnitGUID and UnitGUID("player") end,members=A.BetMembers,snapshot=A.BetSnapshot,rolls=function() return A.rolls end,
        send=function(message)
            local channel=distribution(); if not channel or not A.bettingAvailable then return false end
            local ok,result,legacy=pcall(api.SendAddonMessage,"LootGoblinBets",message,channel)
            local status=legacy or result
            return ok and (status==nil or status==true or status==0)
        end}
    A.betClient=A.NewBetClient(A.db,env)
    if not A.bettingAvailable then return end
    local ok,registered=pcall(api.RegisterAddonMessagePrefix,"LootGoblinBets")
    if not ok or (registered~=nil and registered~=true and registered~=0) then A.bettingAvailable=false; return end
    local frame=CreateFrame("Frame"); A.betEventFrame=frame
    frame:RegisterEvent("CHAT_MSG_ADDON"); frame:RegisterEvent("GROUP_ROSTER_UPDATE"); frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent",function(_,event,prefix,message,channel,sender)
        if event=="CHAT_MSG_ADDON" then
            if prefix~="LootGoblinBets" or (channel~="PARTY" and channel~="RAID" and channel~="INSTANCE_CHAT") then return end
            local _,names=A.BetMembers()
            local guid=names[normalized(sender)]
            if not guid and sender and not sender:find("-",1,true) then
                local _,full=A.CharacterIdentity({playerName=sender}); guid=names[normalized(full)]
            end
            if guid then A.betClient:Receive(guid,message) end
        end
    end)
end

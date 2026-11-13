local _,A=...
local M=A.BetModel
local function number(s,max)
    local n=tonumber(s); if not n or n~=n or n<0 or n>max or n~=math.floor(n) then return nil end; return math.floor(n)
end
local function encode(op,...)
    local fields={op,"1",...}
    for i,v in ipairs(fields) do
        v=tostring(v)
        if #v>96 or v:find("[|%c]") then return nil end
        fields[i]=v
    end
    local message=table.concat(fields,"|"); return #message<=255 and message or nil
end
local function decode(message)
    if type(message)~="string" or #message>255 or message:find("%c") then return nil end
    local fields={}; for field in (message.."|"):gmatch("(.-)|") do fields[#fields+1]=field end
    if fields[2]~="1" or #fields>10 then return nil end
    return fields
end
local function active(r) return r.state=="OPEN" or r.state=="AWAITING_LOCK" or r.state=="LOCKED" end
function A.NewBetClient(db,env)
    if type(db.betLedger)~="table" then db.betLedger={} end
    local ledger=db.betLedger
    ledger.records=type(ledger.records)=="table" and ledger.records or {}
    ledger.nextID=type(ledger.nextID)=="number" and ledger.nextID or 1
    ledger.sessions=(tonumber(ledger.sessions) or 0)+1
    for _,r in ipairs(ledger.records) do if active(r) then M.Void(r,"interrupted") end end
    local C={contexts={},byRoll={},peers={},queue={},revision=0,serial=0,credits=800,lastPump=env.now(),
        nonce=tostring(env.wall()).."."..ledger.sessions,lastHello=-100}
    local function changed() C.revision=C.revision+1 end
    local function remember(round,roll)
        local snapshot=env.snapshot(roll)
        local context={record=round,roll=roll,hostSeen=env.now(),lastPing=-100,lastSync=-100,pending={},acks={},incoming={}}
        context.expires=env.now()+((snapshot and snapshot.leftMs) or 60000)/1000+15
        context.closesAt=env.now()+math.max(0,((snapshot and snapshot.leftMs) or round.closeRemaining)-round.closeRemaining)/1000
        C.contexts[round.id]=context; C.byRoll[roll]=context; ledger.records[#ledger.records+1]=round
        -- Only completed/voided records may be pruned; active rounds keep their book.
        if #ledger.records>1000 then
            for i,r in ipairs(ledger.records) do if not active(r) then
                local old=C.contexts[r.id]
                if old then C.byRoll[old.roll]=nil; old.roll.betBlockedReason=old.roll.betBlockedReason or "window"; C.contexts[r.id]=nil end
                table.remove(ledger.records,i); break
            end end
        end
        changed(); return context
    end
    function C:Send(op,...)
        local message=encode(op,...)
        if not message or #self.queue>=240 then return false end
        for _,packet in ipairs(self.queue) do if packet.text==message then return true end end
        self.queue[#self.queue+1]={text=message,at=env.now()}; return true
    end
    function C:Pump()
        local now=env.now(); self.credits=math.min(800,self.credits+math.max(0,now-self.lastPump)*800); self.lastPump=now
        local sent=0
        while self.queue[1] and sent<8 do
            local packet=self.queue[1]; local cost=#packet.text+16
            if now-packet.at>15 then table.remove(self.queue,1)
            elseif cost>self.credits then break
            elseif env.send(packet.text) then self.credits=self.credits-cost; table.remove(self.queue,1); sent=sent+1
            else break end
        end
    end
    function C:Hello(force)
        if not db.betsEnabled or not env.selfGUID() then return end
        if force or env.now()-self.lastHello>=5 then
            self.lastHello=env.now(); self:Send("HELLO",self.nonce)
        end
    end
    function C:Void(context,reason,announce)
        local round=context.record
        if round.state=="VOID" then
            if announce then self:Send(round.host==env.selfGUID() and "VOID" or "ABORT",round.id,round.reason or reason) end
            return
        end
        M.Void(round,reason); context.roll.betBlockedReason=reason
        if announce then
            self:Send(round.host==env.selfGUID() and "VOID" or "ABORT",round.id,reason)
        end
        changed()
    end
    function C:SetEnabled(enabled)
        local was=db.betsEnabled; db.betsEnabled=not not enabled
        if not enabled and was then
            for _,context in pairs(self.contexts) do if active(context.record) then self:Void(context,"disabled",true) end end
            self:Send("LEAVE",self.nonce)
        elseif enabled then self:Hello(true) end
        changed()
    end
    function C:Start(roll)
        if not db.betsEnabled then return nil,"disabled" end
        if self.byRoll[roll] or roll.betBlockedReason then return nil,roll.betBlockedReason or "window" end
        local me=env.selfGUID(); local members=env.members(); local count=members[me] and 1 or 0
        for key in pairs(self.peers) do if key~=me and members[key] then count=count+1 end end
        if count<2 then self:Hello(true); return nil,"peers" end
        local snapshot=env.snapshot(roll)
        local id=tostring(me)..":"..ledger.sessions..":"..ledger.nextID; ledger.nextID=ledger.nextID+1
        local round,reason=M.New(id,me,snapshot,{percent=db.betPercent,cutoff=db.betCutoff,
            window=db.betWindow,maxStake=db.betMaxGold*10000},env.wall())
        if not round then if reason=="threshold" then roll.betBlockedReason=reason end; return nil,reason end
        round.itemName=roll.name; round.itemLink=roll.link
        local context=remember(round,roll)
        if not self:Send("OPEN",id,round.itemKey,round.rosterKey,round.closeRemaining,round.percent,round.cutoff,round.maxStake,db.betWindow) then
            self:Void(context,"sync",true); return nil,"sync"
        end
        return round
    end
    function C:Entry(context,e)
        return self:Send("ENTRY",context.record.id,e.seq,e.bettor,e.target,e.stake,e.nonce)
    end
    function C:Close(context)
        local round=context.record
        if round.state~="OPEN" then return end
        if round.host==env.selfGUID() then
            if #round.entries<2 then self:Void(context,"few",true)
            else
                M.Lock(round,#round.entries,M.Digest(round)); self:Send("LOCK",round.id,#round.entries,round.digest)
                self:Acknowledge(context)
            end
        else round.state="AWAITING_LOCK"; self:RequestSync(context) end
        changed()
    end
    function C:HandleBet(context,bettor,target,stake,nonce)
        if context.record.host~=env.selfGUID() then return end
        for _,entry in ipairs(context.record.entries) do
            if entry.bettor==bettor and entry.nonce==nonce and entry.target==target and entry.stake==stake then
                self:Entry(context,entry); return
            end
        end
        local snapshot=env.snapshot(context.roll) -- Fresh native timer and history at receipt, never the sender's timestamp.
        if snapshot and context.record.state=="OPEN" then
            if env.now()>=context.closesAt then self:Close(context)
            elseif snapshot.finished then self:Void(context,"finished",true); return
            elseif number(tostring(snapshot.leftMs),3600000) and
                (snapshot.leftMs<=context.record.closeRemaining or snapshot.leftMs<=context.record.cutoff*1000) then
                self:Close(context)
            else
                local valid,reason=M.Available(snapshot,context.record.percent)
                if not valid then self:Void(context,reason,true); return end
            end
        end
        local entry,reason=M.Accept(context.record,snapshot,bettor,target,stake,nonce)
        if not entry then
            self:Send("REJECT",context.record.id,bettor,nonce,reason)
            if bettor==env.selfGUID() then context.pending[bettor]={error=reason} end
        else
            if not self:Entry(context,entry) then self:Void(context,"sync",true); return end
            context.pending[bettor]=nil; changed()
        end
    end
    function C:Submit(roll,target,stake)
        local context=self.byRoll[roll]; if not context then return false,"window" end
        local round=context.record; local me=env.selfGUID()
        local ok,reason=M.CanBet(round,env.snapshot(roll)); if not ok then return false,reason end
        if round.host~=me and not self.peers[round.host] then return false,"host" end
        if not number(tostring(stake),round.maxStake) or stake<1 or not round.participants[target] then return false,"stake" end
        for _,e in ipairs(round.entries) do if e.bettor==me then return false,"duplicate" end end
        local pending=context.pending[me]
        if pending and pending.nonce and (pending.target~=target or pending.stake~=stake) then return false,"duplicate" end
        if not pending or not pending.nonce then
            self.serial=self.serial+1; pending={nonce=self.nonce..":"..self.serial,target=target,stake=stake}; context.pending[me]=pending
        end
        if round.host==me then self:HandleBet(context,me,target,stake,pending.nonce)
        elseif not self:Send("BET",round.id,pending.nonce,target,stake) then return false,"sync" end
        changed(); return true
    end
    function C:RequestSync(context)
        if env.now()-context.lastSync<1 then return end
        context.lastSync=env.now(); self:Send("SYNC",context.record.id,#context.record.entries)
    end
    function C:FinishLock(context)
        local expected=context.expectedLock; if not expected then return end
        local ok=M.Lock(context.record,expected.count,expected.digest)
        if ok then context.expectedLock=nil; self:Acknowledge(context); changed() else self:RequestSync(context) end
    end
    function C:Acknowledge(context)
        local round=context.record
        if not round.digest then return end
        for _,e in ipairs(round.entries) do if e.bettor==env.selfGUID() then
            context.acks[e.bettor]=round.digest; self:Send("ACK",round.id,round.digest); context.lastAck=env.now(); break
        end end
    end
    function C:BookAgreed(context)
        for _,e in ipairs(context.record.entries) do if context.acks[e.bettor]~=context.record.digest then return false end end
        return true
    end
    function C:Receive(sender,message)
        if sender==env.selfGUID() or not env.members()[sender] then return end
        local fields=decode(message); if not fields then return end
        local op,id=fields[1],fields[3]
        if op=="LEAVE" then
            self.peers[sender]=nil
            for _,context in pairs(self.contexts) do if active(context.record) then
                for _,e in ipairs(context.record.entries) do
                    if context.record.host==sender or e.bettor==sender then self:Void(context,"disabled",true); break end
                end
                if context.record.host==sender then self:Void(context,"disabled",true) end
            end end
            return
        end
        if not db.betsEnabled then return end
        if op=="HELLO" and #fields==3 then
            local old=self.peers[sender]; self.peers[sender]={nonce=id}
            if old and old.nonce~=id then
                for _,context in pairs(self.contexts) do if active(context.record) then
                    local affected=context.record.host==sender
                    for _,e in ipairs(context.record.entries) do if e.bettor==sender then affected=true end end
                    if affected then self:Void(context,"host",true) end
                end end
            end
            if not old or old.nonce~=id then self:Hello() end
            return
        end
        if not self.peers[sender] then self:Hello(); return end
        if op=="OPEN" and #fields==10 then
            if self.contexts[id] then return end
            if id:sub(1,#sender+1)~=sender..":" then return end
            local close=number(fields[6],3600000); local percent=number(fields[7],100)
            local cutoff=number(fields[8],30); local maximum=number(fields[9],10000000); local window=number(fields[10],20)
            if not close or percent~=db.betPercent or cutoff~=db.betCutoff or window~=db.betWindow or not maximum or maximum<1 or maximum>db.betMaxGold*10000 then return end
            local found,snapshot
            for _,roll in ipairs(env.rolls()) do
                if not roll.demo and roll.link and M.ItemKey(roll.link)==fields[4] then
                    local candidate=env.snapshot(roll)
                    if candidate and not candidate.finished then
                        if found then return end; found=roll; snapshot=candidate
                    end
                end
            end
            if not found or snapshot.rosterKey~=fields[5] or not snapshot.participants[sender] then return end
            local existing=self.byRoll[found]
            if existing then
                if active(existing.record) then self:Void(existing,"conflict",true); self:Send("ABORT",id,"conflict") end
                return
            end
            if found.betBlockedReason then return end
            local round={id=id,host=sender,state="OPEN",percent=percent,cutoff=cutoff,maxStake=maximum,closeRemaining=close,
                rosterKey=fields[5],itemKey=fields[4],participants=A.Copy(snapshot.participants),entries={},timestamp=env.wall(),
                itemName=found.name,itemLink=found.link,paidLocally={}}
            if close<cutoff*1000 or not snapshot.leftMs or snapshot.leftMs-close>window*1000+1000 then return end
            local ok=M.CanBet(round,snapshot); if not ok then return end
            remember(round,found); return
        end
        local context=self.contexts[id]; if not context then return end
        local round=context.record
        if op=="VOID" and #fields==4 and sender==round.host then
            self:Void(context,M.reasons[fields[4]] and fields[4] or "sync",false); return
        end
        if op=="ABORT" and #fields==4 and round.host==env.selfGUID() and round.participants[sender] then
            self:Void(context,M.reasons[fields[4]] and fields[4] or "sync",true); return
        end
        if op=="PING" and #fields==3 and sender==round.host and round.state=="VOID" then
            self:Send("ABORT",id,round.reason or "sync"); return
        end
        if op=="SYNC" and #fields==4 and round.host==env.selfGUID() and round.participants[sender] then
            local have=number(fields[4],40); if not have then return end
            if env.now()-(context.lastReply or -100)<1 then return end; context.lastReply=env.now()
            if round.state=="VOID" then self:Send("VOID",id,round.reason or "sync"); return end
            for i=have+1,#round.entries do self:Entry(context,round.entries[i]) end
            if round.digest then self:Send("LOCK",id,#round.entries,round.digest) end
            if round.state=="SETTLED" then self:Send("RESULT",id,round.winner,round.digest) end
            return
        end
        if op=="LOCK" and sender==round.host and round.state=="SETTLED" then self:Acknowledge(context); return end
        if not active(round) then return end
        if op=="BET" and #fields==6 and round.host==env.selfGUID() and round.participants[sender] then
            local stake=number(fields[6],round.maxStake)
            if stake and #fields[4]<=64 then self:HandleBet(context,sender,fields[5],stake,fields[4]) end
            return
        end
        if op=="ACK" and #fields==4 then
            for _,e in ipairs(round.entries) do if e.bettor==sender then context.acks[sender]=fields[4]; break end end
            return
        end
        if sender~=round.host then return end
        context.hostSeen=env.now()
        if op=="ENTRY" and #fields==8 then
            local seq=number(fields[4],40); local stake=number(fields[7],round.maxStake)
            if not seq or not stake then self:Void(context,"sync",true); return end
            if fields[5]==env.selfGUID() and seq>#round.entries then
                local pending=context.pending[fields[5]]
                if not pending or pending.nonce~=fields[8] or pending.target~=fields[6] or pending.stake~=stake then
                    self:Void(context,"sync",true); return
                end
            end
            local entry={seq=seq,bettor=fields[5],target=fields[6],stake=stake,nonce=fields[8]}
            local ok,reason=M.ApplyEntry(round,entry)
            if not ok then
                if reason=="sync" then
                    local previous=context.incoming[seq]
                    if previous and (previous.bettor~=entry.bettor or previous.target~=entry.target or previous.stake~=entry.stake or previous.nonce~=entry.nonce) then
                        self:Void(context,"sync",true); return
                    end
                    context.incoming[seq]=entry; self:RequestSync(context)
                else self:Void(context,"sync",true) end
            else
                context.pending[fields[5]]=nil
                local nextEntry=context.incoming[#round.entries+1]
                while nextEntry do
                    local accepted=M.ApplyEntry(round,nextEntry)
                    if not accepted then self:Void(context,"sync",true); return end
                    context.pending[nextEntry.bettor]=nil; context.incoming[nextEntry.seq]=nil
                    nextEntry=context.incoming[#round.entries+1]
                end
                self:FinishLock(context); changed()
            end
        elseif op=="LOCK" and #fields==5 then
            local count=number(fields[4],40); if not count then self:Void(context,"sync",true); return end
            context.expectedLock={count=count,digest=fields[5]}; round.state="AWAITING_LOCK"; self:FinishLock(context)
        elseif op=="RESULT" and #fields==5 then
            if not round.participants[fields[4]] then self:Void(context,"data",true); return end
            context.expectedResult={winner=fields[4],digest=fields[5]}
        elseif op=="VOID" and #fields==4 then self:Void(context,M.reasons[fields[4]] and fields[4] or "sync",false)
        elseif op=="REJECT" and #fields==6 and fields[4]==env.selfGUID() then
            local pending=context.pending[fields[4]]
            if pending and pending.nonce==fields[5] then context.pending[fields[4]]={error=fields[6]}; changed() end
        end
    end
    function C:Tick()
        local members=env.members(); local me=env.selfGUID()
        if db.betsEnabled then self:Hello() end
        if db.betsEnabled then
            for _,roll in ipairs(env.rolls()) do
                local context=self.byRoll[roll]
                if not context then
                    local snapshot=env.snapshot(roll)
                    if snapshot and not M.Available(snapshot,db.betPercent) then roll.betBlockedReason="threshold" end
                end
            end
        end
        for _,context in pairs(self.contexts) do
            local round=context.record
            if round.state=="SETTLED" and context.roll.ambiguous then self:Void(context,"ambiguous",true) end
            if round.state=="SETTLED" and env.now()-(context.settledAt or 0)<12 then
                if round.host==me and env.now()-context.lastPing>=2 then context.lastPing=env.now(); self:Send("PING",round.id) end
                if env.now()-(context.lastAck or -100)>=2 then self:Acknowledge(context) end
            end
            if active(round) then
                if env.now()>context.expires then self:Void(context,"sync",true)
                elseif not db.betsEnabled then self:Void(context,"disabled",true)
                elseif not members[round.host] then self:Void(context,"host",true)
                elseif round.host~=me and env.now()-context.hostSeen>8 then self:Void(context,"host",false)
                else
                    local snapshot=env.snapshot(context.roll)
                    if not snapshot or snapshot.rosterKey~=round.rosterKey then self:Void(context,"data",true)
                    else
                        for guid in pairs(round.participants) do if not members[guid] then self:Void(context,"roster",true); break end end
                        if round.state=="OPEN" then
                            if env.now()>=context.closesAt then self:Close(context)
                            elseif snapshot.finished then self:Void(context,"finished",true)
                            elseif not number(tostring(snapshot.leftMs),3600000) then self:Void(context,"data",true)
                            elseif snapshot.leftMs<=round.closeRemaining or snapshot.leftMs<=round.cutoff*1000 then
                                self:Close(context)
                            else
                                local ok,reason=M.Available(snapshot,round.percent)
                                if not ok then self:Void(context,reason,true)
                                elseif snapshot.finished then self:Void(context,"finished",true) end
                            end
                        end
                        if round.state=="LOCKED" then
                            if env.now()-(context.lastAck or -100)>=2 then self:Acknowledge(context) end
                            if snapshot.allPassed then self:Void(context,"allpass",round.host==me)
                            elseif snapshot.confirmed and snapshot.winner then
                                local canSettle=round.host==me and self:BookAgreed(context)
                                if round.host~=me and context.expectedResult then
                                    if context.expectedResult.winner~=snapshot.winner or context.expectedResult.digest~=round.digest then
                                        self:Void(context,"data",true)
                                    else canSettle=true end
                                end
                                if round.state=="LOCKED" and canSettle then
                                    local ok,reason=M.Settle(round,snapshot.winner)
                                    if ok then
                                        context.settledAt=env.now()
                                        if round.host==me then self:Send("RESULT",round.id,round.winner,round.digest) end
                                    else self:Void(context,reason or "data",true) end
                                    changed()
                                elseif round.state=="LOCKED" then self:RequestSync(context) end
                            elseif snapshot.finished then self:Void(context,"data",true) end
                        elseif round.state=="AWAITING_LOCK" then self:FinishLock(context) end
                    end
                    if active(round) and round.host==me and env.now()-context.lastPing>=2 then
                        context.lastPing=env.now(); self:Send("PING",round.id)
                    end
                end
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
        if not p.playerGUID or not members[p.playerGUID] or participants[p.playerGUID] or not number(tostring(p.state),5) then return nil end
        total=total+1; participants[p.playerGUID]=members[p.playerGUID]
        if p.state~=4 then selected=selected+1 end
        if p.isWinner then winner=p.playerGUID end
    end
    if total<2 or total>40 then return nil end
    local left=GetLootRollTimeLeft(roll.id)
    if type(left)=="number" and left==left and left>=0 and left<=3600000 then left=math.floor(left) else left=nil end
    return {participants=participants,total=total,selected=selected,rosterKey=M.RosterKey(participants),
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
            local ok,result,legacy=pcall(api.SendAddonMessage,"ClearLootBets",message,channel)
            local status=legacy or result
            return ok and (status==nil or status==true or status==0)
        end}
    A.betClient=A.NewBetClient(A.db,env)
    if not A.bettingAvailable then return end
    local ok,registered=pcall(api.RegisterAddonMessagePrefix,"ClearLootBets")
    if not ok or (registered~=nil and registered~=true and registered~=0) then A.bettingAvailable=false; return end
    local frame=CreateFrame("Frame"); A.betEventFrame=frame
    frame:RegisterEvent("CHAT_MSG_ADDON"); frame:RegisterEvent("GROUP_ROSTER_UPDATE"); frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent",function(_,event,prefix,message,channel,sender)
        if event=="CHAT_MSG_ADDON" then
            if prefix~="ClearLootBets" or (channel~="PARTY" and channel~="RAID" and channel~="INSTANCE_CHAT") then return end
            local _,names=A.BetMembers()
            local guid=names[normalized(sender)]
            if not guid and sender and not sender:find("-",1,true) then
                local _,full=A.CharacterIdentity({playerName=sender}); guid=names[normalized(full)]
            end
            if guid then A.betClient:Receive(guid,message) end
        else A.betClient:Hello() end
    end)
    A.betClient:Hello(true)
end
function A.HoldLootForBets(roll)
    local context=A.betClient and A.betClient.byRoll[roll]
    if not context or context.record.state~="OPEN" then return false end
    local snapshot=A.BetSnapshot(roll)
    return M.CanBet(context.record,snapshot)
end

local _,A=...
A.nativeCards={}
A.demoFrames={}
-- Siblings of Blizzard's frames: hiding/recycling a native roll must not hide
-- the retained result or turn a later item's controls into controls for this roll.
local function enabled()
    local gamepad=InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
    return A.db and A.db.presentation=="native" and not gamepad
end
function A.LayoutNative()
    local container=GroupLootContainer
    if not container or type(container.reservedSize)~="number" then return end
    if InCombatLockdown and InCombatLockdown() then return end
    A.nativeSpacing=A.nativeSpacing or container.reservedSize
    local size=A.nativeSpacing
    if enabled() then
        for _,r in ipairs(A.rolls) do
            if not r.demo and r.nativeAttached and r.nativeCard then
                size=math.max(size,(r.nativeFrame:GetHeight() or 80)+r.nativeCard:GetHeight()+16)
            end
        end
    end
    if container.reservedSize~=size then
        container.reservedSize=size
        if GroupLootContainer_Update then GroupLootContainer_Update(container) end
    end
    for i=1,4 do
        local f=_G["GroupLootFrame"..i]
        if f and f:IsShown() and f.rollID and A.byID[f.rollID] and enabled() then
            A.RestoreLootPosition(f,i)
        end
    end
end
function A.RenderAttachments()
    for _,r in ipairs(A.rolls) do
        r.nativeAttached=false
    end
    if enabled() and not A.historyView then
        for i=1,4 do
            local native=_G["GroupLootFrame"..i]
            local r=native and native.rollID and A.byID[native.rollID]
            if r and not r.demo and not r.dismissed and native:IsShown() then
                local card=A.nativeCards[i]
                if not card then
                    card=A.MakeCard(UIParent); card:SetFrameStrata("DIALOG")
                    A.nativeCards[i]=card
                end
                A.AttachTable(native,r,card,i)
            end
        end
    end
    for _,card in pairs(A.nativeCards) do
        if not card.roll or not card.roll.nativeAttached then card:Hide() end
    end
    A.RenderNativeDemo()
    A.LayoutNative()
end
function A.InitNativeUI()
    if GroupLootContainer_Update then
        hooksecurefunc("GroupLootContainer_Update",function() A.LayoutNative() end)
    end
    for i=1,4 do
        local native=_G["GroupLootFrame"..i]
        if native then
            native:HookScript("OnShow",function() C_Timer.After(0,function() A.Render() end) end)
            native:HookScript("OnHide",function() C_Timer.After(0,function() A.Render() end) end)
        end
    end
end

-- Live and preview frames use this exact table sizing/anchoring path.
function A.AttachTable(native,r,card,slot)
    r.nativeCard=card
    r.nativeSeen=true; r.nativeFrame=native; r.nativeAttached=true
    card.tableOnly=true; card.attached=true; card.tableWidth=math.max(260,native:GetWidth())
    card:SetScale(native:GetEffectiveScale()/UIParent:GetEffectiveScale())
    A.UpdateCard(card,r)
    card:ClearAllPoints(); card:SetPoint("TOP",native,"BOTTOM",0,-2)
    card:Show(); r.frame=card
    A.EnableLootDragging(native,card,slot)
end
local function makeDemoFrame(index)
    if A.demoTemplateWarning then return nil end
    local ok,f=pcall(CreateFrame,"Frame","ClearLootDemoLootFrame"..index,UIParent,"ClearLootDemoLootFrameTemplate")
    if not ok or not f or not f.IconFrame or not f.Name or not f.Timer or not f.LootButtonContainer then
        if not A.demoTemplateWarning then
            print("ClearLoot 0.6.0: native dungeon-roll demo could not load. Restart the client to load Demo.xml. "..tostring(ok and "Missing Forever loot frame fields" or f))
            A.demoTemplateWarning=true
        end
        if ok and f then f:Hide() end
        return nil
    end
    f:UnregisterAllEvents()
    for _,script in ipairs({"OnShow","OnHide","OnEvent","OnUpdate"}) do f:SetScript(script,nil) end
    -- The inherited icon scripts query real roll IDs. Preview icons have only
    -- descriptive tooltips and never run those scripts or modified-item clicks.
    f.IconFrame:SetScript("OnUpdate",nil); f.IconFrame:SetScript("OnClick",nil)
    f.IconFrame:SetScript("OnEnter",function(icon)
        GameTooltip:SetOwner(icon,"ANCHOR_RIGHT")
        GameTooltip:SetText(f.roll.name.." (demo)"); GameTooltip:Show()
    end)
    f.IconFrame:SetScript("OnLeave",function() GameTooltip:Hide() end)
    for key,kind in pairs({NeedButton=1,GreedButton=2,PassButton=0,TransmogButton=4,DisenchantButton=3}) do
        local b=f.LootButtonContainer[key]
        if b then
            local choice=kind
            b:SetScript("OnClick",function() if f.roll then A.Choose(f.roll,choice) end end)
            b:SetScript("OnEnter",function()
                GameTooltip:SetOwner(b,"ANCHOR_RIGHT")
                GameTooltip:SetText((b.tooltipText or key).." (demo only)"); GameTooltip:Show()
            end)
            b:SetScript("OnLeave",function() GameTooltip:Hide() end)
        end
    end
    if f.NeedRollAnim then f.NeedRollAnim:Hide() end
    f.card=A.MakeCard(UIParent); f.card:SetFrameStrata("DIALOG")
    return f
end
function A.RenderNativeDemo()
    for _,f in ipairs(A.demoFrames) do f.demoVisible=false end
    if A.demoContainer then A.demoContainer:Hide() end
    local function hideUnused()
        for _,f in ipairs(A.demoFrames) do
            if not f.demoVisible then f:Hide(); f.card:Hide() end
        end
    end
    if A.historyView then hideUnused(); return end
    local hasDemo=false
    for _,r in ipairs(A.rolls) do if r.demo and not r.dismissed then hasDemo=true; break end end
    if not hasDemo or A.demoTemplateWarning then hideUnused(); return end
    if not GroupLootContainer_AddFrame or not GroupLootContainer_Update then
        A.demoTemplateWarning=true
        print("ClearLoot 0.6.0: this client has no native loot container layout functions; demo stopped.")
        return
    end
    local visible={}; local height=0; local tableHeight=0
    if not A.demoContainer then
        local c=CreateFrame("Frame","ClearLootDemoLootContainer",UIParent)
        c:SetSize(256,1); c:SetFrameStrata("DIALOG")
        c:SetPoint("BOTTOM",UIParent,"BOTTOM",0,60)
        -- Blizzard's native layout calls its managed-alert parent. This preview
        -- container is independent, so it keeps its own anchor and never docks
        -- into the player's live alert stack.
        c.layoutParent={Layout=function() end}
        c.waitingRolls={}; c.rollFrames={}; c.maxIndex=0; c.reservedSize=100
        A.demoContainer=c
    end
    local container=A.demoContainer
    container.rollFrames={}; container.maxIndex=0; container.reservedSize=100
    for _,r in ipairs(A.rolls) do
        if r.demo and not r.dismissed then
            local index=#visible+1
            local f=A.demoFrames[index]
            if not f then f=makeDemoFrame(index); A.demoFrames[index]=f end
            if f then
                f.roll=r -- Intentionally no rollID: never impersonate a live roll.
                f.Name:SetText(r.name); f.IconFrame.Icon:SetTexture(r.texture)
                if f.IconFrame.Count then f.IconFrame.Count:Hide() end
                f.Timer:SetMinMaxValues(0,r.duration)
                f.Timer:SetValue(r.finished and 0 or math.max(0,r.started+r.duration-GetTime()))
                for key,kind in pairs({NeedButton=1,GreedButton=2,PassButton=0,TransmogButton=4,DisenchantButton=3}) do
                    local b=f.LootButtonContainer[key]
                    if b then
                        b:SetShown(not not r.allowed[kind])
                        b:SetEnabled(not r.finished and not r.choice)
                    end
                end
                f.demoVisible=true
                A.AttachTable(f,r,f.card,index)
                visible[#visible+1]=f
                local slot=f:GetHeight()+f.card:GetHeight()+18
                container.reservedSize=math.max(container.reservedSize,slot)
                height=math.max(height,slot); tableHeight=math.max(tableHeight,f.card:GetHeight())
            end
        end
    end
    hideUnused()
    if #visible==0 then container:Hide(); return end
    for _,f in ipairs(visible) do
        if f.clearLootDragging then container:Show(); return end
    end
    -- Use the game client's normal dungeon-roll placement function. The only
    -- simulated pieces are item/participant data and the choice callbacks.
    local scale=math.min(A.db.scale,math.max(0.1,(UIParent:GetHeight()-120)/math.max(1,height*#visible)))
    container:SetScale(scale)
    -- Native slots center the header; include the table's downward overhang
    -- when placing the independent preview stack above the bottom screen edge.
    container:ClearAllPoints(); container:SetPoint("BOTTOM",UIParent,"BOTTOM",0,60/scale+tableHeight/2)
    for _,f in ipairs(visible) do
        f:SetScale(scale); f.card:SetScale(scale)
        GroupLootContainer_AddFrame(container,f)
    end
    for _,f in ipairs(visible) do A.RestoreLootPosition(f,f.clearLootSlot) end
end

-- Position the header and let the table follow its anchor. Store UIParent-space
-- coordinates so changing the preview scale does not change the saved location.
function A.RestoreLootPosition(frame,slot)
    local p=A.db.lootPositions[slot]
    if not p or frame.clearLootDragging then return end
    local ratio=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
    frame:ClearAllPoints(); frame:SetPoint("CENTER",UIParent,"CENTER",p.x/ratio,p.y/ratio)
end
function A.EnableLootDragging(native,card,slot)
    native.clearLootSlot=slot
    native:SetMovable(true); native:SetClampedToScreen(true)
    if not card.dragHandle then
        local handle=CreateFrame("Frame",nil,card)
        card.dragHandle=handle; handle:EnableMouse(true); handle:RegisterForDrag("LeftButton")
        handle:SetPoint("TOPLEFT",8,-4); handle:SetPoint("TOPRIGHT",-8,-4); handle:SetHeight(25)
        handle:SetScript("OnDragStart",function(self)
            local frame=self.owner
            if A.db.locked or (not self.roll.demo and InCombatLockdown and InCombatLockdown()) then return end
            frame.clearLootDragging=true; frame:StartMoving()
        end)
        handle:SetScript("OnDragStop",function(self)
            local frame=self.owner
            if not frame.clearLootDragging then return end
            frame:StopMovingOrSizing(); frame.clearLootDragging=false
            local x,y=frame:GetCenter(); local px,py=UIParent:GetCenter()
            local ratio=frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
            A.db.lootPositions[frame.clearLootSlot]={x=x*ratio-px,y=y*ratio-py}
            A.Render()
        end)
    end
    card.dragHandle.owner=native; card.dragHandle.roll=card.roll
    native.clearLootDragHandle=card.dragHandle
    if not card.wholePanelDrag then
        card.wholePanelDrag=true
        card:EnableMouse(true); card:RegisterForDrag("LeftButton")
        card:SetScript("OnDragStart",function()
            local handle=card.dragHandle
            handle:GetScript("OnDragStart")(handle)
        end)
        card:SetScript("OnDragStop",function()
            local handle=card.dragHandle
            handle:GetScript("OnDragStop")(handle)
        end)
    end
    if not native.clearLootWholeDrag then
        native.clearLootWholeDrag=true
        local function start()
            local handle=native.clearLootDragHandle
            if handle and handle.roll and handle.roll.nativeAttached and
                (handle.roll.demo or enabled()) then handle:GetScript("OnDragStart")(handle) end
        end
        local function stop()
            local handle=native.clearLootDragHandle
            if handle then handle:GetScript("OnDragStop")(handle) end
        end
        -- Leave all existing native scripts and loot-button clicks in place.
        -- The icon consumes mouse input, so it forwards dragging separately.
        for _,surface in ipairs({native,native.IconFrame}) do
            surface:EnableMouse(true); surface:RegisterForDrag("LeftButton")
            surface:HookScript("OnDragStart",start); surface:HookScript("OnDragStop",stop)
        end
    end
    A.RestoreLootPosition(native,slot)
end

    local enabled,statuses={},{}
    local currentId="farm"
    local collectTouches,collectTouchAt=0,-math.huge
    local inventory,inventoryAt,inventoryValid={},-math.huge,false
    local inventoryNext=0
    local spent=0
    local gachaVerify,storeVerify,gachaUncertain=nil,nil,false
    local storedRejected=setmetatable({},{__mode="k"})
    local questSentAt,questAttempts,ownedQuest=0,0,nil
    local masteryStart,masteryLast,masteryKills,masteryTarget=0,0,0,nil
    local observedDamage,healthTrack=0,setmetatable({},{__mode="k"})
    local function state(id,value,reason) statuses[id]={state=value,reason=reason or ""} end
    local function wallet() local d=player:FindFirstChild("Data");local b=d and d:FindFirstChild("Beli");return b and b.Value or 0 end
    local function budget(price,maxBudget)
        return maxBudget>0 and spent+price<=maxBudget and wallet()-price>=config.reserve
    end
    local function carried()
        local result={}
        for _,bag in pairs({player:FindFirstChild("Backpack"),player.Character}) do
            for _,tool in ipairs(bag:GetChildren()) do if tool:IsA("Tool") then result[tool]=true end end
        end
        return result
    end
    local function ownsTool(tool)
        local bag=player:FindFirstChild("Backpack")
        return tool.Parent and ((bag and tool:IsDescendantOf(bag)) or (player.Character and tool:IsDescendantOf(player.Character)))
    end
    local function excluded(name)
        for part in (config.excludeFruits or ""):gmatch("[^,]+") do
            if part:match("^%s*(.-)%s*$")==name then return true end
        end
        return false
    end
    local function requestInventory(now)
        if now<inventoryNext or transport:has("inventory") then return end
        inventoryNext=now+10
        transport:send("inventory",{"getInventory"},function(ok,result)
            if not ok or type(result)~="table" then inventoryValid=false;return end
            local fresh={}
            for _,entry in pairs(result) do
                if type(entry)=="table" and type(entry.Name)=="string" then
                    fresh[entry.Name]={count=tonumber(entry.Count) or 1,type=entry.Type,mastery=tonumber(entry.Mastery)}
                end
            end
            inventory,inventoryAt,inventoryValid=fresh,clock(),true
        end)
    end
    local function count(name)
        if not inventoryValid or clock()-inventoryAt>20 then return nil end
        return inventory[name] and inventory[name].count or 0
    end
    transport.beforeSend=function(request)
        if request.id=="gacha" or request.id=="shop" then
            request.estimate=request.id=="gacha" and config.gachaMaxPrice or config.shopMaxPrice
            request.balance=wallet();spent=spent+request.estimate
        end
    end
    transport.afterResponse=function(request)
        if request.balance then spent=spent+math.max(0,request.balance-wallet()-(request.estimate or 0)) end
    end
    carriedFruit=function(now)
        for tool in pairs(carried()) do
            local name=FRUIT_IDS[tool.Name]
            if name and not storedRejected[tool] and not excluded(tool.Name) and now>=(storeTried[tool] or 0) then return tool,name end
        end
    end
    local rawSend=transport.send
    function transport:send(id,args,callback,guard)
        local original=guard
        if id=="shop" then guard=function() return enabled.shop and budget(config.shopMaxPrice,config.shopBudget) and (not original or original()) end end
        return rawSend(self,id,args,callback,guard)
    end
    function adapter.maintenance(now,allowRequests)
        if closed then return end
        if allowRequests~=false and (enabled.item or enabled.fruit or enabled.sword) then requestInventory(now) end
        if gachaVerify then
            local before=gachaVerify.before
            for tool in pairs(carried()) do
                if not before[tool] and tool.Name:find("Fruit",1,true) then
                    state("gacha","en attente","Fruit physique confirme : "..tool.Name.."; attente du prochain delai")
                    say("Gacha : fruit physique recu : "..tool.Name)
                    gachaVerify=nil;break
                end
            end
            if gachaVerify and now-gachaVerify.at>8 then
                gachaUncertain=true;state("gacha","erreur","Fruit non confirme; aucune nouvelle depense")
                say("Gacha incertain : aucun fruit physique confirme");gachaVerify=nil
            end
        end
        if storeVerify and now-storeVerify.at>=2 then
            if allowRequests~=false then requestInventory(now) end
            local s=storeVerify;local n=count(s.name)
            if not ownsTool(s.tool) and n and inventoryAt>s.at and n>s.before then
                state("fruit","en attente","Stockage confirme : "..s.tool.Name);say("Stockage confirme : "..s.tool.Name);storeVerify=nil
            elseif now-s.at>15 then
                storedRejected[s.tool]=true
                state("fruit","en attente","Stockage non confirme/refuse; fruit conserve, essai bloque")
                say("Stockage non confirme; verifier capacite et inventaire");storeVerify=nil
            end
        end
    end
    function adapter.setEnabled(id,value)
        enabled[id]=value;transport:cancel(id)
        if value then state(id,"en attente","") else state(id,"desactivee","") end
    end
    function adapter.pauseRequests() transport.paused=true;transport:cancel() end
    function adapter.resumeRequests() transport.paused=false end
    function adapter.taskStatus(id)
        local s=statuses[id] or {state="en attente",reason=""}
        if movement.goal and currentId==id and s.state~="erreur" then return {state="en deplacement",reason=s.reason} end
        return s
    end
    function adapter.canClose() return not movement.blocked end
    function adapter.recover(retry) return movement:stop(retry) end
    function adapter.resetStore() storedRejected=setmetatable({},{__mode="k"});state("fruit","en attente","Nouvel essai demande") end
    local function adoptQuest(ui)
        local level=player.Data.Level.Value
        for _,q in ipairs(QUESTS) do
            if q.sea==sea and q.level<=level and questMatches(ui,q.name) then return q end
        end
    end
    local function ensureQuest(now)
        local ui=questUI()
        if not ui then error("Interface de quete non detectee") end
        local level=player.Data.Level.Value
        if ui.Visible then
            local actual=adoptQuest(ui)
            local expected=ownedQuest or chooseQuest(sea,level,config.bosses,function(name) return enemies[name]~=nil end)
            if actual and expected and actual.quest==expected.quest and actual.index==expected.index then
                activeQuest=actual;questAttempts=0;return true
            end
            if config.replaceQuest then
                if not transport:has("quest") then
                    transport:send("quest",{"AbandonQuest"},function() questSentAt=clock() end,function() return enabled.farm or enabled.quest end)
                end
                state(currentId,"en attente","Remplacement de quete autorise; verification de l'affichage")
            else state(currentId,"en attente","Conflit avec une quete manuelle; remplacement OFF") end
            return false
        end
        -- Updated identifiers/positions cannot be reconstructed from wiki prose.
        if (sea==1 and level>=225 and level<250) or (sea==3 and level>=1575 and level<1700) then
            error("Zone remaniee : identifiants de quete non verifies; utiliser Auto Boss ou une quete manuelle reconnue")
        end
        if sea==3 and level>=2550 then error("Catalogue historique limite; nouveau palier non valide") end
        if transport:has("quest") or now-questSentAt<5 then return false end
        if questAttempts>=2 then error("Quete non acceptee apres deux demandes; catalogue/API a verifier") end
        activeQuest=chooseQuest(sea,level,config.bosses,function(name) return enemies[name]~=nil end)
        if not activeQuest then error("Aucune quete compatible") end
        state(currentId,"en deplacement","PNJ / "..activeQuest.name.." (catalogue historique)")
        if moveTo(activeQuest.pos,3) then
            local q=activeQuest
            if transport:send("quest",{"StartQuest",q.quest,q.index},function(ok,result)
                questSentAt=clock();ownedQuest=q
                if not ok then state(currentId,"erreur","Demande refusee: "..tostring(result)) end
            end,function() return enabled.farm or enabled.quest end) then questAttempts=questAttempts+1;questSentAt=now end
        end
        return false
    end
    farm=function(now)
        local c=character();if not c then state("farm","en attente","Respawn");activeQuest=nil;return false end
        refreshEnemies(now)
        if not ensureQuest(now) then return false end
        return fightNamed(activeQuest.name,activeQuest.spawn,now)
    end
    local function findTool(name)
        for tool in pairs(carried()) do if tool.Name==name then return tool end end
    end
    local function fightTarget(name)
        local _,_,root=character();if not root then return end
        local target,distance=nil,math.huge
        for _,model in ipairs(enemies[name] or {}) do
            local r=model:FindFirstChild("HumanoidRootPart");local h=model:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health>0 then local d=(root.Position-r.Position).Magnitude;if d<distance then target,distance=model,d end end
        end
        return target
    end
    local function mastery(now)
        local tool=findTool(config.masteryTool)
        if not tool then error("Equipement mastery non possede; selectionner son nom exact") end
        local value=tool:FindFirstChild("Level")
        if not value or type(value.Value)~="number" then error("Mastery de cet outil non observable") end
        if tool.ToolTip~="Sword" and tool.ToolTip~="Melee" then error("Fruit/Gun : skills/aim non valides; module non pris en charge") end
        if value.Value>=config.masteryGoal then state("mastery","terminee","Mastery cible confirmee : "..value.Value);return true end
        if masteryStart==0 then masteryStart=value.Value;masteryLast=value.Value end
        if value.Value>masteryLast then masteryLast=value.Value;masteryKills=0 end
        refreshEnemies(now)
        local q=chooseQuest(sea,player.Data.Level.Value,false,function() return false end)
        if not q then error("Aucune cible connue pour mastery") end
        local target=fightTarget(q.name)
        if not target then state("mastery","en attente","Attente ennemi; aucune mastery supposee");return moveTo(q.spawn,5) end
        if masteryTarget and masteryTarget~=target then
            local previous=masteryTarget:FindFirstChildOfClass("Humanoid")
            if previous and previous.Health<=0 then masteryKills=masteryKills+1 end
        end
        masteryTarget=target
        if masteryKills>=6 then error("Aucune augmentation de mastery apres six cibles; arret") end
        local h=target:FindFirstChildOfClass("Humanoid")
        local previous=healthTrack[target]
        if previous and previous.primary and previous.health>h.Health then observedDamage=math.max(observedDamage,previous.health-h.Health) end
        local oldWeapon,oldExact=config.weapon,config.exactWeapon
        local finish=h.Health<=math.max(h.MaxHealth*config.masteryThreshold,observedDamage*1.5)
        healthTrack[target]={health=h.Health,primary=not finish}
        if finish then config.weapon=tool.ToolTip;config.exactWeapon=tool.Name end
        local ok,result=pcall(fightNamed,q.name,q.spawn,now)
        config.weapon,config.exactWeapon=oldWeapon,oldExact
        if not ok then error(result) end
        state("mastery","en combat","Mastery "..value.Value.." / "..config.masteryGoal..(finish and " — arme a entrainer" or " — affaiblissement"))
        return result
    end
    local function itemFarm(now)
        local objective=config.itemObjective
        if not objective or objective.sea~=sea then error("Objet incompatible avec la mer actuelle") end
        local n=count(objective.name)
        if n==nil then state("item","en attente","Inventaire serveur non confirme");requestInventory(now);return true end
        if n>=config.itemQuantity then state("item","terminee",objective.name.." : quantite confirmee "..n);return true end
        local q,chosen
        for _,name in ipairs(objective.enemies) do
            if enemies[name] then chosen=name;break end
        end
        for _,entry in ipairs(QUESTS) do
            if entry.sea==sea and entry.name==(chosen or objective.enemies[1]) then q=entry;break end
        end
        if not q then error("Source sans destination validee") end
        state("item","en combat",objective.name.." : "..n.." / "..config.itemQuantity.." ; aucun drop garanti")
        return fightNamed(chosen or q.name,q.spawn,now)
    end
    local function bossFarm(now)
        local target=config.bossTarget
        if not target then error("Selectionner un boss") end
        state("boss","en combat","Combat du boss charge : "..target)
        return fightNamed(target,nil,now)
    end
    local function eventFarm(now)
        local event=config.eventObjective
        if not event or event.sea~=sea then error("Evenement incompatible avec cette mer") end
        if not event.enemies then error(event.name.." : "..event.status.." / "..event.needs) end
        for _,name in ipairs(event.enemies) do
            if enemies[name] then state("event","en combat",event.name.." — boss deja present, aucune invocation");return fightNamed(name,nil,now) end
        end
        return true
    end
    local oldReady,oldStep=adapter.ready,adapter.step
    function adapter.ready(id,now)
        adapter.maintenance(now);refreshEnemies(now)
        if closed then return false end
        if id=="boss" then local found=config.bossTarget and enemies[config.bossTarget]~=nil;if not found then state(id,"en attente","Boss non detecte dans la zone chargee") end;return found end
        if id=="event" then
            local event=config.eventObjective
            if not event or not event.enemies then state(id,"en attente",event and event.status or "Choisir un evenement");return false end
            if event.sea~=sea then state(id,"en attente","Aller en mer "..event.sea);return false end
            for _,name in ipairs(event.enemies) do if enemies[name] then return true end end
            state(id,"en attente","Evenement non detecte dans la zone chargee");return false
        end
        if id=="mastery" or id=="item" then return true end
        if id=="quest" then local ui=questUI();return not ui or not ui.Visible end
        if id=="fruit" then return not storeVerify and not transport:has(id) and carriedFruit(now)~=nil end
        if id=="gacha" then return not gachaVerify and not gachaUncertain and not transport:has(id) and now>=nextGacha end
        if id=="sword" then
            if sea~=2 then state(id,"en attente","Sea 2 requise; aucun changement de mer automatique");return false end
            state(id,"erreur","Protocoles consultation/achat non confirmes; aucun achat automatique lance")
            return false
        end
        if id=="shop" and transport:has(id) then return false end
        return oldReady(id,now)
    end
    function adapter.step(id,now)
        currentId=id
        if id=="mastery" then return mastery(now) end
        if id=="item" then return itemFarm(now) end
        if id=="boss" then return bossFarm(now) end
        if id=="event" then return eventFarm(now) end
        if id=="quest" then ensureQuest(now);return true end
        if id=="collect" then
            if not collectTarget then collectTarget=nearestFruit(now);collectStart=now;collectTouches=0;collectTouchAt=-math.huge end
            local fruit=collectTarget
            if not fruit then return true end
            if ownsTool(fruit) then
                state(id,"en attente","Fruit physique dans le Backpack/personnage")
                say("Collecte confirmee : "..fruit.Name.."; reprise des options actives")
                collectTarget=nil;stopMovement();return true
            end
            if not isGround(fruit) or now-collectStart>20 then
                collectTried[fruit]=now+90;collectTarget=nil;stopMovement()
                state(id,"en attente","Fruit disparu/inaccessible; reprise des options actives");return true
            end
            state(id,"en deplacement","Farm suspendu — collecte de "..fruit.Name)
            if moveTo(fruit.Handle.CFrame,2) and collectTouches<3 and now-collectTouchAt>=1 then
                collectTouches=collectTouches+1;collectTouchAt=now
                local _,h,root=character()
                if type(firetouchinterest)=="function" and root then
                    pcall(function() firetouchinterest(root,fruit.Handle,0);firetouchinterest(root,fruit.Handle,1) end)
                elseif h then h:MoveTo(fruit.Handle.Position) end
                state(id,"en attente","Ramassage tente; presence a confirmer")
            end
            return false
        end
        if id=="gacha" then
            local data=player:FindFirstChild("Data");local level=data and data:FindFirstChild("Level")
            if not level or level.Value<50 then error("Gacha : niveau 50 requis") end
            local price=config.gachaMaxPrice
            if not budget(price,config.gachaBudget) then state(id,"en attente","Budget/prix maximal/reserve insuffisants");return true end
            local before=carried()
            transport:send(id,{"Cousin","Buy"},function(ok,result)
                nextGacha=clock()+7200
                gachaVerify={before=before,at=clock()}
                state(id,"en attente","Verification du fruit; reponse : "..tostring(result):sub(1,80))
            end,function() return enabled.gacha and budget(price,config.gachaBudget) end)
            state(id,"en attente","Demande unique en file; cooldown serveur prioritaire");return true
        end
        if id=="fruit" then
            local tool,name=carriedFruit(now)
            if not tool or storedRejected[tool] or excluded(tool.Name) then return true end
            local before=count(name)
            if before==nil then requestInventory(now);state(id,"en attente","Inventaire/capacite serveur non confirmes");return true end
            storeTried[tool]=now+30
            local sent=transport:send(id,{"StoreFruit",name,tool},function(ok,result)
                if not ok or result~=true then
                    storedRejected[tool]=true;state(id,"en attente","Stockage refuse/non reconnu : "..tostring(result):sub(1,100))
                else storeVerify={tool=tool,name=name,before=before,at=clock()};inventoryNext=0 end
            end,function() return enabled.fruit and ownsTool(tool) and not excluded(tool.Name) end)
            state(id,"en attente",sent and "Verification serveur du stockage" or "Transport occupe");return true
        end
        if id=="shop" then
            if not budget(config.shopMaxPrice,config.shopBudget) then state(id,"en attente","Configurer budget/prix maximal/reserve boutique");return true end
        end
        local done=oldStep(id,now)
        if movement.goal then state(id,"en deplacement",lastMessage)
        elseif lastMessage:find("Combat",1,true) then state(id,"en combat",lastMessage)
        else state(id,"en attente",lastMessage) end
        return done
    end
    local oldDiagnostics=adapter.diagnostics
    function adapter.diagnostics()
        local d=oldDiagnostics();d.spent=spent;d.queue=#transport.queue;d.movementBlocked=movement.blocked;d.statuses=statuses
        return d
    end
    function adapter.suspend(id,transfer)
        if id=="farm" or id=="collect" or id=="race2" or id=="swordfarm" or id=="navigate" or
            id=="mastery" or id=="item" or id=="boss" or id=="event" or id=="quest" then
            if transfer then return movement:handoff() end
            return movement:stop()
        end
        return true
    end
    function adapter.cleanupDeferred() return movement.deferred==true end
    function adapter.close(force)
        if closed then return true end
        if not movement:close(force) then return false end
        closed=true;transport:close();groundConnection:Disconnect();return true
    end

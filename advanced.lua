    -- Own implementation: normal input and visible dialogue, no guessed game remotes.
    local keysHeld,skillNext,skillCursor={},0,0
    local cameraSaved,skillLastTarget,skillHealth,skillDamageAt
    local inputService
    local function input()
        if not inputService then
            local ok,value=pcall(function() return game:GetService("VirtualInputManager") end)
            if not ok then error("Commandes virtuelles indisponibles dans cet executeur") end
            inputService=value
        end
        return inputService
    end
    local function key(keyName,down)
        if down==not not keysHeld[keyName] then return end
        local ok,err=pcall(function() input():SendKeyEvent(down,Enum.KeyCode[keyName],false,game) end)
        if not ok then error("Commande "..keyName.." refusee : "..tostring(err)) end
        keysHeld[keyName]=down and true or nil
    end
    local function releaseInput()
        for name in pairs(keysHeld) do pcall(function() input():SendKeyEvent(false,Enum.KeyCode[name],false,game) end) end
        keysHeld={}
        if cameraSaved and workspace.CurrentCamera then pcall(function() workspace.CurrentCamera.CFrame=cameraSaved end) end
        cameraSaved=nil
    end
    local pulseKey,pulseUntil
    local function pulse(name,now)
        if pulseKey then return false end
        key(name,true);pulseKey=name;pulseUntil=now+(config.skillHold or 0.15);return true
    end
    local priorMaintenance=adapter.maintenance
    function adapter.maintenance(now,allowRequests)
        priorMaintenance(now,allowRequests)
        if pulseKey and now>=pulseUntil then key(pulseKey,false);pulseKey=nil end
    end
    local function allVisible(obj)
        while obj and obj~=player:FindFirstChild("PlayerGui") do
            if obj:IsA("GuiObject") and not obj.Visible then return false end
            if obj:IsA("ScreenGui") and not obj.Enabled then return false end
            obj=obj.Parent
        end
        return obj~=nil
    end
    local dialogCache,dialogAt={},-math.huge
    local function dialogs(now)
        if now-dialogAt<1 then return dialogCache end
        dialogAt=now;dialogCache={}
        local pg=player:FindFirstChild("PlayerGui")
        for _,obj in ipairs(pg and pg:GetDescendants() or {}) do
            if obj:IsA("Frame") and obj.Name:lower():find("dialog",1,true) and allVisible(obj) then
                local texts,buttons={},{}
                for _,child in ipairs(obj:GetDescendants()) do
                    if child:IsA("TextLabel") and allVisible(child) then texts[#texts+1]=child.Text end
                    if child:IsA("TextButton") and child.Active and allVisible(child) then buttons[#buttons+1]=child end
                end
                dialogCache[#dialogCache+1]={text=table.concat(texts," "),buttons=buttons,object=obj}
            end
        end
        return dialogCache
    end
    local function findDialog(now,context)
        for _,dialog in ipairs(dialogs(now)) do
            local lower=dialog.text:lower()
            for _,word in ipairs(context) do if lower:find(word:lower(),1,true) then return dialog end end
        end
    end
    local function actionButton(dialog,words)
        for _,button in ipairs(dialog.buttons) do
            local text=button.Text:lower():gsub("<[^>]+>","")
            for _,word in ipairs(words) do if text==word or text:find(word,1,true)==1 then return button end end
        end
    end
    local function clickButton(button)
        assert(allVisible(button) and button.Active,"Dialogue ferme ou bouton indisponible")
        local gui=services.polarisGui;local was=gui and gui.Enabled
        if gui then gui.Enabled=false end
        local ok,err=pcall(function()
            local pos=button.AbsolutePosition+button.AbsoluteSize/2
            input():SendMouseButtonEvent(pos.X,pos.Y,0,true,game,0)
            input():SendMouseButtonEvent(pos.X,pos.Y,0,false,game,0)
        end)
        if gui then gui.Enabled=was end
        if not ok then error("Interaction UI refusee : "..tostring(err)) end
        dialogAt=-math.huge
    end
    local function childPath(root,path)
        for _,name in ipairs(path) do root=root and root:FindFirstChild(name) end
        return root
    end
    local function positionOf(obj)
        if not obj then return end
        if obj:IsA("BasePart") then return obj.CFrame end
        if obj:IsA("Model") then local r=obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart;return r and r.CFrame end
    end
    local interactions={}
    local function interactNpc(name,id,now)
        local folder=workspace:FindFirstChild("NPCs");local npc=folder and folder:FindFirstChild(name)
        if not npc then state(id,"en attente",name.." non charge; pas de coordonnee inventee");return false end
        local pos=positionOf(npc)
        if not pos then error("PNJ sans position exploitable : "..name) end
        if not moveTo(pos*CFrame.new(0,0,3),3) then state(id,"en deplacement",name);return false end
        local item=interactions[id]
        if not item or item.npc~=npc then item={npc=npc,attempts=0,at=-math.huge};interactions[id]=item end
        if now-item.at<5 then return false end
        if item.attempts>=2 then error("Dialogue "..name.." non ouvert apres deux essais; interaction a verifier") end
        item.attempts=item.attempts+1;item.at=now
        local prompt=npc:FindFirstChildWhichIsA("ProximityPrompt",true)
        local detector=npc:FindFirstChildWhichIsA("ClickDetector",true)
        if prompt and prompt.Enabled and type(fireproximityprompt)=="function" then fireproximityprompt(prompt)
        elseif detector and type(fireclickdetector)=="function" then fireclickdetector(detector)
        else pulse("E",now) end
        state(id,"en attente","Ouverture du dialogue; reponse visible requise")
        return false
    end
    local function beliPrice(text)
        if text:lower():find("robux",1,true) or text:find("R$",1,true) or text:find(utf8.char(0xE002),1,true) then return end
        local raw=text:match("%$%s*([%d,%. ]+)") or text:match("([%d,%. ]+)%s*[Bb]eli")
        if not raw then return end
        raw=raw:gsub("[,%. ]","");local n=tonumber(raw)
        if n and n>0 then return n end
    end
    -- Accept known historical/current labels only when they are observed in UI/inventory.
    local legendaryNames={Saddi={"Saddi","Saishi"},Shisui={"Shisui","Shizu"},Wando={"Wando","Oroshi"}}
    local function legendaryCount(name)
        local total=0
        for _,alias in ipairs(legendaryNames[name]) do
            local n=count(alias);if n==nil then return nil end
            total=math.max(total,n)
        end
        return total
    end
    local function offeredSword(text)
        local match
        text=text:lower()
        for name,aliases in pairs(legendaryNames) do
            local found=false
            for _,alias in ipairs(aliases) do
                if text:find("%f[%a]"..alias:lower().."%f[%A]") then found=true end
            end
            if found then if match then return nil end;match=name end
        end
        return match
    end
    local legendaryPending,legendarySpent,legendaryAt=nil,0,0
    local legendaryBlocked=false
    local function legendary(now)
        requestInventory(now)
        if legendaryPending then
            local s=legendaryPending;local n=legendaryCount(s.name)
            if inventoryAt>s.at and n and n>0 then
                state("sword","en attente","Possession confirmee : "..s.name);legendaryPending=nil
                legendaryAt=now+15;return true
            end
            if now-s.at>18 then legendaryBlocked=true;legendaryPending=nil;error("Achat non confirme; aucun deuxieme achat automatique") end
            state("sword","en attente","Verification inventaire de "..s.name);return false
        end
        if legendaryBlocked then error("Achat precedent incertain; verifier inventaire avant un rechargement") end
        local wanted,missing={},false
        for rawName in (config.legendaryTargets or "Saddi,Shisui,Wando"):gmatch("[^,]+") do
            local name=rawName:match("^%s*(.-)%s*$")
            if name~="Saddi" and name~="Shisui" and name~="Wando" then error("Selection legendaire invalide : "..name) end
            local n=legendaryCount(name);if n==nil then state("sword","en attente","Inventaire serveur requis");return true end
            if n==0 then wanted[name]=true;missing=true end
        end
        if not missing then state("sword","terminee","Toutes les epees selectionnees sont possedees");return true end
        if now<legendaryAt then return true end
        local dialog=findDialog(now,{"legendary sword dealer","saddi","shisui","wando","saishi","shizu","oroshi"})
        if not dialog then return interactNpc("Legendary Sword Dealer","sword",now) end
        interactions.sword=nil
        local buy=actionButton(dialog,{"buy","purchase","acheter"})
        local offered=buy and (offeredSword(buy.Text) or offeredSword(dialog.text))
        if not offered or not buy then state("sword","en attente","Offre absente/ambigue ou achat explicite indisponible");legendaryAt=now+10;return true end
        if not wanted[offered] then state("sword","en attente","Epee proposee deja possedee; attente d'une offre manquante");legendaryAt=now+15;return true end
        local context=dialog.text.." "..buy.Text
        if context:lower():find("robux",1,true) or context:find("R$",1,true) or context:find(utf8.char(0xE002),1,true) then error("Robux dans le dialogue : aucun achat automatique") end
        local price=beliPrice(buy.Text) or beliPrice(dialog.text)
        if not price then error("Prix Beli absent/ambigu ou Robux; achat bloque") end
        if price>config.legendaryMaxPrice or legendarySpent+price>config.legendaryBudget or wallet()-price<config.reserve then
            state("sword","en attente","Beli insuffisants, reserve ou plafond interne atteint");legendaryAt=now+15;return true
        end
        legendarySpent=legendarySpent+price
        legendaryPending={name=offered,at=now};inventoryNext=0
        clickButton(buy)
        state("sword","en attente","Achat unique envoye via dialogue; possession a confirmer")
        return false
    end
    local function skillCombat(target,tool,now,hoverCombat,taskId)
        local c,h,r=character();if not c then releaseInput();return false end
        local er=target and target:FindFirstChild("HumanoidRootPart")
        local eh=target and target:FindFirstChildOfClass("Humanoid")
        if not er or not eh or eh.Health<=0 then releaseInput();return false end
        if skillLastTarget~=target then skillLastTarget=target;skillHealth=eh.Health;skillDamageAt=now end
        if eh.Health<skillHealth then skillHealth=eh.Health;skillDamageAt=now end
        if now-skillDamageAt>20 then releaseInput();error("Aucun degat confirme en 20 s; skills/equipement a verifier") end
        local distance=(r.Position-er.Position).Magnitude
        if movement.goal or distance>config.skillRange then
            releaseInput()
            if not moveTo(er.CFrame*CFrame.new(0,2,config.skillRange*0.6),3) then return false end
            if (r.Position-er.Position).Magnitude>config.skillRange then return false end
        end
        if hoverCombat then services.characterController:setFlying(true)
        elseif not stopMovement() then error(movement.blocked) end
        if tool.Parent~=c then h:EquipTool(tool) end
        r.CFrame=CFrame.lookAt(r.Position,Vector3.new(er.Position.X,r.Position.Y,er.Position.Z))
        if now<skillNext or pulseKey then return false end
        if config.skillAim then
            local camera=workspace.CurrentCamera
            if not camera then error("Camera absente pour viser") end
            if not cameraSaved then cameraSaved=camera.CFrame end
            camera.CFrame=CFrame.lookAt(camera.CFrame.Position,er.Position)
            input():SendMouseMoveEvent(camera.ViewportSize.X/2,camera.ViewportSize.Y/2,game)
        end
        local selected={}
        for rawName in (config.skillKeys or "Z,X"):gmatch("[^,]+") do
            local name=rawName:upper():gsub("%s","")
            if name~="Z" and name~="X" and name~="C" and name~="V" then error("Touches skills permises : Z,X,C,V (pas de transformation F)") end
            selected[#selected+1]=name
        end
        if #selected==0 then error("Choisir au moins un skill debloque") end
        skillCursor=skillCursor%#selected+1;pulse(selected[skillCursor],now)
        if tool.ToolTip=="Gun" then tool:Activate() end
        skillNext=now+config.skillInterval
        state(taskId or "mastery","en combat","Commandes normales / "..selected[skillCursor].." ; degats/mastery observes")
        return false
    end
    local priorMastery=mastery
    mastery=function(now)
        local tool=findTool(config.masteryTool)
        if not tool then error("Equipement mastery non possede") end
        if tool.ToolTip~="Gun" and tool.ToolTip~="Blox Fruit" then return priorMastery(now) end
        local value=tool:FindFirstChild("Level")
        if not value or type(value.Value)~="number" then error("Mastery non observable sur l'outil selectionne") end
        if value.Value>=config.masteryGoal then releaseInput();state("mastery","terminee","Mastery cible confirmee");return true end
        refreshEnemies(now)
        local q=chooseQuest(sea,player.Data.Level.Value,false,function() return false end)
        if not q then error("Aucune cible connue") end
        local target=fightTarget(q.name)
        if not target then releaseInput();state("mastery","en attente","Attente de "..q.name);moveTo(q.spawn,5);return false end
        if value.Value>masteryLast then masteryLast=value.Value;masteryKills=0 end
        if masteryTarget and masteryTarget~=target then
            local prior=masteryTarget:FindFirstChildOfClass("Humanoid")
            if prior and prior.Health<=0 then masteryKills=masteryKills+1 end
        end
        masteryTarget=target
        if masteryKills>=6 then releaseInput();error("Mastery Fruit/Gun non augmentee apres six cibles; arret") end
        local h=target:FindFirstChildOfClass("Humanoid")
        if h.Health>math.max(h.MaxHealth*config.masteryThreshold,observedDamage*1.5) then
            releaseInput();local previous=healthTrack[target]
            local oldHealth=type(previous)=="table" and previous.health or previous
            if oldHealth and oldHealth>h.Health then observedDamage=math.max(observedDamage,oldHealth-h.Health) end
            healthTrack[target]={health=h.Health,primary=true};return fightNamed(q.name,q.spawn,now)
        end
        return skillCombat(target,tool,now)
    end
    -- Character movement never controls a boat. Only normal seat controls are used.
    local boatSeat,boatBest,boatProgress,boatGoal=nil,math.huge,0,nil
    local boatOriginal
    local function boatStop()
        releaseInput();pulseKey=nil
        if boatSeat and boatOriginal then pcall(function() boatSeat.ThrottleFloat=boatOriginal.throttle;boatSeat.SteerFloat=boatOriginal.steer end) end
        boatOriginal=nil;boatBest=math.huge;boatGoal=nil
    end
    local function boat(now)
        local c,h,r=character();if not c then boatStop();state("boat","en attente","Respawn");return false end
        local dest=config.boatDestination
        if not dest then state("boat","en attente","Choisir une destination maritime");return true end
        local seat=h.SeatPart
        if not seat or not seat:IsA("VehicleSeat") then
            boatStop()
            if boatSeat and boatSeat.Parent then
                local owner=boatSeat:FindFirstAncestorOfClass("Model");owner=owner and owner:FindFirstChild("Owner")
                if owner and tostring(owner.Value)~=player.Name then boatSeat=nil end
            end
            if not boatSeat then
                local boats=workspace:FindFirstChild("Boats")
                for _,model in ipairs(boats and boats:GetChildren() or {}) do
                    local owner=model:FindFirstChild("Owner")
                    if owner and tostring(owner.Value)==player.Name then boatSeat=model:FindFirstChildWhichIsA("VehicleSeat",true);if boatSeat then break end end
                end
            end
            if not boatSeat then state("boat","en attente","Aucun bateau possede charge. Achete-en un manuellement puis assieds-toi.");return true end
            if moveTo(boatSeat.CFrame*CFrame.new(0,2,0),3) then boatSeat:Sit(h) end
            state("boat","en deplacement","Rejoindre son siege; controle bateau encore OFF");return false
        end
        if not stopMovement() then error(movement.blocked) end
        if services.characterController.flying then error("Vol incompatible avec navigation") end
        if boatSeat~=seat then boatStop();boatSeat=seat end
        if not boatOriginal then boatOriginal={throttle=seat.ThrottleFloat,steer=seat.SteerFloat} end
        local delta=dest-seat.Position;delta=Vector3.new(delta.X,0,delta.Z)
        local distance=delta.Magnitude
        if boatGoal~=dest then boatGoal=dest;boatBest=distance;boatProgress=now end
        if distance<=config.boatTolerance then boatStop();state("boat","terminee","Destination maritime atteinte");return true end
        if distance<boatBest-2 then boatBest=distance;boatProgress=now end
        if now-boatProgress>20 then boatStop();error("Bateau immobile/corrige depuis 20 s; controle arrete") end
        local direction=delta.Unit
        local side=seat.CFrame.RightVector:Dot(direction)
        local forward=seat.CFrame.LookVector:Dot(direction)
        local steer=math.abs(side)<0.12 and 0 or (side>0 and 1 or -1)
        if forward<0 and steer==0 then steer=1 end
        key("A",steer<0);key("D",steer>0);key("W",forward>0.1)
        seat.SteerFloat=steer;seat.ThrottleFloat=forward>0.1 and 1 or 0
        state("boat","en deplacement","Navigation normale / "..math.floor(distance).." studs; aucun vol du bateau")
        return false
    end
    -- V3 uses Arowe's visible dialogue as the source of truth, not kill counters alone.
    local v3={stage="inspect",race=nil,at=0,bosses={},chests=0,seen=setmetatable({},{__mode="k"})}
    local chestCache,chestAt={},-math.huge
    local function chests(now)
        if now-chestAt<8 then return chestCache end
        chestAt=now;chestCache={}
        local ok,collection=pcall(function() return game:GetService("CollectionService") end)
        if ok then for _,obj in ipairs(collection:GetTagged("_ChestTagged")) do chestCache[#chestCache+1]=obj end end
        -- Historical direct children only; no complete Workspace scan every frame.
        for _,obj in ipairs(workspace:GetChildren()) do
            if obj.Name=="Chest1" or obj.Name=="Chest2" or obj.Name=="Chest3" then chestCache[#chestCache+1]=obj end
        end
        return chestCache
    end
    local chestPending
    local function chestStep(now)
        if chestPending then
            local p=chestPending
            if not p.object.Parent or p.object:GetAttribute("IsDisabled")==true then
                v3.chests=v3.chests+1;v3.seen[p.object]=true;chestPending=nil;return true
            end
            if now-p.at>6 then v3.seen[p.object]=true;chestPending=nil end
            return false
        end
        local _,_,r=character();if not r then return false end
        local target,distance=nil,math.huge
        for _,obj in ipairs(chests(now)) do
            local cf=positionOf(obj)
            if cf and obj.Parent and not v3.seen[obj] and not obj:GetAttribute("IsDisabled") then
                local d=(r.Position-cf.Position).Magnitude;if d<distance then target,distance=obj,d end
            end
        end
        if not target then state("race3","en attente","Aucun coffre accessible charge / "..v3.chests.." disparitions observees (compteur serveur non confirme)");return true end
        local cf=positionOf(target)
        if moveTo(cf,2) then
            local prompt=target:FindFirstChildWhichIsA("ProximityPrompt",true)
            if prompt and type(fireproximityprompt)=="function" then fireproximityprompt(prompt)
            elseif target:IsA("BasePart") and type(firetouchinterest)=="function" then firetouchinterest(r,target,0);firetouchinterest(r,target,1)
            else error("Coffre sans interaction prise en charge") end
            chestPending={object=target,at=now}
        end
        return false
    end
    local function race3(now)
        if sea~=2 then error("Arowe : mer 2 requise") end
        local data=player:FindFirstChild("Data");local race=data and data:FindFirstChild("Race")
        local level=data and data:FindFirstChild("Level")
        if not race or not level or level.Value<1000 then error("Race V3 : niveau 1000+ et race observables requis") end
        if race.Value=="Draco" then error("Draco utilise une autre chaine; Dragon Wizard non implemente") end
        if v3.race~=race.Value then v3={stage="inspect",race=race.Value,at=now,bosses={},chests=0,seen=setmetatable({},{__mode="k"})};chestPending=nil end
        local dialog=findDialog(now,{"arowe"})
        if dialog then
            local text=dialog.text:lower()
            if text:find("already evolved",1,true) or text:find("already unlocked",1,true) then
                state("race3","terminee","V3 deja debloquee selon Arowe");return true
            end
            local paid=actionButton(dialog,{"buy","purchase","acheter"})
            if paid then
                local price=beliPrice(dialog.text.." "..paid.Text)
                if not price or price>config.race3Budget or wallet()-price<config.reserve then error("Evolution V3 : prix visible/Beli/budget/reserve insuffisants") end
                if v3.stage=="paid" then state("race3","en attente","Evolution demandee; verification Arowe requise");return false end
                v3.stage="paid";v3.at=now;clickButton(paid);interactions.race3=nil
                state("race3","en attente","Paiement unique via dialogue; evolution non encore confirmee");return false
            end
            if v3.stage=="paid" then
                if text:find("congrat",1,true) or text:find("evolved",1,true) or text:find("upgraded",1,true) then
                    state("race3","terminee","Evolution confirmee par le dialogue serveur");return true
                end
                if now-v3.at>15 then error("Evolution V3 incertaine; aucun nouveau paiement") end
                return false
            end
            local accept=actionButton(dialog,{"accept","yes","accepter","oui"})
            if accept and v3.stage=="inspect" then
                if beliPrice(dialog.text.." "..accept.Text) then error("Etape payante non identifiee comme evolution; aucune validation aveugle") end
                v3.stage="accepting";v3.at=now;clickButton(accept);return false
            end
            if (v3.stage=="accepting" or v3.stage=="inspect") and not accept and
                (text:find("come back",1,true) or text:find("your task",1,true) or text:find("defeat",1,true) or text:find("collect 30",1,true) or text:find("show me",1,true)) then
                v3.stage="work";v3.at=now;state("race3","en attente","Objectif Arowe lu; progression serveur requise")
            end
        end
        if v3.stage=="inspect" or v3.stage=="accepting" or v3.stage=="paid" then
            if v3.stage=="accepting" and now-v3.at>20 then error("Acceptation V3 non confirmee dans le dialogue") end
            return interactNpc("Arowe","race3",now)
        end
        if v3.race=="Human" then
            for _,name in ipairs({"Diamond","Jeremy","Fajita"}) do
                local saved=v3.bosses[name]
                if saved and saved.model then
                    local health=saved.model:FindFirstChildOfClass("Humanoid")
                    if health and health.Health<=0 then saved.done=true;saved.model=nil end
                end
                if not saved or not saved.done then
                    local target=fightTarget(name)
                    if target then v3.bosses[name]={model=target};state("race3","en combat","Arowe / "..(ALIASES[name] or name));return fightNamed(name,nil,now) end
                    state("race3","en attente","Attente de "..(ALIASES[name] or name).." ; aucun credit serveur suppose")
                    for _,q in ipairs(QUESTS) do if q.sea==2 and q.name==name then moveTo(q.spawn,5);break end end
                    return false
                end
            end
        elseif v3.race=="Mink" or v3.race=="Rabbit" then
            if v3.chests<30 then return chestStep(now) end
        elseif v3.race=="Cyborg" then
            if not carriedFruit(now) then state("race3","en attente","Porter un fruit physique reconnu; jamais mange ou sacrifie");return true end
        elseif v3.race=="Fishman" or v3.race=="Shark" then
            state("race3","en attente","Sea Beast naturel requis. Combat maritime specifique non implemente; aucune fausse validation.");return true
        elseif v3.race=="Angel" or v3.race=="Skypiea" or v3.race=="Ghoul" then
            state("race3","en attente","Epreuve PvP a realiser manuellement; credits suspects refuses par le serveur ne sont pas simules.");return true
        else error("Race V3 inconnue") end
        v3.verifyAttempts=(v3.verifyAttempts or 0)+1
        if v3.verifyAttempts>3 then error("Arowe ne confirme pas les objectifs apres trois retours; progression locale non fiable") end
        v3.stage="inspect";interactions.race3=nil
        state("race3","en attente","Objectifs locaux termines; retour Arowe pour validation serveur")
        return interactNpc("Arowe","race3",now)
    end
    -- Summoning and puzzle modules use loaded objects and bounded verified transitions.
    local summonAt,summonAttempt,summonStarted=0,false,0
    local function summon(now)
        local name=config.summonTarget
        local paths={
            ["Soul Reaper"]={item="Hallow Essence",sea=3,path={"Map","Haunted Castle","Summoner","Detection"}},
        }
        local spec=paths[name]
        if not spec then state("summon","en attente","Invocation "..tostring(name).." : conditions/objets non implementes");return true end
        if sea~=spec.sea then error("Invocation : mer "..spec.sea.." requise") end
        refreshEnemies(now)
        if enemies[name] then state("summon","terminee","Boss detecte : "..name.." (attribution de l'invocation non prouvee)");return true end
        if not config.allowRare then state("summon","en attente","Consommation de "..spec.item.." OFF");return true end
        if summonAttempt then
            if now-summonStarted>20 then error("Invocation non confirmee; aucun deuxieme objet consomme") end
            state("summon","en attente","Invocation tentee; attendre boss charge");return false
        end
        local tool=findTool(spec.item)
        if not tool then state("summon","en attente",spec.item.." non possede; aucun achat aleatoire");return true end
        local detector=childPath(workspace,spec.path)
        if not detector or not detector:IsA("BasePart") then error("Autel historique absent; mise a jour non prise en charge") end
        local c,h,r=character();if not c then return false end
        if tool.Parent~=c then h:EquipTool(tool) end
        state("summon","en deplacement","Autel / "..spec.item.." ; consommation explicitement autorisee")
        if moveTo(detector.CFrame,2) then
            summonAttempt=true;summonStarted=now
            if type(firetouchinterest)=="function" then firetouchinterest(r,detector,0);firetouchinterest(r,detector,1) end
        end
        return false
    end
    local puzzleAttempts,puzzleWait,puzzleTarget,puzzleBefore=0,0,nil,nil
    local function puzzle(now)
        if config.puzzleTarget~="Saber plates" then state("puzzle","en attente","Puzzle selectionne non implemente");return true end
        if sea~=1 or player.Data.Level.Value<200 then error("Plaques Saber : mer 1, niveau 200+ requis") end
        local plates=childPath(workspace,{"Map","Jungle","QuestPlates"})
        local door=plates and plates:FindFirstChild("Door")
        if not plates or not door or not door:IsA("BasePart") then error("Structure du puzzle historique absente; aucune modification de carte") end
        if not door.CanCollide then state("puzzle","terminee","Porte ouverte observee. Torch/Cup/Relic et reste de Saber non implementes.");return true end
        if puzzleTarget then
            if puzzleTarget.BrickColor~=puzzleBefore or not door.CanCollide then puzzleTarget=nil;puzzleAttempts=0 end
            if puzzleTarget and now<puzzleWait then return false end
            if puzzleTarget and puzzleAttempts>=2 then error("Plaque non validee apres deux essais; progression arretee") end
        end
        if not puzzleTarget then
            for i=1,5 do
                local plate=plates:FindFirstChild("Plate"..i);local button=plate and plate:FindFirstChild("Button")
                if button and button:IsA("BasePart") and button.BrickColor~=BrickColor.new("Camo") then puzzleTarget=button;puzzleBefore=button.BrickColor;break end
            end
        end
        if not puzzleTarget then error("Plaques actives mais porte fermee; aucune reussite supposee") end
        state("puzzle","en deplacement","Saber : plaque "..puzzleTarget.Parent.Name)
        if moveTo(puzzleTarget.CFrame,2) then
            local _,_,r=character();puzzleAttempts=puzzleAttempts+1;puzzleWait=now+4
            if type(firetouchinterest)=="function" then firetouchinterest(r,puzzleTarget,0);firetouchinterest(r,puzzleTarget,1) end
        end
        return false
    end
    local advancedReady,advancedStep,advancedSuspend,advancedClose=adapter.ready,adapter.step,adapter.suspend,adapter.close
    function adapter.ready(id,now)
        if id=="sword" then
            adapter.maintenance(now)
            if sea~=2 then state(id,"en attente","Marchand legendaire : Sea 2 requise");return false end
            if legendaryPending or legendaryBlocked then return true end
            if now<legendaryAt then return false end
            requestInventory(now)
            if legendaryCount("Saddi")==nil then state(id,"en attente","Inventaire serveur requis");return false end
            local missing=false
            for rawName in (config.legendaryTargets or "Saddi,Shisui,Wando"):gmatch("[^,]+") do
                local name=rawName:match("^%s*(.-)%s*$");if legendaryCount(name)==0 then missing=true end
            end
            if not missing then return true end
            if config.legendaryBudget<=0 then state(id,"en attente","Configurer le budget legendaire pour autoriser un achat");return false end
            if findDialog(now,{"legendary sword dealer","saddi","shisui","wando","saishi","shizu","oroshi"}) then return true end
            local folder=workspace:FindFirstChild("NPCs")
            if folder and folder:FindFirstChild("Legendary Sword Dealer") then return true end
            state(id,"en attente","Marchand non charge; les autres options peuvent continuer");return false
        end
        if id=="boat" or id=="race3" or id=="summon" or id=="puzzle" then return true end
        return advancedReady(id,now)
    end
    function adapter.step(id,now)
        if id=="sword" then currentId=id;return legendary(now) end
        if id=="boat" then currentId=id;return boat(now) end
        if id=="race3" then currentId=id;return race3(now) end
        if id=="summon" then currentId=id;return summon(now) end
        if id=="puzzle" then currentId=id;return puzzle(now) end
        return advancedStep(id,now)
    end
    function adapter.suspend(id,transfer)
        releaseInput();pulseKey=nil
        if id=="boat" then boatStop();local _,h=character();if transfer and h then h.Sit=false end end
        if id=="sword" or id=="race3" or id=="summon" or id=="puzzle" or id=="boat" then
            if transfer then return movement:handoff() end
            return movement:stop()
        end
        return advancedSuspend(id,transfer)
    end
    function adapter.close(force) releaseInput();pulseKey=nil;boatStop();return advancedClose(force) end
    local advancedDiagnostics=adapter.diagnostics
    function adapter.diagnostics()
        local d=advancedDiagnostics();d.legendarySpent=legendarySpent;d.race3=v3.stage;d.boat=boatSeat and boatSeat.Name or "--";return d
    end

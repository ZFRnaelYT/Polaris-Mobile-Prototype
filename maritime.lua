    -- Loaded-world maritime targets; no template scanning or guessed sea-event remotes.
    local marineTargets,marineScan={},-math.huge
    local marineFacades=setmetatable({},{__mode="k"})
    local marineCurrent,marineCompleted=nil,0
    local searchStarted,patrolAnchor,patrolIndex=nil,nil,1
    local mirageOriginal,mirageRouting,mirageRouteIsland,mirageRouteTarget=nil,false,nil,nil
    local function maritimeName(model)
        local name=model.Name:gsub("%s*%[.*%]","")
        local lower=name:lower():gsub("%s","")
        if lower:match("^seabeast%d*$") then return "Sea Beast" end
        return name
    end
    local function marineHealth(model)
        local humanoid=model:FindFirstChildOfClass("Humanoid")
        if humanoid then return function() return humanoid.Health,humanoid.MaxHealth end end
        local value=model:FindFirstChild("Health")
        if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
            local maximum=model:FindFirstChild("MaxHealth")
            local initial=value.Value
            return function() return value.Value,maximum and maximum.Value or initial end
        end
        local attr=model:GetAttribute("Health")
        if type(attr)=="number" then
            local initial=attr
            return function() return model:GetAttribute("Health"),model:GetAttribute("MaxHealth") or initial end
        end
    end
    local function marineFacade(model)
        if marineFacades[model] then return marineFacades[model] end
        local root=model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChild("RootPart")
        local read=marineHealth(model)
        if not root or not root:IsA("BasePart") or not read then return end
        local health=setmetatable({},{__index=function(_,field) local hp,max=read();if field=="Health" then return hp or 0 elseif field=="MaxHealth" then return max or 1 end end})
        local proxy={model=model,root=root,read=read}
        function proxy:FindFirstChild(name) if name=="HumanoidRootPart" then return self.root end end
        function proxy:FindFirstChildOfClass(class) if class=="Humanoid" then return health end end
        marineFacades[model]=proxy;return proxy
    end
    local function scanMarine(now)
        if now-marineScan<1 then return end
        marineScan=now;marineTargets={}
        local seen={}
        for _,folderName in ipairs({"Enemies","SeaBeasts","Sea Beast"}) do
            local folder=workspace:FindFirstChild(folderName)
            for _,model in ipairs(folder and folder:GetChildren() or {}) do
                if model:IsA("Model") and not seen[model] then
                    seen[model]=true
                    local name=maritimeName(model)
                    if name=="Sea Beast" or name=="Piranha" or name=="Fish Crew Member" or name=="Shark" or name=="Terrorshark" then
                        local proxy=marineFacade(model)
                        marineTargets[#marineTargets+1]={name=name,model=model,proxy=proxy}
                    end
                end
            end
        end
    end
    local function selectedMarine(now,wanted)
        scanMarine(now)
        local _,_,root=character();if not root then return end
        local best,dist=nil,config.marineDetectRange
        for _,target in ipairs(marineTargets) do
            if wanted[target.name] and target.model.Parent and target.proxy then
                local health=target.proxy.read()
                if type(health)=="number" and health>0 then
                    local d=(root.Position-target.proxy.root.Position).Magnitude
                    if d<dist then best,dist=target,d end
                end
            end
        end
        return best
    end
    local function wantedMarine()
        local result={}
        for raw in config.marineTargets:gmatch("[^,]+") do
            local name=raw:match("^%s*(.-)%s*$")
            if name~="Sea Beast" and name~="Piranha" and name~="Fish Crew Member" and name~="Shark" and name~="Terrorshark" then error("Cible maritime inconnue : "..name) end
            result[name]=true
        end
        return result
    end
    local function restoreMirageRoute()
        if mirageRouting then config.boatDestination=mirageOriginal;mirageRouting=false;mirageOriginal=nil end
        mirageRouteIsland=nil;mirageRouteTarget=nil
    end
    local function patrol(now,id)
        local _,h=character();if not h then state(id,"en attente","Respawn");return false end
        if not config.marinePatrol then state(id,"en attente","Aucune cible chargee. Patrouille OFF; aucune apparition garantie");return true end
        if not searchStarted then searchStarted=now end
        if now-searchStarted>config.marineSearchSeconds then boatStop();error("Recherche maritime terminee sans cible dans le delai configure") end
        if not patrolAnchor then
            local seat=h.SeatPart or boatSeat
            if not seat or not seat.Parent then state(id,"en attente","Assieds-toi dans un bateau possede avant la patrouille");return true end
            patrolAnchor=seat.Position
        end
        local points={Vector3.new(1,0,0),Vector3.new(0,0,1),Vector3.new(-1,0,0),Vector3.new(0,0,-1)}
        local saved=config.boatDestination
        config.boatDestination=patrolAnchor+points[patrolIndex]*config.marineSearchRadius
        local ok,done=pcall(boat,now)
        config.boatDestination=saved
        if not ok then error(done) end
        if done and statuses.boat and statuses.boat.state=="terminee" then patrolIndex=patrolIndex%4+1 end
        state(id,"en deplacement","Patrouille bateau bornee / point "..patrolIndex.." ; aucun fly maritime")
        return false
    end
    local function marineFight(target,now,id)
        local c,h=character();if not c then releaseInput();state(id,"en attente","Respawn");return false end
        if marineCurrent and marineCurrent~=target.model then
            local previous=marineFacades[marineCurrent]
            if previous then local health=previous.read();if health and health<=0 then marineCompleted=marineCompleted+1 end end
        end
        marineCurrent=target.model
        if h.Health/h.MaxHealth<config.marineHealthReserve then
            releaseInput();boatStop()
            state(id,"en attente","Sante faible; retour au bateau, aucune attaque")
            local saved=config.boatDestination
            if boatSeat and boatSeat.Parent then config.boatDestination=boatSeat.Position;local ok,err=pcall(boat,now);config.boatDestination=saved;if not ok then error(err) end end
            return false
        end
        -- Stop seat controls before leaving it; flight never controls the boat.
        if boatOriginal or h.SeatPart then boatStop() end
        if h.SeatPart and h.SeatPart:IsA("VehicleSeat") then
            boatSeat=h.SeatPart;h.Sit=false;state(id,"en attente","Quitter le siege avant le combat");return false
        end
        local tool=findTool(config.marineTool)
        if not tool then error("Choisir le nom exact d'un equipement maritime possede") end
        if tool.ToolTip~="Blox Fruit" and tool.ToolTip~="Gun" and tool.ToolTip~="Sword" and tool.ToolTip~="Melee" then error("Equipement sans skills reconnus") end
        local pos=target.proxy.root.CFrame*CFrame.new(0,math.min(config.marineHeight,config.skillRange*0.4),config.skillRange*0.5)
        local _,_,root=character()
        if movement.goal or (root.Position-pos.Position).Magnitude>4 then
            releaseInput()
            if not moveTo(pos,3) then state(id,"en deplacement","Approche fantome / "..target.name);return false end
        end
        -- Hover is temporary, owned by this foreground task, and cleaned on transfer.
        services.characterController:setFlying(true)
        skillCombat(target.proxy,tool,now,true,id)
        state(id,"en combat",target.name.." / skills normaux; provenance et drops non garantis")
        return false
    end
    local function marine(now,id)
        id=id or "marine"
        if sea~=2 and sea~=3 then error("Evenements marins : Sea 2 ou Sea 3 requise") end
        local wanted=id=="seafish" and {["Piranha"]=true,["Fish Crew Member"]=true,["Shark"]=true} or wantedMarine();local target=selectedMarine(now,wanted)
        if target then searchStarted=nil;return marineFight(target,now,id) end
        for _,entry in ipairs(marineTargets) do
            if wanted[entry.name] and not entry.proxy then
                state(id,"en attente",entry.name.." detecte, mais sante/position non lisibles : schema non pris en charge")
                return true
            end
        end
        if marineCurrent then
            local previous=marineFacades[marineCurrent];local health=previous and previous.read()
            if health and health<=0 then marineCompleted=marineCompleted+1 end
            marineCurrent=nil;releaseInput()
            if not stopMovement() then error(movement.blocked) end
        end
        return patrol(now,id)
    end
    local function mirageObject()
        local map=workspace:FindFirstChild("Map")
        local island=map and (map:FindFirstChild("MysticIsland") or map:FindFirstChild("Mirage Island"))
        return island
    end
    local function miragePosition(island)
        local cf=positionOf(island)
        if cf then return cf.Position end
        if island:IsA("Model") then return island:GetPivot().Position end
        local part=island:FindFirstChildWhichIsA("BasePart",true)
        return part and part.Position
    end
    local function mirage(now)
        if sea~=3 then error("Mirage : Sea 3 requise") end
        local island=mirageObject()
        if not island then restoreMirageRoute();return patrol(now,"mirage") end
        local pos=miragePosition(island)
        if not pos then state("mirage","en attente","Mirage chargee sans position exploitable");return true end
        local _,h,root=character();if not root then return false end
        if not h.SeatPart or not h.SeatPart:IsA("VehicleSeat") then
            state("mirage","en attente","Mirage detectee; rester/revenir dans un bateau pour l'approche maritime")
            local saved=config.boatDestination;config.boatDestination=pos
            local ok,result=pcall(boat,now);config.boatDestination=saved;if not ok then error(result) end
            return false
        end
        local delta=h.SeatPart.Position-pos;delta=Vector3.new(delta.X,0,delta.Z)
        if mirageRouteIsland~=island or not mirageRouteTarget then
            mirageRouteIsland=island
            mirageRouteTarget=delta.Magnitude>1 and pos+delta.Unit*config.mirageStandOff or pos+Vector3.new(config.mirageStandOff,0,0)
        end
        local shore=mirageRouteTarget
        if (Vector3.new(root.Position.X,0,root.Position.Z)-Vector3.new(shore.X,0,shore.Z)).Magnitude<=config.boatTolerance then
            boatStop();restoreMirageRoute();state("mirage","terminee","Mirage chargee approchee. Gear, resonance et trials restent a verifier/realiser.");return true
        end
        if not mirageRouting then mirageOriginal=config.boatDestination;mirageRouting=true end
        config.boatDestination=shore
        local done=boat(now);state("mirage","en deplacement","Approche Mirage par bateau; aucun scan des zones non chargees")
        return false
    end
    local earlierRace3=race3
    race3=function(now)
        local race=player.Data.Race.Value
        if v3.stage=="work" and (race=="Shark" or race=="Fishman") then
            local target=selectedMarine(now,{["Sea Beast"]=true})
            if target then
                local health=target.proxy.read()
                if health and health>0 then return marineFight(target,now,"race3") end
            end
            if marineCurrent then
                local proxy=marineFacades[marineCurrent];local health=proxy and proxy.read()
                if health and health<=0 then
                    marineCurrent=nil;releaseInput();v3.stage="inspect";interactions.race3=nil
                    return interactNpc("Arowe","race3",now)
                end
            end
            state("race3","en attente","Attente Sea Beast charge; provenance naturelle non confirmee, Arowe valide la quete")
            return patrol(now,"race3")
        end
        return earlierRace3(now)
    end
    local baseReady,baseStep,baseSuspend,baseClose=adapter.ready,adapter.step,adapter.suspend,adapter.close
    function adapter.ready(id,now)
        if id=="marine" or id=="seafish" or id=="mirage" then
            scanMarine(now)
            if id=="mirage" and mirageObject() then return true end
            if id~="mirage" and selectedMarine(now,id=="seafish" and {["Piranha"]=true,["Fish Crew Member"]=true,["Shark"]=true} or wantedMarine()) then return true end
            if id~="mirage" then
                local wanted=id=="seafish" and {["Piranha"]=true,["Fish Crew Member"]=true,["Shark"]=true} or wantedMarine()
                for _,entry in ipairs(marineTargets) do
                    if wanted[entry.name] and not entry.proxy then state(id,"en attente",entry.name.." detecte : sante/position non lisibles, schema non pris en charge");return false end
                end
            end
            if config.marinePatrol then return true end
            state(id,"en attente","Aucune cible/ile chargee; patrouille OFF")
            return false
        end
        return baseReady(id,now)
    end
    function adapter.step(id,now)
        if id=="marine" or id=="seafish" then currentId=id;return marine(now,id) end
        if id=="mirage" then currentId=id;return mirage(now) end
        return baseStep(id,now)
    end
    function adapter.suspend(id,transfer)
        if id=="marine" or id=="seafish" or id=="mirage" then
            releaseInput();boatStop();restoreMirageRoute()
            if transfer then return movement:handoff() end
            return movement:stop()
        end
        return baseSuspend(id,transfer)
    end
    function adapter.close(force) restoreMirageRoute();return baseClose(force) end
    function adapter.raceOverview(now)
        requestInventory(now)
        local data=player:FindFirstChild("Data");local race=data and data:FindFirstChild("Race")
        return {race=race and race.Value or "?",v2=race and race:FindFirstChild("Evolved")~=nil or false,
            v3Confirmed=statuses.race3 and statuses.race3.state=="terminee" or false,
            mirrorFractal=count("Mirror Fractal"),mirageLoaded=mirageObject()~=nil,
            v4="Trials, resonance, levier et horloge non implementes"}
    end

    -- Loading/respawn is a waiting state, not a task failure.
    local loadedReady=adapter.ready
    function adapter.ready(id,now)
        if closed then return false end
        local data=player:FindFirstChild("Data")
        local level=data and data:FindFirstChild("Level")
        if not level or type(level.Value)~="number" then
            state(id,"en attente","Chargement des donnees du joueur")
            return false
        end
        if not character() then
            state(id,"en attente","Personnage indisponible / respawn")
            return false
        end
        if (id=="farm" or id=="quest") and not questUI() then
            state(id,"en attente","Chargement de Main/Quest ; aucun appel de quete envoye")
            return false
        end
        return loadedReady(id,now)
    end

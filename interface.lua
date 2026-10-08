
local services={Players=game:GetService("Players"),TweenService=game:GetService("TweenService"),
    Input=game:GetService("UserInputService"),Lighting=game:GetService("Lighting"),Run=game:GetService("RunService")}
local player=services.Players.LocalPlayer
assert(player,"Polaris doit etre execute cote client")
local playerGui=player:WaitForChild("PlayerGui")
local old=playerGui:FindFirstChild("PolarisMobileDemo")
if old then local event=old:FindFirstChild("Cleanup");if event then event:Fire() end;assert(not old:GetAttribute("PolarisBlocked"),"Ancien trajet bloque : liberer une sortie avant de remplacer Polaris");old:Destroy() end
-- Old UI cleanup can create a safety token; check AFTER it has stopped.
local pendingCleanup=playerGui:FindFirstChild("PolarisSafetyCleanup")
if pendingCleanup then
    pendingCleanup:Fire()
    assert(not pendingCleanup:GetAttribute("PolarisBlocked"),"Ancien arret dans un obstacle : rejoindre un espace libre ou respawn avant de reexecuter Polaris")
end
local config={bosses=true,weapon="Melee",speed=220,fruitRange=5000,phaseFlight=true,exitRadius=10,
 reserve=100000,gachaBudget=0,gachaMaxPrice=500000,shopBudget=0,shopMaxPrice=1200000,excludeFruits="",
 masteryTool="",masteryGoal=300,masteryThreshold=0.25,itemQuantity=10,replaceQuest=false,
 legendaryTargets="Saddi,Shisui,Wando",legendaryBudget=6000000,legendaryMaxPrice=2000000,
 skillKeys="Z,X",skillInterval=6,skillHold=0.15,skillRange=30,skillAim=true,
 boatTolerance=35,race3Budget=0,allowRare=false,summonTarget="Soul Reaper",puzzleTarget="Saber plates",marineTargets="Sea Beast",marineTool="",marinePatrol=false,
 marineDetectRange=2500,marineSearchRadius=1500,marineSearchSeconds=600,marineHeight=12,
 marineHealthReserve=0.35,mirageStandOff=180}
services.characterController=newCharacterController(player,services.Run)
local colors={bg=Color3.fromRGB(9,10,13),card=Color3.fromRGB(17,18,23),accent=Color3.fromRGB(239,43,65),
    text=Color3.fromRGB(239,244,255),muted=Color3.fromRGB(151,153,165),green=Color3.fromRGB(239,43,65)}
local links,closed,pages,tabButtons,toggleButtons={},false,{},{},{}
local toggleWidgets={}
local engine,adapter
local history={}
local function bind(signal,fn) local connection=signal:Connect(fn);table.insert(links,connection);return connection end
local function make(class,parent,props)
    local object=Instance.new(class)
    for key,value in pairs(props or {}) do object[key]=value end
    object.Parent=parent;return object
end
local function corner(obj,radius) make("UICorner",obj,{CornerRadius=UDim.new(0,radius or 12)}) end
local function stroke(obj) make("UIStroke",obj,{Color=Color3.fromRGB(125,30,42),Thickness=1,Transparency=0.15}) end
local function label(parent,value,size,pos)
    return make("TextLabel",parent,{Text=value,Size=size,Position=pos or UDim2.new(),BackgroundTransparency=1,
        Font=Enum.Font.Gotham,TextSize=14,TextColor3=colors.text,TextWrapped=true,
        TextXAlignment=Enum.TextXAlignment.Left})
end
local function button(parent,value,size,pos)
    local b=make("TextButton",parent,{Text=value,Size=size,Position=pos or UDim2.new(),BackgroundColor3=colors.card,
        TextColor3=colors.text,TextSize=14,Font=Enum.Font.GothamMedium,TextWrapped=true,BorderSizePixel=0})
    corner(b);return b
end
local gui=make("ScreenGui",playerGui,{Name="PolarisMobileDemo",ResetOnSpawn=false,DisplayOrder=40,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local cleanup=make("BindableEvent",gui,{Name="Cleanup"})
local panel=make("Frame",gui,{Name="PolarisPanel",Size=UDim2.new(0.78,0,0.80,0),Position=UDim2.fromScale(0.5,0.5),
    AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=colors.bg,BorderSizePixel=0})
corner(panel,18);stroke(panel)
services.polarisGui=gui
local panelLimit=make("UISizeConstraint",panel,{MaxSize=Vector2.new(660,500)})
local banner=make("Frame",panel,{Size=UDim2.new(1,0,0,64),BackgroundColor3=colors.card,BorderSizePixel=0})
corner(banner,18)
make("Frame",banner,{Size=UDim2.new(1,-24,0,1),Position=UDim2.new(0,12,1,-1),BackgroundColor3=colors.accent,BorderSizePixel=0})
local title=label(banner,"POLARIS",UDim2.new(1,-230,0,30),UDim2.new(0,18,0,7))
title.TextSize=23;title.Font=Enum.Font.GothamBold
local subtitle=label(banner,"v0.10  /  MOBILE + PC  /  EXPERIMENTAL",UDim2.new(1,-230,0,20),UDim2.new(0,18,0,37))
subtitle.TextSize=11
local sizeButton=button(banner,"PETIT",UDim2.fromOffset(84,36),UDim2.new(1,-184,0,14))
sizeButton.TextSize=11
local sizePresets={{label="PETIT",x=.78,y=.80,w=660,h=500},{label="NORMAL",x=.90,y=.88,w=840,h=640},{label="GRAND",x=.96,y=.94,w=980,h=740}}
local sizeIndex=1
bind(sizeButton.Activated,function()
    sizeIndex=sizeIndex%#sizePresets+1
    local preset=sizePresets[sizeIndex]
    panel.Size=UDim2.new(preset.x,0,preset.y,0)
    panelLimit.MaxSize=Vector2.new(preset.w,preset.h)
    panel.Position=UDim2.fromScale(.5,.5)
    sizeButton.Text=preset.label
end)
local minimize=button(banner,"—",UDim2.fromOffset(38,36),UDim2.new(1,-94,0,14))
local close=button(banner,"×",UDim2.fromOffset(38,36),UDim2.new(1,-50,0,14))
local reopen=button(gui,"POLARIS",UDim2.fromOffset(110,42),UDim2.new(0,12,0.45,0));reopen.Visible=false
local function minimizePanel() panel.Visible=false;reopen.Visible=true end
bind(minimize.Activated,minimizePanel)
bind(reopen.Activated,function() panel.Visible=true;reopen.Visible=false end)
-- Drag from the header only; no permanent frame callback for dragging.
local dragging,dragInput,dragStart,startPosition
bind(banner.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true;dragStart=input.Position;startPosition=panel.Position;dragInput=input
    end
end)
bind(services.Input.InputEnded,function(input) if input==dragInput then dragging=false end end)
bind(services.Input.InputChanged,function(input)
    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input==dragInput) then
        local delta=input.Position-dragStart
        local bounds=gui.AbsoluteSize
        local half=panel.AbsoluteSize/2
        local x=math.clamp(startPosition.X.Scale*bounds.X+startPosition.X.Offset+delta.X,half.X,bounds.X-half.X)
        local y=math.clamp(startPosition.Y.Scale*bounds.Y+startPosition.Y.Offset+delta.Y,half.Y,bounds.Y-half.Y)
        panel.Position=UDim2.fromOffset(x,y)
    end
end)
local nav=make("ScrollingFrame",panel,{Name="PolarisNavigation",Size=UDim2.new(1,-24,0,43),Position=UDim2.new(0,12,0,73),
    BackgroundTransparency=1,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.X,
    CanvasSize=UDim2.new(),ScrollBarThickness=2,ScrollingDirection=Enum.ScrollingDirection.X})
local navLayout=make("UIListLayout",nav,{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
local status=label(panel,"INITIALISATION",UDim2.new(1,-30,0,28),UDim2.new(0,15,0,122))
status.TextSize=12;status.TextColor3=colors.muted
local area=make("Frame",panel,{Name="PolarisPages",Size=UDim2.new(1,-24,1,-220),Position=UDim2.new(0,12,0,158),BackgroundTransparency=1})
local orders={}
local pageTitle=label(panel,"Accueil",UDim2.new(1,-30,0,30),UDim2.new(0,15,0,120))
pageTitle.Font=Enum.Font.GothamBold;pageTitle.TextSize=24
local pageGroups={Epees="Equipement",Boutique="Equipement",Maitrise="Farm",Objets="Farm",Boss="Farm",Evenements="Farm",Invocations="Farm",Puzzles="Races",V4="Races",Navigation="Mer",Mirage="Mer",Performance="Reglages",Journal="Reglages"}
local function group(page) return pageGroups[page] or page end
local function showPage(name)
    name=group(name)
    pageTitle.Text=name
    for key,page in pairs(pages) do page.Visible=key==name end
    for key,b in pairs(tabButtons) do
        b.BackgroundColor3=key==name and Color3.fromRGB(37,18,25) or colors.bg
        b.TextColor3=key==name and colors.text or colors.muted
        local line=b:FindFirstChild("SelectionLine");if line then line.Visible=key==name end
    end
end
for index,name in ipairs({"Accueil","Farm","Fruits","Equipement","Mer","Races","Reglages"}) do
    local page=make("ScrollingFrame",area,{Name=name,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
        BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,Visible=index==1})
    make("UIListLayout",page,{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder})
    make("UIPadding",page,{PaddingRight=UDim.new(0,7),PaddingBottom=UDim.new(0,12)})
    pages[name],orders[name]=page,0
    local b=button(nav,name,UDim2.fromOffset(name=="Performance" and 130 or 104,36));b.LayoutOrder=index
    b.TextXAlignment=Enum.TextXAlignment.Left;b.TextSize=13
    make("UIPadding",b,{PaddingLeft=UDim.new(0,12)})
    local line=make("Frame",b,{Name="SelectionLine",Size=UDim2.fromOffset(3,24),Position=UDim2.new(0,0,0.5,-12),BackgroundColor3=colors.accent,BorderSizePixel=0,Visible=index==1});corner(line,2)
    tabButtons[name]=b;bind(b.Activated,function() showPage(name) end)
end
local function responsiveLayout()
    local wide=panel.AbsoluteSize.X>=700
    if wide then
        nav.Position=UDim2.fromOffset(12,82);nav.Size=UDim2.new(0,172,1,-100)
        nav.ScrollingDirection=Enum.ScrollingDirection.Y;nav.AutomaticCanvasSize=Enum.AutomaticSize.Y
        navLayout.FillDirection=Enum.FillDirection.Vertical
        pageTitle.Position=UDim2.fromOffset(204,82);pageTitle.Size=UDim2.new(1,-220,0,32)
        status.Position=UDim2.fromOffset(204,119);status.Size=UDim2.new(1,-220,0,26)
        area.Position=UDim2.fromOffset(204,153);area.Size=UDim2.new(1,-220,1,-164)
    else
        nav.Position=UDim2.fromOffset(12,74);nav.Size=UDim2.new(1,-24,0,42)
        nav.ScrollingDirection=Enum.ScrollingDirection.X;nav.AutomaticCanvasSize=Enum.AutomaticSize.X
        navLayout.FillDirection=Enum.FillDirection.Horizontal
        pageTitle.Position=UDim2.fromOffset(15,118);pageTitle.Size=UDim2.new(1,-30,0,25)
        status.Position=UDim2.fromOffset(15,146);status.Size=UDim2.new(1,-30,0,22)
        area.Position=UDim2.fromOffset(12,172);area.Size=UDim2.new(1,-24,1,-182)
    end
    for _,b in pairs(tabButtons) do b.Size=wide and UDim2.fromOffset(168,36) or UDim2.fromOffset(112,36) end
end
bind(panel:GetPropertyChangedSignal("AbsoluteSize"),responsiveLayout)
responsiveLayout();showPage("Accueil")
local sectionAdded={}
local function row(page,textValue,isButton,height)
    local section=page;page=group(page)
    if section~=page and not sectionAdded[section] then
        sectionAdded[section]=true;orders[page]=orders[page]+1
        local header=label(pages[page],string.upper(section),UDim2.new(1,-2,0,30))
        header.TextSize=12;header.Font=Enum.Font.GothamBold;header.TextColor3=colors.accent;header.LayoutOrder=orders[page]
    end
    orders[page]=orders[page]+1
    local obj
    if isButton then obj=button(pages[page],textValue,UDim2.new(1,-2,0,height or 54))
    else
        obj=label(pages[page],textValue,UDim2.new(1,-2,0,0))
        obj.AutomaticSize=Enum.AutomaticSize.Y
        obj.TextColor3=colors.muted
        make("UIPadding",obj,{PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,8),PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6)})
    end
    obj.LayoutOrder=orders[page];return obj
end
local welcome=row("Accueil","Chaque interrupteur lance ou arrete directement sa fonction. Les achats utilisent ton argent du jeu. Compatibilite des appels et du combat a tester dans Delta.",false)
local summary=row("Accueil","",false)
local stats=row("Accueil","",false)
local action=row("Accueil","Derniere action: --",false)
row("Accueil","Cette version implemente des actions reelles, sans garantir leur acceptation par le serveur. Raids complets, changement de mer, tous les puzzles et V3 de toutes les races ne sont pas implementes. Les nouveaux modules restent experimentaux.",false)
local logLabel=row("Journal","Aucun evenement",false)
logLabel.TextYAlignment=Enum.TextYAlignment.Top
local function report(message)
    if closed then return end
    message=tostring(message):sub(1,240)
    action.Text="Derniere action: "..message
    table.insert(history,1,os.date("%H:%M:%S").."  "..message)
    while #history>25 do table.remove(history) end
    logLabel.Text=table.concat(history,"\n")
end
local storage=game:GetService("ReplicatedStorage")
local knownPlace=({[2753915549]=true,[4442272183]=true,[7449423635]=true})[game.PlaceId]
local expectedGame=game.GameId==994732206 or knownPlace==true
local supported=false
local initializationDeadline=os.clock()+30
local initializationFinished=false
local priorityDefaults={collect=90,event=80,boss=65,quest=20,farm=10,mastery=25,item=30}
local function initializeActions()
    if initializationFinished or closed then return end
    if not expectedGame then
        initializationFinished=true
        status.Text="Blox Fruits non detecte"
        report("Actions indisponibles : ce jeu n'est pas Blox Fruits.")
        return
    end
    local remotes=storage:FindFirstChild("Remotes")
    local remote=remotes and remotes:FindFirstChild("CommF_")
    if not remote or not remote:IsA("RemoteFunction") then
        if os.clock()>=initializationDeadline then
            initializationFinished=true
            status.Text="Erreur : CommF_ absent apres 30 s"
            report("Initialisation impossible : Remotes/CommF_ absent apres 30 s. Attendre le chargement du jeu puis reexecuter.")
        else status.Text="Chargement du jeu / attente CommF_" end
        return
    end
    initializationFinished=true
    adapter=newAdapter(player,remote,services,config,report)
    engine=newEngine(adapter,os.clock,function(message,severity)
        status.Text=message
        if severity=="erreur" then report("Erreur : "..message) end
    end)
    engine.prefix="POLARIS : "
    for _,entry in ipairs({{"fruit","Stocker les fruits portes",100,2,true},{"collect","Chercher les fruits au sol",90,2},
        {"sword","Auto achat legendaire",70,2},{"gacha","Random fruit / Gacha",60,2,true},
        {"race2","Quete race V2 / fleurs",85,2},{"swordfarm","Farm cible pour epee",30,0.2},
        {"navigate","Aller au PNJ selectionne",110,0.2},
        {"shop","Acheter la liste de 18 objets",50,3,true},{"farm","Auto Farm Level",10,0.2},{"quest","Auto Quest",20,0.5},
        {"mastery","Auto Farm Mastery",25,0.2},{"item","Auto Farm Item",30,0.2},
        {"boss","Auto Boss",65,0.2},{"event","Auto Event",80,0.2},
        {"boat","Navigation maritime",55,0.2},{"race3","Race V3 / Arowe",75,0.2},
        {"summon","Invocation autorisee",60,0.2},{"puzzle","Puzzle Saber / plaques",40,0.2},
        {"marine","Auto Sea Beast",60,0.2},{"seafish","Auto Sea Fish",50,0.2},{"mirage","Auto recherche Mirage",85,0.2}}) do
        engine:add(table.unpack(entry))
    end
    supported=true
    for _,button in pairs(toggleButtons) do button.Active=true;button.AutoButtonColor=true end
    status.Text="Pret / active une option"
    report("Connexion au jeu prete. Active une option ; elle demarre directement.")
end
local function safeInitializeActions()
    local ok,err=pcall(initializeActions)
    if not ok then
        initializationFinished=true;supported=false
        status.Text="Erreur d'initialisation / voir Journal"
        warn("[Polaris] Initialisation : "..tostring(err))
        report("Erreur d'initialisation : "..tostring(err))
    end
end
safeInitializeActions()
local function anyOptionEnabled()
    if not engine then return false end
    for _,entry in ipairs(engine.sequence) do if entry.enabled then return true end end
    return false
end
local function enableTask(id,value)
    if not engine then return end
    engine:enable(id,value)
    if value then
        if adapter.canClose() then engine:start()
        else report("Option activee, mais sortie libre requise. Reglages > Retenter une sortie libre.") end
    elseif not anyOptionEnabled() then engine:pause() end
end
local function toggle(page,id,labelValue)
    local b=row(page,labelValue.."  [OFF]",true,70);toggleButtons[id]=b
    b.TextXAlignment=Enum.TextXAlignment.Left;b.TextSize=12
    make("UIPadding",b,{PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,76)})
    local track=make("Frame",b,{Name="ToggleTrack_"..id,Size=UDim2.fromOffset(44,24),Position=UDim2.new(1,-60,0.5,-12),BackgroundColor3=Color3.fromRGB(37,38,46),BorderSizePixel=0});corner(track,12);stroke(track)
    local thumb=make("Frame",track,{Size=UDim2.fromOffset(18,18),Position=UDim2.fromOffset(3,3),BackgroundColor3=colors.muted,BorderSizePixel=0});corner(thumb,9)
    toggleWidgets[id]={track=track,thumb=thumb}
    b.Active=supported==true;b.AutoButtonColor=supported==true
    bind(b.Activated,function()
        if not engine then return end
        enableTask(id,not engine.tasks[id].enabled)
        local on=engine.tasks[id].enabled
        track.BackgroundColor3=on and colors.accent or Color3.fromRGB(37,38,46)
        thumb.BackgroundColor3=on and colors.text or colors.muted
        thumb.Position=on and UDim2.fromOffset(23,3) or UDim2.fromOffset(3,3)
        report(engine.tasks[id].label..(engine.tasks[id].enabled and " active" or " desactive"))
    end)
end
toggle("Farm","farm","AUTO FARM")
local bossButton=row("Farm","Priorite aux boss disponibles  [ON]",true)
bind(bossButton.Activated,function()
    config.bosses=not config.bosses
    bossButton.Text="Priorite aux boss disponibles  ["..(config.bosses and "ON" or "OFF").."]"
end)
local weaponButton=row("Farm","Arme de combat : Melee",true)
bind(weaponButton.Activated,function() config.weapon=config.weapon=="Melee" and "Sword" or "Melee";weaponButton.Text="Arme de combat : "..config.weapon end)
local speedButton=row("Farm","Vitesse de deplacement : 220",true)
bind(speedButton.Activated,function() config.speed=config.speed==100 and 220 or config.speed==220 and 300 or 100;speedButton.Text="Vitesse de deplacement : "..config.speed end)
row("Farm","DEPLACEMENTS AUTOMATIQUES : MODE FANTOME TOUJOURS ACTIF. Traverse les obstacles pendant le trajet ; restaure les collisions uniquement dans un espace libre.",false)
local ghostButton=row("Farm","APPARENCE FANTOME LOCALE  [OFF]",true)
bind(ghostButton.Activated,function()
    local controller=services.characterController
    controller:setGhost(not controller.ghost)
    ghostButton.Text="APPARENCE FANTOME LOCALE  ["..(controller.ghost and "ON" or "OFF").."]"
end)
row("Farm","Vol : collisions du corps coupees pendant le trajet et restaurees a l'arrivee ou en pause. Fantome : corps translucide bleu, arme visible, combat conserve. Effet visuel local ; aucun changement de race ni invulnerabilite.",false)
row("Farm","Catalogue historique des 3 mers, jusqu'a 2525. Le farm utilise Tool:Activate a cadence normale, sans fast attack. Le serveur peut refuser les mouvements ou les attaques. Termine ta quete manuelle avant de demarrer.",false)
row("Farm","Sante <25 % : pause des attaques jusqu'a 65 %. Une arme Melee ou Sword doit etre disponible. Les boss sont choisis avant une nouvelle quete ; une quete en cours n'est pas abandonnee pour changer de cible.",false)
toggle("Fruits","collect","RECHERCHE FRUITS / interrompt le farm")
toggle("Fruits","fruit","STOCKAGE AUTOMATIQUE")
toggle("Fruits","gacha","RANDOM FRUIT AUTOMATIQUE")
local range=row("Fruits","Distance de recherche : 5000 studs",true)
bind(range.Activated,function() config.fruitRange=config.fruitRange==5000 and 1500 or 5000;range.Text="Distance de recherche : "..config.fruitRange.." studs" end)
row("Fruits","Collecte limitee aux fruits physiques detectes dans la zone chargee. Un essai expire apres 20 s, puis le farm reprend. Active aussi le stockage. Aucun fruit n'est mange, jete ou sacrifie.",false)
row("Fruits","Gacha : au moins 2 h entre tentatives dans cette session. Le cooldown serveur reste prioritaire. Stockage : liste historique de noms reconnus ; un fruit renomme/inconnu est conserve.",false)
toggle("Boutique","sword","AUTO ACHAT EPEES LEGENDAIRES")
toggle("Boutique","shop","ACHETER 18 OBJETS DE BOUTIQUE")
row("Boutique","Liste : "..table.concat(STOCK,", ")..". Une reponse non reconnue arrete la liste. Cette fonction ne debloque pas les armes obtenues par quetes ou drops.",false)
local retry=row("Boutique","Recommencer la liste d'achats",true)
bind(retry.Activated,function() if adapter then adapter.resetShop();report("Liste remise au debut. Activer la boutique.") end end)
row("Boutique","Un interrupteur pour Saddi, Shisui et Wando : acheter uniquement les epees manquantes en Sea 2. Prix Beli lu dans le dialogue, plafond interne 2 000 000 par epee et 6 000 000 au total. La reserve globale reste appliquee. Le marchand doit etre charge.",false)
row("Epees","ACHATS ET DROPS : les boutons lancent une tentative ou un farm cible. Une epee de drop n'est jamais garantie en un clic.",false)
row("Epees","Le marchand depend du serveur ; ce n'est pas un spawn reserve a la nuit. Aucun appel numerique de consultation/achat n'est devine. Le module utilise le dialogue du marchand charge. Aucun minuteur de spawn invente.",false)
for _,entry in ipairs({{"Rengoku","Rengoku / farmer Snow Lurker pour Hidden Key",2},
    {"Thunder God","Pole (1st Form) / farmer Thunder God",1},{"Cyborg","Farm Cyborg / drops",1},
    {"Smoke Admiral","Jitte / farmer Smoke Admiral",2},{"Tide Keeper","Dragon Trident / farmer Tide Keeper",2},
    {"Stone","Farm Stone / drops",3},{"Beautiful Pirate","Canvander / farmer Beautiful Pirate",3}}) do
    local target,labelValue,requiredSea=entry[1],entry[2],entry[3]
    local b=row("Epees",labelValue,true)
    bind(b.Activated,function()
        if not engine then return end
        if adapter.diagnostics().sea~=requiredSea then report("Cette cible demande la mer "..requiredSea);return end
        config.swordTarget=target
        enableTask("swordfarm",true)
        report("Cible : "..target..". Lancement automatique. Acces et prerequis a debloquer avant.")
    end)
end
row("Epees","Saber, Tushita, Yama, Cursed Dual Katana, True Triple Katana, Shark Anchor et les autres chaines de quetes : modules complets indisponibles. Les 18 achats standards sont dans Boutique. Le combat normal peut echouer selon le serveur.",false)
toggle("Races","race2","AUTO V2 : Alchemist + fleurs + combat")
row("Races","V2 hors Draco : mer 2, niveau 850+, quete du Colisee terminee, 500 000 Beli pour l'evolution. Le module tente de demarrer la quete, ramasser les fleurs visibles, combattre des Swan Pirates pour la jaune et valider chez l'Alchemist.",false)
row("Races","V2 prend la priorite sur le farm. Les fleurs sont detectees dans la zone chargee. Leur ramassage et les reponses de l'Alchemist doivent etre testes. Draco n'est pas pris en charge.",false)
local raceInfo=row("Races","",false)
local v3guide={Human="Human : battre Diamond, Jeremy et le troisieme boss demande par Arowe (anciens scripts : Fajita).",
    Mink="Rabbit : collecter 30 coffres apres acceptation de la quete.",Rabbit="Rabbit : collecter 30 coffres apres acceptation de la quete.",
    Fishman="Shark : battre un Sea Beast apparu naturellement.",Shark="Shark : battre un Sea Beast apparu naturellement.",
    Skypiea="Angel : battre un autre joueur Angel.",Angel="Angel : battre un autre joueur Angel.",
    Ghoul="Ghoul : battre 5 joueurs selon les conditions d'Arowe.",Cyborg="Cyborg : montrer un fruit physique a Arowe.",
    Draco="Draco : progression specifique du Dragon Wizard non implementee."}
local checkV3=row("Races","Consulter etat V3 (experimental)",true)
bind(checkV3.Activated,function()
    report("Arowe : active le module V3 ci-dessous. Son dialogue visible sera utilise ; aucun appel Wenlocktoad non verifie.")
end)
local visitV3=row("Races","Aller a Arowe / aide V3",true)
bind(visitV3.Activated,function()
    if adapter and adapter.goToNpc({"Arowe","arowe","Wenlocktoad"}) then enableTask("navigate",true);engine:start() end
end)
row("Races","V3 : V2 deja debloquee, niveau 1000+, Don Swan et acces requis, 2 000 000 Beli. Le menu fournit le suivi et l'acces au PNJ charge. Les objectifs V3 ne sont pas automatisés dans cette version ; accepte et valide ta quete chez Arowe.",false)

-- Reversible graphics changes, applied in batches, with one added-instance listener.
local lowGraphics=false
local originals=setmetatable({},{__mode="k"})
local oldShadows=services.Lighting.GlobalShadows
local graphicsEpoch=0
local function lighten(obj)
    if not lowGraphics or obj:IsDescendantOf(gui) then return end
    if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("PostEffect") then
        if originals[obj]==nil then originals[obj]=obj.Enabled end
        obj.Enabled=false
    end
end
local graphicButton=row("Performance","MODE GRAPHIQUE LEGER  [OFF]",true)
local fpsLabel=row("Performance","FPS client : --",false)
local antiIdle=false
local idleButton=row("Performance","MAINTIEN AFK (experimental)  [OFF]",true)
bind(idleButton.Activated,function() antiIdle=not antiIdle;idleButton.Text="MAINTIEN AFK (experimental)  ["..(antiIdle and "ON" or "OFF").."]" end)
bind(player.Idled,function()
    if not antiIdle or closed then return end
    local ok,err=pcall(function()
        local user=game:GetService("VirtualUser")
        user:CaptureController();user:ClickButton2(Vector2.new(0,0))
    end)
    if not ok then report("AFK non disponible: "..tostring(err):sub(1,100)) end
end)
bind(graphicButton.Activated,function()
    lowGraphics=not lowGraphics;graphicsEpoch=graphicsEpoch+1
    graphicButton.Text="MODE GRAPHIQUE LEGER  ["..(lowGraphics and "ON" or "OFF").."]"
    if lowGraphics then
        oldShadows=services.Lighting.GlobalShadows;services.Lighting.GlobalShadows=false
        local epoch=graphicsEpoch
        task.spawn(function()
            for _,root in ipairs({workspace,services.Lighting}) do
                for i,obj in ipairs(root:GetDescendants()) do
                    if closed or not lowGraphics or epoch~=graphicsEpoch then return end
                    lighten(obj);if i%100==0 then task.wait() end
                end
            end
        end)
    else
        services.Lighting.GlobalShadows=oldShadows
        for obj,value in pairs(originals) do if obj.Parent then pcall(function() obj.Enabled=value end) end end
        originals=setmetatable({},{__mode="k"})
    end
end)
bind(workspace.DescendantAdded,lighten);bind(services.Lighting.DescendantAdded,lighten)
row("Performance","Desactive temporairement ombres, particules, trails, beams et effets de post-traitement. Les valeurs d'origine sont restaurees quand tu desactives ce mode ou fermes Polaris.",false)
row("Performance","Moteur a 5 passages/s, liste d'ennemis actualisee a 1 Hz, une requete serveur a la fois, journal limite a 25 entrees. Pas de promesse de zero lag : MuMu, ton appareil et le serveur influencent les performances.",false)
local frames,fpsStart=0,os.clock()
bind(services.Run.RenderStepped,function()
    frames=frames+1
    local now=os.clock()
    if now-fpsStart>=1 then
        if panel.Visible and pages.Performance.Visible then fpsLabel.Text="FPS client : "..math.floor(frames/(now-fpsStart)+0.5) end
        frames,fpsStart=0,now
    end
end)
local clear=row("Journal","Effacer le journal",true)
bind(clear.Activated,function() history={};logLabel.Text="Journal vide" end)
local function dispose()
    if closed then return end
    if engine then engine:close(true) end
    if adapter then adapter.close(true) end
    gui:SetAttribute("PolarisBlocked",false)
    if not adapter or not adapter.cleanupDeferred() then services.characterController:close() end
    closed=true;graphicsEpoch=graphicsEpoch+1
    if lowGraphics then
        services.Lighting.GlobalShadows=oldShadows
        for obj,value in pairs(originals) do if obj.Parent then pcall(function() obj.Enabled=value end) end end
    end
    for _,connection in ipairs(links) do connection:Disconnect() end
end
bind(close.Activated,function() if dispose()~=false then gui:Destroy() end end)
bind(cleanup.Event,dispose);bind(gui.Destroying,dispose)
bind(services.Input.InputBegan,function(input,processed)
    if not processed and input.KeyCode==Enum.KeyCode.RightControl then
        if panel.Visible then minimizePanel() else panel.Visible=true;reopen.Visible=false end
    end
end)

local function textSetting(page,key,titleValue,default,minValue,maxValue)
    row(page,titleValue,false);page=group(page)
    local input=make("TextBox",pages[page],{Size=UDim2.new(1,-2,0,42),Text=tostring(default),ClearTextOnFocus=false,
        BackgroundColor3=colors.card,TextColor3=colors.text,TextSize=14,Font=Enum.Font.Gotham,BorderSizePixel=0})
    orders[page]=orders[page]+1;input.LayoutOrder=orders[page];corner(input)
    bind(input.FocusLost,function()
        if minValue then
            local n=tonumber(input.Text)
            if not n or n~=n or n<minValue or n>maxValue then input.Text=tostring(config[key]);report("Valeur attendue entre "..minValue.." et "..maxValue);return end
            config[key]=n
        else config[key]=input.Text end
        report(titleValue.." : "..tostring(config[key]))
    end)
end
local function choice(page,key,titleValue,list,display)
    local index=1;config[key]=list[1]
    local function text() return titleValue.." : "..tostring(display and display(list[index]) or list[index]) end
    local b=row(page,text(),true)
    bind(b.Activated,function() index=index%#list+1;config[key]=list[index];b.Text=text() end)
end
toggle("Farm","quest","AUTO QUEST")
local replace=row("Farm","Remplacer une quete manuelle differente [OFF]",true)
bind(replace.Activated,function() config.replaceQuest=not config.replaceQuest;replace.Text="Remplacer quete manuelle ["..(config.replaceQuest and "ON" or "OFF").."]" end)
toggle("Maitrise","mastery","AUTO FARM MASTERY")
textSetting("Maitrise","masteryTool","Nom exact de l'equipement possede","",nil)
textSetting("Maitrise","masteryGoal","Mastery cible",300,1,600)
textSetting("Maitrise","masteryThreshold","Seuil de finition (fraction de sante)",0.25,0.05,0.75)
row("Maitrise","Melee / Sword : changement d'arme. Fruit / Gun : touches normales selectionnees, visee camera facultative et degats observes. Choisis uniquement des skills debloques. Tool.Level doit etre observable.",false)
toggle("Objets","item","AUTO FARM ITEM")
choice("Objets","itemObjective","Materiau",MATERIALS,function(x) return x.name.." / mer "..x.sea end)
textSetting("Objets","itemQuantity","Quantite totale cible",10,1,99999)
row("Objets","La fin depend de getInventory, pas du nombre d'ennemis vaincus. Les sources historiques doivent etre confirmees dans ta version du jeu.",false)
toggle("Boss","boss","AUTO BOSS")
local bossList={};local seen={}
for _,q in ipairs(QUESTS) do if q.boss and not seen[q.name] then seen[q.name]=true;table.insert(bossList,q.name) end end
table.insert(bossList,"Longma");choice("Boss","bossTarget","Boss present",bossList,function(x) return ALIASES[x] or x end)
row("Boss","Combat uniquement si le boss est charge et vivant. Aucun objet d'invocation n'est consomme.",false)
toggle("Evenements","event","AUTO EVENT")
choice("Evenements","eventObjective","Activite",ACTIVITIES,function(x) return x.name.." / "..x.status end)
row("Evenements","Les modules de combat traitent uniquement une cible deja presente. Les invocations, puzzles et bateaux disposent de pages separees avec leurs limites explicites. Aucun vol ne simule une navigation maritime.",false)
textSetting("Reglages","reserve","Reserve minimale Beli",100000,0,1000000000)
textSetting("Reglages","gachaBudget","Budget Gacha de cette session (0 = bloque)",0,0,1000000000)
textSetting("Reglages","gachaMaxPrice","Plafond estime par Gacha : doit couvrir le prix reel",500000,1,100000000)
textSetting("Reglages","shopBudget","Budget boutique de cette session (0 = bloque)",0,0,1000000000)
textSetting("Reglages","shopMaxPrice","Plafond estime par achat boutique",1200000,1,100000000)
textSetting("Reglages","speed","Vitesse de vol reglable (studs/s)",220,80,320)
textSetting("Reglages","exitRadius","Recherche d'une sortie libre : rayon maximal studs",10,2,12)
textSetting("Reglages","excludeFruits","Fruits exclus (noms exacts separes par virgules)","",nil)
row("Reglages","Les plafonds sont des estimations configurees, pas un devis serveur. Les budgets reservent ces montants a chaque demande envoyee, meme si elle est refusee. Pas d'achat automatique de Robux.",false)
for _,id in ipairs({"collect","event","boss","quest","farm","mastery","item"}) do
    local key="priority_"..id
    config[key]=engine and engine.tasks[id].priority or priorityDefaults[id]
    textSetting("Reglages",key,"Priorite "..id,config[key],0,150)
end
local recover=row("Reglages","Retenter une sortie libre (une tentative bornee)",true)
bind(recover.Activated,function() if adapter then local ok=adapter.recover(true);if ok and anyOptionEnabled() then engine:start() end;gui:SetAttribute("PolarisBlocked",not ok);report(ok and "Sortie libre confirmee" or "Aucune sortie libre proche ; deplacement suspendu") end end)
local resetStore=row("Fruits","Reessayer les fruits refuses au stockage",true)
bind(resetStore.Activated,function() if adapter then adapter.resetStore();report("Refus remis a zero par l'utilisateur") end end)


textSetting("Maitrise","skillKeys","Skills debloques (Z,X,C,V separes par virgules)",config.skillKeys,nil)
textSetting("Maitrise","skillInterval","Delai entre commandes skills (respecte tes cooldowns)",6,1,120)
textSetting("Maitrise","skillHold","Duree de maintien de touche en secondes",0.15,0.05,2)
textSetting("Maitrise","skillRange","Distance de combat Fruit/Gun",30,8,100)
local aim=row("Maitrise","Visee camera vers la cible [ON]",true)
bind(aim.Activated,function() config.skillAim=not config.skillAim;aim.Text="Visee camera ["..(config.skillAim and "ON" or "OFF").."]" end)
row("Maitrise","Les commandes virtuelles doivent etre disponibles. Le serveur valide les degats et cooldowns. Sans degats observes en 20 s, le module s'arrete. F/transformation n'est jamais envoye.",false)
toggle("Navigation","boat","NAVIGATION MARITIME")
local takeDestination=row("Navigation","Destination : position actuelle + 1000 studs devant",true)
bind(takeDestination.Activated,function()
 local char=player.Character;local r=char and char:FindFirstChild("HumanoidRootPart")
 if r then config.boatDestination=r.Position+r.CFrame.LookVector*1000;report("Destination maritime choisie a 1000 studs devant. Assieds-toi dans un bateau.") end
end)
local bx,by,bz="", "", ""
textSetting("Navigation","boatX","Destination X (studs)","",nil)
textSetting("Navigation","boatZ","Destination Z (studs)","",nil)
local applyDestination=row("Navigation","Appliquer la destination X / Z",true)
bind(applyDestination.Activated,function()
 local x,z=tonumber(config.boatX),tonumber(config.boatZ)
 if not x or not z or x~=x or z~=z or math.abs(x)>100000 or math.abs(z)>100000 then report("X/Z numeriques, entre -100000 et 100000");return end
 config.boatDestination=Vector3.new(x,0,z);report("Destination bateau mise a jour")
end)
textSetting("Navigation","boatTolerance","Rayon d'arrivee maritime",35,10,100)
row("Navigation","Siege actuel ou bateau possede charge. Direction et acceleration normales ; aucun tween/fly du bateau, aucun achat automatique ni evenement maritime garanti. Destruction, interruption ou 20 s sans progression : arret des commandes.",false)
toggle("Races","race3","RACE V3 / AROWE (PARTIEL)")
textSetting("Races","race3Budget","Budget evolution V3 (0 bloque paiement)",0,0,1000000000)
row("Races","Arowe : lecture/acceptation/paiement par dialogue visible. Human : boss; Rabbit : coffres charges; Cyborg : fruit porte. Shark : skills sur Sea Beast charge, puis validation Arowe. Origine naturelle non deduite automatiquement. Angel/Ghoul : epreuve PvP manuelle. Draco non implemente. La fin depend de la confirmation serveur.",false)
toggle("Invocations","summon","PREPARER UNE INVOCATION")
choice("Invocations","summonTarget","Boss a invoquer",{"Soul Reaper","rip_indra True Form","Dough King","Darkbeard"})
local rare=row("Invocations","Autoriser consommation de l'objet rare [OFF]",true)
bind(rare.Activated,function() config.allowRare=not config.allowRare;rare.Text="Consommation objet rare ["..(config.allowRare and "ON" or "OFF").."]" end)
row("Invocations","Implemente : Soul Reaper avec Hallow Essence possedee et autel historique charge. Une seule tentative ; presence du boss verifiee. Autres invocations non implementees et sans consommation. Aucun chalice/Fist sacrifies automatiquement.",false)
toggle("Puzzles","puzzle","PUZZLE SABER : PLAQUES (PARTIEL)")
row("Puzzles","Mer 1, niveau 200+. Lecture des 5 plaques et de la porte historique. Deux essais maximum par plaque ; verification du changement de couleur/porte. Torch, Cup, Relic, Yama, Tushita et CDK non implementes. Aucune porte ni collision de carte modifiee.",false)


toggle("Mer","marine","AUTO SEA BEAST / SKILLS")
toggle("Mer","seafish","AUTO SEA FISH : PIRANHA / FISH CREW / SHARK")
textSetting("Mer","marineTargets","Cibles Auto Beast (Sea Beast,Terrorshark...)",config.marineTargets,nil)
textSetting("Mer","marineTool","Nom exact de ton fruit/arme maritime",config.marineTool,nil)
textSetting("Mer","marineDetectRange","Distance de detection (zones chargees)",2500,100,5000)
textSetting("Mer","marineHeight","Hauteur de combat souhaitee (bornee a la portee)",12,2,20)
textSetting("Mer","marineHealthReserve","Pause/retour bateau si sante sous cette fraction",0.35,0.2,0.8)
local patrolButton=row("Mer","Patrouille bateau si aucune cible [OFF]",true)
bind(patrolButton.Activated,function() config.marinePatrol=not config.marinePatrol;patrolButton.Text="Patrouille bateau ["..(config.marinePatrol and "ON" or "OFF").."]" end)
textSetting("Mer","marineSearchRadius","Rayon de patrouille autour du depart",1500,250,5000)
textSetting("Mer","marineSearchSeconds","Duree maximale de recherche sans cible (secondes)",600,60,3600)
row("Mer","Choisir l'equipement et ses touches dans Maitrise. Detection une fois/seconde : Enemies/SeaBeasts charges, sante numerique requise. Skills uniquement ; aucun drop garanti. Combat et bateau ne sont jamais controles ensemble. Schemas de sante non reconnus : attente explicite.",false)
toggle("Mirage","mirage","AUTO FIND / APPROCHE MIRAGE")
textSetting("Mirage","mirageStandOff","Distance d'approche au centre de l'ile",180,80,500)
row("Mirage","Detection de Map.MysticIsland ou Mirage Island chargee. Patrouille facultative depuis un bateau, approche avec commandes normales. Aucun spawn force, aucun scan d'iles non chargees. Resonance/Blue Gear ne sont pas simules.",false)
local v4Info=row("V4","Verification des prerequis : non lancee",false)
local v4Check=row("V4","Verifier les prerequis observables",true)
bind(v4Check.Activated,function()
 if not adapter then return end
 local d=adapter.raceOverview(os.clock())
 v4Info.Text="Race : "..d.race.." / marqueur V2 : "..tostring(d.v2).."\nV3 confirme par ce module : "..tostring(d.v3Confirmed)..
  " / Mirror Fractal inventaire : "..(d.mirrorFractal==nil and "requete en attente; recliquer" or tostring(d.mirrorFractal))..
  "\nMirage chargee : "..tostring(d.mirageLoaded).."\n"..d.v4
end)
row("V4","V4 hors Draco : V3, progression Sealed King / indra, Mirror Fractal, resonance lunaire sur Mirage, Blue Gear, levier, trials et horloge. Certaines etapes demandent plusieurs joueurs. Le script aide a chercher Mirage et lire l'inventaire ; trials et puzzles V4 automatiques NON IMPLEMENTES.",false)
row("V4","Human : Strength ; Shark : Water ; Rabbit : Speed ; Angel : King ; Ghoul : Carnage ; Cyborg : Machine. Chaque trial a sa logique propre ; aucun trajet unique ne valide toutes les races. Draco suit sa propre chaine/Trial of Flames, non implementee.",false)
row("Races","V2 hors Draco : module fleurs historique conserve, acces/argent verifies par Alchemist. Draco V2/V3/V4 : chaines specifiques non implementees. Aucune evolution annoncee uniquement parce que le personnage est arrive a un PNJ.",false)

local function refresh()
    if not engine then return end
    local count=0
    for id,b in pairs(toggleButtons) do
        local entry=engine.tasks[id]
        local detail=adapter.taskStatus(id) or {}
        local widget=toggleWidgets[id]
        if widget then
            widget.track.BackgroundColor3=entry.enabled and colors.accent or Color3.fromRGB(37,38,46)
            widget.thumb.BackgroundColor3=entry.enabled and colors.text or colors.muted
            widget.thumb.Position=entry.enabled and UDim2.fromOffset(23,3) or UDim2.fromOffset(3,3)
        end
        local textValue=entry.label..(entry.enabled and "  [ON]" or "  [OFF]").."\n"..(entry.enabled and (detail.state or entry.state or "en attente") or entry.state or "desactivee").." : "..(entry.enabled and (detail.reason or entry.reason or "") or entry.reason or "")
        if b.Text~=textValue then b.Text=textValue;b.BackgroundColor3=colors.card end
        if entry.enabled then count=count+1 end
    end
    summary.Text=count.." option(s) active(s)  /  "..(engine.running and "EN MARCHE" or "EN PAUSE")
    local d=adapter.diagnostics()
    local data=player:FindFirstChild("Data")
    local function value(name) local v=data and data:FindFirstChild(name);return v and tostring(v.Value) or "--" end
    local race=value("Race")
    raceInfo.Text="Race actuelle : "..race.."\n"..(v3guide[race] or "Consulte Arowe pour l'objectif de ta race.")
    stats.Text="Mer "..d.sea.."   |   Niveau "..value("Level").."   |   Beli "..value("Beli").."   |   Fragments "..value("Fragments")..
        "\nQuete : "..d.quest.."   |   Appels : "..d.requests.."\nGacha : "..math.floor(d.gachaWait/60).." min   |   Boutique : "..d.shop..(d.shopBlocked and " (arretee)" or "")
    if d.blocked or d.movementBlocked then if engine.running then engine:pause() end;status.Text=d.blocked or d.movementBlocked end
end
report("Polaris v0.10 charge. Menu compact ; toutes les actions sont OFF.")
refresh()
task.spawn(function()
    local lastRefresh=0
    while not closed do
        local ok,err=pcall(function()
            if not initializationFinished then safeInitializeActions() end
            if adapter then adapter.transport:poll();adapter.maintenance(os.clock(),engine and engine.running) end
            if engine then for _,id in ipairs({"collect","event","boss","quest","farm","mastery","item"}) do engine.tasks[id].priority=config["priority_"..id] end;engine:tick() end
            if os.clock()-lastRefresh>=1 then lastRefresh=os.clock();refresh() end
        end)
        if not ok then if engine then engine:pause() end;warn("[Polaris] "..tostring(err));report("Arret: "..tostring(err):sub(1,200)) end
        task.wait(0.2)
    end
end)

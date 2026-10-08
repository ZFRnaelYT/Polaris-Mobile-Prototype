-- POLARIS v0.9 | Client experimental, sans dependance distante.
-- Input: polaris_mobile(1).lua v0.5, SHA256 deae6e159f1269edb6bccd6175315a4c1bb2a7161f60e184ade9da970a527dab.
-- Implemented: shared movement, bounded exits, exact property restoration,
-- foreground scheduler, cancellable background queue, observable inventory checks.
-- Partial: historical quest catalog, ordinary Tool:Activate combat, Sword/Melee mastery,
-- material sources, visible-fruit collection/storage, Gacha, existing V2 flower chain.
-- Legendary purchases: visible NPC dialogue only, exact sword and displayed Beli price required.
-- Experimental: normal-input skills, current-seat navigation, V3 assistance, Saber plates, Soul Reaper.
-- Added: loaded maritime targets with readable HP, skill-only Sea Beast combat, boat patrol and loaded Mirage approach.
-- V4 is guidance/preflight only; no automatic trials or completed awakening is claimed.
-- NOT COMPLETE: full V3 for all races, all summons and all puzzles. Live-game validation still required.
-- No universal server compatibility, zero-lag or undetected-execution guarantee.
-- Purchases use configurable estimates, reserve and conservative session budgets.
-- Existing race V2 chain retains its own evolution cost; do not enable without funds.
-- Sources inspected:
-- https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/WorldRoot.yaml
-- Roblox/creator-docs/LICENSE: CC BY 4.0. API semantics studied, no documentation text copied.
-- https://create.roblox.com/docs/reference/engine/classes/VehicleSeat
-- https://create.roblox.com/docs/reference/engine/classes/VirtualInputManager
-- https://bffr.fr/wiki/en/activites/sea-beast/
-- https://bffr.fr/wiki/en/guides/race-awakening/
-- https://bffr.fr/wiki/en/quetes/arowe/
-- https://bffr.fr/wiki/en/objets/ancient-relic/
-- https://create.roblox.com/docs/reference/engine/classes/LinearVelocity
-- https://github.com/BLOXFRUIT-SCRIPT/REDZ-HUB-V2/blob/main/REDZ%20HUB%20V2
-- No LICENSE found in repository root; no new implementation copied. Historical input data retained.
-- https://bffr.fr/wiki/quetes/quests/ (changed zones blocked pending live quest IDs).
-- https://bffr.fr/wiki/en/activites/events/ (metadata; no verified live-game catalog).
-- Verified tests are reported in the delivered response; no live Delta/Roblox session available.
local function newEngine(adapter,clock,publish)
    local self={running=false,closed=false,tasks={},sequence={},active=nil,steps=0,prefix="POLARIS : ",since=0}
    local function status(message) if self.lastStatus~=message then self.lastStatus=message;publish(message) end end
    local function invoke(name,...) return pcall(adapter[name],...) end
    function self:add(id,label,priority,interval,background)
        local e={id=id,label=label,priority=priority,interval=interval,background=background or false,
            enabled=false,nextAt=0,failures=0,state="desactivee",reason=""}
        self.tasks[id]=e;table.insert(self.sequence,e)
    end
    function self:release(transfer)
        if not self.active then return true end
        local previous=self.active;self.active=nil
        local ok,result=invoke("suspend",previous.id,transfer)
        previous.state=previous.enabled and "suspendue" or "desactivee"
        if not ok or result==false then
            self.running=false;previous.state="erreur";status("Arret impossible : "..tostring(result));return false
        end
        return true
    end
    function self:enable(id,value)
        local e=assert(self.tasks[id],id)
        e.enabled=value;e.failures=0;e.nextAt=0;e.state=value and "en attente" or "desactivee"
        if adapter.setEnabled then adapter.setEnabled(id,value) end
        if not value and self.active==e then self:release(false) end
    end
    function self:start()
        if not self.closed then
            if adapter.resumeRequests then adapter.resumeRequests() end
            self.running=true;status("Demarre")
        end
    end
    function self:pause()
        self.running=false
        if adapter.pauseRequests then adapter.pauseRequests() end
        if self:release(false) then
            if adapter.recover and not adapter.recover() then status("Pause : sortie libre requise") else status("Pause") end
        end
    end
    function self:close()
        self:pause()
        if adapter.canClose and not adapter.canClose() then return false end
        self.closed=true;return true
    end
    function self:fail(e,reason)
        e.failures=e.failures+1;e.reason=tostring(reason);e.state="erreur"
        -- A movement refusal is never retried by teleport spam.
        e.enabled=false
        if adapter.setEnabled then adapter.setEnabled(e.id,false) end
        if self.active==e then self:release(false) end
        e.state="erreur"
        status(e.label.." : "..e.reason)
    end
    function self:runStep(e,now)
        local ok,done=invoke("step",e.id,now)
        self.steps=self.steps+1
        if not ok then self:fail(e,done);return end
        local s=adapter.taskStatus and adapter.taskStatus(e.id)
        if s then e.state,e.reason=s.state,s.reason end
        if done then
            e.nextAt=now+e.interval
            if self.active==e then self:release(false) end
        end
        if s and s.state=="terminee" then self:enable(e.id,false);e.state="terminee" end
    end
    function self:tick()
        if not self.running or self.closed then return end
        local now=clock();local ready={};local selected
        for _,e in ipairs(self.sequence) do
            if e.enabled and now>=e.nextAt then
                local ok,value=invoke("ready",e.id,now)
                if not ok then self:fail(e,value)
                elseif value then
                    ready[e.id]=true
                    if e.background then self:runStep(e,now)
                    elseif not selected or e.priority>selected.priority then selected=e end
                elseif e~=self.active and e.state~="erreur" and e.state~="terminee" then e.state="en attente" end
            end
        end
        if not self.running then return end
        local active=self.active
        -- Equal-priority tasks do not bounce; a task retains its target for >=1.5 s.
        if active and active.enabled and ready[active.id] and selected~=active and
            (not selected or selected.priority<=active.priority or now-self.since<1.5) then selected=active end
        if selected~=active then
            if not self:release(selected~=nil) then return end
            self.active=selected;self.since=now
        end
        if selected then self:runStep(selected,now);status(self.prefix..selected.label)
        else status("En attente / aucune cible disponible") end
    end
    return self
end
local QUESTS = {
    {sea=1, level=1, boss=false, name="Bandit", quest="BanditQuest1", index=1, pos=CFrame.new(1059, 17, 1546), spawn=CFrame.new(943, 45, 1562)},
    {sea=1, level=10, boss=false, name="Monkey", quest="JungleQuest", index=1, pos=CFrame.new(-1598, 37, 153), spawn=CFrame.new(-1524, 50, 37)},
    {sea=1, level=20, boss=true, name="The Gorilla King", quest="JungleQuest", index=3, pos=CFrame.new(-1598, 37, 153), spawn=CFrame.new(-1128, 6, -451)},
    {sea=1, level=15, boss=false, name="Gorilla", quest="JungleQuest", index=2, pos=CFrame.new(-1598, 37, 153), spawn=CFrame.new(-1128, 40, -451)},
    {sea=1, level=30, boss=false, name="Pirate", quest="BuggyQuest1", index=1, pos=CFrame.new(-1140, 4, 3829), spawn=CFrame.new(-1262, 40, 3905)},
    {sea=1, level=55, boss=true, name="Bobby", quest="BuggyQuest1", index=3, pos=CFrame.new(-1140, 4, 3829), spawn=CFrame.new(-1131, 14, 4080)},
    {sea=1, level=40, boss=false, name="Brute", quest="BuggyQuest1", index=2, pos=CFrame.new(-1140, 4, 3829), spawn=CFrame.new(-976, 55, 4304)},
    {sea=1, level=60, boss=false, name="Desert Bandit", quest="DesertQuest", index=1, pos=CFrame.new(897, 6, 4389), spawn=CFrame.new(938, 6, 4470)},
    {sea=1, level=75, boss=false, name="Desert Officer", quest="DesertQuest", index=2, pos=CFrame.new(897, 6, 4389), spawn=CFrame.new(1546, 14, 4384)},
    {sea=1, level=90, boss=false, name="Snow Bandit", quest="SnowQuest", index=1, pos=CFrame.new(1385, 87, -1298), spawn=CFrame.new(1303, 106, -1441)},
    {sea=1, level=105, boss=true, name="Yeti", quest="SnowQuest", index=3, pos=CFrame.new(1385, 87, -1298), spawn=CFrame.new(1185, 106, -1518)},
    {sea=1, level=100, boss=false, name="Snowman", quest="SnowQuest", index=2, pos=CFrame.new(1385, 87, -1298), spawn=CFrame.new(1185, 106, -1518)},
    {sea=1, level=130, boss=true, name="Vice Admiral", quest="MarineQuest2", index=2, pos=CFrame.new(-5035, 29, 4326), spawn=CFrame.new(-4807, 21, 4360)},
    {sea=1, level=120, boss=false, name="Chief Petty Officer", quest="MarineQuest2", index=1, pos=CFrame.new(-5035, 29, 4326), spawn=CFrame.new(-4807, 21, 4360)},
    {sea=1, level=150, boss=false, name="Sky Bandit", quest="SkyQuest", index=1, pos=CFrame.new(-4844, 718, -2621), spawn=CFrame.new(-4956, 296, -2901)},
    {sea=1, level=175, boss=false, name="Dark Master", quest="SkyQuest", index=2, pos=CFrame.new(-4844, 718, -2621), spawn=CFrame.new(-5268, 392, -2213)},
    {sea=1, level=190, boss=false, name="Prisoner", quest="PrisonerQuest", index=1, pos=CFrame.new(5306, 2, 477), spawn=CFrame.new(5288, 2, 470)},
    {sea=1, level=240, boss=true, name="Swan", quest="ImpelQuest", index=3, pos=CFrame.new(5191, 4, 692), spawn=CFrame.new(5230, 4, 749)},
    {sea=1, level=230, boss=true, name="Chief Warden", quest="ImpelQuest", index=2, pos=CFrame.new(5191, 4, 692), spawn=CFrame.new(5230, 4, 749)},
    {sea=1, level=220, boss=true, name="Warden", quest="ImpelQuest", index=1, pos=CFrame.new(5191, 4, 692), spawn=CFrame.new(5230, 4, 749)},
    {sea=1, level=210, boss=false, name="Dangerous Prisoner", quest="PrisonerQuest", index=2, pos=CFrame.new(5306, 2, 477), spawn=CFrame.new(5282, 2, 1052)},
    {sea=1, level=250, boss=false, name="Toga Warrior", quest="ColosseumQuest", index=1, pos=CFrame.new(-1581, 7, -2982), spawn=CFrame.new(-1897, 7, -2796)},
    {sea=1, level=275, boss=false, name="Gladiator", quest="ColosseumQuest", index=2, pos=CFrame.new(-1581, 7, -2982), spawn=CFrame.new(-1327, 59, -3231)},
    {sea=1, level=300, boss=false, name="Military Soldier", quest="MagmaQuest", index=1, pos=CFrame.new(-5319, 12, 8515), spawn=CFrame.new(-5335, 46, 8638)},
    {sea=1, level=350, boss=true, name="Magma Admiral", quest="MagmaQuest", index=3, pos=CFrame.new(-5319, 12, 8515), spawn=CFrame.new(-5694, 18, 8735)},
    {sea=1, level=325, boss=false, name="Military Spy", quest="MagmaQuest", index=2, pos=CFrame.new(-5319, 12, 8515), spawn=CFrame.new(-5791, 97, 8834)},
    {sea=1, level=375, boss=false, name="Fishman Warrior", quest="FishmanQuest", index=1, pos=CFrame.new(61122, 18, 1567), spawn=CFrame.new(60998, 50, 1534)},
    {sea=1, level=425, boss=true, name="Fishman Lord", quest="FishmanQuest", index=3, pos=CFrame.new(61122, 18, 1567), spawn=CFrame.new(61350, 31, 1095)},
    {sea=1, level=400, boss=false, name="Fishman Commando", quest="FishmanQuest", index=2, pos=CFrame.new(61122, 18, 1567), spawn=CFrame.new(61866, 55, 1655)},
    {sea=1, level=450, boss=false, name="God's Guard", quest="SkyExp1Quest", index=1, pos=CFrame.new(-4720, 846, -1951), spawn=CFrame.new(-4641, 880, -1902)},
    {sea=1, level=500, boss=true, name="Wysper", quest="SkyExp1Quest", index=3, pos=CFrame.new(-7861, 5545, -381), spawn=CFrame.new(-7927, 5551, -637)},
    {sea=1, level=475, boss=false, name="Shanda", quest="SkyExp1Quest", index=2, pos=CFrame.new(-7861, 5545, -381), spawn=CFrame.new(-7741, 5580, -395)},
    {sea=1, level=525, boss=false, name="Royal Squad", quest="SkyExp2Quest", index=1, pos=CFrame.new(-7903, 5636, -1412), spawn=CFrame.new(-7727, 5650, -1410)},
    {sea=1, level=575, boss=true, name="Thunder God", quest="SkyExp2Quest", index=3, pos=CFrame.new(-7903, 5636, -1412), spawn=CFrame.new(-7751, 5607, -2315)},
    {sea=1, level=550, boss=false, name="Royal Soldier", quest="SkyExp2Quest", index=2, pos=CFrame.new(-7903, 5636, -1412), spawn=CFrame.new(-7894, 5640, -1629)},
    {sea=1, level=625, boss=false, name="Galley Pirate", quest="FountainQuest", index=1, pos=CFrame.new(5258, 39, 4052), spawn=CFrame.new(5391, 70, 4023)},
    {sea=1, level=675, boss=true, name="Cyborg", quest="FountainQuest", index=3, pos=CFrame.new(5258, 39, 4052), spawn=CFrame.new(6138, 10, 3939)},
    {sea=1, level=650, boss=false, name="Galley Captain", quest="FountainQuest", index=2, pos=CFrame.new(5258, 39, 4052), spawn=CFrame.new(5985, 70, 4790)},
    {sea=2, level=700, boss=false, name="Raider", quest="Area1Quest", index=1, pos=CFrame.new(-427, 73, 1835), spawn=CFrame.new(-614, 90, 2240)},
    {sea=2, level=750, boss=true, name="Diamond", quest="Area1Quest", index=3, pos=CFrame.new(-427, 73, 1835), spawn=CFrame.new(-1569, 199, -31)},
    {sea=2, level=725, boss=false, name="Mercenary", quest="Area1Quest", index=2, pos=CFrame.new(-427, 73, 1835), spawn=CFrame.new(-867, 110, 1621)},
    {sea=2, level=775, boss=false, name="Swan Pirate", quest="Area2Quest", index=1, pos=CFrame.new(635, 73, 919), spawn=CFrame.new(778, 110, 1129)},
    {sea=2, level=850, boss=true, name="Jeremy", quest="Area2Quest", index=3, pos=CFrame.new(635, 73, 919), spawn=CFrame.new(2316, 449, 787)},
    {sea=2, level=800, boss=false, name="Factory Staff", quest="Area2Quest", index=2, pos=CFrame.new(635, 73, 919), spawn=CFrame.new(882, 110, -49)},
    {sea=2, level=875, boss=false, name="Marine Lieutenant", quest="MarineQuest3", index=1, pos=CFrame.new(-2441, 73, -3219), spawn=CFrame.new(-2552, 110, -3050)},
    {sea=2, level=925, boss=true, name="Fajita", quest="MarineQuest3", index=3, pos=CFrame.new(-2441, 73, -3219), spawn=CFrame.new(-2086, 73, -4208)},
    {sea=2, level=900, boss=false, name="Marine Captain", quest="MarineQuest3", index=2, pos=CFrame.new(-2441, 73, -3219), spawn=CFrame.new(-1695, 110, -3299)},
    {sea=2, level=950, boss=false, name="Zombie", quest="ZombieQuest", index=1, pos=CFrame.new(-5495, 48, -794), spawn=CFrame.new(-5715, 90, -917)},
    {sea=2, level=975, boss=false, name="Vampire", quest="ZombieQuest", index=2, pos=CFrame.new(-5495, 48, -794), spawn=CFrame.new(-6027, 50, -1130)},
    {sea=2, level=1000, boss=false, name="Snow Trooper", quest="SnowMountainQuest", index=1, pos=CFrame.new(607, 401, -5371), spawn=CFrame.new(445, 440, -5175)},
    {sea=2, level=1050, boss=false, name="Winter Warrior", quest="SnowMountainQuest", index=2, pos=CFrame.new(607, 401, -5371), spawn=CFrame.new(1224, 460, -5332)},
    {sea=2, level=1100, boss=false, name="Lab Subordinate", quest="IceSideQuest", index=1, pos=CFrame.new(-6061, 16, -4904), spawn=CFrame.new(-5941, 50, -4322)},
    {sea=2, level=1150, boss=true, name="Smoke Admiral", quest="IceSideQuest", index=3, pos=CFrame.new(-6061, 16, -4904), spawn=CFrame.new(-5078, 24, -5352)},
    {sea=2, level=1125, boss=false, name="Horned Warrior", quest="IceSideQuest", index=2, pos=CFrame.new(-6061, 16, -4904), spawn=CFrame.new(-6306, 50, -5752)},
    {sea=2, level=1175, boss=false, name="Magma Ninja", quest="FireSideQuest", index=1, pos=CFrame.new(-5430, 16, -5298), spawn=CFrame.new(-5233, 60, -6227)},
    {sea=2, level=1200, boss=false, name="Lava Pirate", quest="FireSideQuest", index=2, pos=CFrame.new(-5430, 16, -5298), spawn=CFrame.new(-4955, 60, -4836)},
    {sea=2, level=1250, boss=false, name="Ship Deckhand", quest="ShipQuest1", index=1, pos=CFrame.new(1033, 125, 32909), spawn=CFrame.new(1185, 180, 32979)},
    {sea=2, level=1275, boss=false, name="Ship Engineer", quest="ShipQuest1", index=2, pos=CFrame.new(1033, 125, 32909), spawn=CFrame.new(809, 80, 33090)},
    {sea=2, level=1300, boss=false, name="Ship Steward", quest="ShipQuest2", index=1, pos=CFrame.new(973, 125, 33245), spawn=CFrame.new(838, 160, 33408)},
    {sea=2, level=1325, boss=false, name="Ship Officer", quest="ShipQuest2", index=2, pos=CFrame.new(973, 125, 33245), spawn=CFrame.new(1238, 220, 33148)},
    {sea=2, level=1350, boss=false, name="Arctic Warrior", quest="FrostQuest", index=1, pos=CFrame.new(5668, 28, -6484), spawn=CFrame.new(5836, 80, -6257)},
    {sea=2, level=1400, boss=true, name="Awakened Ice Admiral", quest="FrostQuest", index=3, pos=CFrame.new(5668, 28, -6484), spawn=CFrame.new(6473, 297, -6944)},
    {sea=2, level=1375, boss=false, name="Snow Lurker", quest="FrostQuest", index=2, pos=CFrame.new(5668, 28, -6484), spawn=CFrame.new(5700, 80, -6724)},
    {sea=2, level=1425, boss=false, name="Sea Soldier", quest="ForgottenQuest", index=1, pos=CFrame.new(-3056, 240, -10145), spawn=CFrame.new(-2583, 80, -9821)},
    {sea=2, level=1475, boss=true, name="Tide Keeper", quest="ForgottenQuest", index=3, pos=CFrame.new(-3056, 240, -10145), spawn=CFrame.new(-3711, 77, -11469)},
    {sea=2, level=1450, boss=false, name="Water Fighter", quest="ForgottenQuest", index=2, pos=CFrame.new(-3056, 240, -10145), spawn=CFrame.new(-3339, 290, -10412)},
    {sea=3, level=1500, boss=false, name="Pirate Millionaire", quest="PiratePortQuest", index=1, pos=CFrame.new(-291, 44, 5580), spawn=CFrame.new(-44, 70, 5623)},
    {sea=3, level=1550, boss=true, name="Stone", quest="PiratePortQuest", index=3, pos=CFrame.new(-291, 44, 5580), spawn=CFrame.new(-1049, 40, 6791)},
    {sea=3, level=1525, boss=false, name="Pistol Billionaire", quest="PiratePortQuest", index=2, pos=CFrame.new(-291, 44, 5580), spawn=CFrame.new(219, 105, 6018)},
    {sea=3, level=1575, boss=false, name="Dragon Crew Warrior", quest="AmazonQuest", index=1, pos=CFrame.new(5834, 51, -1103), spawn=CFrame.new(5992, 90, -1581)},
    {sea=3, level=1600, boss=false, name="Dragon Crew Archer", quest="AmazonQuest", index=2, pos=CFrame.new(5834, 51, -1103), spawn=CFrame.new(6472, 370, -151)},
    {sea=3, level=1625, boss=false, name="Female Islander", quest="AmazonQuest2", index=1, pos=CFrame.new(5448, 602, 748), spawn=CFrame.new(4836, 740, 928)},
    {sea=3, level=1675, boss=true, name="Island Empress", quest="AmazonQuest2", index=3, pos=CFrame.new(5448, 602, 748), spawn=CFrame.new(5730, 602, 199)},
    {sea=3, level=1650, boss=false, name="Giant Islander", quest="AmazonQuest2", index=2, pos=CFrame.new(5448, 602, 748), spawn=CFrame.new(4784, 660, 155)},
    {sea=3, level=1700, boss=false, name="Marine Commodore", quest="MarineTreeIsland", index=1, pos=CFrame.new(2180, 29, -6738), spawn=CFrame.new(3156, 120, -7837)},
    {sea=3, level=1750, boss=true, name="Kilo Admiral", quest="MarineTreeIsland", index=3, pos=CFrame.new(2180, 29, -6738), spawn=CFrame.new(2889, 424, -7233)},
    {sea=3, level=1725, boss=false, name="Marine Rear Admiral", quest="MarineTreeIsland", index=2, pos=CFrame.new(2180, 29, -6738), spawn=CFrame.new(3205, 120, -6742)},
    {sea=3, level=1775, boss=false, name="Fishman Raider", quest="DeepForestIsland3", index=1, pos=CFrame.new(-10581, 332, -8758), spawn=CFrame.new(-10550, 380, -8574)},
    {sea=3, level=1800, boss=false, name="Fishman Captain", quest="DeepForestIsland3", index=2, pos=CFrame.new(-10581, 332, -8758), spawn=CFrame.new(-10764, 380, -8799)},
    {sea=3, level=1825, boss=false, name="Forest Pirate", quest="DeepForestIsland", index=1, pos=CFrame.new(-13233, 332, -7626), spawn=CFrame.new(-13335, 380, -7660)},
    {sea=3, level=1875, boss=true, name="Captain Elephant", quest="DeepForestIsland", index=3, pos=CFrame.new(-13233, 332, -7626), spawn=CFrame.new(-13393, 319, -8423)},
    {sea=3, level=1850, boss=false, name="Mythological Pirate", quest="DeepForestIsland", index=2, pos=CFrame.new(-13233, 332, -7626), spawn=CFrame.new(-13844, 520, -7016)},
    {sea=3, level=1900, boss=false, name="Jungle Pirate", quest="DeepForestIsland2", index=1, pos=CFrame.new(-12682, 391, -9901), spawn=CFrame.new(-12166, 380, -10375)},
    {sea=3, level=1950, boss=true, name="Beautiful Pirate", quest="DeepForestIsland2", index=3, pos=CFrame.new(-12682, 391, -9901), spawn=CFrame.new(5241, 23, 129)},
    {sea=3, level=1925, boss=false, name="Musketeer Pirate", quest="DeepForestIsland2", index=2, pos=CFrame.new(-12682, 391, -9901), spawn=CFrame.new(-13098, 450, -9831)},
    {sea=3, level=1975, boss=false, name="Reborn Skeleton", quest="HauntedQuest1", index=1, pos=CFrame.new(-9481, 142, 5565), spawn=CFrame.new(-8680, 190, 5852)},
    {sea=3, level=2000, boss=false, name="Living Zombie", quest="HauntedQuest1", index=2, pos=CFrame.new(-9481, 142, 5565), spawn=CFrame.new(-10104, 200, 5739)},
    {sea=3, level=2025, boss=false, name="Demonic Soul", quest="HauntedQuest2", index=1, pos=CFrame.new(-9515, 172, 6078), spawn=CFrame.new(-9275, 210, 6166)},
    {sea=3, level=2050, boss=false, name="Posessed Mummy", quest="HauntedQuest2", index=2, pos=CFrame.new(-9515, 172, 6078), spawn=CFrame.new(-9442, 60, 6304)},
    {sea=3, level=2075, boss=false, name="Peanut Scout", quest="NutsIslandQuest", index=1, pos=CFrame.new(-2104, 38, -10194), spawn=CFrame.new(-1870, 100, -10225)},
    {sea=3, level=2100, boss=false, name="Peanut President", quest="NutsIslandQuest", index=2, pos=CFrame.new(-2104, 38, -10194), spawn=CFrame.new(-2005, 100, -10585)},
    {sea=3, level=2125, boss=false, name="Ice Cream Chef", quest="IceCreamIslandQuest", index=1, pos=CFrame.new(-818, 66, -10964), spawn=CFrame.new(-501, 100, -10883)},
    {sea=3, level=2175, boss=true, name="Cake Queen", quest="IceCreamIslandQuest", index=3, pos=CFrame.new(-818, 66, -10964), spawn=CFrame.new(-710, 382, -11150)},
    {sea=3, level=2150, boss=false, name="Ice Cream Commander", quest="IceCreamIslandQuest", index=2, pos=CFrame.new(-818, 66, -10964), spawn=CFrame.new(-690, 100, -11350)},
    {sea=3, level=2200, boss=false, name="Cookie Crafter", quest="CakeQuest1", index=1, pos=CFrame.new(-2023, 38, -12028), spawn=CFrame.new(-2332, 90, -12049)},
    {sea=3, level=2225, boss=false, name="Cake Guard", quest="CakeQuest1", index=2, pos=CFrame.new(-2023, 38, -12028), spawn=CFrame.new(-1514, 90, -12422)},
    {sea=3, level=2250, boss=false, name="Baking Staff", quest="CakeQuest2", index=1, pos=CFrame.new(-1931, 38, -12840), spawn=CFrame.new(-1930, 90, -12963)},
    {sea=3, level=2275, boss=false, name="Head Baker", quest="CakeQuest2", index=2, pos=CFrame.new(-1931, 38, -12840), spawn=CFrame.new(-2123, 110, -12777)},
    {sea=3, level=2300, boss=false, name="Cocoa Warrior", quest="ChocQuest1", index=1, pos=CFrame.new(235, 25, -12199), spawn=CFrame.new(110, 80, -12245)},
    {sea=3, level=2325, boss=false, name="Chocolate Bar Battler", quest="ChocQuest1", index=2, pos=CFrame.new(235, 25, -12199), spawn=CFrame.new(579, 80, -12413)},
    {sea=3, level=2350, boss=false, name="Sweet Thief", quest="ChocQuest2", index=1, pos=CFrame.new(150, 25, -12777), spawn=CFrame.new(-68, 80, -12692)},
    {sea=3, level=2375, boss=false, name="Candy Rebel", quest="ChocQuest2", index=2, pos=CFrame.new(150, 25, -12777), spawn=CFrame.new(17, 80, -12962)},
    {sea=3, level=2400, boss=false, name="Candy Pirate", quest="CandyQuest1", index=1, pos=CFrame.new(-1148, 14, -14446), spawn=CFrame.new(-1371, 70, -14405)},
    {sea=3, level=2425, boss=false, name="Snow Demon", quest="CandyQuest1", index=2, pos=CFrame.new(-1148, 14, -14446), spawn=CFrame.new(-836, 70, -14326)},
    {sea=3, level=2450, boss=false, name="Isle Outlaw", quest="TikiQuest1", index=1, pos=CFrame.new(-16547, 56, -172), spawn=CFrame.new(-16431, 90, -223)},
    {sea=3, level=2475, boss=false, name="Island Boy", quest="TikiQuest1", index=2, pos=CFrame.new(-16547, 56, -172), spawn=CFrame.new(-16668, 70, -243)},
    {sea=3, level=2500, boss=false, name="Sun-kissed Warrior", quest="TikiQuest2", index=1, pos=CFrame.new(-16540, 56, 1051), spawn=CFrame.new(-16345, 80, 1004)},
    {sea=3, level=2525, boss=false, name="Isle Champion", quest="TikiQuest2", index=2, pos=CFrame.new(-16540, 56, 1051), spawn=CFrame.new(-16634, 85, 1106)},
}

-- Activity metadata; combat-present and preparation are intentionally distinct.
local ALIASES={Bobby="Chef",Wysper="Sky Warlord",Fajita="Orbitus",["Island Empress"]="Hydra Leader"}
local MATERIALS={
    {name="Angel Wings",sea=1,enemies={"Royal Soldier","Royal Squad"}},
    {name="Magma Ore",sea=1,enemies={"Military Soldier","Military Spy"}},
    {name="Fish Tail",sea=1,enemies={"Fishman Warrior","Fishman Commando"}},
    {name="Leather",sea=1,enemies={"Pirate","Brute"}},
    {name="Scrap Metal",sea=1,enemies={"Pirate","Brute"}},
    {name="Ectoplasm",sea=2,enemies={"Ship Deckhand","Ship Engineer","Ship Steward","Ship Officer"}},
    {name="Mystic Droplet",sea=2,enemies={"Water Fighter"}},
    {name="Radioactive Material",sea=2,enemies={"Factory Staff"}},
    {name="Vampire Fang",sea=2,enemies={"Vampire"}},
    {name="Gunpowder",sea=3,enemies={"Pistol Billionaire"}},
    {name="Mini Tusk",sea=3,enemies={"Mythological Pirate"}},
    {name="Conjured Cocoa",sea=3,enemies={"Cocoa Warrior","Chocolate Bar Battler"}},
    {name="Bones",sea=3,enemies={"Reborn Skeleton","Living Zombie","Demonic Soul","Posessed Mummy"}},
}
local ACTIVITIES={
    {name="Greybeard",sea=1,enemies={"Greybeard"},status="combat present",needs="Boss deja apparu; aucun spawn garanti"},
    {name="Saber",sea=1,status="partiel : plaques uniquement",needs="Page Puzzles; Torch/Cup/Relic non implementes"},
    {name="Passage Sea 2",sea=1,status="non pris en charge",needs="Quete de progression et voyage dedies"},
    {name="Factory",sea=2,enemies={"Core"},status="combat present",needs="Core present et vulnerable; progression serveur"},
    {name="Darkbeard",sea=2,enemies={"Darkbeard"},status="combat present",needs="Deja invoque; aucun Fist of Darkness consomme"},
    {name="Order",sea=2,enemies={"Order"},status="combat present",needs="Raid deja lance; aucune puce achetee"},
    {name="Cursed Captain",sea=2,enemies={"Cursed Captain"},status="combat present",needs="Boss deja present"},
    {name="Races V2",sea=2,status="partiel",needs="850+, Colisee, 500000 Beli, hors Draco; module fleurs existant"},
    {name="Races V3",sea=2,status="partiel : Arowe/Human/Rabbit/Cyborg",needs="Page Races; Shark/PvP/Draco non implementes"},
    {name="Pirate Raid",sea=3,status="non pris en charge",needs="Reconnaissance des vagues du Castle requise"},
    {name="rip_indra True Form",sea=3,enemies={"rip_indra True Form"},status="combat present",needs="Invoque par un joueur; aucun God's Chalice consomme"},
    {name="Soul Reaper",sea=3,enemies={"Soul Reaper"},status="combat present",needs="Deja invoque; aucune Hallow Essence consommee"},
    {name="Cake Prince",sea=3,enemies={"Cake Prince"},status="combat present",needs="Portail ouvert et boss charge; aucune preparation automatique"},
    {name="Dough King",sea=3,enemies={"Dough King"},status="combat present",needs="Boss charge; aucun Sweet Chalice consomme"},
    {name="Tyrant of the Skies",sea=3,enemies={"Tyrant of the Skies"},status="combat present",needs="Liberation deja realisee; boss charge; combat normal seulement"},
    {name="Raids de fruits",sea=2,status="non pris en charge",needs="Puce, groupe, entree et vagues dedies"},
    {name="Raids de fruits",sea=3,status="non pris en charge",needs="Puce, groupe, entree et vagues dedies"},
    {name="Sea Beasts / Ship Raids",sea=2,status="non pris en charge",needs="Controle bateau et attaque maritime dedies"},
    {name="Sea Beasts / Ship Raids",sea=3,status="non pris en charge",needs="Controle bateau et attaque maritime dedies"},
    {name="Rumbling Waters / Terrorshark",sea=3,status="non pris en charge",needs="Navigation maritime, danger et combat specifiques"},
    {name="Mirage Island",sea=3,status="non pris en charge",needs="Exploration/puzzle, aucune cible de combat standard"},
    {name="Kitsune Island",sea=3,status="non pris en charge",needs="Navigation, conditions nocturnes, collecte et remise dediees"},
    {name="Prehistoric Island",sea=3,status="non pris en charge",needs="Groupe, activite et conditions specifiques"},
    {name="Frozen Dimension / Leviathan",sea=3,status="non pris en charge",needs="Groupe, Beast Hunter, navigation et segments de boss"},
    {name="Yama / Tushita / CDK",sea=3,status="non pris en charge",needs="Progression, puzzles, maitrise et prerequis dedies"},
}

-- Metadata is descriptive, not a claim of live validation or reward acquisition.
for _,activity in ipairs(ACTIVITIES) do
    activity.verifiedInGame=false
    activity.preconditions=activity.needs
    activity.availability=activity.enemies and "Cible vivante detectee dans la zone chargee" or "Detection dediee non implementee"
    activity.destination=activity.enemies and "Position reelle de la cible chargee" or "Non validee"
    activity.steps=activity.enemies and {"Verifier mer et presence", "Rejoindre cible", "Combat normal", "Relire presence/sante"} or {}
    activity.rewards={"A verifier dans l'inventaire serveur; aucune recompense garantie"}
    activity.consumes={}
    activity.group="Prerequis de groupe non controles par ce module de combat"
    activity.success="Fin du combat ne prouve pas un drop ni la reussite de toutes les etapes"
    activity.failure="Cible disparue, acces refuse ou progression non confirmee"
end
for _,item in ipairs(MATERIALS) do
    item.verifiedInGame=false;item.source="Ennemis du catalogue historique"
    item.preconditions="Mer et zone accessibles; equipement utilisable"
    item.acquisition="getInventory confirme la quantite cible"
end
local function newCharacterController(player,runService)
    local self={ghost=false,flying=false,closed=false}
    local current,parts,collision,visual=nil,{}, {},{}
    local flightLink,charLink,highlight,attachment,hover,autoRotate
    local function restore(values,key)
        for obj,value in pairs(values) do pcall(function() obj[key]=value end) end
        return {}
    end
    local function cosmetic(part)
        if self.ghost and not part:FindFirstAncestorOfClass("Tool") and part.Name~="HumanoidRootPart" then
            if visual[part]==nil then visual[part]=part.LocalTransparencyModifier end
            part.LocalTransparencyModifier=math.max(visual[part],0.6)
        end
    end
    local function add(obj)
        if obj:IsA("BasePart") then
            parts[obj]=true;cosmetic(obj)
            if self.flying then if collision[obj]==nil then collision[obj]=obj.CanCollide end;obj.CanCollide=false end
        end
    end
    function self:setFlying(value)
        if self.closed then return end
        self.flying=value
        if not value then
            if flightLink then flightLink:Disconnect();flightLink=nil end
            if hover then hover:Destroy();hover=nil end
            if attachment then attachment:Destroy();attachment=nil end
            collision=restore(collision,"CanCollide")
            local h=current and current:FindFirstChildOfClass("Humanoid")
            if h and autoRotate~=nil then h.AutoRotate=autoRotate end
            autoRotate=nil;return
        end
        if flightLink then return end
        local root=current and current:FindFirstChild("HumanoidRootPart")
        local h=current and current:FindFirstChildOfClass("Humanoid")
        assert(root and h and h.Health>0 and not root.Anchored,"Personnage indisponible/ancre")
        autoRotate=h.AutoRotate;h.AutoRotate=false
        attachment=Instance.new("Attachment");attachment.Name="PolarisFlightAttachment";attachment.Parent=root
        hover=Instance.new("LinearVelocity");hover.Name="PolarisFlightHover";hover.Attachment0=attachment
        hover.RelativeTo=Enum.ActuatorRelativeTo.World;hover.VectorVelocity=Vector3.zero
        hover.ForceLimitsEnabled=false;hover.Parent=root
        local function apply()
            for part in pairs(parts) do
                if part.Parent and part:IsDescendantOf(current) then
                    if collision[part]==nil then collision[part]=part.CanCollide end
                    part.CanCollide=false
                else
                    if collision[part]~=nil then pcall(function() part.CanCollide=collision[part] end) end
                    collision[part]=nil;parts[part]=nil
                end
            end
            if root.Parent then root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero end
        end
        apply();flightLink=runService.PreSimulation:Connect(apply)
    end
    function self:setGhost(value)
        self.ghost=value
        if highlight then highlight:Destroy();highlight=nil end
        if not value then visual=restore(visual,"LocalTransparencyModifier");return end
        for part in pairs(parts) do cosmetic(part) end
        if current then
            highlight=Instance.new("Highlight");highlight.Name="PolarisPhantom";highlight.Adornee=current
            highlight.FillColor=Color3.fromRGB(119,202,255);highlight.OutlineColor=Color3.fromRGB(216,243,255)
            highlight.FillTransparency=0.82;highlight.OutlineTransparency=0.35
            highlight.DepthMode=Enum.HighlightDepthMode.Occluded;highlight.Parent=current
        end
    end
    local function attach(c)
        self:setFlying(false);visual=restore(visual,"LocalTransparencyModifier")
        if charLink then charLink:Disconnect() end
        if highlight then highlight:Destroy();highlight=nil end
        current=c;parts={}
        if c then for _,obj in ipairs(c:GetDescendants()) do add(obj) end;charLink=c.DescendantAdded:Connect(add) end
        self:setGhost(self.ghost)
    end
    local added=player.CharacterAdded:Connect(attach)
    local removed=player.CharacterRemoving:Connect(function() attach(nil) end)
    attach(player.Character)
    function self:close()
        if self.closed then return end
        self:setFlying(false);self:setGhost(false)
        self.closed=true;if charLink then charLink:Disconnect() end;added:Disconnect();removed:Disconnect()
    end
    return self
end

local function newMovement(player,services,config,report,clock)
    clock=clock or os.clock
    local self={root=nil,goal=nil,raw=nil,tween=nil,blocked=nil,closed=false}
    local controller=services.characterController
    local deadline,lastProgress,best,lastPosition=0,0,0,nil
    local speedUsed=0
    local corrections=0
    local function character()
        local c=player.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and h.Health>0 and not r.Anchored then return c,h,r end
    end
    function self:free(cf)
        local c,_,r=character();if not c then return true end
        local bcf,size=c:GetBoundingBox()
        -- Bound the query, rather than silently shrinking a large avatar.
        if size.X>40 or size.Y>40 or size.Z>40 then return false end
        local volume=cf*r.CFrame:ToObjectSpace(bcf)
        local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={c};params.MaxParts=0;params.RespectCanCollide=true
        for _,part in ipairs(workspace:GetPartBoundsInBox(volume,size,params)) do if part.CanCollide then return false end end
        -- Conservative voxel check also rejects terrain occupancy; only on arrival/stop.
        local terrain=workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            local half=size/2
            local region=Region3.new(volume.Position-half,volume.Position+half):ExpandToGrid(4)
            local materials,occupancy=terrain:ReadVoxels(region,4)
            for x,plane in ipairs(occupancy) do for y,row in ipairs(plane) do for z,value in ipairs(row) do
                if value>0.25 and materials[x][y][z]~=Enum.Material.Water then return false end
            end end end
        end
        return true
    end
    function self:exit(cf)
        if self:free(cf) then return cf end
        local max=config.exitRadius or 10
        for radius=2,max,2 do
            for _,dir in ipairs({Vector3.new(0,1,0),Vector3.new(1,0,0),Vector3.new(-1,0,0),
                Vector3.new(0,0,1),Vector3.new(0,0,-1),Vector3.new(0,-1,0)}) do
                local candidate=cf+dir*radius
                if self:free(candidate) then return candidate end
            end
        end
    end
    local function cancel() if self.tween then self.tween:Cancel();self.tween=nil end end
    function self:handoff()
        cancel();self.goal=nil;self.raw=nil
        -- Keep ghost/hover while the next task selects its destination.
        return true
    end
    function self:stop(retry)
        if self.blocked and not retry then return false end
        cancel();self.goal=nil;self.raw=nil
        local _,h,r=character()
        if r and controller.flying then
            local safe=self:exit(r.CFrame)
            if not safe then
                self.blocked="Aucune sortie libre a moins de "..(config.exitRadius or 10).." studs. Vol suspendu; collisions non restaurees."
                report(self.blocked);return false
            end
            r.CFrame=safe
        end
        controller:setFlying(false)
        if r then r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero end
        if h then h:Move(Vector3.zero) end
        self.root=nil;self.blocked=nil;return true
    end
    function self:moveTo(cf,tolerance)
        assert(not self.closed,"Mouvement ferme")
        if self.blocked then error(self.blocked) end
        local _,h,r=character()
        if not r then self:stop();return false end
        if h.SeatPart and h.SeatPart:IsA("VehicleSeat") then
            if not self:stop() then error(self.blocked) end
            h.Sit=false;return false
        end
        local now=clock()
        local speed=math.clamp(tonumber(config.speed) or 220,80,320)
        if speed==speedUsed and self.root==r and self.raw and (self.raw.Position-cf.Position).Magnitude<4 then
            local remaining=(r.Position-self.goal.Position).Magnitude
            if remaining<=math.min(tolerance or 3,1.5) then
                if not self:stop() then error(self.blocked) end
                return true
            end
            if remaining<best-0.75 then best=remaining;lastProgress=now end
            if lastPosition and (r.Position-lastPosition).Magnitude>speed*0.6+8 and remaining>best+5 then corrections=corrections+1 end
            lastPosition=r.Position
            if corrections>=2 or now-lastProgress>5 or now>deadline then
                local reason=corrections>=2 and "Corrections serveur suspectees" or "Progression non confirmee (serveur/physique)"
                self:stop();error(reason.." : tache arretee, aucun forcage du trajet")
            end
            return false
        end
        self:handoff()
        local goal=self:exit(cf)
        if not goal then self:stop();error("Destination occupee, aucune sortie proche") end
        self.root,self.raw,self.goal=r,cf,goal
        local distance=(r.Position-goal.Position).Magnitude
        if distance<1.5 then return self:stop() end
        controller:setFlying(true)
        speedUsed=speed
        deadline=now+distance/speed+12;lastProgress=now;best=distance;lastPosition=r.Position;corrections=0
        self.tween=services.TweenService:Create(r,TweenInfo.new(math.max(0.15,distance/speed),Enum.EasingStyle.Linear),{CFrame=goal})
        self.tween:Play();return false
    end
    function self:close()
        if self.closed then return true end
        if not self:stop() then return false end
        self.closed=true;return true
    end
    return self
end

local STOCK = {"Katana","Cutlass","Dual Katana","Iron Mace","Triple Katana","Pipe",
    "Dual-Headed Blade","Soul Cane","Bisento","Musket","Slingshot","Flintlock",
    "Refined Slingshot","Refined Flintlock","Cannon","Black Cape","Swordsman Hat","Tomoe Ring"}
local FRUIT_IDS = {}
for _,name in ipairs({"Rocket","Spin","Chop","Spring","Bomb","Smoke","Spike","Flame",
    "Falcon","Ice","Sand","Dark","Ghost","Diamond","Light","Rubber","Barrier","Magma",
    "Quake","Buddha","Love","Spider","Sound","Phoenix","Portal","Rumble","Pain",
    "Blizzard","Gravity","Mammoth","T-Rex","Dough","Shadow","Venom","Control",
    "Spirit","Dragon","Leopard","Kitsune"}) do FRUIT_IDS[name.." Fruit"]=name.."-"..name end

local function chooseQuest(sea,level,bosses,alive)
    local regular,boss
    for _,q in ipairs(QUESTS) do
        if q.sea==sea and q.level<=level then
            if q.boss then
                if bosses and alive(q.name) and (not boss or q.level>boss.level) then boss=q end
            elseif not regular or q.level>regular.level then regular=q end
        end
    end
    -- Avoid abandoning a useful level quest for a much lower-level boss.
    if boss and (not regular or boss.level>=regular.level) then return boss end
    return regular
end

local function newTransport(remote,spawn,clock,report)
    local self={pending=nil,queue={},blocked=nil,nextAt=0,closed=false,count=0,paused=false}
    function self:has(id)
        if self.pending and self.pending.id==id then return true end
        for _,r in ipairs(self.queue) do if r.id==id then return true end end
        return false
    end
    function self:cancel(id)
        for i=#self.queue,1,-1 do if not id or self.queue[i].id==id then table.remove(self.queue,i) end end
    end
    function self:send(id,args,callback,guard)
        if self.closed or self.blocked or self:has(id) or #self.queue>=8 then return false end
        table.insert(self.queue,{id=id,args=args,callback=callback,guard=guard});return true
    end
    function self:poll()
        if self.closed then return end
        local r=self.pending
        if r and not r.done then
            if clock()-r.started>12 then self.blocked="Requete serveur >12 s; aucun nouvel appel" end
            return
        end
        if r then
            self.pending=nil;self.nextAt=clock()+1.25
            if self.afterResponse then self.afterResponse(r) end
            if r.callback then
                local ok,err=pcall(r.callback,r.ok,r.result)
                if not ok then report("Erreur de verification: "..tostring(err):sub(1,120)) end
            end
        end
        if self.blocked or self.paused or self.pending or clock()<self.nextAt then return end
        while #self.queue>0 do
            local request=table.remove(self.queue,1)
            if not request.guard or request.guard() then
                if self.beforeSend then self.beforeSend(request) end
                request.started=clock();self.pending=request;self.count=self.count+1
                request.worker=spawn(function()
                    request.ok,request.result=pcall(function() return remote:InvokeServer(table.unpack(request.args)) end)
                    request.done=true
                end)
                return
            end
        end
    end
    function self:close()
        if self.closed then return end
        self.closed=true;self.queue={}
        if self.pending and self.pending.worker and not self.pending.done and type(task)=="table" and type(task.cancel)=="function" then
            pcall(task.cancel,self.pending.worker)
        end
        self.pending=nil
    end
    return self
end

local function newAdapter(player,remote,services,config,report)
    local clock=os.clock
    local transport=newTransport(remote,task.spawn,clock,report)
    local adapter={transport=transport}
    local closed=false
    local raceStage,racePoll,raceDone=nil,0,false
    local lastAttack,questRetry,enemyScan=0,0,0
    local nextGacha,shopIndex,swordIndex=0,1,1
    local shopBlocked=false
    local storeTried,collectTried=setmetatable({},{__mode="k"}),setmetatable({},{__mode="k"})
    local ground=setmetatable({},{__mode="k"})
    local enemies,activeQuest,collectTarget,collectStart={},nil,nil,0
    local lastMessage,recovering="",false
    local sea=({[2753915549]=1,[4442272183]=2,[7449423635]=3})[game.PlaceId]
    local function say(message)
        if message~=lastMessage then lastMessage=message;report(message) end
    end
    local movement=newMovement(player,services,config,report,clock)
    local function character()
        local c=player.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if h and r and h.Health>0 then return c,h,r end
    end
    local function stopMovement() return movement:stop() end
    local function moveTo(cf,tolerance) return movement:moveTo(cf,tolerance) end
    local function isGround(tool)
        return tool:IsA("Tool") and tool.Name:find("Fruit",1,true) and tool:IsDescendantOf(workspace)
            and not (player.Character and tool:IsDescendantOf(player.Character))
            and tool:FindFirstChild("Handle") and not tool:FindFirstAncestorOfClass("Model")
    end
    local function register(obj)
        if obj:IsA("Tool") and obj.Name:find("Fruit",1,true) then ground[obj]=true end
    end
    local groundConnection=workspace.DescendantAdded:Connect(register)
    task.spawn(function()
        for i,obj in ipairs(workspace:GetDescendants()) do
            if closed then return end
            register(obj)
            if i%150==0 then task.wait() end
        end
    end)
    local function nearestFruit(now)
        local _,_,root=character()
        if not root then return end
        local best,distance=nil,math.huge
        for tool in pairs(ground) do
            if not tool.Parent then ground[tool]=nil
            elseif isGround(tool) and now>=(collectTried[tool] or 0) then
                local d=(root.Position-tool.Handle.Position).Magnitude
                if d<distance and d<=config.fruitRange then best,distance=tool,d end
            end
        end
        return best
    end
    local function carriedFruit(now)
        local backpack=player:FindFirstChild("Backpack")
        for _,bag in pairs({backpack,player.Character}) do
            for _,tool in ipairs(bag:GetChildren()) do
                if tool:IsA("Tool") and FRUIT_IDS[tool.Name] and now>=(storeTried[tool] or 0) then
                    return tool,FRUIT_IDS[tool.Name]
                end
            end
        end
    end
    local function refreshEnemies(now)
        if now<enemyScan then return end
        enemyScan=now+1;enemies={}
        local folder=workspace:FindFirstChild("Enemies")
        if not folder then return end
        for _,model in ipairs(folder:GetChildren()) do
            local h=model:FindFirstChildOfClass("Humanoid")
            local root=model:FindFirstChild("HumanoidRootPart")
            if h and root and h.Health>0 then
                local name=model.Name:gsub("%s*%[.*%]","")
                for old,new in pairs(ALIASES) do if name==new then name=old;break end end
                enemies[name]=enemies[name] or {};table.insert(enemies[name],model)
            end
        end
    end
    local function questUI()
        local gui=player:FindFirstChild("PlayerGui")
        local main=gui and gui:FindFirstChild("Main")
        return main and main:FindFirstChild("Quest")
    end
    local function questMatches(ui,name)
        for _,obj in ipairs(ui:GetDescendants()) do
            if obj:IsA("TextLabel") and (obj.Text:lower():find(name:lower(),1,true) or (ALIASES[name] and obj.Text:lower():find(ALIASES[name]:lower(),1,true))) then return true end
        end
        return false
    end
    local function weapon(c,h)
        local backpack=player:FindFirstChild("Backpack")
        for _,bag in pairs({c,backpack}) do
            for _,tool in ipairs(bag:GetChildren()) do
                if tool:IsA("Tool") and not tool.Name:find("Fruit",1,true) then
                    local tip=tool.ToolTip
                    if (not config.exactWeapon or tool.Name==config.exactWeapon) and ((config.weapon=="Melee" and tip=="Melee") or (config.weapon=="Sword" and tip=="Sword")) then
                        if tool.Parent~=c then h:EquipTool(tool) end
                        return tool
                    end
                end
            end
        end
    end
    local function fightNamed(name,spawn,now)
        local c,h,root=character()
        if not c then stopMovement();return false end
        if h.Health/h.MaxHealth<0.25 then recovering=true end
        if recovering then
            stopMovement();say("Pause sante: reprise a 65 %")
            if h.Health/h.MaxHealth>=0.65 then recovering=false end
            return false
        end
        refreshEnemies(now)
        local target,distance=nil,math.huge
        for _,model in ipairs(enemies[name] or {}) do
            local er=model:FindFirstChild("HumanoidRootPart")
            local eh=model:FindFirstChildOfClass("Humanoid")
            if er and eh and eh.Health>0 then
                local d=(root.Position-er.Position).Magnitude
                if d<distance then target,distance=model,d end
            end
        end
        if not target then say("Attente de "..name);if spawn then moveTo(spawn,8) end;return false end
        local er=target.HumanoidRootPart
        -- Finish the shared ghost journey before switching to combat, even inside
        -- melee range. Distance alone must never restore collisions inside a wall.
        if movement.goal or distance>7 then
            if not moveTo(er.CFrame*CFrame.new(0,1,4),3) then return false end
            distance=(root.Position-er.Position).Magnitude
            if distance>7 then say("Position libre hors portee; attente de la cible");return false end
        end
        if not stopMovement() then error(movement.blocked) end
        local tool=weapon(c,h)
        if not tool then say("Aucune arme "..config.weapon.." disponible");return false end
        root.CFrame=CFrame.lookAt(root.Position,Vector3.new(er.Position.X,root.Position.Y,er.Position.Z))
        if now-lastAttack>=0.55 then tool:Activate();lastAttack=now end
        say("Combat: "..name.." / "..tool.Name)
        return false
    end
    local function hasItem(name)
        for _,bag in pairs({player:FindFirstChild("Backpack"),player.Character}) do
            local item=bag:FindFirstChild(name)
            if item then return item end
        end
    end
    local function raceV2(now)
        local data=player:FindFirstChild("Data")
        local race=data and data:FindFirstChild("Race")
        local level=data and data:FindFirstChild("Level")
        if sea~=2 then error("Race V2 : aller en mer 2") end
        if not race or not level or level.Value<850 then error("Race V2 : niveau 850 requis") end
        if tostring(race.Value)=="Draco" then error("Draco : quete differente non implementee") end
        if race:FindFirstChild("Evolved") then raceDone=true;say("V2 deja debloquee");return true end
        if now>=racePoll then
            if transport:send("race2",{"Alchemist","1"},function(ok,result)
                raceStage=ok and tonumber(result) or nil
                if raceStage~=0 and raceStage~=1 and raceStage~=2 then
                    say("Alchemist: "..tostring(result).." / verifier les prerequis")
                end
            end) then racePoll=now+8 end
            return true
        end
        local pos=CFrame.new(-2777,73,-3570)
        if raceStage==0 or raceStage==2 then
            if moveTo(pos,4) then
                transport:send("race2",{"Alchemist",raceStage==0 and "2" or "3"},function(ok,result)
                    racePoll=clock()+2;say("Alchemist: "..tostring(result):sub(1,100))
                end)
                return true
            end
            return false
        end
        if raceStage~=1 then return true end
        if hasItem("Flower 1") and hasItem("Flower 2") and hasItem("Flower 3") then racePoll=0;return true end
        for index=1,2 do
            local flower=workspace:FindFirstChild("Flower"..index)
            if not hasItem("Flower "..index) and flower and flower:IsA("BasePart") and flower.Transparency<1 then
                say("V2: collecte Flower "..index)
                if moveTo(flower.CFrame,3) then
                    local _,_,root=character()
                    if root and type(firetouchinterest)=="function" then
                        pcall(function() firetouchinterest(root,flower,0);firetouchinterest(root,flower,1) end)
                    end
                    return true
                end
                return false
            end
        end
        if not hasItem("Flower 3") then return fightNamed("Swan Pirate",CFrame.new(778,73,1129),now) end
        stopMovement();say("V2: attente des fleurs jour/nuit");return true
    end
    function adapter.inspectV3()
        return transport:send("manual",{"Wenlocktoad","info"},function(ok,result)
            say("Etat V3 (reponse historique): "..tostring(result):sub(1,160))
        end)
    end
    function adapter.goToNpc(names)
        local folder=workspace:FindFirstChild("NPCs")
        for _,npc in ipairs(folder and folder:GetChildren() or {}) do
            for _,name in ipairs(names) do
                if npc.Name:lower()==name:lower() then
                    local root=npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
                    if root then config.destination=root.CFrame*CFrame.new(0,0,3);return true end
                end
            end
        end
        say("PNJ non charge dans cette zone");return false
    end
    local function farm(now)
        local c,h,root=character()
        if not c then stopMovement();activeQuest=nil;say("Attente du personnage / respawn");return false end
        if h.Health/h.MaxHealth<0.25 then recovering=true end
        if recovering then
            stopMovement();say("Pause sante: reprise a 65 %")
            if h.Health/h.MaxHealth>=0.65 then recovering=false end
            return false
        end
        if not sea then error("Carte non prise en charge pour les quetes") end
        local data=player:FindFirstChild("Data")
        local level=data and data:FindFirstChild("Level")
        if not level then error("Data.Level absent") end
        local ui=questUI()
        if not ui then error("Interface Main.Quest absente") end
        refreshEnemies(now)
        if not ui.Visible then
            if now<questRetry then return false end
            activeQuest=chooseQuest(sea,level.Value,config.bosses,function(name) return enemies[name]~=nil end)
            if not activeQuest then error("Aucune quete connue pour ce niveau") end
            -- Historical catalog ends at 2525; no claim to support newer zones.
            if sea==3 and level.Value>=2550 then error("Catalogue ancien limite aux niveaux <2550") end
            if level.Value<10 and tostring(player.Team)=="Marines" then
                activeQuest={name="Trainee",quest="MarineQuest",index=1,pos=CFrame.new(-2708,25,2103),spawn=CFrame.new(-2754,25,2063)}
            end
            say("Quete: "..activeQuest.name)
            if moveTo(activeQuest.pos,4) then
                local q=activeQuest
                transport:send("farm",{"StartQuest",q.quest,q.index},function(ok,result)
                    questRetry=clock()+5
                    if not ok then say("Quete refusee: "..tostring(result):sub(1,80)) end
                end)
            end
            return false
        end
        if not activeQuest or not questMatches(ui,activeQuest.name) then
            stopMovement();say("Termine ou annule ta quete actuelle, puis relance le farm.");return false
        end
        local target,distance=nil,math.huge
        for _,model in ipairs(enemies[activeQuest.name] or {}) do
            local er=model:FindFirstChild("HumanoidRootPart")
            local eh=model:FindFirstChildOfClass("Humanoid")
            if er and eh and eh.Health>0 then
                local d=(root.Position-er.Position).Magnitude
                if d<distance then target,distance=model,d end
            end
        end
        if not target then
            say("Attente de "..activeQuest.name);moveTo(activeQuest.spawn,8);return false
        end
        local er=target.HumanoidRootPart
        -- Finish the shared ghost journey before switching to combat, even inside
        -- melee range. Distance alone must never restore collisions inside a wall.
        if movement.goal or distance>7 then
            if not moveTo(er.CFrame*CFrame.new(0,1,4),3) then return false end
            distance=(root.Position-er.Position).Magnitude
            if distance>7 then say("Position libre hors portee; attente de la cible");return false end
        end
        if not stopMovement() then error(movement.blocked) end
        local tool=weapon(c,h)
        if not tool then say("Aucune arme "..config.weapon.." equipee/disponible");return false end
        root.CFrame=CFrame.lookAt(root.Position,Vector3.new(er.Position.X,root.Position.Y,er.Position.Z))
        if now-lastAttack>=0.55 then tool:Activate();lastAttack=now end
        say("Combat normal: "..activeQuest.name.." / "..tool.Name)
        return false
    end
    function adapter.ready(id,now)
        transport:poll()
        if closed or transport.blocked then return false end
        if id=="farm" then return true end
        if id=="race2" then return not raceDone end
        if id=="swordfarm" then return config.swordTarget~=nil end
        if id=="navigate" then return config.destination~=nil end
        if id=="collect" then return collectTarget~=nil or nearestFruit(now)~=nil end
        if now<transport.nextAt then return false end
        if id=="fruit" then return carriedFruit(now)~=nil end
        if id=="gacha" then return now>=nextGacha end
        if id=="shop" then return not shopBlocked and shopIndex<=#STOCK end
        if id=="sword" then return sea==2 end
        return false
    end
    function adapter.step(id,now)
        transport:poll()
        if id=="farm" then return farm(now) end
        if id=="race2" then return raceV2(now) end
        if id=="navigate" then
            if moveTo(config.destination,4) then config.destination=nil;return true end
            return false
        end
        if id=="swordfarm" then
            local target=config.swordTarget
            if target=="Rengoku" then
                local key=hasItem("Hidden Key")
                if key then
                    local c,h=character()
                    if h then h:EquipTool(key) end
                    say("Rengoku: approche du coffre avec Hidden Key")
                    if moveTo(CFrame.new(6571,299,-6968),3) then config.swordTarget=nil;return true end
                    return false
                end
                return fightNamed("Snow Lurker",CFrame.new(5700,28,-6724),now)
            end
            local q
            for _,entry in ipairs(QUESTS) do if entry.boss and entry.name==target and entry.sea==sea then q=entry end end
            if not q then error("Cible d'epee non disponible dans cette mer") end
            local data=player:FindFirstChild("Data")
            local level=data and data:FindFirstChild("Level")
            if not level or level.Value<q.level then error("Niveau insuffisant pour cette cible") end
            return fightNamed(q.name,q.spawn,now)
        end
        if id=="collect" then
            if not collectTarget then collectTarget=nearestFruit(now);collectStart=now end
            local fruit=collectTarget
            if not fruit or not isGround(fruit) then collectTarget=nil;stopMovement();return true end
            if now-collectStart>20 then
                collectTried[fruit]=now+90;collectTarget=nil;stopMovement()
                say("Collecte expiree; reprise du farm");return true
            end
            say("Recherche fruit: "..fruit.Name)
            if moveTo(fruit.Handle.CFrame,3) then
                local _,h,root=character()
                if root and type(firetouchinterest)=="function" then
                    pcall(function() firetouchinterest(root,fruit.Handle,0);firetouchinterest(root,fruit.Handle,1) end)
                elseif h then h:MoveTo(fruit.Handle.Position) end
                collectTried[fruit]=now+90;collectTarget=nil;return true
            end
            return false
        end
        if id=="fruit" then
            local tool,name=carriedFruit(now)
            if not tool then return true end
            storeTried[tool]=now+30
            transport:send(id,{"StoreFruit",name,tool},function(ok,result)
                say("Stockage "..tool.Name..": "..tostring(result):sub(1,100))
            end)
        elseif id=="gacha" then
            if transport:send(id,{"Cousin","Buy"},function(ok,result)
                say("Gacha: "..tostring(result):sub(1,100))
            end) then nextGacha=now+7200 end
        elseif id=="sword" then
            local index=swordIndex
            if transport:send(id,{"LegendarySwordDealer",tostring(index)},function(ok,result)
                say("Marchand legendaire "..index..": "..tostring(result):sub(1,100))
            end) then swordIndex=index%3+1 end
        elseif id=="shop" then
            local item=STOCK[shopIndex]
            transport:send(id,{"BuyItem",item},function(ok,result)
                say("Boutique "..item..": "..tostring(result):sub(1,100))
                if ok and result==true then shopIndex=shopIndex+1 else shopBlocked=true end
            end)
        end
        return true
    end
    function adapter.suspend(id)
        if id=="farm" or id=="collect" or id=="race2" or id=="swordfarm" or id=="navigate" then stopMovement() end
    end
    function adapter.resetShop() shopBlocked=false;shopIndex=1 end
    function adapter.diagnostics()
        return {sea=sea or "?",quest=activeQuest and activeQuest.name or "--",
            gachaWait=math.max(0,math.ceil(nextGacha-clock())),shop=STOCK[shopIndex] or "Termine",
            shopBlocked=shopBlocked,requests=transport.count,blocked=transport.blocked,
            pending=transport.pending~=nil,action=lastMessage}
    end
    function adapter.close()
        closed=true;stopMovement();transport:close();groundConnection:Disconnect()
    end
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
    function adapter.close()
        if closed then return true end
        if not movement:close() then return false end
        closed=true;transport:close();groundConnection:Disconnect();return true
    end
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
        local item=interactions[id] or {attempts=0,at=-math.huge};interactions[id]=item
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
    local legendaryPending,legendarySpent,legendaryAt=nil,0,0
    local legendaryBlocked=false
    local function legendary(now)
        requestInventory(now)
        if legendaryPending then
            local s=legendaryPending;local n=count(s.name)
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
            local n=count(name);if n==nil then state("sword","en attente","Inventaire serveur requis");return true end
            if n==0 then wanted[name]=true;missing=true end
        end
        if not missing then state("sword","terminee","Toutes les epees selectionnees sont possedees");return true end
        if now<legendaryAt then return true end
        local dialog=findDialog(now,{"legendary sword dealer","saddi","shisui","wando"})
        if not dialog then return interactNpc("Legendary Sword Dealer","sword",now) end
        local offered
        for name in pairs(wanted) do if dialog.text:lower():find(name:lower(),1,true) then offered=name;break end end
        local buy=actionButton(dialog,{"buy","purchase","acheter"})
        if not offered or not buy then state("sword","en attente","Dialogue sans offre selectionnee ou achat explicite");legendaryAt=now+10;return true end
        local context=dialog.text.." "..buy.Text
        if context:lower():find("robux",1,true) or context:find("R$",1,true) or context:find(utf8.char(0xE002),1,true) then error("Robux dans le dialogue : aucun achat automatique") end
        local price=beliPrice(buy.Text) or beliPrice(dialog.text)
        if not price then error("Prix Beli absent/ambigu ou Robux; achat bloque") end
        if price>config.legendaryMaxPrice or legendarySpent+price>config.legendaryBudget or wallet()-price<config.reserve then
            state("sword","en attente","Budget legendaire / prix maximal / reserve insuffisants");return true
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
            if count("Saddi")==nil then state(id,"en attente","Inventaire serveur requis");return false end
            local missing=false
            for rawName in (config.legendaryTargets or "Saddi,Shisui,Wando"):gmatch("[^,]+") do
                local name=rawName:match("^%s*(.-)%s*$");if count(name)==0 then missing=true end
            end
            if not missing then return true end
            if config.legendaryBudget<=0 then state(id,"en attente","Configurer le budget legendaire pour autoriser un achat");return false end
            if findDialog(now,{"legendary sword dealer","saddi","shisui","wando"}) then return true end
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
    function adapter.close() releaseInput();boatStop();return advancedClose() end
    local advancedDiagnostics=adapter.diagnostics
    function adapter.diagnostics()
        local d=advancedDiagnostics();d.legendarySpent=legendarySpent;d.race3=v3.stage;d.boat=boatSeat and boatSeat.Name or "--";return d
    end
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
    function adapter.close() restoreMirageRoute();return baseClose() end
    function adapter.raceOverview(now)
        requestInventory(now)
        local data=player:FindFirstChild("Data");local race=data and data:FindFirstChild("Race")
        return {race=race and race.Value or "?",v2=race and race:FindFirstChild("Evolved")~=nil or false,
            v3Confirmed=statuses.race3 and statuses.race3.state=="terminee" or false,
            mirrorFractal=count("Mirror Fractal"),mirageLoaded=mirageObject()~=nil,
            v4="Trials, resonance, levier et horloge non implementes"}
    end

    return adapter
end
if POLARIS_TEST then return {newEngine=newEngine,newTransport=newTransport,chooseQuest=chooseQuest,quests=QUESTS,newAdapter=newAdapter,newCharacterController=newCharacterController,newMovement=newMovement,activities=ACTIVITIES} end

local services={Players=game:GetService("Players"),TweenService=game:GetService("TweenService"),
    Input=game:GetService("UserInputService"),Lighting=game:GetService("Lighting"),Run=game:GetService("RunService")}
local player=services.Players.LocalPlayer
assert(player,"Polaris doit etre execute cote client")
local playerGui=player:WaitForChild("PlayerGui")
local old=playerGui:FindFirstChild("PolarisMobileDemo")
if old then local event=old:FindFirstChild("Cleanup");if event then event:Fire() end;assert(not old:GetAttribute("PolarisBlocked"),"Ancien trajet bloque : liberer une sortie avant de remplacer Polaris");old:Destroy() end
local config={bosses=true,weapon="Melee",speed=220,fruitRange=5000,phaseFlight=true,exitRadius=10,
 reserve=100000,gachaBudget=0,gachaMaxPrice=500000,shopBudget=0,shopMaxPrice=1200000,excludeFruits="",
 masteryTool="",masteryGoal=300,masteryThreshold=0.25,itemQuantity=10,replaceQuest=false,
 legendaryTargets="Saddi,Shisui,Wando",legendaryBudget=0,legendaryMaxPrice=2000000,
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
local panel=make("Frame",gui,{Name="PolarisPanel",Size=UDim2.new(0.92,0,0.90,0),Position=UDim2.fromScale(0.5,0.5),
    AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=colors.bg,BorderSizePixel=0})
corner(panel,18);stroke(panel)
services.polarisGui=gui
make("UISizeConstraint",panel,{MaxSize=Vector2.new(980,740)})
local banner=make("Frame",panel,{Size=UDim2.new(1,0,0,64),BackgroundColor3=colors.card,BorderSizePixel=0})
corner(banner,18)
make("Frame",banner,{Size=UDim2.new(1,-24,0,1),Position=UDim2.new(0,12,1,-1),BackgroundColor3=colors.accent,BorderSizePixel=0})
local title=label(banner,"POLARIS",UDim2.new(1,-120,0,30),UDim2.new(0,18,0,7))
title.TextSize=23;title.Font=Enum.Font.GothamBold
local subtitle=label(banner,"v0.9  /  MOBILE + PC  /  EXPERIMENTAL",UDim2.new(1,-120,0,20),UDim2.new(0,18,0,37))
subtitle.TextSize=11
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
local footer=make("Frame",panel,{Name="PolarisActions",Size=UDim2.new(1,-24,0,46),Position=UDim2.new(0,12,1,-55),BackgroundTransparency=1})
local run=button(footer,"DEMARRER",UDim2.new(0.32,0,1,0));run.BackgroundColor3=colors.accent
local pause=button(footer,"PAUSE",UDim2.new(0.32,0,1,0),UDim2.fromScale(0.34,0))
local stop=button(footer,"TOUT ARRETER",UDim2.new(0.32,0,1,0),UDim2.fromScale(0.68,0))
local orders={}
local pageTitle=label(panel,"Accueil",UDim2.new(1,-30,0,30),UDim2.new(0,15,0,120))
pageTitle.Font=Enum.Font.GothamBold;pageTitle.TextSize=24
local function showPage(name)
    pageTitle.Text=name
    for key,page in pairs(pages) do page.Visible=key==name end
    for key,b in pairs(tabButtons) do
        b.BackgroundColor3=key==name and Color3.fromRGB(37,18,25) or colors.bg
        b.TextColor3=key==name and colors.text or colors.muted
        local line=b:FindFirstChild("SelectionLine");if line then line.Visible=key==name end
    end
end
for index,name in ipairs({"Accueil","Farm","Fruits","Epees","Races","Boutique","Maitrise","Objets","Boss","Evenements","Reglages","Navigation","Invocations","Puzzles","Mer","Mirage","V4","Performance","Journal"}) do
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
        nav.Position=UDim2.fromOffset(12,82);nav.Size=UDim2.new(0,172,1,-150)
        nav.ScrollingDirection=Enum.ScrollingDirection.Y;nav.AutomaticCanvasSize=Enum.AutomaticSize.Y
        navLayout.FillDirection=Enum.FillDirection.Vertical
        pageTitle.Position=UDim2.fromOffset(204,82);pageTitle.Size=UDim2.new(1,-220,0,32)
        status.Position=UDim2.fromOffset(204,119);status.Size=UDim2.new(1,-220,0,26)
        area.Position=UDim2.fromOffset(204,153);area.Size=UDim2.new(1,-220,1,-216)
        footer.Position=UDim2.new(0,204,1,-55);footer.Size=UDim2.new(1,-220,0,44)
    else
        nav.Position=UDim2.fromOffset(12,74);nav.Size=UDim2.new(1,-24,0,42)
        nav.ScrollingDirection=Enum.ScrollingDirection.X;nav.AutomaticCanvasSize=Enum.AutomaticSize.X
        navLayout.FillDirection=Enum.FillDirection.Horizontal
        pageTitle.Position=UDim2.fromOffset(15,123);pageTitle.Size=UDim2.new(1,-30,0,30)
        status.Position=UDim2.fromOffset(15,157);status.Size=UDim2.new(1,-30,0,25)
        area.Position=UDim2.fromOffset(12,188);area.Size=UDim2.new(1,-24,1,-250)
        footer.Position=UDim2.new(0,12,1,-55);footer.Size=UDim2.new(1,-24,0,44)
    end
    for _,b in pairs(tabButtons) do b.Size=wide and UDim2.fromOffset(168,36) or UDim2.fromOffset(112,36) end
end
bind(panel:GetPropertyChangedSignal("AbsoluteSize"),responsiveLayout)
responsiveLayout();showPage("Accueil")
local function row(page,textValue,isButton,height)
    orders[page]=orders[page]+1
    local obj
    if isButton then obj=button(pages[page],textValue,UDim2.new(1,-2,0,height or 64))
    else
        obj=label(pages[page],textValue,UDim2.new(1,-2,0,0))
        obj.AutomaticSize=Enum.AutomaticSize.Y
        obj.TextColor3=colors.muted
        make("UIPadding",obj,{PaddingTop=UDim.new(0,8),PaddingBottom=UDim.new(0,8),PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6)})
    end
    obj.LayoutOrder=orders[page];return obj
end
local welcome=row("Accueil","Active une option puis DEMARRER. Les achats utilisent ton argent du jeu. Compatibilite des appels et du combat a tester dans Delta.",false)
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
local remotes=game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
local remote=remotes and remotes:FindFirstChild("CommF_")
local supported=game.GameId==994732206 and remote and remote:IsA("RemoteFunction")
if supported then
    adapter=newAdapter(player,remote,services,config,report)
    engine=newEngine(adapter,os.clock,function(message) status.Text=message end)
    engine.prefix="POLARIS : "
    for _,entry in ipairs({{"fruit","Stocker les fruits portes",100,2,true},{"collect","Chercher les fruits au sol",90,2},
        {"sword","Auto achat legendaire via dialogue",70,2},{"gacha","Random fruit / Gacha",60,2,true},
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
    status.Text="Pret / en pause"
else
    status.Text="Blox Fruits / CommF_ non detecte"
    report("Les actions sont desactivees hors de Blox Fruits. Le menu et le mode graphique restent disponibles.")
end
local function toggle(page,id,labelValue)
    local b=row(page,labelValue.."  [OFF]",true,76);toggleButtons[id]=b
    b.TextXAlignment=Enum.TextXAlignment.Left;b.TextSize=12
    make("UIPadding",b,{PaddingLeft=UDim.new(0,14),PaddingRight=UDim.new(0,76)})
    local track=make("Frame",b,{Name="ToggleTrack_"..id,Size=UDim2.fromOffset(44,24),Position=UDim2.new(1,-60,0.5,-12),BackgroundColor3=Color3.fromRGB(37,38,46),BorderSizePixel=0});corner(track,12);stroke(track)
    local thumb=make("Frame",track,{Size=UDim2.fromOffset(18,18),Position=UDim2.fromOffset(3,3),BackgroundColor3=colors.muted,BorderSizePixel=0});corner(thumb,9)
    toggleWidgets[id]={track=track,thumb=thumb}
    b.Active=supported==true;b.AutoButtonColor=supported==true
    bind(b.Activated,function()
        if not engine then return end
        engine:enable(id,not engine.tasks[id].enabled)
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
bind(retry.Activated,function() if adapter then adapter.resetShop();report("Liste remise au debut. Activer la boutique puis Demarrer.") end end)
row("Boutique","Marchand legendaire : dialogue visible uniquement, nom selectionne et prix Beli explicite requis. Inventaire avant/apres, budget et reserve. Compatibilite du dialogue a verifier en jeu.",false)
row("Epees","ACHATS ET DROPS : les boutons lancent une tentative ou un farm cible. Une epee de drop n'est jamais garantie en un clic.",false)
local legendary=row("Epees","Activer achat auto : Saddi / Shisui / Wando",true)
bind(legendary.Activated,function()
    if engine then engine:enable("sword",not engine.tasks.sword.enabled);report("Option marchand legendaire modifiee. Appuyer sur Demarrer.") end
end)
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
        engine:enable("swordfarm",true)
        report("Cible : "..target..". Appuyer sur Demarrer. Acces et prerequis a debloquer avant.")
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
    if adapter and adapter.goToNpc({"Arowe","arowe","Wenlocktoad"}) then engine:enable("navigate",true);engine:start() end
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
bind(run.Activated,function() if engine then engine:start() end end)
bind(pause.Activated,function() if engine then engine:pause() end end)
bind(stop.Activated,function()
    if engine then engine:pause();for _,entry in ipairs(engine.sequence) do engine:enable(entry.id,false) end end
    report("Options arretees. Une requete deja envoyee peut encore terminer.")
end)
local function dispose()
    if closed then return end
    if engine and engine:close()==false then gui:SetAttribute("PolarisBlocked",true);report("Fermeture suspendue : aucune sortie libre proche. Garder le menu pour recuperer.");return false end
    if adapter and adapter.close()==false then gui:SetAttribute("PolarisBlocked",true);return false end
    gui:SetAttribute("PolarisBlocked",false)
    services.characterController:close()
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
    row(page,titleValue,false)
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
    config[key]=engine and engine.tasks[id].priority or 10
    textSetting("Reglages",key,"Priorite "..id,config[key],0,150)
end
local recover=row("Reglages","Retenter une sortie libre (une tentative bornee)",true)
bind(recover.Activated,function() if adapter then local ok=adapter.recover(true);gui:SetAttribute("PolarisBlocked",not ok);report(ok and "Sortie libre confirmee" or "Aucune sortie libre proche ; deplacement suspendu") end end)
local resetStore=row("Fruits","Reessayer les fruits refuses au stockage",true)
bind(resetStore.Activated,function() if adapter then adapter.resetStore();report("Refus remis a zero par l'utilisateur") end end)


textSetting("Boutique","legendaryTargets","Epees souhaitees (Saddi,Shisui,Wando)",config.legendaryTargets,nil)
textSetting("Boutique","legendaryBudget","Budget legendaire session (0 bloque)",0,0,1000000000)
textSetting("Boutique","legendaryMaxPrice","Prix maximal Beli par epee",2000000,1,100000000)
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
        local textValue=entry.label..(entry.enabled and "  [ON]" or "  [OFF]").."\n"..(entry.enabled and (detail.state or entry.state or "en attente") or entry.state or "desactivee").." : "..(entry.enabled and (detail.reason or "") or "")
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
report("Polaris v0.9 charge. Toutes les actions sont OFF.")
refresh()
task.spawn(function()
    local lastRefresh=0
    while not closed do
        local ok,err=pcall(function()
            if adapter then adapter.transport:poll();adapter.maintenance(os.clock(),engine and engine.running) end
            if engine then for _,id in ipairs({"collect","event","boss","quest","farm","mastery","item"}) do engine.tasks[id].priority=config["priority_"..id] end;engine:tick() end
            if os.clock()-lastRefresh>=1 then lastRefresh=os.clock();refresh() end
        end)
        if not ok then if engine then engine:pause() end;report("Arret: "..tostring(err):sub(1,160)) end
        task.wait(0.2)
    end
end)

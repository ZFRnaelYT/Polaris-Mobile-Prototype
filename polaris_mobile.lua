-- Polaris v0.5 | Experimental Blox Fruits client. No external UI dependencies.
-- Historical quest/API data: BLOXFRUIT-SCRIPT/REDZ-HUB-V2 (compatibility unverified).
-- Test the features individually before combining them. No zero-lag guarantee.
local function newEngine(adapter, clock, publish)
    local self = {running = false, closed = false, active = nil, tasks = {}, prefix = "DEMO: ",
        sequence = {}, lastStatus = nil, steps = 0}
    local function status(message)
        if self.lastStatus ~= message then
            self.lastStatus = message
            publish(message)
        end
    end
    local function invoke(name, ...)
        local fn = adapter[name]
        if type(fn) ~= "function" then
            return false, "Adaptateur incomplet: " .. name
        end
        return pcall(fn, ...)
    end
    function self:add(id, label, priority, interval)
        assert(not self.tasks[id], "Identifiant deja utilise")
        self.tasks[id] = {id = id, label = label, priority = priority,
            interval = interval, enabled = false, nextAt = 0, failures = 0}
        table.insert(self.sequence, self.tasks[id])
    end
    function self:release()
        if not self.active then return true end
        local previous = self.active
        self.active = nil
        local ok, reason = invoke("suspend", previous.id)
        if not ok then
            self.running = false
            status("Arret: impossible de suspendre " .. previous.label .. ": " .. tostring(reason))
        end
        return ok
    end
    function self:enable(id, enabled)
        assert(self.tasks[id], "Tache inconnue")
        self.tasks[id].enabled = enabled
        if not enabled and self.active == self.tasks[id] then self:release() end
    end
    function self:start()
        if not self.closed then self.running = true; status(self.prefix .. "demarre") end
    end
    function self:pause()
        self.running = false
        if self:release() then status("Pause") end
    end
    function self:close()
        self:pause()
        self.closed = true
    end
    function self:fail(entry, reason, now)
        entry.failures = entry.failures + 1
        entry.nextAt = now + math.min(30, 2 ^ entry.failures)
        if entry.failures >= 3 then entry.enabled = false end
        self:release()
        status("Erreur " .. entry.label .. ": " .. tostring(reason))
    end
    function self:tick()
        if not self.running or self.closed then return end
        local now, selected = clock(), nil
        for _, entry in ipairs(self.sequence) do
            if entry.enabled and now >= entry.nextAt then
                local ok, ready = invoke("ready", entry.id, now)
                if not ok then self:fail(entry, ready, now)
                elseif ready and (not selected or entry.priority > selected.priority) then
                    selected = entry
                end
            end
        end
        -- An error while scanning may stop the engine (failed cancellation).
        if not self.running then return end
        if self.active ~= selected then
            if not self:release() then return end
            self.active = selected
        end
        if not selected then status(self.prefix .. "attente / aucune tache disponible"); return end
        local ok, done = invoke("step", selected.id, now, 1)
        self.steps = self.steps + 1
        if not ok then self:fail(selected, done, now); return end
        status(self.prefix .. selected.label)
        if done then
            selected.failures = 0
            selected.nextAt = now + selected.interval
            self:release()
        end
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
    local self={pending=nil,blocked=nil,nextAt=0,closed=false,count=0}
    function self:poll()
        local r=self.pending
        if not r then return end
        if not r.done then
            if clock()-r.started>12 then self.blocked="Requete serveur bloquee (>12 s). Fermer puis relancer." end
            return
        end
        self.pending=nil
        self.nextAt=math.max(self.nextAt,clock()+1)
        if not self.closed and r.callback then r.callback(r.ok,r.result) end
        if not r.ok and not self.closed then report("Erreur serveur: "..tostring(r.result):sub(1,100)) end
    end
    function self:send(id,args,callback)
        if self.closed or self.blocked or self.pending or clock()<self.nextAt then return false end
        local r={id=id,started=clock(),callback=callback,done=false}
        self.pending=r; self.count=self.count+1; self.nextAt=clock()+1
        spawn(function()
            r.ok,r.result=pcall(function() return remote:InvokeServer(table.unpack(args)) end)
            r.done=true
        end)
        return true
    end
    function self:close() self.closed=true end
    return self
end

local function newAdapter(player,remote,services,config,report)
    local clock=os.clock
    local transport=newTransport(remote,task.spawn,clock,report)
    local adapter={transport=transport}
    local closed=false
    local raceStage,racePoll,raceDone=nil,0,false
    local tween,movementRoot,movementGoal,movementStart=nil,nil,nil,0
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
    local function stopMovement()
        if tween then tween:Cancel();tween=nil end
        local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
        if h then h:Move(Vector3.zero) end
        movementRoot,movementGoal=nil,nil
    end
    local function character()
        local c=player.Character
        local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if h and r and h.Health>0 then return c,h,r end
    end
    local function moveTo(cf,tolerance)
        local _,_,root=character()
        if not root then stopMovement();return false end
        local distance=(root.Position-cf.Position).Magnitude
        if distance<=(tolerance or 4) then stopMovement();return true end
        if movementGoal and movementRoot==root and (movementGoal.Position-cf.Position).Magnitude<5 then
            if clock()-movementStart>math.min(70,distance/config.speed+15) then
                stopMovement();error("Deplacement bloque: se rapprocher de la zone manuellement")
            end
            return false
        end
        stopMovement()
        movementRoot,movementGoal,movementStart=root,cf,clock()
        tween=services.TweenService:Create(root,TweenInfo.new(math.max(0.15,distance/config.speed),Enum.EasingStyle.Linear),{CFrame=cf})
        tween:Play()
        return false
    end
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
            if obj:IsA("TextLabel") and obj.Text:lower():find(name:lower(),1,true) then return true end
        end
        return false
    end
    local function weapon(c,h)
        local backpack=player:FindFirstChild("Backpack")
        for _,bag in pairs({c,backpack}) do
            for _,tool in ipairs(bag:GetChildren()) do
                if tool:IsA("Tool") and not tool.Name:find("Fruit",1,true) then
                    local tip=tool.ToolTip
                    if (config.weapon=="Melee" and tip=="Melee") or (config.weapon=="Sword" and tip=="Sword") then
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
        if distance>7 then moveTo(er.CFrame*CFrame.new(0,1,4),5);return false end
        stopMovement()
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
        if distance>7 then moveTo(er.CFrame*CFrame.new(0,1,4),5);return false end
        stopMovement()
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
        if transport.pending then return transport.pending.id==id end
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
        if transport.pending then return false end
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
    return adapter
end

if POLARIS_TEST then return {newEngine=newEngine,newTransport=newTransport,chooseQuest=chooseQuest,quests=QUESTS,newAdapter=newAdapter} end

local services={Players=game:GetService("Players"),TweenService=game:GetService("TweenService"),
    Input=game:GetService("UserInputService"),Lighting=game:GetService("Lighting"),Run=game:GetService("RunService")}
local player=services.Players.LocalPlayer
assert(player,"Polaris doit etre execute cote client")
local playerGui=player:WaitForChild("PlayerGui")
local old=playerGui:FindFirstChild("PolarisMobileDemo")
if old then local event=old:FindFirstChild("Cleanup");if event then event:Fire() end;old:Destroy() end
local config={bosses=true,weapon="Melee",speed=140,fruitRange=5000}
local colors={bg=Color3.fromRGB(11,16,27),card=Color3.fromRGB(22,30,47),accent=Color3.fromRGB(83,113,255),
    text=Color3.fromRGB(239,244,255),muted=Color3.fromRGB(153,168,196),green=Color3.fromRGB(48,170,129)}
local links,closed,pages,tabButtons,toggleButtons={},false,{},{},{}
local engine,adapter
local history={}
local function bind(signal,fn) local connection=signal:Connect(fn);table.insert(links,connection);return connection end
local function make(class,parent,props)
    local object=Instance.new(class)
    for key,value in pairs(props or {}) do object[key]=value end
    object.Parent=parent;return object
end
local function corner(obj,radius) make("UICorner",obj,{CornerRadius=UDim.new(0,radius or 12)}) end
local function stroke(obj) make("UIStroke",obj,{Color=Color3.fromRGB(54,67,98),Thickness=1,Transparency=0.35}) end
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
local panel=make("Frame",gui,{Size=UDim2.new(0.93,0,0.89,0),Position=UDim2.fromScale(0.5,0.5),
    AnchorPoint=Vector2.new(0.5,0.5),BackgroundColor3=colors.bg,BorderSizePixel=0})
corner(panel,18);stroke(panel)
make("UISizeConstraint",panel,{MaxSize=Vector2.new(860,680)})
local banner=make("Frame",panel,{Size=UDim2.new(1,0,0,64),BackgroundColor3=colors.card,BorderSizePixel=0})
corner(banner,18)
make("UIGradient",banner,{Color=ColorSequence.new(colors.accent,colors.card),Rotation=15})
local title=label(banner,"POLARIS",UDim2.new(1,-120,0,30),UDim2.new(0,18,0,7))
title.TextSize=23;title.Font=Enum.Font.GothamBold
local subtitle=label(banner,"v0.5  /  MOBILE + PC  /  EXPERIMENTAL",UDim2.new(1,-120,0,20),UDim2.new(0,18,0,37))
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
local nav=make("ScrollingFrame",panel,{Size=UDim2.new(1,-24,0,43),Position=UDim2.new(0,12,0,73),
    BackgroundTransparency=1,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.X,
    CanvasSize=UDim2.new(),ScrollBarThickness=2,ScrollingDirection=Enum.ScrollingDirection.X})
make("UIListLayout",nav,{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,6),SortOrder=Enum.SortOrder.LayoutOrder})
local status=label(panel,"INITIALISATION",UDim2.new(1,-30,0,28),UDim2.new(0,15,0,122))
status.TextSize=12;status.TextColor3=colors.muted
local area=make("Frame",panel,{Size=UDim2.new(1,-24,1,-220),Position=UDim2.new(0,12,0,158),BackgroundTransparency=1})
local footer=make("Frame",panel,{Size=UDim2.new(1,-24,0,46),Position=UDim2.new(0,12,1,-55),BackgroundTransparency=1})
local run=button(footer,"DEMARRER",UDim2.new(0.32,0,1,0));run.BackgroundColor3=colors.accent
local pause=button(footer,"PAUSE",UDim2.new(0.32,0,1,0),UDim2.fromScale(0.34,0))
local stop=button(footer,"TOUT ARRETER",UDim2.new(0.32,0,1,0),UDim2.fromScale(0.68,0))
local orders={}
local function showPage(name)
    for key,page in pairs(pages) do page.Visible=key==name end
    for key,b in pairs(tabButtons) do b.BackgroundColor3=key==name and colors.accent or colors.card end
end
for index,name in ipairs({"Accueil","Farm","Fruits","Epees","Races","Boutique","Performance","Journal"}) do
    local page=make("ScrollingFrame",area,{Name=name,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
        BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,Visible=index==1})
    make("UIListLayout",page,{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder})
    make("UIPadding",page,{PaddingRight=UDim.new(0,7),PaddingBottom=UDim.new(0,12)})
    pages[name],orders[name]=page,0
    local b=button(nav,name,UDim2.fromOffset(name=="Performance" and 130 or 104,36));b.LayoutOrder=index
    tabButtons[name]=b;bind(b.Activated,function() showPage(name) end)
end
showPage("Accueil")
local function row(page,textValue,isButton,height)
    orders[page]=orders[page]+1
    local obj
    if isButton then obj=button(pages[page],textValue,UDim2.new(1,-2,0,height or 52))
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
row("Accueil","Cette version implemente des actions reelles, sans garantir leur acceptation par le serveur. Raids, fragments, armes de quete, changement de mer et skills de fruit ne sont pas implementes.",false)
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
    for _,entry in ipairs({{"fruit","Stocker les fruits portes",100,2},{"collect","Chercher les fruits au sol",90,2},
        {"sword","Acheter epees legendaires (mer 2)",70,20},{"gacha","Random fruit / Gacha",60,2},
        {"race2","Quete race V2 / fleurs",85,2},{"swordfarm","Farm cible pour epee",30,0.2},
        {"navigate","Aller au PNJ selectionne",110,0.2},
        {"shop","Acheter la liste de 18 objets",50,3},{"farm","Auto quetes + combat normal",10,0.2}}) do
        engine:add(table.unpack(entry))
    end
    status.Text="Pret / en pause"
else
    status.Text="Blox Fruits / CommF_ non detecte"
    report("Les actions sont desactivees hors de Blox Fruits. Le menu et le mode graphique restent disponibles.")
end
local function toggle(page,id,labelValue)
    local b=row(page,labelValue.."  [OFF]",true);toggleButtons[id]=b
    b.Active=supported==true;b.AutoButtonColor=supported==true
    bind(b.Activated,function()
        if not engine then return end
        engine:enable(id,not engine.tasks[id].enabled)
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
local speedButton=row("Farm","Vitesse de deplacement : 140",true)
bind(speedButton.Activated,function() config.speed=config.speed==140 and 80 or 140;speedButton.Text="Vitesse de deplacement : "..config.speed end)
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
row("Boutique","Marchand legendaire : une tentative toutes les 20 s, en alternant les 3 epees. Presence du marchand, possession, prerequis et solde sont verifies par le serveur.",false)
row("Epees","ACHATS ET DROPS : les boutons lancent une tentative ou un farm cible. Une epee de drop n'est jamais garantie en un clic.",false)
local legendary=row("Epees","Activer achat auto : Saddi / Shisui / Wando",true)
bind(legendary.Activated,function()
    if engine then engine:enable("sword",not engine.tasks.sword.enabled);report("Option marchand legendaire modifiee. Appuyer sur Demarrer.") end
end)
row("Epees","Le marchand depend du serveur ; ce n'est pas un spawn reserve a la nuit. L'option reste active pendant le farm et tente d'acheter quand le serveur le permet. Aucun minuteur de spawn invente.",false)
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
        engine:enable("farm",false);engine:enable("race2",false);engine:enable("swordfarm",true)
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
    if adapter and not adapter.inspectV3() then report("Transport occupe; reessayer dans quelques secondes") end
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
    if engine then engine:close() end
    if adapter then adapter.close() end
    closed=true;graphicsEpoch=graphicsEpoch+1
    if lowGraphics then
        services.Lighting.GlobalShadows=oldShadows
        for obj,value in pairs(originals) do if obj.Parent then pcall(function() obj.Enabled=value end) end end
    end
    for _,connection in ipairs(links) do connection:Disconnect() end
end
bind(close.Activated,function() dispose();gui:Destroy() end)
bind(cleanup.Event,dispose);bind(gui.Destroying,dispose)
bind(services.Input.InputBegan,function(input,processed)
    if not processed and input.KeyCode==Enum.KeyCode.RightControl then
        if panel.Visible then minimizePanel() else panel.Visible=true;reopen.Visible=false end
    end
end)
local function refresh()
    if not engine then return end
    local count=0
    for id,b in pairs(toggleButtons) do
        local entry=engine.tasks[id]
        local textValue=entry.label..(entry.enabled and "  [ON]" or "  [OFF]")
        if b.Text~=textValue then b.Text=textValue;b.BackgroundColor3=entry.enabled and colors.green or colors.card end
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
    if d.blocked then engine:pause();status.Text=d.blocked end
end
report("Polaris v0.5 charge. Toutes les actions sont OFF.")
refresh()
task.spawn(function()
    local lastRefresh=0
    while not closed do
        local ok,err=pcall(function()
            if adapter then adapter.transport:poll() end
            if engine then engine:tick() end
            if os.clock()-lastRefresh>=1 then lastRefresh=os.clock();refresh() end
        end)
        if not ok then if engine then engine:pause() end;report("Arret: "..tostring(err):sub(1,160)) end
        task.wait(0.2)
    end
end)

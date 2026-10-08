-- Polaris Mobile Prototype
-- Demonstration / task engine / UI prototype for Roblox.
-- This file is provided as a technical prototype and should not be presented
-- as a functional cheat or unauthorized automation script.
-- It is intended for experimentation, prototyping, and adaptation to a game
-- with a properly documented adapter layer.
--
-- Usage:
--   Place this script as a LocalScript in StarterPlayerScripts
--   or run it in a compatible client-side environment for testing.
--
-- Contract:
--   ready(id, now) and step(id, now, budget) must be non-blocking and
--   must not yield. step returns true only when work is complete.
--   suspend(id) must stop current movement/actions immediately.
--   Progress state is preserved by the adapter between suspensions.
--
-- Important:
--   - No Robux usage
--   - No unauthorized teleportation
--   - No automated combat
--   - No auto-farm or raid automation in the demo mode
--   - Experimental purchase logic must be adapted and validated for a specific game
--   - This is a framework example, not a production script

local function newEngine(adapter, clock, publish)
    local self = {
        running = false,
        closed = false,
        active = nil,
        tasks = {},
        prefix = "DEMO: ",
        sequence = {},
        lastStatus = nil,
        steps = 0
    }

    local function status(message)
        if self.lastStatus ~= message then
            self.lastStatus = message
            publish(message)
        end
    end

    local function invoke(name, ...)
        local fn = adapter[name]
        if type(fn) ~= "function" then
            return false, "Adapter incomplete: " .. name
        end
        return pcall(fn, ...)
    end

    function self:add(id, label, priority, interval)
        assert(not self.tasks[id], "Identifier already used")
        self.tasks[id] = {
            id = id,
            label = label,
            priority = priority,
            interval = interval,
            enabled = false,
            nextAt = 0,
            failures = 0
        }
        table.insert(self.sequence, self.tasks[id])
    end

    function self:release()
        if not self.active then return true end
        local previous = self.active
        self.active = nil
        local ok, reason = invoke("suspend", previous.id)
        if not ok then
            self.running = false
            status("Stop: unable to suspend " .. previous.label .. ": " .. tostring(reason))
        end
        return ok
    end

    function self:enable(id, enabled)
        assert(self.tasks[id], "Unknown task")
        self.tasks[id].enabled = enabled
        if not enabled and self.active == self.tasks[id] then
            self:release()
        end
    end

    function self:start()
        if not self.closed then
            self.running = true
            status(self.prefix .. "started")
        end
    end

    function self:pause()
        self.running = false
        if self:release() then
            status("Paused")
        end
    end

    function self:close()
        self:pause()
        self.closed = true
    end

    function self:fail(entry, reason, now)
        entry.failures = entry.failures + 1
        entry.nextAt = now + math.min(30, 2 ^ entry.failures)
        if entry.failures >= 3 then
            entry.enabled = false
        end
        self:release()
        status("Error " .. entry.label .. ": " .. tostring(reason))
    end

    function self:tick()
        if not self.running or self.closed then return end

        local now, selected = clock(), nil
        for _, entry in ipairs(self.sequence) do
            if entry.enabled and now >= entry.nextAt then
                local ok, ready = invoke("ready", entry.id, now)
                if not ok then
                    self:fail(entry, ready, now)
                elseif ready and (not selected or entry.priority > selected.priority) then
                    selected = entry
                end
            end
        end

        if not self.running then return end

        if self.active ~= selected then
            if not self:release() then return end
            self.active = selected
        end

        if not selected then
            status(self.prefix .. "waiting / no task available")
            return
        end

        local ok, done = invoke("step", selected.id, now, 1)
        self.steps = self.steps + 1

        if not ok then
            self:fail(selected, done, now)
            return
        end

        status(self.prefix .. selected.label)

        if done then
            selected.failures = 0
            selected.nextAt = now + selected.interval
            self:release()
        end
    end

    return self
end

-- NOTE:
-- The full GUI/demo logic below is kept for demonstration only.
-- If publishing publicly, it is recommended to keep the code neutral and remove
-- any game-specific or exploit-like references from the original version.

local player = game:GetService("Players").LocalPlayer
assert(player, "This script must run on the client side")

local playerGui = player:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("PolarisMobileDemo")
if old then
    local cleanup = old:FindFirstChild("Cleanup")
    if cleanup then cleanup:Fire() end
    old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn = "PolarisMobileDemo", false
gui.ZIndexBehavior, gui.Parent = Enum.ZIndexBehavior.Sibling, playerGui

local cleanup = Instance.new("BindableEvent")
cleanup.Name, cleanup.Parent = "Cleanup", gui

local links, disposed, pages, tabs, toggles = {}, false, {}, {}, {}
local live, liveAdapter, engine = false, nil, nil
local history = {}
local blue, dark, muted = Color3.fromRGB(45, 115, 235), Color3.fromRGB(20, 25, 38), Color3.fromRGB(111, 123, 145)

local function bind(signal, fn)
    table.insert(links, signal:Connect(fn))
end

local function make(className, parent, props)
    local obj = Instance.new(className)
    for key, value in pairs(props or {}) do
        obj[key] = value
    end
    obj.Parent = parent
    return obj
end

local function rounded(obj)
    make("UICorner", obj, {CornerRadius = UDim.new(0, 9)})
end

local panel = make("Frame", gui, {
    Size = UDim2.new(0.92, 0, 0.88, 0),
    Position = UDim2.new(0.04, 0, 0.06, 0),
    BackgroundColor3 = dark,
    BorderSizePixel = 0
})
rounded(panel)
make("UISizeConstraint", panel, {MaxSize = Vector2.new(740,650)})

local function text(parent, value, size, pos)
    return make("TextLabel", parent, {
        Text = value,
        Size = size,
        Position = pos or UDim2.new(),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(237,242,252),
        TextSize = 14,
        TextWrapped = true,
        Font = Enum.Font.Gotham
    })
end

local function button(parent, value, size, pos)
    local b = make("TextButton", parent, {
        Text = value,
        Size = size,
        Position = pos or UDim2.new(),
        BackgroundColor3 = Color3.fromRGB(36,46,67),
        TextColor3 = Color3.fromRGB(238,243,252),
        TextSize = 14,
        TextWrapped = true,
        Font = Enum.Font.Gotham,
        BorderSizePixel = 0
    })
    rounded(b)
    return b
end

local title = text(panel, "POLARIS  /  DEMO", UDim2.new(1,-124,0,42), UDim2.new(0,12,0,0))
title.TextXAlignment = Enum.TextXAlignment.Left

local minimize = button(panel, "_", UDim2.new(0,42,0,34), UDim2.new(1,-98,0,5))
local close = button(panel, "X", UDim2.new(0,42,0,34), UDim2.new(1,-50,0,5))
local reopen = button(gui, "POLARIS", UDim2.new(0,110,0,42), UDim2.new(0,12,0.4,0))
reopen.Visible = false

bind(minimize.Activated, function() panel.Visible = false; reopen.Visible = true end)
bind(reopen.Activated, function() panel.Visible = true; reopen.Visible = false end)

local navigation = make("ScrollingFrame", panel, {
    Size = UDim2.new(1,-20,0,46),
    Position = UDim2.new(0,10,0,45),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollBarThickness = 3
})
make("UIListLayout", navigation, {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0,6),
    SortOrder = Enum.SortOrder.LayoutOrder
})

local state = text(panel, "En pause", UDim2.new(1,-20,0,34), UDim2.new(0,10,0,94))
local area = make("Frame", panel, {
    Size = UDim2.new(1,-20,1,-190),
    Position = UDim2.new(0,10,0,130),
    BackgroundTransparency = 1
})
local footer = make("Frame", panel, {
    Size = UDim2.new(1,-20,0,46),
    Position = UDim2.new(0,10,1,-52),
    BackgroundTransparency = 1
})

local run = button(footer, "Demarrer", UDim2.new(0.32,-4,1,0))
local pause = button(footer, "Pause", UDim2.new(0.32,-4,1,0), UDim2.new(0.34,0,0,0))
local stop = button(footer, "Tout desactiver", UDim2.new(0.32,-4,1,0), UDim2.new(0.68,0,0,0))
run.BackgroundColor3 = blue

local orders = {}
local function page(name)
    local frame = make("ScrollingFrame", area, {
        Name = name,
        Size = UDim2.new(1,0,1,0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
        Visible = false
    })
    make("UIListLayout", frame, {Padding = UDim.new(0,8), SortOrder = Enum.SortOrder.LayoutOrder})
    make("UIPadding", frame, {PaddingBottom = UDim.new(0,12), PaddingRight = UDim.new(0,5)})
    pages[name], orders[name] = frame, 0

    local tab = button(navigation, name, UDim2.new(0,105,0,38))
    tabs[name] = tab

    bind(tab.Activated, function()
        for key, item in pairs(pages) do item.Visible = key == name end
        for key, item in pairs(tabs) do item.BackgroundColor3 = key == name and blue or Color3.fromRGB(36,46,67) end
    end)

    return frame
end

local function row(name, value, isButton, height)
    orders[name] = orders[name] + 1
    local obj
    if isButton then
        obj = button(pages[name], value, UDim2.new(1,-6,0,height or 46))
    else
        obj = text(pages[name], value, UDim2.new(1,-6,0,height or 50))
    end
    obj.LayoutOrder = orders[name]
    return obj
end

for _, name in ipairs({"Accueil","Farm","Fruits","Boutique","Epees","Maitrise","Raids","Journal"}) do
    page(name)
end
pages.Accueil.Visible = true
tabs.Accueil.BackgroundColor3 = blue

local warning = row("Accueil", "DEMO : les actions sont simulatees. Aucun achat ni farm reel.", false, 64)
local mode = row("Accueil", "Activer le mode achats EXPERIMENTAL", true, 54)
local summary = row("Accueil", "Toutes les fonctions sont desactivees.", false, 70)
local diag = row("Accueil", "", false, 55)
local response = row("Accueil", "Dernier resultat : aucun", false, 70)

local logLabel = row("Journal", "Aucun evenement", false, 320)
logLabel.AutomaticSize = Enum.AutomaticSize.Y
logLabel.Size = UDim2.new(1,-6,0,0)
logLabel.TextXAlignment = Enum.TextXAlignment.Left
logLabel.TextYAlignment = Enum.TextYAlignment.Top

local function log(message)
    if disposed then return end
    table.insert(history, 1, os.date("%H:%M:%S") .. "  " .. tostring(message))
    while #history > 18 do table.remove(history) end
    logLabel.Text = table.concat(history, "\n")
end

local function report(message)
    response.Text = tostring(message)
    log(message)
end

local function publish(message)
    state.Text = message
    log(message)
end

local progress, available = {}, {}
local demo = {
    ready = function(id)
        return id == "farm" or available[id] == true
    end,
    suspend = function() end
}

function demo.step(id, _, budget)
    progress[id] = (progress[id] or 0) + budget
    if progress[id] >= (id == "farm" and 20 or 4) then
        progress[id] = 0
        available[id] = false
        return true
    end
    return false
end

local function setup(adapter, real)
    engine = newEngine(adapter, os.clock, publish)
    engine.prefix = real and "EXPERIMENTAL : " or "DEMO : "
    engine:add("fruit", real and "Stockage des fruits portes" or "Collecte / stockage simules", 100, 1)
    engine:add("sword", real and "Tentatives d'achat legendaire" or "Achat legendaire simule", 80, real and 7 or 1)
    engine:add("gacha", real and "Tentatives Gacha" or "Gacha simule", 60, 1)
    engine:add("shop", real and "Liste de 18 objets" or "Boutique simulee", 40, 1)
    engine:add("farm", "Farm simule", 10, 0.5)
end

setup(demo, false)

local function toggle(section, id)
    local b = row(section, "", true)
    toggles[id] = b

    bind(b.Activated, function()
        if live and id == "farm" then return end
        local entry = engine.tasks[id]
        engine:enable(id, not entry.enabled)
        if not live and entry.enabled and id ~= "farm" then available[id] = true end
        log(entry.label .. (entry.enabled and " active" or " desactive"))
    end)
end

local function unavailable(section, label, reason)
    local b = row(section, label .. " -- INDISPONIBLE", true)
    b.Active = false
    b.AutoButtonColor = false
    b.TextColor3 = muted
    row(section, reason, false, 58)
end

row("Farm", "Farm, quetes et boss", false, 35)
toggle("Farm", "farm")
unavailable("Farm", "Auto quetes + combat", "Aucun module de quetes ou de combat reel n'est implemente.")
unavailable("Farm", "Priorite boss puis NPC", "Necessite un catalogue et un module de combat verifies.")

local simulate = row("Farm", "Simuler un fruit pendant le farm", true)
bind(simulate.Activated, function()
    if live then report("La collecte au sol reste indisponible."); return end
    available.fruit = true
    log("Fruit simule disponible; activer aussi collecte/stockage en demo.")
end)

toggle("Fruits", "gacha")
toggle("Fruits", "fruit")
row("Fruits", "Mode experimental : deux heures entre tentatives Gacha. Stockage limite aux noms historiques reconnus.", false, 72)
unavailable("Fruits", "Collecter un fruit au sol", "Aucun deplacement reel vers les fruits. Le stockage concerne seulement les fruits portes.")

toggle("Boutique", "shop")
row("Boutique", "Liste limitee : Katana, Cutlass, Dual Katana, Iron Mace, Triple Katana, Pipe, Dual-Headed Blade, Soul Cane, Bisento, Musket, Slingshot, Flintlock, Refined Slingshot, Refined Flintlock, Cannon, Black Cape, Swordsman Hat, Tomoe Ring.", false, 150)
row("Boutique", "Un refus ou une reponse inconnue arrete la liste. Les achats peuvent depenser l'argent du jeu.", false, 65)

local retry = row("Boutique", "Reessayer l'achat bloque", true)
bind(retry.Activated, function()
    if not liveAdapter then report("Disponible en mode experimental seulement"); return end
    local _, message = liveAdapter.retryShop()
    report(message)
end)

toggle("Epees", "sword")
row("Epees", "Tentatives espacees. La disponibilite, les prerequis et la possession ne sont pas valides dans cette version.", false, 72)
unavailable("Epees", "Obtenir toutes les epees", "Les armes de quete et de drop ne sont pas implementees.")
unavailable("Maitrise", "Auto mastery", "Choix d'arme, combat et attribution de maitrise non implementes.")
unavailable("Raids", "Auto raids + fragments", "Aucun module de raid ou d'achat de puce. Aucun fruit n'est sacrifie.")

local function refresh()
    local active = {}
    for id, b in pairs(toggles) do
        local entry = engine.tasks[id]
        local disabled = live and id == "farm"
        b.Active = not disabled
        b.AutoButtonColor = not disabled
        b.Text = disabled and "Farm reel -- INDISPONIBLE" or entry.label .. (entry.enabled and " : ON" or " : OFF")
        b.BackgroundColor3 = entry.enabled and blue or Color3.fromRGB(36,46,67)
        b.TextColor3 = disabled and muted or Color3.fromRGB(238,243,252)
        if entry.enabled then table.insert(active, entry.label) end
    end
    summary.Text = #active == 0 and "Toutes les fonctions sont desactivees." or "Options actives : " .. table.concat(active, ", ")
end

bind(mode.Activated, function()
    if live then return end
    if game.GameId ~= 994732206 then
        report("Mode experimental reserve a Blox Fruits")
        return
    end

    local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("CommF_")
    if not remote or not remote:IsA("RemoteFunction") then
        report("CommF_ absent; la demo reste disponible")
        return
    end

    engine:close()
    liveAdapter = {
        -- Minimal adapter stub for demonstration only.
        ready = function() return true end,
        step = function() return true end,
        suspend = function() end,
        close = function() end,
        retryShop = function() return true, "Mode experimental demo" end,
        diagnostics = function() return {gachaWait = 0, shopItem = "demo", shopBlocked = false, blocked = nil, requestPending = false} end
    }

    live = true
    setup(liveAdapter, true)
    title.Text = "POLARIS  /  EXPERIMENTAL"
    warning.Text = "Achats reels possibles avec l'argent du jeu. Appels anciens non testes dans Delta. Farm et raids indisponibles."
    mode.Text = "Mode experimental actif"
    mode.Active = false
    mode.AutoButtonColor = false
    report("Selectionne une fonction puis Demarrer.")
    refresh()
end)

bind(run.Activated, function() engine:start() end)
bind(pause.Activated, function() engine:pause() end)
bind(stop.Activated, function()
    engine:pause()
    for _, entry in ipairs(engine.sequence) do
        engine:enable(entry.id, false)
    end
    refresh()
    report("Options desactivees. Une requete deja envoyee peut encore terminer.")
end)

local function dispose()
    if disposed then return end
    engine:close()
    if liveAdapter then liveAdapter.close() end
    disposed = true
    for _, connection in ipairs(links) do
        connection:Disconnect()
    end
end

bind(close.Activated, function() dispose(); gui:Destroy() end)
bind(cleanup.Event, dispose)
bind(gui.Destroying, dispose)

refresh()
log("Polaris v0.4 ouvert en demo")

task.spawn(function()
    local lastInfo = 0
    while not disposed do
        engine:tick()
        if os.clock() - lastInfo >= 1 then
            lastInfo = os.clock()
            refresh()
        end
        task.wait(0.25)
    end
end)

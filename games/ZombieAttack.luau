getgenv().AutoFarmEnabled = false
getgenv().GroundDistance = 8
getgenv().BehindDistance = 9
getgenv().FireDelay = 0.05
getgenv().globalTarget = nil

local lib = loadstring(game:HttpGet("https://raw.githubusercontent.com/nondevelopers/Vape-UiLibrary/main/source.luau"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local enemies = Workspace.enemies
local bossFolder = Workspace.BossFolder
local allFolders = {bossFolder, enemies}

local THEME = "Dark"
local CONFIG_FILE = "ZombieAttackFarm_config.json"

local config = {
    AutoEquip = true,
    AntiAFK = true,
    ESP = false,
    BossPriority = false,
    WaveAware = true,
    MultiTarget = true,
    MaxTargets = 3,
    SafeEnabled = false,
    SafeBelow = 30,
    SafeResume = 80,
    AutoBuy = false,
    BuyBetweenWaves = true,
    BuyRemote = "",
    BuyArgs = "",
    BuyDelay = 5,
}

local persistedKeys = {
    "AutoEquip", "AntiAFK", "BossPriority", "WaveAware", "MultiTarget", "MaxTargets",
    "SafeEnabled", "SafeBelow", "SafeResume", "BuyBetweenWaves", "BuyRemote", "BuyArgs", "BuyDelay",
}
local persistedGlobals = {"GroundDistance", "BehindDistance", "FireDelay"}

local function canUseFiles()
    return typeof(isfile) == "function" and typeof(readfile) == "function" and typeof(writefile) == "function"
end

local function saveConfig()
    if not canUseFiles() then
        return false
    end
    local data = {}
    for _, k in ipairs(persistedGlobals) do
        data[k] = getgenv()[k]
    end
    for _, k in ipairs(persistedKeys) do
        data[k] = config[k]
    end
    local ok = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(data))
    end)
    return ok
end

local function loadConfig()
    if not canUseFiles() or not isfile(CONFIG_FILE) then
        return false
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if not ok or type(data) ~= "table" then
        return false
    end
    for _, k in ipairs(persistedGlobals) do
        if type(data[k]) == "number" then
            getgenv()[k] = data[k]
        end
    end
    for _, k in ipairs(persistedKeys) do
        if data[k] ~= nil and type(data[k]) == type(config[k]) then
            config[k] = data[k]
        end
    end
    return true
end

loadConfig()

local function accentFor(theme)
    return theme == "Light" and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
end

local win = lib:Window(
    "Zombie Attack - Autofarm",
    accentFor(THEME),
    Enum.KeyCode.RightControl,
    Vector2.new(500, 330),
    0.1,
    THEME
)

local farmTab = win:Tab("Autofarm", "crosshair")
local statsTab = win:Tab("Stats", "activity")
local visualTab = win:Tab("Visuals", "eye")
local miscTab = win:Tab("Misc", "settings")
local settingsTab = win:Tab("Settings", "sliders-horizontal")

local function isAlive(model)
    if not model or not model.Parent then
        return false
    end
    local hum = model:FindFirstChild("Humanoid")
    return hum ~= nil
        and hum.Health > 0
        and model:FindFirstChild("Head") ~= nil
        and model:FindFirstChild("HumanoidRootPart") ~= nil
end

local function collect()
    local list = {}
    local char = player.Character
    local head = char and char:FindFirstChild("Head")
    if not head then
        return list
    end
    local myPos = head.Position
    for _, folder in ipairs(allFolders) do
        local isBoss = folder == bossFolder
        for _, v in ipairs(folder:GetChildren()) do
            if isAlive(v) then
                list[#list + 1] = {m = v, d = (myPos - v.Head.Position).Magnitude, boss = isBoss}
            end
        end
    end
    table.sort(list, function(a, b)
        if config.BossPriority and a.boss ~= b.boss then
            return a.boss
        end
        return a.d < b.d
    end)
    return list
end

local function ensureTool()
    local char = player.Character
    if not char then
        return nil
    end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        return tool
    end
    if config.AutoEquip then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local backpack = player:FindFirstChildOfClass("Backpack")
        local candidate = backpack and backpack:FindFirstChildOfClass("Tool")
        if hum and candidate then
            hum:EquipTool(candidate)
            return candidate
        end
    end
    return nil
end

local kills = 0
local shots = 0
local credited = setmetatable({}, {__mode = "k"})
local watched = setmetatable({}, {__mode = "k"})
local lastFired = setmetatable({}, {__mode = "k"})

local function credit(model)
    if credited[model] then
        return
    end
    credited[model] = true
    kills += 1
end

local function watch(model)
    if watched[model] then
        return
    end
    watched[model] = true
    local hum = model:FindFirstChild("Humanoid")
    if hum then
        hum.HealthChanged:Connect(function(h)
            if h <= 0 then
                credit(model)
            end
        end)
        hum.Died:Connect(function()
            credit(model)
        end)
    end
    model.AncestryChanged:Connect(function(_, parent)
        if not parent and os.clock() - (lastFired[model] or 0) < 2 then
            credit(model)
        end
    end)
end

local connection
local retreating = false
local isIdle = true
local safePos
local farmSession = 0
local runAccum = 0
local runStart

local function elapsed()
    return runAccum + (runStart and (os.clock() - runStart) or 0)
end

local function getSafePos(root)
    if not safePos then
        safePos = root.Position + Vector3.new(0, 150, 0)
    end
    return safePos
end

local function zeroVel(char, root)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    local torso = char:FindFirstChild("Torso")
    if torso then
        torso.AssemblyLinearVelocity = Vector3.zero
    end
end

local function stopFarm()
    if runStart then
        runAccum += os.clock() - runStart
        runStart = nil
    end
    getgenv().AutoFarmEnabled = false
    if connection then
        connection:Disconnect()
        connection = nil
    end
    getgenv().globalTarget = nil
    retreating = false
    isIdle = true
    farmSession += 1
end

local function fireAt(model, toolName)
    local head = model:FindFirstChild("Head")
    if not head then
        return
    end
    watch(model)
    lastFired[model] = os.clock()
    shots += 1
    ReplicatedStorage.Gun:FireServer({
        ["Normal"] = Vector3.new(0, 0, 0),
        ["Direction"] = head.Position,
        ["Name"] = toolName,
        ["Hit"] = head,
        ["Origin"] = head.Position,
        ["Pos"] = head.Position
    })
end

local function step()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end
    local hum = char:FindFirstChildOfClass("Humanoid")

    if config.SafeEnabled and hum and hum.MaxHealth > 0 then
        local pct = hum.Health / hum.MaxHealth * 100
        local resume = math.max(config.SafeResume, config.SafeBelow + 5)
        if pct < config.SafeBelow then
            retreating = true
        elseif retreating and pct >= resume then
            retreating = false
        end
    elseif retreating then
        retreating = false
    end

    if retreating then
        root.CFrame = CFrame.new(getSafePos(root))
        zeroVel(char, root)
        return
    end

    local list = collect()
    local target = list[1] and list[1].m or nil
    getgenv().globalTarget = target

    if not target then
        isIdle = true
        if config.WaveAware then
            root.CFrame = CFrame.new(getSafePos(root))
            zeroVel(char, root)
        end
        return
    end

    isIdle = false

    local cam = Workspace.CurrentCamera
    cam.CFrame = CFrame.new(cam.CFrame.Position, target.Head.Position)
    root.CFrame = target.HumanoidRootPart.CFrame * CFrame.new(0, getgenv().GroundDistance, getgenv().BehindDistance)
    zeroVel(char, root)
end

local function volley()
    if retreating then
        return
    end
    local target = getgenv().globalTarget
    if not isAlive(target) then
        return
    end
    local tool = ensureTool()
    if not tool then
        return
    end
    fireAt(target, tool.Name)
    if config.MultiTarget then
        local fired = 1
        for _, entry in ipairs(collect()) do
            if fired >= config.MaxTargets then
                break
            end
            if entry.m ~= target and isAlive(entry.m) then
                fireAt(entry.m, tool.Name)
                fired += 1
            end
        end
    end
end

farmTab:Section("Lock & Kill")

farmTab:Toggle("AutoFarm Lock (Spam Kill)", false, function(state)
    stopFarm()
    if not state then
        return
    end
    getgenv().AutoFarmEnabled = true
    runStart = os.clock()
    connection = RunService.RenderStepped:Connect(step)

    local current = farmSession
    task.spawn(function()
        while getgenv().AutoFarmEnabled and farmSession == current do
            volley()
            task.wait(getgenv().FireDelay)
        end
    end)
end)

farmTab:Toggle("Multi-Target Volley (no switch delay)", config.MultiTarget, function(state)
    config.MultiTarget = state
end)

farmTab:Slider("Max Targets Per Volley", 1, 8, math.clamp(config.MaxTargets, 1, 8), function(v)
    config.MaxTargets = v
end)

farmTab:Toggle("Auto Equip Tool", config.AutoEquip, function(state)
    config.AutoEquip = state
end)

farmTab:Toggle("Boss Priority", config.BossPriority, function(state)
    config.BossPriority = state
end)

farmTab:Section("Waves")

farmTab:Toggle("Wave Aware (hold safe spot when empty)", config.WaveAware, function(state)
    config.WaveAware = state
end)

farmTab:Section("Safe Spot")

farmTab:Toggle("Retreat On Low Health", config.SafeEnabled, function(state)
    config.SafeEnabled = state
    if not state then
        retreating = false
    end
end)

farmTab:Slider("Retreat Below (%)", 5, 90, config.SafeBelow, function(v)
    config.SafeBelow = v
end)

farmTab:Slider("Resume Above (%)", 20, 100, config.SafeResume, function(v)
    config.SafeResume = v
end)

farmTab:Button("Set Safe Spot Here", function()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        safePos = root.Position
        lib:Notification("Safe Spot", "Position saved.", 3)
    end
end)

farmTab:Section("Tuning")

farmTab:Slider("Height", 5, 20, math.clamp(getgenv().GroundDistance, 5, 20), function(v)
    getgenv().GroundDistance = v
end)

farmTab:Slider("Distance Behind Target", 0, 20, math.clamp(getgenv().BehindDistance, 0, 20), function(v)
    getgenv().BehindDistance = v
end)

farmTab:Slider("Fire Delay (ms)", 20, 200, math.clamp(math.floor(getgenv().FireDelay * 1000 + 0.5), 20, 200), function(v)
    getgenv().FireDelay = v / 1000
end)

local function statsText()
    local e = elapsed()
    local s = math.floor(e)
    local rate = e > 0 and kills / (e / 60) or 0
    return {
        kills = "Kills: " .. kills,
        rate = string.format("Kills/min: %.1f", rate),
        shots = "Shots: " .. shots,
        time = string.format("Runtime: %02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60),
    }
end

local sKills = statsTab:Section("Kills: 0")
local sRate = statsTab:Section("Kills/min: 0.0")
local sShots = statsTab:Section("Shots: 0")
local sTime = statsTab:Section("Runtime: 00:00:00")

local function setStat(obj, text)
    pcall(function()
        if obj.Set then
            obj:Set(text)
        elseif obj.SetText then
            obj:SetText(text)
        end
    end)
end

statsTab:Button("Show Stats", function()
    local t = statsText()
    lib:Notification("Stats", t.kills .. " | " .. t.rate .. " | " .. t.shots .. " | " .. t.time, 6)
end)

statsTab:Button("Reset Stats", function()
    kills = 0
    shots = 0
    runAccum = 0
    if runStart then
        runStart = os.clock()
    end
end)

local statsAlive = true

task.spawn(function()
    while statsAlive do
        local t = statsText()
        setStat(sKills, t.kills)
        setStat(sRate, t.rate)
        setStat(sShots, t.shots)
        setStat(sTime, t.time)
        task.wait(1)
    end
end)

local espSession = 0
local espObjects = {}

local function clearESP()
    for _, e in pairs(espObjects) do
        e.h:Destroy()
        e.g:Destroy()
    end
    table.clear(espObjects)
end

local function addESP(m, isBoss)
    local h = Instance.new("Highlight")
    h.Adornee = m
    h.FillColor = isBoss and Color3.fromRGB(255, 170, 0) or Color3.fromRGB(255, 50, 50)
    h.OutlineColor = Color3.fromRGB(255, 255, 255)
    h.FillTransparency = 0.5
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = m

    local g = Instance.new("BillboardGui")
    g.Adornee = m.Head
    g.AlwaysOnTop = true
    g.Size = UDim2.fromOffset(90, 14)
    g.StudsOffset = Vector3.new(0, 2.2, 0)
    g.Parent = m.Head

    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Size = UDim2.fromScale(1, 1)
    t.Font = Enum.Font.GothamMedium
    t.TextSize = 11
    t.Text = m.Name
    t.TextColor3 = Color3.fromRGB(255, 255, 255)
    t.TextStrokeTransparency = 0.5
    t.Parent = g

    espObjects[m] = {h = h, g = g}
end

visualTab:Section("ESP")

visualTab:Toggle("Zombie ESP", false, function(state)
    config.ESP = state
    espSession += 1
    local current = espSession

    if not state then
        clearESP()
        return
    end

    task.spawn(function()
        while config.ESP and espSession == current do
            for _, folder in ipairs(allFolders) do
                for _, m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and isAlive(m) and not espObjects[m] then
                        addESP(m, folder == bossFolder)
                    end
                end
            end
            for m, e in pairs(espObjects) do
                if not isAlive(m) then
                    e.h:Destroy()
                    e.g:Destroy()
                    espObjects[m] = nil
                end
            end
            task.wait(0.5)
        end
    end)
end)

miscTab:Section("Utility")

miscTab:Toggle("Anti AFK", config.AntiAFK, function(state)
    config.AntiAFK = state
end)

local idledConnection = player.Idled:Connect(function()
    if config.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

local function parseArgs(raw)
    local args = {}
    if raw == "" then
        return args
    end
    for piece in raw:gmatch("[^,]+") do
        local s = piece:match("^%s*(.-)%s*$")
        local n = tonumber(s)
        if n then
            table.insert(args, n)
        elseif s == "true" then
            table.insert(args, true)
        elseif s == "false" then
            table.insert(args, false)
        else
            table.insert(args, (s:gsub("^[\"'](.*)[\"']$", "%1")))
        end
    end
    return args
end

local function scanRemotes()
    local found = {}
    local keywords = {"shop", "buy", "purchase", "upgrade", "weapon", "gun", "ammo", "perk", "unlock", "equip"}
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
            local n = d.Name:lower()
            for _, k in ipairs(keywords) do
                if n:find(k, 1, true) then
                    table.insert(found, d.Name)
                    break
                end
            end
        end
    end
    return found
end

local buySession = 0

miscTab:Section("Auto Buy / Upgrade")

miscTab:Textbox("Remote Name", true, function(t)
    config.BuyRemote = t
end)

miscTab:Textbox("Arguments (comma separated)", true, function(t)
    config.BuyArgs = t
end)

miscTab:Slider("Buy Interval (s)", 1, 30, math.clamp(config.BuyDelay, 1, 30), function(v)
    config.BuyDelay = v
end)

miscTab:Toggle("Buy Only Between Waves", config.BuyBetweenWaves, function(state)
    config.BuyBetweenWaves = state
end)

miscTab:Toggle("Auto Buy", false, function(state)
    config.AutoBuy = state
    buySession += 1
    local current = buySession

    if not state then
        return
    end

    task.spawn(function()
        while config.AutoBuy and buySession == current do
            if config.BuyRemote ~= "" and (not config.BuyBetweenWaves or isIdle) then
                local remote = ReplicatedStorage:FindFirstChild(config.BuyRemote, true)
                if remote then
                    local args = parseArgs(config.BuyArgs)
                    pcall(function()
                        if remote:IsA("RemoteFunction") then
                            remote:InvokeServer(table.unpack(args))
                        elseif remote:IsA("RemoteEvent") then
                            remote:FireServer(table.unpack(args))
                        end
                    end)
                end
            end
            task.wait(config.BuyDelay)
        end
    end)
end)

miscTab:Button("Scan Shop Remotes", function()
    local found = scanRemotes()
    if #found == 0 then
        lib:Notification("Remotes", "No matching remotes found.", 4)
        return
    end
    if typeof(setclipboard) == "function" then
        setclipboard(table.concat(found, "\n"))
    end
    lib:Notification("Remotes", table.concat(found, ", ", 1, math.min(#found, 10)), 6)
end)

miscTab:Section("Scripts")
miscTab:Button("Infinite Yield", function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
end)
miscTab:Button("decompiler", function()
    loadstring(game:HttpGet("https://robloxscripts.com/raw/new-decompiler-lua-expert"))()
    lib:Notification("decompiler", "decompiler active", 3)
end)
miscTab:Button("Dex Recontinued", function()
    loadstring(game:HttpGet("https://github.com/Tesker-103/DexRecontinued/releases/latest/download/out.lua"))()
end)

miscTab:Section("Info")
miscTab:Label("created by: @nondevelopers")
miscTab:Label("Discord: nonfq")
miscTab:Label("Version: v2")

settingsTab:Section("Appearance")

local accentPicker = settingsTab:Colorpicker("Change UI Color", accentFor(THEME), function(t)
    lib:ChangePresetColor(Color3.fromRGB(t.R * 255, t.G * 255, t.B * 255))
end)

settingsTab:Dropdown("Theme", {"Dark", "Light", "Black"}, function(t)
    lib:SetTheme(t)
    accentPicker:Set(accentFor(t))
end)

settingsTab:Section("Config")

settingsTab:Button("Save Config", function()
    if saveConfig() then
        lib:Notification("Config", "Saved.", 3)
    else
        lib:Notification("Config", "Save failed (no file access).", 4)
    end
end)

settingsTab:Button("Load Config", function()
    if loadConfig() then
        lib:Notification("Config", "Loaded. Sliders sync on next execute.", 4)
    else
        lib:Notification("Config", "No saved config found.", 4)
    end
end)

settingsTab:Section("Danger Zone")

settingsTab:Button("Fully Close", function()
    stopFarm()
    statsAlive = false
    config.ESP = false
    espSession += 1
    clearESP()
    config.AutoBuy = false
    buySession += 1
    idledConnection:Disconnect()
    lib:Destroy()
end)

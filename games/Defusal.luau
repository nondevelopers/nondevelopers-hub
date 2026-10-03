local ALLOWED_ID = 79393329652220

local cref = cloneref or function(x) return x end
local Players = cref(game:GetService("Players"))
local LocalPlayer = Players.LocalPlayer

if game.PlaceId ~= ALLOWED_ID and game.GameId ~= ALLOWED_ID then
    LocalPlayer:Kick("This script only works in the game it was made for.")
    return
end

local genv = (getgenv and getgenv()) or _G

if genv.__DefusalMenu then
    pcall(genv.__DefusalMenu)
    genv.__DefusalMenu = nil
end

local RunService = cref(game:GetService("RunService"))
local CoreGui = cref(game:GetService("CoreGui"))
local Workspace = cref(game:GetService("Workspace"))

local okLib, lib = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/nondevelopers/Vape-UiLibrary/main/source.luau"))()
end)
if not okLib or not lib then
    warn("[Defusal Menu] Could not load the UI library: " .. tostring(lib))
    return
end

local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
if not hasDrawing then
    warn("[Defusal Menu] Drawing library not found: ESP boxes and health bars are unavailable. Chams still work.")
end

local Settings = {
    Enabled = false,
    Sticky = true,
    TeamCheck = true,
    WallCheck = true,
    LockHead = true,
    ShowFOV = true,
    FOVSize = "Medium",
    Boxes = false,
    Health = false,
    Chams = false,
    NoRec = false,
    InfAmo = false,
    RapidFire = false,
}

local FOV_SIZES = {Small = 80, Medium = 150, Large = 250}
local RELEASE_MULT = 1.6
local WALL_GRACE = 0.3
local DEFAULT_COLOR = Color3.fromRGB(255, 70, 70)
local LOCK_NAME = "DefusalMenuLock"

local alive = true
local connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end

local gui = Instance.new("ScreenGui")
gui.Name = "DefusalMenuESP"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999
local okParent = pcall(function() gui.Parent = (gethui and gethui()) or CoreGui end)
if not okParent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local fovCircle
if hasDrawing then
    fovCircle = Drawing.new("Circle")
    fovCircle.Thickness = 1
    fovCircle.NumSides = 64
    fovCircle.Filled = false
    fovCircle.Visible = false
    fovCircle.Color = Color3.fromRGB(255, 255, 255)
end

local TEAM_ATTRS = {"Team", "TeamName", "TeamId", "TeamID", "team", "Side", "Faction"}

local function attrOf(obj)
    if not obj then return nil end
    for _, name in ipairs(TEAM_ATTRS) do
        local v = obj:GetAttribute(name)
        if v ~= nil then return v end
    end
    return nil
end

local function valueOf(obj)
    if not obj then return nil end
    for _, name in ipairs(TEAM_ATTRS) do
        local c = obj:FindFirstChild(name)
        if c and c:IsA("ValueBase") then return c.Value end
    end
    return nil
end

local function statsOf(plr)
    local ls = plr:FindFirstChild("leaderstats")
    return valueOf(ls)
end

local function highlightOf(plr)
    local char = plr.Character
    local hl = char and char:FindFirstChildOfClass("Highlight")
    return hl and hl.FillColor or nil
end

local teamSources = {
    function(p) return p.Team end,
    function(p) if not p.Neutral then return p.TeamColor end end,
    function(p) return attrOf(p) end,
    function(p) return attrOf(p.Character) end,
    function(p) return valueOf(p) end,
    function(p) return valueOf(p.Character) end,
    statsOf,
    highlightOf,
}

local function isTeammate(plr)
    for _, source in ipairs(teamSources) do
        local okA, a = pcall(source, LocalPlayer)
        local okB, b = pcall(source, plr)
        if okA and okB and a ~= nil and b ~= nil then
            return a == b
        end
    end
    return false
end

local function getColor(plr)
    if plr.Team and plr.TeamColor then
        return plr.TeamColor.Color
    end
    return DEFAULT_COLOR
end

local function isVisible(part, char, camera)
    local ignore = {LocalPlayer.Character, camera}
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.IgnoreWater = true
    local origin = camera.CFrame.Position
    local direction = part.Position - origin
    for _ = 1, 6 do
        params.FilterDescendantsInstances = ignore
        local hit = Workspace:Raycast(origin, direction, params)
        if not hit then return true end
        local inst = hit.Instance
        if inst:IsDescendantOf(char) then return true end
        if inst.Transparency >= 0.95 or not inst.CanCollide then
            ignore[#ignore + 1] = inst
        else
            return false
        end
    end
    return false
end

local function getAimPart(char)
    if Settings.LockHead then
        return char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
    end
    return char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Head")
end

local currentTarget = nil
local lastSeen = 0

local function evaluate(plr, camera, point, radius, skipWall)
    if plr == LocalPlayer then return nil end
    local char = plr.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health > 0) then return nil end
    local part = getAimPart(char)
    if not part then return nil end
    if Settings.TeamCheck and isTeammate(plr) then return nil end
    local sp, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen then return nil end
    local dist = (Vector2.new(sp.X, sp.Y) - point).Magnitude
    if dist > radius then return nil end
    if Settings.WallCheck and not skipWall and not isVisible(part, char, camera) then return nil end
    return part, dist
end

local function getTarget(camera, point)
    local fov = FOV_SIZES[Settings.FOVSize]
    if Settings.Sticky and currentTarget then
        local part = evaluate(currentTarget, camera, point, fov * RELEASE_MULT, false)
        if part then
            lastSeen = os.clock()
            return part
        end
        if os.clock() - lastSeen < WALL_GRACE then
            local held = evaluate(currentTarget, camera, point, fov * RELEASE_MULT, true)
            if held then return held end
        end
        currentTarget = nil
    end
    local best, bestDist, bestPlr
    for _, plr in ipairs(Players:GetPlayers()) do
        local part, dist = evaluate(plr, camera, point, fov, false)
        if part and (not bestDist or dist < bestDist) then
            best, bestDist, bestPlr = part, dist, plr
        end
    end
    currentTarget = bestPlr
    if best then lastSeen = os.clock() end
    return best
end

local objects = {}

local function newDrawing(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props) do d[k] = v end
    return d
end

local function createObjects(plr)
    if objects[plr] then return end
    local o = {}
    if hasDrawing then
        o.BoxOutline = newDrawing("Square", {Thickness = 3, Filled = false, Visible = false, ZIndex = 1, Color = Color3.new(0, 0, 0)})
        o.Box = newDrawing("Square", {Thickness = 1, Filled = false, Visible = false, ZIndex = 2, Color = DEFAULT_COLOR})
        o.HealthBG = newDrawing("Line", {Thickness = 4, Visible = false, ZIndex = 1, Color = Color3.new(0, 0, 0)})
        o.HealthBar = newDrawing("Line", {Thickness = 2, Visible = false, ZIndex = 2, Color = Color3.fromRGB(0, 255, 0)})
    end
    local hl = Instance.new("Highlight")
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled = false
    hl.Parent = gui
    o.Highlight = hl
    objects[plr] = o
end

local function hide(o)
    for key, obj in pairs(o) do
        if key == "Highlight" then
            obj.Enabled = false
            obj.Adornee = nil
        else
            obj.Visible = false
        end
    end
end

local function removeObjects(plr)
    local o = objects[plr]
    if not o then return end
    for key, obj in pairs(o) do
        if key == "Highlight" then
            obj:Destroy()
        else
            pcall(function() obj:Remove() end)
        end
    end
    objects[plr] = nil
end

local function readHealth(plr, char, hum)
    local h = char:GetAttribute("Health") or plr:GetAttribute("Health")
    local m = char:GetAttribute("MaxHealth") or plr:GetAttribute("MaxHealth")
    if type(h) == "number" then
        return h, type(m) == "number" and m or hum.MaxHealth
    end
    local hv = char:FindFirstChild("Health") or plr:FindFirstChild("Health")
    if hv and hv:IsA("ValueBase") and type(hv.Value) == "number" then
        local mv = char:FindFirstChild("MaxHealth") or plr:FindFirstChild("MaxHealth")
        local max = (mv and mv:IsA("ValueBase") and type(mv.Value) == "number") and mv.Value or hum.MaxHealth
        return hv.Value, max
    end
    return hum.Health, hum.MaxHealth
end

local function updateESP(camera)
    for plr, o in pairs(objects) do
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        local hum = char and char:FindFirstChildOfClass("Humanoid")

        local valid = hrp and head and hum and hum.Health > 0
        if valid and Settings.TeamCheck and isTeammate(plr) then
            valid = false
        end

        if not valid then
            hide(o)
        else
            local color = getColor(plr)

            if Settings.Chams then
                o.Highlight.Adornee = char
                o.Highlight.FillColor = color
                o.Highlight.OutlineColor = color
                o.Highlight.Enabled = true
            else
                o.Highlight.Enabled = false
            end

            if hasDrawing then
                local rootPos, onScreen = camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local top = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.7, 0))
                    local bottom = camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                    local height = math.abs(bottom.Y - top.Y)
                    local width = height / 1.6
                    local x = rootPos.X - width / 2
                    local y = top.Y

                    o.Box.Visible = Settings.Boxes
                    o.BoxOutline.Visible = Settings.Boxes
                    if Settings.Boxes then
                        o.Box.Size = Vector2.new(width, height)
                        o.Box.Position = Vector2.new(x, y)
                        o.Box.Color = color
                        o.BoxOutline.Size = o.Box.Size
                        o.BoxOutline.Position = o.Box.Position
                    end

                    o.HealthBG.Visible = Settings.Health
                    o.HealthBar.Visible = Settings.Health
                    if Settings.Health then
                        local hp, maxHp = readHealth(plr, char, hum)
                        local pct = math.clamp(hp / math.max(maxHp, 1), 0, 1)
                        local bx = x - 5
                        o.HealthBG.From = Vector2.new(bx, y + height + 1)
                        o.HealthBG.To = Vector2.new(bx, y - 1)
                        o.HealthBar.From = Vector2.new(bx, y + height)
                        o.HealthBar.To = Vector2.new(bx, y + height - height * pct)
                        o.HealthBar.Color = Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 255, 0), pct)
                    end
                else
                    o.Box.Visible = false
                    o.BoxOutline.Visible = false
                    o.HealthBG.Visible = false
                    o.HealthBar.Visible = false
                end
            end
        end
    end
end

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then createObjects(plr) end
end
connect(Players.PlayerAdded, function(plr)
    if plr ~= LocalPlayer then createObjects(plr) end
end)
connect(Players.PlayerRemoving, function(plr)
    if currentTarget == plr then currentTarget = nil end
    removeObjects(plr)
end)

connect(RunService.RenderStepped, function()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    updateESP(camera)
    if fovCircle then
        fovCircle.Visible = Settings.Enabled and Settings.ShowFOV
        fovCircle.Position = camera.ViewportSize / 2
        fovCircle.Radius = FOV_SIZES[Settings.FOVSize]
    end
end)

RunService:BindToRenderStep(LOCK_NAME, Enum.RenderPriority.Last.Value, function()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    if not Settings.Enabled then
        currentTarget = nil
        return
    end
    local part = getTarget(camera, camera.ViewportSize / 2)
    if not part then return end
    camera.CFrame = CFrame.new(camera.CFrame.Position, part.Position)
end)

local recoilWords = {"recoil", "spread", "sway", "bloom", "kick"}

local ammoNames = {}
for _, n in ipairs({
    "ammo", "currentammo", "curammo", "clipammo", "magammo", "ammoinclip", "storedammo",
    "reserveammo", "totalammo", "bullets", "maxammo", "clipsize", "magsize", "magazinesize",
}) do ammoNames[n] = true end

local rateNames = {}
for _, n in ipairs({
    "firerate", "fire_rate", "rpm", "firedelay", "shootdelay", "shootcooldown",
    "firecooldown", "rateoffire", "rof", "cooldown",
}) do rateNames[n] = true end

local classCache = {}

local function classify(key)
    local cached = classCache[key]
    if cached ~= nil then
        if cached then return cached[1], cached[2] end
        return nil
    end
    local lk = string.lower(key)
    local kind
    for _, w in ipairs(recoilWords) do
        if lk:find(w, 1, true) then kind = "recoil" break end
    end
    if not kind and ammoNames[lk] then kind = "ammo" end
    if not kind and rateNames[lk] then kind = "rate" end
    if kind then
        classCache[key] = {kind, lk}
        return kind, lk
    end
    classCache[key] = false
    return nil
end

local function kindEnabled(kind)
    return (kind == "recoil" and Settings.NoRec)
        or (kind == "ammo" and Settings.InfAmo)
        or (kind == "rate" and Settings.RapidFire)
end

local function anyGunMod()
    return Settings.NoRec or Settings.InfAmo or Settings.RapidFire
end

local function unlock(t)
    if isreadonly and isreadonly(t) and setreadonly then
        pcall(setreadonly, t, false)
    end
end

local originals = setmetatable({}, {__mode = "k"})

local function writeValue(container, key, mode, value)
    if mode == "table" then
        unlock(container)
        rawset(container, key, value)
    elseif mode == "value" then
        container.Value = value
    else
        container:SetAttribute(key, value)
    end
end

local function remember(container, key, rec)
    local map = originals[container]
    if not map then
        map = {}
        originals[container] = map
    end
    map[key] = rec
    return rec
end

local function applyValue(container, key, current, mode)
    local kind, lk = classify(key)
    if not kind or not kindEnabled(kind) then return end
    local map = originals[container]
    local rec = map and map[key]
    local t = typeof(current)

    if kind == "recoil" then
        if t == "number" then
            if current ~= 0 then
                if not rec then remember(container, key, {kind = kind, mode = mode, val = current}) end
                writeValue(container, key, mode, 0)
            end
        elseif t == "Vector3" or t == "Vector2" then
            local zero = t == "Vector3" and Vector3.zero or Vector2.zero
            if current ~= zero then
                if not rec then remember(container, key, {kind = kind, mode = mode, val = current}) end
                writeValue(container, key, mode, zero)
            end
        elseif t == "table" and mode == "table" then
            local saved = rec and rec.val or {}
            local changed = false
            unlock(current)
            for k, v in next, current do
                if type(v) == "number" and v ~= 0 then
                    if saved[k] == nil then saved[k] = v end
                    rawset(current, k, 0)
                    changed = true
                end
            end
            if changed and not rec then
                remember(container, key, {kind = kind, mode = mode, nested = current, val = saved})
            end
        end
        return
    end

    if t ~= "number" then return end
    if not rec then rec = remember(container, key, {kind = kind, mode = mode, val = current}) end
    local newValue
    if kind == "ammo" then
        newValue = 99999
    elseif lk:find("rpm", 1, true) or lk:find("rof", 1, true) or rec.val > 20 then
        newValue = 3000
    else
        newValue = 0.02
    end
    if current ~= newValue then
        writeValue(container, key, mode, newValue)
    end
end

local function restoreDisabled()
    for container, map in pairs(originals) do
        for key, rec in pairs(map) do
            if not kindEnabled(rec.kind) then
                if rec.nested then
                    pcall(function()
                        unlock(rec.nested)
                        for k, v in pairs(rec.val) do rawset(rec.nested, k, v) end
                    end)
                else
                    pcall(writeValue, container, key, rec.mode, rec.val)
                end
                map[key] = nil
            end
        end
    end
end

local gunTables = {}
local scanRequested = true
local lastScan = 0

local function requestScan()
    scanRequested = true
end

local function usable(kind, v)
    local t = typeof(v)
    if kind == "recoil" then
        return t == "number" or t == "Vector3" or t == "Vector2" or t == "table"
    end
    return t == "number"
end

local function scanGC()
    if type(getgc) ~= "function" then return end
    local found = {}
    local n = 0
    for _, obj in ipairs(getgc(true)) do
        n += 1
        if n % 3000 == 0 then task.wait() end
        if type(obj) == "table" and obj ~= Settings and obj ~= originals and obj ~= gunTables and obj ~= classCache then
            local keys = {}
            pcall(function()
                for k, v in next, obj do
                    if type(k) == "string" then
                        local kind = classify(k)
                        if kind and usable(kind, v) then keys[#keys + 1] = k end
                    end
                end
            end)
            if #keys >= 2 then found[#found + 1] = {tbl = obj, keys = keys} end
        end
    end
    gunTables = found
end

local toolConns = {}
local toolTargets = {}

local function clearTool()
    for _, c in ipairs(toolConns) do pcall(function() c:Disconnect() end) end
    table.clear(toolConns)
    table.clear(toolTargets)
end

local function liveKind(name)
    local kind = classify(name)
    if kind ~= "ammo" then return kind end
    return nil
end

local function trackInstance(inst)
    if (inst:IsA("IntValue") or inst:IsA("NumberValue")) and liveKind(inst.Name) then
        toolTargets[#toolTargets + 1] = {inst = inst, key = inst.Name, mode = "value"}
        toolConns[#toolConns + 1] = inst:GetPropertyChangedSignal("Value"):Connect(function()
            if anyGunMod() then pcall(applyValue, inst, inst.Name, inst.Value, "value") end
        end)
    end
    for name, val in pairs(inst:GetAttributes()) do
        if type(val) == "number" and liveKind(name) then
            toolTargets[#toolTargets + 1] = {inst = inst, key = name, mode = "attr"}
            toolConns[#toolConns + 1] = inst:GetAttributeChangedSignal(name):Connect(function()
                local cur = inst:GetAttribute(name)
                if type(cur) == "number" and anyGunMod() then pcall(applyValue, inst, name, cur, "attr") end
            end)
        end
    end
end

local function refreshTool()
    clearTool()
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return end
    trackInstance(tool)
    for _, d in ipairs(tool:GetDescendants()) do trackInstance(d) end
    toolConns[#toolConns + 1] = tool.DescendantAdded:Connect(function(d)
        trackInstance(d)
    end)
end

local function applyAll()
    if not anyGunMod() then return end
    for _, tgt in ipairs(toolTargets) do
        local inst = tgt.inst
        if inst.Parent then
            local cur
            if tgt.mode == "value" then cur = inst.Value else cur = inst:GetAttribute(tgt.key) end
            if type(cur) == "number" then applyValue(inst, tgt.key, cur, tgt.mode) end
        end
    end
    for _, entry in ipairs(gunTables) do
        local t = entry.tbl
        for _, k in ipairs(entry.keys) do
            local v = rawget(t, k)
            if v ~= nil and classify(k) ~= "ammo" then applyValue(t, k, v, "table") end
        end
    end
end

local function applyAmmoOld()
    if not Settings.InfAmo then return end
    for _, entry in ipairs(gunTables) do
        pcall(function()
            for k, v in next, entry.tbl do
                if type(k) == "string" and type(v) == "number" and classify(k) == "ammo" then
                    applyValue(entry.tbl, k, v, "table")
                end
            end
        end)
    end
    local char = LocalPlayer.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return end
    local function attrs(inst)
        for name, val in pairs(inst:GetAttributes()) do
            if type(val) == "number" and classify(name) == "ammo" then
                applyValue(inst, name, val, "attr")
            end
        end
    end
    attrs(tool)
    for _, inst in ipairs(tool:GetDescendants()) do
        if inst:IsA("ValueBase") and type(inst.Value) == "number" and classify(inst.Name) == "ammo" then
            applyValue(inst, inst.Name, inst.Value, "value")
        end
        attrs(inst)
    end
end

connect(RunService.Heartbeat, function() pcall(applyAll) end)
connect(RunService.RenderStepped, function() pcall(applyAll) end)

local function onCharacter(char)
    connect(char.ChildAdded, function(c)
        if c:IsA("Tool") then
            refreshTool()
            requestScan()
        end
    end)
    connect(char.ChildRemoved, function(c)
        if c:IsA("Tool") then refreshTool() end
    end)
    refreshTool()
end

if LocalPlayer.Character then onCharacter(LocalPlayer.Character) end
connect(LocalPlayer.CharacterAdded, function(char)
    onCharacter(char)
    requestScan()
end)

task.spawn(function()
    while alive do
        if anyGunMod() and (scanRequested or os.clock() - lastScan > 3) then
            scanRequested = false
            lastScan = os.clock()
            pcall(scanGC)
        end
        pcall(restoreDisabled)
        pcall(applyAmmoOld)
        task.wait(0.1)
    end
end)

local THEME = "Black"
local function accentFor(theme)
    return theme == "Light" and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
end

local win = lib:Window(
    "Defusal Menu",
    accentFor(THEME),
    Enum.KeyCode.RightControl,
    Vector2.new(480, 270),
    0.1,
    THEME
)

local aimTab = win:Tab("Aimbot", "crosshair")
aimTab:Section("Lock")
aimTab:Toggle("Aimbot", Settings.Enabled, function(t) Settings.Enabled = t end)
aimTab:Toggle("Sticky Lock", Settings.Sticky, function(t) Settings.Sticky = t end)
aimTab:Toggle("Lock Head (off = torso)", Settings.LockHead, function(t) Settings.LockHead = t end)
aimTab:Section("Checks")
aimTab:Toggle("Team Check", Settings.TeamCheck, function(t) Settings.TeamCheck = t end)
aimTab:Toggle("Wall Check", Settings.WallCheck, function(t) Settings.WallCheck = t end)
aimTab:Section("FOV")
aimTab:Toggle("Show FOV Circle", Settings.ShowFOV, function(t) Settings.ShowFOV = t end)
aimTab:Dropdown("FOV Size", {"Small", "Medium", "Large"}, function(t) Settings.FOVSize = t end)

local visTab = win:Tab("Visuals", "eye")
visTab:Section("ESP")
visTab:Toggle("Boxes", Settings.Boxes, function(t) Settings.Boxes = t end)
visTab:Toggle("Health Bars", Settings.Health, function(t) Settings.Health = t end)
visTab:Toggle("Chams", Settings.Chams, function(t) Settings.Chams = t end)
if not hasDrawing then
    visTab:Label("Boxes and health bars need the Drawing library")
end

local gunTab = win:Tab("Gun", "wrench")
gunTab:Section("Weapon")
gunTab:Toggle("No Recoil", Settings.NoRec, function(t)
    Settings.NoRec = t
    requestScan()
end)
gunTab:Toggle("Infinite Ammo", Settings.InfAmo, function(t)
    Settings.InfAmo = t
    requestScan()
end)
gunTab:Toggle("Fire Rate", Settings.RapidFire, function(t)
    Settings.RapidFire = t
    requestScan()
end)

local setTab = win:Tab("Settings", "settings")
setTab:Section("Appearance")
local accentPicker = setTab:Colorpicker("UI Color", accentFor(THEME), function(c)
    lib:ChangePresetColor(Color3.fromRGB(c.R * 255, c.G * 255, c.B * 255))
end)
setTab:Dropdown("Theme", {"Dark", "Light", "Black"}, function(t)
    lib:SetTheme(t)
    accentPicker:Set(accentFor(t))
end)
setTab:Section("Danger Zone")

local function destroy()
    alive = false
    pcall(function() RunService:UnbindFromRenderStep(LOCK_NAME) end)
    Settings.NoRec, Settings.InfAmo, Settings.RapidFire = false, false, false
    pcall(restoreDisabled)
    clearTool()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    for plr in pairs(objects) do removeObjects(plr) end
    if fovCircle then pcall(function() fovCircle:Remove() end) end
    pcall(function() gui:Destroy() end)
    pcall(function() lib:Destroy() end)
end

setTab:Button("Fully Close", function()
    genv.__DefusalMenu = nil
    destroy()
end)

genv.__DefusalMenu = destroy
lib:Notification("Defusal Menu", "Loaded. Press Right Ctrl to hide the menu.")

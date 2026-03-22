-- V1perThrow - TRUE SILENT AIM (Camera spoofing without visual movement)
-- The camera changes but you won't see it move because it happens in 1 frame
-- Run this as a LocalScript via your executor

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

local Actors  = require(ReplicatedStorage.Modules.Actors)
local Network = require(ReplicatedStorage.Modules.Network)
local Util    = require(ReplicatedStorage.Modules.Util)

-- ════════════════════════════════════════
--   PLATFORM DETECTION
-- ════════════════════════════════════════

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ════════════════════════════════════════
--   RUNTIME STATE
-- ════════════════════════════════════════

local enabled     = false
local aimbotOn    = false
local patched     = false
local crystalCB   = nil
local unloaded    = false

local AIM_OFFSET     = -0.3
local AIM_OFFSET_MIN = -5.0
local AIM_OFFSET_MAX =  5.0

local PREDICTION     = 0.6
local PREDICTION_MIN = 0.0
local PREDICTION_MAX = 1.0

local killerMotionData = {}

-- ════════════════════════════════════════
--   CONFIG SYSTEM
-- ════════════════════════════════════════

local fs = {
    hasFolder  = isfolder   or function() return false end,
    makeFolder = makefolder or function() end,
    write      = writefile  or function() end,
    hasFile    = isfile     or function() return false end,
    read       = readfile   or function() return "" end,
}
local Config = {}
do
    local DIR  = "V1perThrow"
    local FILE = DIR .. "/config.json"
    local hs   = game:GetService("HttpService")
    local function prep()
        if not fs.hasFolder(DIR) then fs.makeFolder(DIR) end
    end
    function Config.load()
        prep()
        if not fs.hasFile(FILE) then return end
        local raw = fs.read(FILE)
        if not raw or raw == "" then return end
        local ok, t = pcall(hs.JSONDecode, hs, raw)
        if ok and type(t) == "table" then
            for k, v in pairs(t) do Config._data[k] = v end
        end
    end
    function Config.save()
        prep()
        local ok, s = pcall(hs.JSONEncode, hs, Config._data)
        if ok and s and s ~= "" then pcall(fs.write, FILE, s) end
    end
    function Config.get(k, default)
        local v = Config._data[k]
        if v == nil then return default end
        return v
    end
    function Config.set(k, v) Config._data[k] = v; Config.save() end
    Config._data = {}
    Config.load()
end

enabled       = Config.get("enabled",      false)
aimbotOn      = Config.get("aimbotOn",     false)
AIM_OFFSET    = Config.get("aimOffset",    AIM_OFFSET)
PREDICTION    = Config.get("prediction",   PREDICTION)

-- ════════════════════════════════════════
--   KILLER TRACKING
-- ════════════════════════════════════════

local function getKillerVelocity(hrp)
    local now  = tick()
    local pos  = hrp.Position
    local data = killerMotionData[hrp]
    if not data then
        killerMotionData[hrp] = { lastPos = pos, lastTime = now, velocity = Vector3.zero }
        return Vector3.zero
    end
    local dt = now - data.lastTime
    if dt <= 0 then return data.velocity end
    local vel     = (pos - data.lastPos) / dt
    data.lastPos  = pos
    data.lastTime = now
    data.velocity = vel
    return vel
end

local function getNearestKiller(fromPos)
    local folder = workspace:FindFirstChild("Players")
    folder = folder and folder:FindFirstChild("Killers")
    if not folder then return nil end
    local nearest, best = nil, math.huge
    for _, model in ipairs(folder:GetChildren()) do
        local hrp = model:FindFirstChild("HumanoidRootPart")
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hrp and hum and hum.Health > 0 then
            local d = (hrp.Position - fromPos).Magnitude
            if d < best then best = d; nearest = model end
        end
    end
    return nearest
end

-- ════════════════════════════════════════
--   SILENT AIM (Instant Camera Spoof)
-- ════════════════════════════════════════

local function calculateAimCFrame(myHRP, killerHRP, abilityCfg)
    local vel = getKillerVelocity(killerHRP)
    
    if isMobile then
        -- Mobile ballistic calculation
        local v0 = abilityCfg.MaxSpeed
        local g  = abilityCfg.ProjectileArc
        
        local hum = myHRP.Parent and myHRP.Parent:FindFirstChildOfClass("Humanoid")
        local hipH = hum and hum.HipHeight or 1.35
        local v238 = (hipH + myHRP.Size.Y / 2) / 2
        
        local spawnPos = myHRP.CFrame.Position + Vector3.new(0, v238, 0)
        local predicted = killerHRP.Position + vel * PREDICTION
        local target = predicted + Vector3.new(0, AIM_OFFSET, 0)
        
        local delta = target - spawnPos
        local flatV = Vector3.new(delta.X, 0, delta.Z)
        local dx = flatV.Magnitude
        local dy = delta.Y
        
        if dx < 0.01 then
            local straight = dy >= 0 and Vector3.new(0, 1, 0) or Vector3.new(0, -1, 0)
            return CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + straight)
        end
        
        local flatDir = flatV.Unit
        local v2 = v0 * v0
        local v4 = v2 * v2
        local disc = v4 - g * (g * dx * dx + 2 * dy * v2)
        
        local theta
        if disc < 0 then
            theta = math.atan2(dy, dx)
        else
            theta = math.atan2(v2 - math.sqrt(disc), g * dx)
        end
        
        local T = math.tan(theta)
        local denom = 3 + T
        local alpha
        if math.abs(denom) < 0.0001 then
            alpha = -math.pi / 2
        else
            alpha = math.atan2(3 * T - 1, denom)
        end
        
        local yawCF = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + flatDir)
        local pitchCF = CFrame.Angles(alpha, 0, 0)
        
        return yawCF * pitchCF
    else
        -- PC direct aim
        local aimPoint = killerHRP.Position + vel * PREDICTION
        aimPoint = Vector3.new(aimPoint.X, Camera.CFrame.Position.Y + AIM_OFFSET, aimPoint.Z)
        
        return CFrame.lookAt(Camera.CFrame.Position, aimPoint)
    end
end

local function silentAimAndFire(myHRP, killerHRP, fireCallback, abilityCfg)
    -- Store original camera
    local originalCF = Camera.CFrame
    local originalType = Camera.CameraType
    
    -- Calculate aim
    local aimCF = calculateAimCFrame(myHRP, killerHRP, abilityCfg)
    
    -- Set camera to scriptable and aim (happens in 1 frame - invisible to player)
    Camera.CameraType = Enum.CameraType.Scriptable
    Camera.CFrame = aimCF
    
    -- Wait ONE frame for server to register
    RunService.RenderStepped:Wait()
    
    -- Fire the crystal (server reads our spoofed camera)
    fireCallback()
    
    -- Immediately restore camera (next frame - player never sees the change)
    RunService.RenderStepped:Wait()
    Camera.CFrame = originalCF
    Camera.CameraType = originalType
end

-- ════════════════════════════════════════
--   DISPATCHER
-- ════════════════════════════════════════

local function aimAndFire(myHRP, fireCallback, abilityCfg)
    local killer = getNearestKiller(myHRP.Position)
    if not killer then fireCallback() return end

    local killerHRP = killer:FindFirstChild("HumanoidRootPart")
    if not killerHRP then fireCallback() return end

    silentAimAndFire(myHRP, killerHRP, fireCallback, abilityCfg)
end

-- ════════════════════════════════════════
--   PATCH LOGIC
-- ════════════════════════════════════════

local function getLocalActor()
    for _, actor in Actors.CurrentActors do
        if actor.Player == LocalPlayer then return actor end
    end
    return nil
end

local function applyPatch(actor)
    if patched or not actor or not actor.Behavior then return end
    if not actor.Behavior.Abilities or not actor.Behavior.Abilities.Crystal then return end

    crystalCB = actor.Behavior.Abilities.Crystal.Callback

    actor.Behavior.Abilities.Crystal.Callback = function(self, p290)
        if RunService:IsServer() then return crystalCB(self, p290) end
        if not enabled then return crystalCB(self, p290) end
        if p290 == "Cancelled" or not p290 then return crystalCB(self, p290) end

        self.State.IsCrystalEquipped = true
        Util:ToggleLockForAbilityIcon("Axe", "JaneDoeCrystalEquipped", true)

        task.spawn(function()
            local abilityCfg = self.Config.Crystal
            task.wait(abilityCfg.ChannelTime + 0.05)

            if not (self.State.IsCrystalEquipped and enabled) then return end

            local function doFire()
                Network:FireServerConnection(
                    ("%sCrystalInput"):format(self.Player.Name),
                    "REMOTE_EVENT",
                    1
                )
            end

            if aimbotOn then
                local myHRP = self.Rig and self.Rig:FindFirstChild("HumanoidRootPart")
                if myHRP then
                    aimAndFire(myHRP, doFire, abilityCfg)
                else
                    doFire()
                end
            else
                doFire()
            end
        end)
    end

    patched = true
    print("[V1perThrow] Silent Aim patch active.")
end

local function removePatch(actor)
    if not patched or not actor then return end
    if not actor.Behavior or not actor.Behavior.Abilities then return end
    if not actor.Behavior.Abilities.Crystal then return end
    if crystalCB then
        actor.Behavior.Abilities.Crystal.Callback = crystalCB
        crystalCB = nil
    end
    patched = false
    print("[V1perThrow] Patch removed.")
end

-- ════════════════════════════════════════
--   WINDUI
-- ════════════════════════════════════════

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

local Window = WindUI:CreateWindow({
    Title  = "V1perThrow - Silent Aim",
    Icon   = "gem",
    Author = "V1perThrow",
    Folder = "V1perThrow",
    Theme  = "Dark",
})

if not isMobile then
    Window:SetToggleKey(Enum.KeyCode.K)
end

local Tab = Window:Tab({ Title = "Main", Icon = "crosshair" })

local StatusParagraph = Tab:Paragraph({
    Title   = "Status",
    Content = "Waiting for actor...",
})

local function setStatus(text)
    StatusParagraph:SetDesc(text)
end

Tab:Paragraph({
    Title   = "Mode",
    Content = "Silent Aim - Camera changes for 1 frame (invisible), shots auto-aim",
})

Tab:Paragraph({
    Title   = "Platform",
    Content = isMobile
        and "Mobile - Ballistic solver active"
        or  "PC - Silent aim active, press K to toggle UI",
})

Tab:Toggle({
    Title = "Enable Patch",
    Desc  = "Auto-fire Crystal when equipped",
    Icon  = "zap",
    Value = enabled,
    Callback = function(state)
        if unloaded then return end
        enabled = state
        Config.set("enabled", state)
        local actor = getLocalActor()
        if enabled and not patched and actor then applyPatch(actor) end
        setStatus(enabled and "Active" or "Inactive")
    end,
})

Tab:Toggle({
    Title = "Silent Aim",
    Desc  = "Auto-aim at killer (camera spoofs for 1 frame)",
    Icon  = "target",
    Value = aimbotOn,
    Callback = function(state)
        if unloaded then return end
        aimbotOn = state
        Config.set("aimbotOn", state)
        if not aimbotOn then
            killerMotionData = {}
        end
        local actor = getLocalActor()
        if aimbotOn and not patched and actor then applyPatch(actor) end
    end,
})

Tab:Divider()

Tab:Slider({
    Title = "Aim Offset",
    Desc  = "Y adjustment — 0 = center, negative = lower",
    Step  = 0.1,
    Value = { Min = AIM_OFFSET_MIN, Max = AIM_OFFSET_MAX, Default = AIM_OFFSET },
    Callback = function(v) AIM_OFFSET = v; Config.set("aimOffset", v) end,
})

Tab:Slider({
    Title = "Prediction",
    Desc  = "Lead time in seconds (0 = no prediction)",
    Step  = 0.01,
    Value = { Min = PREDICTION_MIN, Max = PREDICTION_MAX, Default = PREDICTION },
    Callback = function(v) PREDICTION = v; Config.set("prediction", v) end,
})

Tab:Divider()

local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })

SettingsTab:Button({
    Title = "Unload Script",
    Desc  = "Remove patch and close window",
    Icon  = "power",
    Callback = function()
        if unloaded then return end
        unloaded = true
        enabled  = false
        aimbotOn = false

        pcall(function() removePatch(getLocalActor()) end)

        WindUI:Notify({
            Title    = "V1perThrow",
            Content  = "Unloaded successfully.",
            Icon     = "check",
            Duration = 3,
        })

        task.delay(0.5, function() Window:Destroy() end)
        print("[V1perThrow] Unloaded.")
    end,
})

-- ════════════════════════════════════════
--   ACTOR WATCHER
-- ════════════════════════════════════════

task.spawn(function()
    setStatus("Waiting for actor...")
    local lastActor = nil

    while not unloaded do
        task.wait(0.5)
        if unloaded then break end

        local currentActor = getLocalActor()

        if currentActor ~= lastActor then
            if lastActor ~= nil then
                patched          = false
                crystalCB        = nil
                killerMotionData = {}
                print("[V1perThrow] New round — resetting.")
                WindUI:Notify({
                    Title    = "V1perThrow",
                    Content  = "New round — patch re-applied.",
                    Icon     = "refresh-cw",
                    Duration = 3,
                })
            end

            lastActor = currentActor

            if currentActor then
                if enabled then
                    applyPatch(currentActor)
                    setStatus("Active")
                else
                    setStatus("Ready — toggle to activate")
                end
                print("[V1perThrow] Ready.")
            else
                setStatus("Waiting for actor...")
            end
        end
    end
end)

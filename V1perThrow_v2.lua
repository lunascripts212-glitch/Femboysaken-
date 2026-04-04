-- V1perThrow w/ WindUI
-- Silent aim via __namecall detection — fires exactly when the crystal remote fires

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ════════════════════════════════════════
--   REMOTES
--   Full paths confirmed from explorer:
--   ReplicatedStorage.Modules.Network.Network.RemoteEvent
--   ReplicatedStorage.Modules.Network.Network.RemoteFunction
-- ════════════════════════════════════════

local RemoteEvent = ReplicatedStorage
    :WaitForChild("Modules")
    :WaitForChild("Network")
    :WaitForChild("Network")
    :WaitForChild("RemoteEvent")

local NetworkRF = nil
pcall(function()
    NetworkRF = ReplicatedStorage
        :WaitForChild("Modules", 10)
        :WaitForChild("Network", 10)
        :WaitForChild("Network", 10)
        :WaitForChild("RemoteFunction", 10)
end)

-- ════════════════════════════════════════
--   PLATFORM DETECTION
-- ════════════════════════════════════════

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ════════════════════════════════════════
--   RUNTIME STATE
-- ════════════════════════════════════════

local enabled  = false
local aimbotOn = false
local unloaded = false

local AIM_OFFSET     = -0.3
local AIM_OFFSET_MIN = -5.0
local AIM_OFFSET_MAX =  5.0

local PREDICTION     = 0.6
local PREDICTION_MIN = 0.0
local PREDICTION_MAX = 1.0

local HOLD_DURATION     = 0.9
local HOLD_DURATION_MIN = 0.3
local HOLD_DURATION_MAX = 2.0

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
HOLD_DURATION = Config.get("holdDuration", HOLD_DURATION)

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
--   BALLISTIC SOLVER
--
--   Server throw formula (from decompile):
--     throwDir ≈ (cam.LookVector + cam.UpVector/3).Unit
--   So camera pitch α must satisfy:
--     tan(α) = (3·tan(θ) − 1) / (3 + tan(θ))
--   where θ is the required ballistic pitch to hit the target.
-- ════════════════════════════════════════

local function buildCamCF(myHRP, killerHRP, v0, g)
    local hum      = myHRP.Parent and myHRP.Parent:FindFirstChildOfClass("Humanoid")
    local hipH     = hum and hum.HipHeight or 1.35
    local v238     = (hipH + myHRP.Size.Y / 2) / 2
    local spawnPos = myHRP.CFrame.Position + Vector3.new(0, v238, 0)

    local vel       = getKillerVelocity(killerHRP)
    local predicted = killerHRP.Position + vel * PREDICTION
    local target    = predicted + Vector3.new(0, AIM_OFFSET, 0)

    local delta = target - spawnPos
    local flatV = Vector3.new(delta.X, 0, delta.Z)
    local dx    = flatV.Magnitude
    local dy    = delta.Y

    if dx < 0.01 then
        local d = dy >= 0 and Vector3.new(0, 1, 0) or Vector3.new(0, -1, 0)
        return CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + d)
    end

    local flatDir = flatV.Unit
    local v2      = v0 * v0
    local disc    = v2 * v2 - g * (g * dx * dx + 2 * dy * v2)
    local theta   = disc < 0
        and math.atan2(dy, dx)
        or  math.atan2(v2 - math.sqrt(disc), g * dx)

    local T     = math.tan(theta)
    local denom = 3 + T
    local alpha = math.abs(denom) < 0.0001
        and -math.pi / 2
        or  math.atan2(3 * T - 1, denom)

    local yawCF = CFrame.new(Camera.CFrame.Position,
                             Camera.CFrame.Position + flatDir)
    return yawCF * CFrame.Angles(alpha, 0, 0)
end

-- ════════════════════════════════════════
--   SILENT AIM HOOK (GetCameraCF spoof)
--
--   Arms the NetworkRF OnClientInvoke hook for HOLD_DURATION+1s.
--   Called right before the crystal FireServer goes through.
-- ════════════════════════════════════════

local function armSilentAim(myHRP, killerHRP)
    local v0 = 250
    local g  = 40

    local originalCB = nil
    pcall(function() originalCB = getcallbackvalue(NetworkRF, "OnClientInvoke") end)
    local origDevice = LocalPlayer:GetAttribute("Device")
    local holdActive = true

    LocalPlayer:SetAttribute("Device", "Mobile")

    if NetworkRF then
        NetworkRF.OnClientInvoke = function(reqName, ...)
            if reqName == "GetCameraCF" and holdActive then
                local ok, cf = pcall(buildCamCF, myHRP, killerHRP, v0, g)
                return (ok and cf) or Camera.CFrame
            end
            if originalCB then return originalCB(reqName, ...) end
        end
    end

    task.delay(HOLD_DURATION + 1.0, function()
        holdActive = false
        pcall(function() NetworkRF.OnClientInvoke = originalCB end)
        LocalPlayer:SetAttribute("Device", origDevice)
    end)
end

-- ════════════════════════════════════════
--   __NAMECALL HOOK
--
--   Intercepts every FireServer call on the game metatable.
--   When it sees RemoteEvent:FireServer("UseActorAbility", ...)
--   and aimbotOn is enabled, it arms silent aim first, then
--   lets the original call through unchanged.
-- ════════════════════════════════════════

local mt         = getrawmetatable(game)
local oldNamecall = mt.__namecall
makereadonly      = makereadonly or function() end
setreadonly(mt, false)

mt.__namecall = newcclosure(function(self, ...)
    local method = getnamecallmethod()

    if method == "FireServer"
    and self == RemoteEvent
    and enabled
    and aimbotOn
    and not unloaded
    then
        local args = {...}
        -- args[1] = "UseActorAbility", args[2] = {[1] = buffer}
        if args[1] == "UseActorAbility" then
            local char  = LocalPlayer.Character
            local myHRP = char and char:FindFirstChild("HumanoidRootPart")
            if myHRP then
                local killer    = getNearestKiller(myHRP.Position)
                local killerHRP = killer and killer:FindFirstChild("HumanoidRootPart")
                if killerHRP then
                    armSilentAim(myHRP, killerHRP)
                end
            end
        end
    end

    return oldNamecall(self, ...)
end)

setreadonly(mt, true)

-- ════════════════════════════════════════
--   WINDUI
-- ════════════════════════════════════════

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

local Window = WindUI:CreateWindow({
    Title  = "V1perThrow",
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
    Content = "Ready",
})

local function setStatus(text)
    StatusParagraph:SetDesc(text)
end

Tab:Paragraph({
    Title   = "Info",
    Content = (isMobile and "Mobile" or "PC")
        .. " — detects crystal FireServer exactly, silent aim via GetCameraCF spoof",
})

Tab:Toggle({
    Title = "Enable",
    Desc  = "Intercept crystal FireServer calls",
    Icon  = "zap",
    Value = enabled,
    Callback = function(state)
        if unloaded then return end
        enabled = state
        Config.set("enabled", state)
        setStatus(state and "Active" or "Inactive")
    end,
})

Tab:Toggle({
    Title = "Silent Aim",
    Desc  = "Spoof GetCameraCF toward nearest killer on every throw",
    Icon  = "target",
    Value = aimbotOn,
    Callback = function(state)
        if unloaded then return end
        aimbotOn = state
        Config.set("aimbotOn", state)
        if not aimbotOn then killerMotionData = {} end
    end,
})

Tab:Divider()

Tab:Slider({
    Title = "Aim Offset",
    Desc  = "Y adjustment on aim target — 0 = killer centre",
    Step  = 0.1,
    Value = { Min = AIM_OFFSET_MIN, Max = AIM_OFFSET_MAX, Default = AIM_OFFSET },
    Callback = function(v) AIM_OFFSET = v; Config.set("aimOffset", v) end,
})

Tab:Slider({
    Title = "Prediction",
    Desc  = "Seconds to lead killer movement (0 = no lead)",
    Step  = 0.01,
    Value = { Min = PREDICTION_MIN, Max = PREDICTION_MAX, Default = PREDICTION },
    Callback = function(v) PREDICTION = v; Config.set("prediction", v) end,
})

Tab:Slider({
    Title = "Hold Duration",
    Desc  = "How long to hold the GetCameraCF hook open after firing",
    Step  = 0.1,
    Value = { Min = HOLD_DURATION_MIN, Max = HOLD_DURATION_MAX, Default = HOLD_DURATION },
    Callback = function(v) HOLD_DURATION = v; Config.set("holdDuration", v) end,
})

Tab:Divider()

local SettingsTab = Window:Tab({ Title = "Settings", Icon = "settings" })

SettingsTab:Button({
    Title = "Unload Script",
    Desc  = "Restore __namecall and close",
    Icon  = "power",
    Callback = function()
        if unloaded then return end
        unloaded = true
        enabled  = false
        aimbotOn = false

        -- Restore original __namecall
        pcall(function()
            setreadonly(mt, false)
            mt.__namecall = oldNamecall
            setreadonly(mt, true)
        end)

        -- Restore NetworkRF callback if still hooked
        pcall(function() NetworkRF.OnClientInvoke = nil end)
        pcall(function() LocalPlayer:SetAttribute("Device", nil) end)

        WindUI:Notify({
            Title    = "V1perThrow",
            Content  = "Unloaded — __namecall restored.",
            Icon     = "check",
            Duration = 3,
        })

        task.delay(0.5, function() Window:Destroy() end)
        print("[V1perThrow] Unloaded.")
    end,
})

print("[V1perThrow] Loaded. __namecall hook active.")
WindUI:Notify({
    Title    = "V1perThrow",
    Content  = "Loaded! __namecall hook active.",
    Icon     = "sparkles",
    Duration = 4,
})

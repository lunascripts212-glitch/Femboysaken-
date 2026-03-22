-- V1perThrow w/ WindUI (MOBILE-STYLE ON PC)
-- Run this as a LocalScript via your executor
-- Modified to use mobile camera spoofing method on PC

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
--   PLATFORM DETECTION (FORCED TO MOBILE)
-- ════════════════════════════════════════

-- CHANGE: Force mobile mode even on PC
local isMobile = true  -- Changed from: UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

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
--   BALLISTIC ARC MATH (for beam + mobile spoof)
-- ════════════════════════════════════════

local function computeArcCurve(gravity, initVel, origin, impactTime)
    local t2   = impactTime * impactTime
    local vt   = initVel * impactTime
    local endP = 0.5 * gravity * t2 + vt + origin
    local cp1  = endP - (gravity * t2 + vt) / 3
    local cp2  = (0.125 * gravity * t2 + 0.5 * vt + origin
                  - 0.125 * (origin + endP)) / 0.375 - cp1
    local cs0  = (cp2 - origin).Magnitude
    local cs1  = (cp1 - endP).Magnitude
    local back  = (origin - endP).Unit
    local fwd   = (cp2 - origin).Unit
    local up    = fwd:Cross(back).Unit
    local right = up:Cross(fwd).Unit
    local fwdE  = (cp1 - endP).Unit
    local upE   = fwdE:Cross(back).Unit
    local startCF = CFrame.new(origin.X,origin.Y,origin.Z,
        fwd.X,up.X,right.X, fwd.Y,up.Y,right.Y, fwd.Z,up.Z,right.Z)
    local endCF = CFrame.new(endP.X,endP.Y,endP.Z,
        fwdE.X,upE.X,right.X, fwdE.Y,upE.Y,right.Y, fwdE.Z,upE.Z,right.Z)
    return cs0, -cs1, startCF, endCF
end

local arcParams = RaycastParams.new()
arcParams.RespectCanCollide = true
arcParams.CollisionGroup    = "Killers"
arcParams.FilterType        = Enum.RaycastFilterType.Exclude
arcParams.FilterDescendantsInstances = workspace.Players:GetDescendants()

local function traceArc(gravity, initVel, origin)
    local prev    = origin
    local hitTime = 5
    for t = 0.05, 5, 0.05 do
        local pos  = gravity * 0.5 * t * t + initVel * t + origin
        local step = pos - prev
        local hit  = workspace:Raycast(prev, step, arcParams)
        if hit then
            hitTime = t - 0.05 + (hit.Position - prev).Magnitude / step.Magnitude * 0.05
            break
        end
        prev = pos
    end
    return computeArcCurve(gravity, initVel, origin, hitTime)
end

-- Compute spawnPos + initVel for a given HRP→target throw
local function getThrowPhysics(myHRP, killerHRP, abilityCfg)
    local vel       = getKillerVelocity(killerHRP)
    local hum       = myHRP.Parent and myHRP.Parent:FindFirstChildOfClass("Humanoid")
    local hipH      = hum and hum.HipHeight or 1.35
    local v238      = (hipH + myHRP.Size.Y / 2) / 2
    local spawnPos  = myHRP.CFrame.Position + Vector3.new(0, v238, 0)
    local predicted = killerHRP.Position + vel * PREDICTION
    local target    = predicted + Vector3.new(0, AIM_OFFSET, 0)
    local throwDir  = CFrame.lookAt(myHRP.Position, target) * CFrame.new(0, 0, -500)
    local initVel   = (throwDir.Position - spawnPos).Unit * abilityCfg.MaxSpeed
    local gravity   = Vector3.new(0, -abilityCfg.ProjectileArc, 0)
    return spawnPos, initVel, gravity, target
end

-- Ballistic-solved camera CFrame (UpVector/3 corrected) — used for mobile spoof
local function buildSpoofCF(myHRP, killerHRP, abilityCfg)
    local vel      = getKillerVelocity(killerHRP)
    local v0       = abilityCfg.MaxSpeed
    local g        = abilityCfg.ProjectileArc
    local hum      = myHRP.Parent and myHRP.Parent:FindFirstChildOfClass("Humanoid")
    local hipH     = hum and hum.HipHeight or 1.35
    local v238     = (hipH + myHRP.Size.Y / 2) / 2
    local spawnPos = myHRP.CFrame.Position + Vector3.new(0, v238, 0)
    local predicted = killerHRP.Position + vel * PREDICTION
    local target    = predicted + Vector3.new(0, AIM_OFFSET, 0)
    local delta     = target - spawnPos
    local flatV     = Vector3.new(delta.X, 0, delta.Z)
    local dx        = flatV.Magnitude
    local dy        = delta.Y
    if dx < 0.01 then
        local d = dy >= 0 and Vector3.new(0,1,0) or Vector3.new(0,-1,0)
        return CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + d)
    end
    local flatDir = flatV.Unit
    local v2   = v0 * v0
    local disc = v2*v2 - g*(g*dx*dx + 2*dy*v2)
    local theta = disc < 0 and math.atan2(dy,dx) or math.atan2(v2-math.sqrt(disc),g*dx)
    local T     = math.tan(theta)
    local denom = 3 + T
    local alpha = math.abs(denom) < 0.0001 and -math.pi/2 or math.atan2(3*T-1,denom)
    local yawCF = CFrame.new(Camera.CFrame.Position, Camera.CFrame.Position + flatDir)
    return yawCF * CFrame.Angles(alpha, 0, 0)
end

-- ════════════════════════════════════════
--   BEAM UPDATER
-- ════════════════════════════════════════

local function updateBeam(indicator, myHRP, killerHRP, abilityCfg)
    if not indicator then return end
    local spawnPos, initVel, gravity = getThrowPhysics(myHRP, killerHRP, abilityCfg)
    local cs0, cs1, startCF, endCF  = traceArc(gravity, initVel, spawnPos)
    pcall(function()
        indicator.Beam.CurveSize0         = cs0
        indicator.Beam.CurveSize1         = cs1
        indicator.AttachmentStart.CFrame  = myHRP.CFrame:Inverse() * startCF
        indicator.AttachmentEnd.CFrame    = workspace.Terrain.CFrame:Inverse() * endCF
        indicator.Target:PivotTo(endCF)
    end)
end

-- ════════════════════════════════════════
--   PATCH LOGIC
-- ════════════════════════════════════════

local NetworkRF = ReplicatedStorage.Modules.Network:FindFirstChild("RemoteFunction")

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

        local abilityCfg = self.Config.Crystal

        -- Create AimIndicator beam
        local indicator     = nil
        local indicatorConn = nil

        pcall(function()
            indicator = self.Behavior:lcl_createCrystalIndicator(self)
        end)

        -- Show ChargeUI at 100% / green (always full charge)
        pcall(function()
            local chargeUI = abilityCfg.ChargeUI:Clone()
            chargeUI.Parent = LocalPlayer.PlayerGui.TemporaryUI
            chargeUI.Bar.Percent.Text = "100%"
            chargeUI.Bar.ImageColor3  = Color3.new(0, 1, 0)
            self._patchChargeUI = chargeUI
        end)

        -- Drive beam each heartbeat (no camera changes here)
        if aimbotOn and indicator then
            indicatorConn = RunService.Heartbeat:Connect(function()
                if not self.State.IsCrystalEquipped then
                    if indicatorConn then indicatorConn:Disconnect(); indicatorConn = nil end
                    return
                end
                local myHRP = self.Rig and self.Rig:FindFirstChild("HumanoidRootPart")
                if not myHRP then return end
                local killer    = getNearestKiller(myHRP.Position)
                local killerHRP = killer and killer:FindFirstChild("HumanoidRootPart")
                if not killerHRP then return end
                updateBeam(indicator, myHRP, killerHRP, abilityCfg)
            end)
        end

        task.spawn(function()
            task.wait(abilityCfg.ChannelTime + 0.05)

            if indicatorConn then indicatorConn:Disconnect(); indicatorConn = nil end
            pcall(function()
                if self.Instances and self.Instances.CrystalIndicator then
                    for _, p in self.Instances.CrystalIndicator do pcall(p.Destroy, p) end
                    self.Instances.CrystalIndicator = nil
                end
            end)
            pcall(function()
                if self._patchChargeUI and self._patchChargeUI.Parent then
                    self._patchChargeUI:Destroy()
                    self._patchChargeUI = nil
                end
            end)

            -- Always apply camera spoof when aimbot is on
            if aimbotOn and self.State.IsCrystalEquipped and enabled then
                local myHRP = self.Rig and self.Rig:FindFirstChild("HumanoidRootPart")
                if myHRP then
                    local killer    = getNearestKiller(myHRP.Position)
                    local killerHRP = killer and killer:FindFirstChild("HumanoidRootPart")
                    if killerHRP then
                        -- Set up camera spoof
                        local spoofCF    = buildSpoofCF(myHRP, killerHRP, abilityCfg)
                        local originalCB = NetworkRF and getcallbackvalue(NetworkRF, "OnClientInvoke")
                        local origDevice = LocalPlayer:GetAttribute("Device") or "PC"
                        
                        -- Switch to Mobile for the spoof
                        LocalPlayer:SetAttribute("Device", "Mobile")
                        
                        local hasFired = false
                        
                        if NetworkRF then
                            NetworkRF.OnClientInvoke = function(reqName, ...)
                                if reqName == "GetCameraCF" and not hasFired then
                                    hasFired = true
                                    -- Return spoofed camera, then immediately restore
                                    task.spawn(function()
                                        RunService.Heartbeat:Wait()
                                        RunService.Heartbeat:Wait()
                                        -- Restore to PC after shot fires
                                        if NetworkRF then
                                            NetworkRF.OnClientInvoke = originalCB
                                        end
                                        LocalPlayer:SetAttribute("Device", "PC")
                                    end)
                                    return spoofCF
                                end
                                if originalCB then return originalCB(reqName, ...) end
                            end
                        end
                        
                        -- Safety restore after 5 seconds if user never fires
                        task.delay(5, function()
                            if not hasFired then
                                if NetworkRF and getcallbackvalue(NetworkRF, "OnClientInvoke") ~= originalCB then
                                    NetworkRF.OnClientInvoke = originalCB
                                end
                                LocalPlayer:SetAttribute("Device", "PC")
                            end
                        end)
                    end
                end
            end
        end)
    end

    patched = true
    print("[V1perThrow] Patched (Mobile-Style).")
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
    Title  = "V1perThrow (Mobile-Style)",
    Icon   = "gem",
    Author = "V1perThrow",
    Folder = "V1perThrow",
    Theme  = "Dark",
})

-- CHANGE: Still allow K key toggle even in mobile mode
Window:SetToggleKey(Enum.KeyCode.K)

local Tab = Window:Tab({ Title = "Main", Icon = "crosshair" })

local StatusParagraph = Tab:Paragraph({
    Title   = "Status",
    Content = "Waiting for actor...",
})

local function setStatus(text)
    StatusParagraph:SetDesc(text)
end

Tab:Paragraph({
    Title   = "Platform",
    Content = "Auto-Spoof Mode — Spoofs to Mobile while charging, auto-restores to PC after firing",
})

Tab:Toggle({
    Title = "Enable Patch",
    Desc  = "Enable camera spoof (you charge & fire manually)",
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
    Title = "Aimbot",
    Desc  = "Auto-aim camera spoof at nearest killer",
    Icon  = "target",
    Value = aimbotOn,
    Callback = function(state)
        if unloaded then return end
        aimbotOn = state
        Config.set("aimbotOn", state)
        if not aimbotOn then killerMotionData = {} end
        local actor = getLocalActor()
        if aimbotOn and not patched and actor then applyPatch(actor) end
    end,
})

Tab:Divider()

Tab:Slider({
    Title = "Aim Offset",
    Desc  = "Y adjustment on aim target (0 = killer centre)",
    Step  = 0.1,
    Value = { Min = AIM_OFFSET_MIN, Max = AIM_OFFSET_MAX, Default = AIM_OFFSET },
    Callback = function(v) AIM_OFFSET = v; Config.set("aimOffset", v) end,
})

Tab:Slider({
    Title = "Prediction",
    Desc  = "Seconds to lead the killer's movement",
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
        WindUI:Notify({ Title = "V1perThrow", Content = "Unloaded.", Icon = "check", Duration = 3 })
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
                print("[V1perThrow] New round — resetting patch.")
                WindUI:Notify({ Title = "V1perThrow", Content = "New round — patch re-applied.", Icon = "refresh-cw", Duration = 3 })
            end
            lastActor = currentActor
            if currentActor then
                if enabled then applyPatch(currentActor); setStatus("Active")
                else setStatus("Ready — toggle to activate") end
                print("[V1perThrow] Actor found. Ready.")
            else
                setStatus("Waiting for actor...")
            end
        end
    end
end)

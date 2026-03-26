--[[
    GRAVITY HUB UI - ROBLOX LOCALSCRIPT
    Compact, phone-friendly (800x600+), gravity-themed hub
    Features: toggles, sliders, close + open button, draggable
    Paste into a LocalScript inside StarterPlayerScripts or ScreenGui
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ─── ScreenGui ───────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GravityHub"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

-- ─── Theme ───────────────────────────────────────────────────
local C = {
    primary   = Color3.fromRGB(100, 200, 255),
    secondary = Color3.fromRGB(150, 100, 255),
    accent    = Color3.fromRGB(255, 100, 150),
    green     = Color3.fromRGB(80,  220, 150),
    orange    = Color3.fromRGB(255, 180, 80),
    purple    = Color3.fromRGB(180, 130, 255),
    dark      = Color3.fromRGB(15,  20,  30),
    glass     = Color3.fromRGB(20,  25,  35),
    text      = Color3.fromRGB(240, 240, 255),
    subtext   = Color3.fromRGB(140, 150, 170),
}

-- ─── Helpers ─────────────────────────────────────────────────
local function tween(obj, props, t, style, dir)
    local ti = TweenInfo.new(t or 0.2, Enum.EasingStyle[style or "Quad"], Enum.EasingDirection[dir or "Out"])
    local tw = TweenService:Create(obj, ti, props)
    tw:Play()
    return tw
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 12)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or C.primary
    s.Thickness = thickness or 1.2
    s.Transparency = transparency or 0.6
    s.Parent = parent
    return s
end

local function label(parent, text, size, font, color, xAlign)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size or 12
    l.Font = font or Enum.Font.Gotham
    l.TextColor3 = color or C.text
    l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

-- ─── Notification ────────────────────────────────────────────
local function notify(title, desc, color)
    local n = Instance.new("Frame")
    n.Size = UDim2.new(0, 220, 0, 58)
    n.Position = UDim2.new(1, 10, 1, -80)
    n.BackgroundColor3 = C.dark
    n.BackgroundTransparency = 0.1
    n.BorderSizePixel = 0
    n.ClipsDescendants = true
    n.Parent = screenGui
    corner(n, 10)
    stroke(n, color or C.primary, 1.5, 0.3)

    local t = label(n, title, 12, Enum.Font.GothamBold, color or C.primary)
    t.Size = UDim2.new(1, -12, 0, 24)
    t.Position = UDim2.new(0, 10, 0, 6)

    local d = label(n, desc, 10, Enum.Font.Gotham, C.subtext)
    d.Size = UDim2.new(1, -12, 0, 22)
    d.Position = UDim2.new(0, 10, 0, 30)
    d.TextWrapped = true

    tween(n, {Position = UDim2.new(1, -230, 1, -80)}, 0.35, "Back", "Out")
    task.delay(3.2, function()
        tween(n, {Position = UDim2.new(1, 10, 1, -80), BackgroundTransparency = 1}, 0.25, "Quad", "In")
        task.wait(0.3)
        n:Destroy()
    end)
end

-- ═══════════════════════════════════════════════════════════════
--   OPEN BUTTON (always visible when hub is closed)
-- ═══════════════════════════════════════════════════════════════
local openBtn = Instance.new("TextButton")
openBtn.Name = "OpenBtn"
openBtn.Size = UDim2.new(0, 44, 0, 44)
openBtn.Position = UDim2.new(0, 10, 0.5, -22)
openBtn.BackgroundColor3 = C.primary
openBtn.BackgroundTransparency = 0.2
openBtn.Text = "⟁"
openBtn.TextColor3 = Color3.fromRGB(255,255,255)
openBtn.TextSize = 20
openBtn.Font = Enum.Font.GothamBold
openBtn.BorderSizePixel = 0
openBtn.ZIndex = 20
openBtn.Visible = false   -- shown only when hub is closed
openBtn.Parent = screenGui
corner(openBtn, 14)
stroke(openBtn, C.primary, 1.5, 0.4)

-- Pulse the open button
local function pulseOpenBtn()
    if not openBtn.Visible then return end
    tween(openBtn, {BackgroundTransparency = 0.5}, 0.8, "Sine", "InOut")
    task.delay(0.8, function()
        tween(openBtn, {BackgroundTransparency = 0.2}, 0.8, "Sine", "InOut")
        task.delay(0.8, pulseOpenBtn)
    end)
end

-- ═══════════════════════════════════════════════════════════════
--   MAIN FRAME  (320 × 460, fits 800×600 nicely)
-- ═══════════════════════════════════════════════════════════════
local W, H = 310, 450

local mainFrame = Instance.new("Frame")
mainFrame.Name = "GravityCore"
mainFrame.Size = UDim2.new(0, W, 0, H)
mainFrame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
mainFrame.BackgroundColor3 = C.glass
mainFrame.BackgroundTransparency = 0.1
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.ZIndex = 10
mainFrame.Parent = screenGui
corner(mainFrame, 18)
stroke(mainFrame, C.primary, 1.5, 0.55)

-- Gradient background
local grad = Instance.new("UIGradient")
grad.Rotation = 135
grad.Color = ColorSequence.new(Color3.fromRGB(25,32,48), Color3.fromRGB(18,22,34))
grad.Parent = mainFrame

-- Scrollable content container
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -56)
scroll.Position = UDim2.new(0, 0, 0, 56)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = C.primary
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)  -- auto later
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ZIndex = 11
scroll.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = scroll

local scrollPad = Instance.new("UIPadding")
scrollPad.PaddingLeft = UDim.new(0, 10)
scrollPad.PaddingRight = UDim.new(0, 10)
scrollPad.PaddingTop = UDim.new(0, 8)
scrollPad.PaddingBottom = UDim.new(0, 8)
scrollPad.Parent = scroll

-- ─── HEADER ──────────────────────────────────────────────────
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 52)
header.BackgroundColor3 = C.dark
header.BackgroundTransparency = 0.4
header.BorderSizePixel = 0
header.ZIndex = 12
header.Parent = mainFrame

local headerGrad = Instance.new("UIGradient")
headerGrad.Rotation = 0
headerGrad.Color = ColorSequence.new(Color3.fromRGB(20,26,40), Color3.fromRGB(15,20,32))
headerGrad.Parent = header

-- Title
local titleLbl = label(header, "⟁  GRAVITY HUB", 16, Enum.Font.GothamBold, C.primary)
titleLbl.Size = UDim2.new(1, -90, 1, 0)
titleLbl.Position = UDim2.new(0, 14, 0, 0)
titleLbl.ZIndex = 13

-- Sub version text
local verLbl = label(header, "v2.0", 9, Enum.Font.Gotham, C.subtext)
verLbl.Size = UDim2.new(0, 30, 0, 14)
verLbl.Position = UDim2.new(0, 14, 0, 34)
verLbl.ZIndex = 13

-- Pulsing orb in header
local orb = Instance.new("Frame")
orb.Size = UDim2.new(0, 28, 0, 28)
orb.Position = UDim2.new(1, -82, 0.5, -14)
orb.BackgroundColor3 = C.primary
orb.BackgroundTransparency = 0.3
orb.BorderSizePixel = 0
orb.ZIndex = 13
orb.Parent = header
corner(orb, 14)
local orbG = Instance.new("UIGradient")
orbG.Rotation = 45
orbG.Color = ColorSequence.new(C.primary, C.secondary)
orbG.Parent = orb
TweenService:Create(orb, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    {BackgroundTransparency = 0.65, Size = UDim2.new(0, 32, 0, 32)}):Play()

-- CLOSE BUTTON ─────────────────────────────────────────────────
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -38, 0.5, -14)
closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 70)
closeBtn.BackgroundTransparency = 0.4
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.GothamBold
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 14
closeBtn.Parent = header
corner(closeBtn, 14)

closeBtn.MouseEnter:Connect(function()
    tween(closeBtn, {BackgroundTransparency = 0.1}, 0.15)
end)
closeBtn.MouseLeave:Connect(function()
    tween(closeBtn, {BackgroundTransparency = 0.4}, 0.15)
end)
closeBtn.MouseButton1Click:Connect(function()
    tween(mainFrame, {BackgroundTransparency = 1, Size = UDim2.new(0, W*0.85, 0, H*0.85), Position = UDim2.new(0.5, -W*0.85/2, 0.5, -H*0.85/2)}, 0.25, "Quad", "In")
    task.delay(0.28, function()
        mainFrame.Visible = false
        mainFrame.Size = UDim2.new(0, W, 0, H)
        mainFrame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
        mainFrame.BackgroundTransparency = 0.1
        openBtn.Visible = true
        pulseOpenBtn()
        notify("HUB MINIMIZED", "Tap ⟁ to reopen", C.primary)
    end)
end)

openBtn.MouseButton1Click:Connect(function()
    openBtn.Visible = false
    mainFrame.Visible = true
    mainFrame.BackgroundTransparency = 1
    mainFrame.Size = UDim2.new(0, W*0.85, 0, H*0.85)
    mainFrame.Position = UDim2.new(0.5, -W*0.85/2, 0.5, -H*0.85/2)
    tween(mainFrame, {BackgroundTransparency = 0.1, Size = UDim2.new(0, W, 0, H), Position = UDim2.new(0.5, -W/2, 0.5, -H/2)}, 0.3, "Back", "Out")
end)

-- ═══════════════════════════════════════════════════════════════
--   SECTION BUILDER HELPERS
-- ═══════════════════════════════════════════════════════════════

-- Section header
local function sectionHeader(parent, title, color, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 0, 22)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order or 0
    f.ZIndex = 12
    f.Parent = parent

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3 = color or C.primary
    line.BackgroundTransparency = 0.7
    line.BorderSizePixel = 0
    line.ZIndex = 12
    line.Parent = f

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, 0, 1, 0)
    bg.BackgroundColor3 = C.glass
    bg.BackgroundTransparency = 0
    bg.BorderSizePixel = 0
    bg.AutomaticSize = Enum.AutomaticSize.X
    bg.ZIndex = 12
    bg.Parent = f

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 6)
    pad.Parent = bg

    local t = label(bg, " " .. title .. " ", 10, Enum.Font.GothamBold, color or C.primary)
    t.Size = UDim2.new(0, 0, 1, 0)
    t.AutomaticSize = Enum.AutomaticSize.X
    t.ZIndex = 13

    return f
end

-- Toggle row
local toggleStates = {}
local function createToggle(parent, name, defaultOn, color, order, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 34)
    row.BackgroundColor3 = C.dark
    row.BackgroundTransparency = 0.55
    row.BorderSizePixel = 0
    row.LayoutOrder = order or 0
    row.ZIndex = 12
    row.Parent = parent
    corner(row, 8)

    local nameLbl = label(row, name, 12, Enum.Font.GothamSemibold, C.text)
    nameLbl.Size = UDim2.new(1, -52, 1, 0)
    nameLbl.Position = UDim2.new(0, 10, 0, 0)
    nameLbl.ZIndex = 13

    -- Toggle track
    local track = Instance.new("Frame")
    track.Size = UDim2.new(0, 38, 0, 20)
    track.Position = UDim2.new(1, -46, 0.5, -10)
    track.BackgroundColor3 = defaultOn and (color or C.primary) or Color3.fromRGB(55,60,75)
    track.BackgroundTransparency = 0.3
    track.BorderSizePixel = 0
    track.ZIndex = 13
    track.Parent = row
    corner(track, 10)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = defaultOn and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 14
    knob.Parent = track
    corner(knob, 7)

    local state = defaultOn
    toggleStates[name] = state

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.ZIndex = 15
    btn.Parent = row

    btn.MouseButton1Click:Connect(function()
        state = not state
        toggleStates[name] = state
        tween(track, {BackgroundColor3 = state and (color or C.primary) or Color3.fromRGB(55,60,75)}, 0.2)
        tween(knob, {Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)}, 0.18, "Quad", "Out")
        if onChange then onChange(state) end
    end)

    return row, function() return state end
end

-- Slider row
local sliderValues = {}
local function createSlider(parent, name, minVal, maxVal, defaultVal, color, order, onChange)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 46)
    row.BackgroundColor3 = C.dark
    row.BackgroundTransparency = 0.55
    row.BorderSizePixel = 0
    row.LayoutOrder = order or 0
    row.ZIndex = 12
    row.Parent = parent
    corner(row, 8)

    local nameLbl = label(row, name, 11, Enum.Font.GothamSemibold, C.text)
    nameLbl.Size = UDim2.new(0.6, 0, 0, 18)
    nameLbl.Position = UDim2.new(0, 10, 0, 4)
    nameLbl.ZIndex = 13

    local valLbl = label(row, tostring(defaultVal), 11, Enum.Font.GothamBold, color or C.primary, Enum.TextXAlignment.Right)
    valLbl.Size = UDim2.new(0.35, -6, 0, 18)
    valLbl.Position = UDim2.new(0.65, 0, 0, 4)
    valLbl.ZIndex = 13

    -- Track bg
    local trackBg = Instance.new("Frame")
    trackBg.Size = UDim2.new(1, -20, 0, 6)
    trackBg.Position = UDim2.new(0, 10, 0, 30)
    trackBg.BackgroundColor3 = Color3.fromRGB(40,48,65)
    trackBg.BorderSizePixel = 0
    trackBg.ZIndex = 13
    trackBg.Parent = row
    corner(trackBg, 3)

    local pct = (defaultVal - minVal) / (maxVal - minVal)
    local trackFill = Instance.new("Frame")
    trackFill.Size = UDim2.new(pct, 0, 1, 0)
    trackFill.BackgroundColor3 = color or C.primary
    trackFill.BorderSizePixel = 0
    trackFill.ZIndex = 14
    trackFill.Parent = trackBg
    corner(trackFill, 3)

    -- Knob
    local sKnob = Instance.new("Frame")
    sKnob.Size = UDim2.new(0, 14, 0, 14)
    sKnob.Position = UDim2.new(pct, -7, 0.5, -7)
    sKnob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    sKnob.BorderSizePixel = 0
    sKnob.ZIndex = 15
    sKnob.Parent = trackBg
    corner(sKnob, 7)
    stroke(sKnob, color or C.primary, 1.5, 0.4)

    local currentVal = defaultVal
    sliderValues[name] = currentVal

    -- Invisible drag button
    local dragBtn = Instance.new("TextButton")
    dragBtn.Size = UDim2.new(1, 0, 0, 24)
    dragBtn.Position = UDim2.new(0, 10, 0, 22)
    dragBtn.BackgroundTransparency = 1
    dragBtn.Text = ""
    dragBtn.ZIndex = 16
    dragBtn.Parent = row

    local draggingSlider = false
    dragBtn.MouseButton1Down:Connect(function() draggingSlider = true end)
    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)

    local function updateSlider(absX)
        local trackAbs = trackBg.AbsolutePosition.X
        local trackW   = trackBg.AbsoluteSize.X
        local newPct   = math.clamp((absX - trackAbs) / trackW, 0, 1)
        local newVal   = math.floor(minVal + newPct * (maxVal - minVal) + 0.5)
        currentVal = newVal
        sliderValues[name] = newVal
        valLbl.Text = tostring(newVal)
        tween(trackFill, {Size = UDim2.new(newPct, 0, 1, 0)}, 0.05)
        tween(sKnob, {Position = UDim2.new(newPct, -7, 0.5, -7)}, 0.05)
        if onChange then onChange(newVal) end
    end

    UserInputService.InputChanged:Connect(function(inp)
        if draggingSlider and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            updateSlider(inp.Position.X)
        end
    end)
    dragBtn.MouseButton1Down:Connect(function(x, y)
        updateSlider(x)
    end)

    return row, function() return currentVal end
end

-- Action button (full-width)
local function createActionBtn(parent, text, color, order, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = color or C.primary
    btn.BackgroundTransparency = 0.6
    btn.Text = text
    btn.TextColor3 = C.text
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamSemibold
    btn.BorderSizePixel = 0
    btn.LayoutOrder = order or 0
    btn.ZIndex = 12
    btn.Parent = parent
    corner(btn, 8)
    stroke(btn, color or C.primary, 1.2, 0.5)

    btn.MouseEnter:Connect(function()
        tween(btn, {BackgroundTransparency = 0.25}, 0.15)
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, {BackgroundTransparency = 0.6}, 0.15)
    end)
    btn.MouseButton1Click:Connect(function()
        tween(btn, {BackgroundTransparency = 0.8}, 0.07)
        task.delay(0.07, function()
            tween(btn, {BackgroundTransparency = 0.25}, 0.1)
        end)
        if onClick then onClick() end
    end)
    return btn
end

-- ═══════════════════════════════════════════════════════════════
--   PLAYER CARD
-- ═══════════════════════════════════════════════════════════════
local playerCard = Instance.new("Frame")
playerCard.Size = UDim2.new(1, 0, 0, 48)
playerCard.BackgroundColor3 = C.dark
playerCard.BackgroundTransparency = 0.4
playerCard.BorderSizePixel = 0
playerCard.LayoutOrder = 1
playerCard.ZIndex = 12
playerCard.Parent = scroll
corner(playerCard, 10)
stroke(playerCard, C.secondary, 1, 0.6)

local pName = label(playerCard, player.Name, 13, Enum.Font.GothamBold, C.primary)
pName.Size = UDim2.new(0.65, 0, 0.5, 0)
pName.Position = UDim2.new(0, 10, 0, 4)
pName.ZIndex = 13

local pStatus = label(playerCard, "● GRAVITY LINK ACTIVE", 9, Enum.Font.Gotham, C.green)
pStatus.Size = UDim2.new(0.7, 0, 0.4, 0)
pStatus.Position = UDim2.new(0, 10, 0.55, 0)
pStatus.ZIndex = 13

-- Mini gravity bar
local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(0.28, 0, 0, 8)
barBg.Position = UDim2.new(0.7, 0, 0.5, -4)
barBg.BackgroundColor3 = Color3.fromRGB(35,42,58)
barBg.BorderSizePixel = 0
barBg.ZIndex = 13
barBg.Parent = playerCard
corner(barBg, 4)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0.75, 0, 1, 0)
barFill.BackgroundColor3 = C.primary
barFill.BorderSizePixel = 0
barFill.ZIndex = 14
barFill.Parent = barBg
corner(barFill, 4)

task.spawn(function()
    while true do
        local t = math.random(40, 95) / 100
        tween(barFill, {Size = UDim2.new(t, 0, 1, 0)}, 1.8, "Sine", "InOut")
        task.wait(3.5)
    end
end)

-- ═══════════════════════════════════════════════════════════════
--   GRAVITY SETTINGS (sliders)
-- ═══════════════════════════════════════════════════════════════
sectionHeader(scroll, "GRAVITY SETTINGS", C.primary, 5)

createSlider(scroll, "Gravity Scale", 0, 200, 100, C.primary, 6, function(v)
    -- workspace.Gravity = v  -- uncomment to apply
    notify("GRAVITY", "Scale → " .. v, C.primary)
end)

createSlider(scroll, "Walk Speed", 1, 100, 16, C.green, 7, function(v)
    -- player.Character.Humanoid.WalkSpeed = v
    notify("SPEED", "WalkSpeed → " .. v, C.green)
end)

createSlider(scroll, "Jump Power", 0, 200, 50, C.secondary, 8, function(v)
    -- player.Character.Humanoid.JumpPower = v
    notify("JUMP", "JumpPower → " .. v, C.secondary)
end)

-- ═══════════════════════════════════════════════════════════════
--   TOGGLES
-- ═══════════════════════════════════════════════════════════════
sectionHeader(scroll, "MODULES", C.secondary, 10)

createToggle(scroll, "Anti-Gravity Mode", false, C.primary, 11, function(on)
    notify("ANTI-GRAVITY", on and "Enabled" or "Disabled", C.primary)
end)

createToggle(scroll, "Infinite Jump", false, C.accent, 12, function(on)
    notify("INF JUMP", on and "Enabled" or "Disabled", C.accent)
end)

createToggle(scroll, "Speed Boost", false, C.green, 13, function(on)
    notify("SPEED BOOST", on and "Enabled" or "Disabled", C.green)
end)

createToggle(scroll, "No Clip", false, C.orange, 14, function(on)
    notify("NO CLIP", on and "Enabled" or "Disabled", C.orange)
end)

createToggle(scroll, "ESP / Wallhack", false, C.purple, 15, function(on)
    notify("ESP", on and "Enabled" or "Disabled", C.purple)
end)

createToggle(scroll, "God Mode", false, C.accent, 16, function(on)
    notify("GOD MODE", on and "Enabled" or "Disabled", C.accent)
end)

-- ═══════════════════════════════════════════════════════════════
--   ACTION BUTTONS
-- ═══════════════════════════════════════════════════════════════
sectionHeader(scroll, "ACTIONS", C.orange, 20)

createActionBtn(scroll, "⚡  Teleport to Spawn", C.primary, 21, function()
    notify("TELEPORT", "Moving to spawn...", C.primary)
end)

createActionBtn(scroll, "🌀  Collect All Items", C.secondary, 22, function()
    notify("COLLECT", "Scanning nearby items...", C.secondary)
end)

createActionBtn(scroll, "✨  Reset Character", C.accent, 23, function()
    notify("RESET", "Respawning...", C.accent)
    -- player.Character:BreakJoints()  -- uncomment to use
end)

createActionBtn(scroll, "🛡️  Toggle Shield FX", C.green, 24, function()
    notify("SHIELD FX", "Visual effect toggled", C.green)
end)

-- Spacer at bottom
local spacer = Instance.new("Frame")
spacer.Size = UDim2.new(1, 0, 0, 4)
spacer.BackgroundTransparency = 1
spacer.LayoutOrder = 99
spacer.Parent = scroll

-- ═══════════════════════════════════════════════════════════════
--   DRAG (header-only for safety)
-- ═══════════════════════════════════════════════════════════════
local dragging = false
local dragStart, frameStart

header.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = inp.Position
        frameStart = mainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(inp)
    if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
        local delta = inp.Position - dragStart
        local cam = workspace.CurrentCamera
        local sw = cam and cam.ViewportSize.X or 800
        local sh = cam and cam.ViewportSize.Y or 600
        local nx = math.clamp(frameStart.X.Offset + delta.X, 0, sw - W)
        local ny = math.clamp(frameStart.Y.Offset + delta.Y, 0, sh - H)
        mainFrame.Position = UDim2.new(0, nx, 0, ny)
    end
end)

UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

-- ═══════════════════════════════════════════════════════════════
--   FLOATING PARTICLES (background, lightweight)
-- ═══════════════════════════════════════════════════════════════
for i = 1, 8 do
    local p = Instance.new("Frame")
    p.Size = UDim2.new(0, math.random(3,8), 0, math.random(3,8))
    p.BackgroundColor3 = (i % 2 == 0) and C.primary or C.secondary
    p.BackgroundTransparency = 0.5
    p.BorderSizePixel = 0
    p.ZIndex = 1
    p.Parent = screenGui
    corner(p, 4)

    local sx = math.random()
    local sy = math.random()
    local ox = math.random() * math.pi * 2
    local oy = math.random() * math.pi * 2
    local ax = math.random(15,50)
    local ay = math.random(15,50)
    local sp = 0.15 + math.random() * 0.2

    RunService.RenderStepped:Connect(function()
        local t = tick()
        p.Position = UDim2.new(sx, math.sin(t * sp + ox) * ax, sy, math.cos(t * sp + oy) * ay)
    end)
end

-- ═══════════════════════════════════════════════════════════════
--   KEYBIND  (Insert = toggle)
-- ═══════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(inp, gp)
    if gp then return end
    if inp.KeyCode == Enum.KeyCode.Insert then
        if mainFrame.Visible then
            closeBtn.MouseButton1Click:Fire()
        else
            openBtn.MouseButton1Click:Fire()
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════
--   STARTUP
-- ═══════════════════════════════════════════════════════════════
mainFrame.BackgroundTransparency = 1
mainFrame.Size = UDim2.new(0, W*0.9, 0, H*0.9)
mainFrame.Position = UDim2.new(0.5, -W*0.9/2, 0.5, -H*0.9/2)

task.wait(0.3)
tween(mainFrame, {
    BackgroundTransparency = 0.1,
    Size = UDim2.new(0, W, 0, H),
    Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
}, 0.45, "Back", "Out")

task.wait(0.6)
notify("GRAVITY HUB ONLINE", "Drag header • [Insert] to toggle", C.primary)

print("[GravityHub] Loaded — Insert to toggle, drag header to move")

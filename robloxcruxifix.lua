-- Vynixu Crucifix — cleaned, minimal-effects version
if getgenv().Vynixu_Crucifix_Everything then
    return getgenv().Vynixu_Crucifix_Everything
end

-- load utilities (keeps existing behavior)
local ok, _ = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/RegularVynixu/Utilities/main/Functions.lua"))()
end)
if not ok then
    warn("Failed to load Utilities.Functions.lua — some helpers may be missing.")
end

-- Services
local TweenService = game:GetService("TweenService") -- kept in case other code uses it
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Local player + character management
local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
LocalPlayer.CharacterAdded:Connect(function(char) Character = char end)

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Mouse = LocalPlayer:GetMouse()

-- Assets (try to load, warn if missing)
local function safeLoad(url)
    local ok, inst = pcall(function() return LoadCustomInstance(url) end)
    if ok and inst then
        return inst
    end
    warn("Failed to load asset:", url)
    return nil
end

local Assets = {
    Repentance = safeLoad("https://github.com/RegularVynixu/Utilities/raw/refs/heads/main/Doors/Entity%20Spawner/Assets/Repentance.rbxm"),
    Crucifix = safeLoad("https://github.com/RegularVynixu/Utilities/raw/refs/heads/main/Doors/Item%20Spawner/Assets/Crucifix.rbxm"),
}

-- Basic module
local Module = {
    Connections = {},
    ActiveTools = {}
}

-- Helper: wait until a sound reaches a time position (safe)
local function WaitUntil(sound, t)
    if not sound or not sound:IsA("Sound") then return end
    while sound.Parent and sound.TimePosition < t do
        RunService.RenderStepped:Wait()
    end
end

-- Main crucifix logic (minimal effects)
local function Crucifix(model, playerTool, config)
    if typeof(config) ~= "table" then config = {} end

    -- handle uses
    if typeof(config.Uses) == "number" then
        config.Uses = config.Uses - 1
        if config.Uses <= 0 then
            if Module.ActiveTools[playerTool] then
                Module.ActiveTools[playerTool] = nil
            end
            if playerTool and playerTool.Parent then
                playerTool:Destroy()
            end
        end
    end

    -- basic sanity checks for assets
    if not Assets.Crucifix or not Assets.Repentance then
        warn("Missing required assets for Crucifix action.")
        return
    end

    -- clone minimal instances
    local toolInstance = Assets.Crucifix:Clone()
    toolInstance:PivotTo(Character:GetPivot())
    toolInstance.Parent = workspace

    local repentance = Assets.Repentance:Clone()
    local crucifixPart = repentance:FindFirstChild("Crucifix", true) or repentance:FindFirstChildWhichIsA("BasePart", true)
    local entityPart = repentance:FindFirstChild("Entity", true) or repentance:FindFirstChildWhichIsA("BasePart", true)

    -- raycast down from model pivot to find ground
    local ok, entityPivot = pcall(function() return model:GetPivot() end)
    if not ok or not entityPivot then
        repentance:Destroy()
        toolInstance:Destroy()
        return
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { Character, model }

    local rayResult = workspace:Raycast(entityPivot.Position, Vector3.new(0, -1000, 0), params)
    if not rayResult then
        repentance:Destroy()
        toolInstance:Destroy()
        return
    end

    model:SetAttribute("BeingBanished", true)

    -- place repentance at raycast hit
    repentance:PivotTo(CFrame.new(rayResult.Position))
    if entityPart and entityPivot then
        -- make the entity proxy match the model pivot immediately
        entityPart.CFrame = entityPivot
    end
    repentance.Parent = workspace

    -- play appropriate sound if present on the crucifix model
    local soundToPlay = nil
    do
        local s = toolInstance:FindFirstChild("Sound", true) or toolInstance:FindFirstChildWhichIsA("Sound", true)
        soundToPlay = s
    end
    if soundToPlay then
        soundToPlay:Play()
    end

    -- If the target doesn't resist -> move it into the repentance entity and destroy it
    if not config.Resist then
        task.spawn(function()
            -- move model onto the repentance.Entity position until repentance is removed
            while model.Parent and repentance.Parent and entityPart do
                -- try to pivot model to entityPart; safe pcall
                pcall(function()
                    model:PivotTo(entityPart.CFrame)
                end)
                task.wait()
            end
            -- cleanup: destroy model if still exists
            if model and model.Parent then
                pcall(function() model:Destroy() end)
            end
        end)
    else
        -- if resisted, clear flags and keep the model alive, minimal feedback
        model:SetAttribute("BeingBanished", false)
    end

    -- minimal cleanup: remove repentance & tool after a short delay
    task.delay(5, function()
        if repentance and repentance.Parent then
            pcall(function() repentance:Destroy() end)
        end
        if toolInstance and toolInstance.Parent then
            pcall(function() toolInstance:Destroy() end)
        end
    end)
end

-- Input handling: use Crucifix
Module.Connections.InputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    local isClick = (input.UserInputType == Enum.UserInputType.MouseButton1) or (input.UserInputType == Enum.UserInputType.Touch)
    if not isClick then return end

    -- check for an equipped Crucifix tool in character
    if not Character or not Character.Parent then return end
    local equipped = Character:FindFirstChildOfClass("Tool")
    if not equipped then return end
    if equipped.Name ~= "Crucifix" then return end

    local playerTool = equipped
    local config = Module.ActiveTools[playerTool]
    if not config then return end

    local target = Mouse.Target
    if not target then return end

    local model = target:FindFirstAncestorOfClass("Model")
    if not model then return end

    -- validate target model
    if not model:IsA("Model") then return end
    if model:GetAttribute("BeingBanished") then return end
    if table.find(config.IgnoreList or {}, model) then return end
    if model:GetAttribute("CustomEntity") then return end

    -- execute
    pcall(function()
        Crucifix(model, playerTool, config)
    end)
end)

-- GiveCrucifix implementation (backpack)
Module.GiveCrucifix = function(self, config)
    if not Assets.Crucifix then
        warn("Crucifix asset missing; cannot give tool.")
        return
    end
    local crucifix = Assets.Crucifix:Clone()
    self.ActiveTools[crucifix] = config or {}
    local backpack = LocalPlayer:FindFirstChild("Backpack") or LocalPlayer:WaitForChild("Backpack")
    crucifix.Parent = backpack
end

-- Unload / cleanup
Module.Unload = function(self)
    for i, v in next, self.Connections do
        if v and v.Disconnect then
            pcall(function() v:Disconnect() end)
        end
        self.Connections[i] = nil
    end
    -- clear ActiveTools (do not destroy tools automatically to avoid surprises)
    for k in next, self.ActiveTools do
        self.ActiveTools[k] = nil
    end
    -- clear fields
    for k in next, self do
        self[k] = nil
    end
end

-- finalize
print("Crucifix Everything script by .vynixu (cleaned)")
getgenv().Vynixu_Crucifix_Everything = Module
return Module

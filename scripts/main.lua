-- ============================================================================
-- 锻造师 - 主入口
-- 玩家绘制武器 → 锻造体验 → 试炼场使用
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")
local DrawState = require("States.DrawState")
local ForgeState = require("States.ForgeState")
local ResultState = require("States.ResultState")
local TrialState = require("States.TrialState")
local MenuState = require("States.MenuState")

-- ============================================================================
-- 全局状态
-- ============================================================================
---@type string
local currentState_ = Config.States.MENU
local uiRoot_ = nil

-- 游戏数据（跨状态共享）
local gameData_ = {}

--- 重置游戏数据到初始状态
local function ResetGameData()
    gameData_.strokes = {}
    gameData_.weaponType = nil
    gameData_.weaponData = nil
    gameData_.forgeScore = 0
    gameData_.quality = nil
    gameData_.isComposite = false
end

ResetGameData()

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = Config.Title
    
    -- 1. 初始化 UI（内部会创建 NanoVG 用于 UI 渲染）
    InitUI()
    
    -- 2. 初始化共享 NanoVG 上下文（游戏自定义绘制用，只创建一次）
    NVG.Init()
    
    -- 3. 订阅全局事件（一次订阅，永不重复）
    SubscribeToEvents()
    
    -- 4. 进入主菜单
    SwitchState(Config.States.MENU)
    
    print("=== 锻造师 启动 ===")
end

function Stop()
    NVG.Shutdown()
    UI.Shutdown()
end

-- ============================================================================
-- UI 初始化
-- ============================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })
end

-- ============================================================================
-- 状态切换
-- ============================================================================

function SwitchState(newState)
    print("[State] " .. currentState_ .. " -> " .. newState)
    
    -- 离开旧状态
    LeaveState(currentState_)
    
    currentState_ = newState
    
    -- 进入新状态
    if newState == Config.States.MENU then
        MenuState.Enter(function()
            SwitchState(Config.States.DRAW)
        end)
        uiRoot_ = MenuState.BuildUI()
        UI.SetRoot(uiRoot_)
    elseif newState == Config.States.DRAW then
        DrawState.Enter(gameData_, function()
            SwitchState(Config.States.FORGE)
        end)
        BuildDrawUI()
    elseif newState == Config.States.FORGE then
        ForgeState.Enter(gameData_, function()
            SwitchState(Config.States.RESULT)
        end)
        BuildForgeUI()
    elseif newState == Config.States.RESULT then
        ResultState.Enter(gameData_, function()
            SwitchState(Config.States.TRIAL)
        end)
        BuildResultUI()
    elseif newState == Config.States.TRIAL then
        TrialState.Enter(gameData_, function()
            ResetGameData()
            SwitchState(Config.States.MENU)
        end)
        BuildTrialUI()
    end
end

--- 离开状态时的清理
function LeaveState(state)
    if state == Config.States.MENU then
        MenuState.Leave()
    elseif state == Config.States.DRAW then
        DrawState.Leave()
    elseif state == Config.States.FORGE then
        ForgeState.Leave()
    elseif state == Config.States.RESULT then
        ResultState.Leave()
    elseif state == Config.States.TRIAL then
        TrialState.Leave()
    end
end

-- ============================================================================
-- 各状态 UI 构建
-- ============================================================================

function BuildDrawUI()
    uiRoot_ = DrawState.BuildUI()
    UI.SetRoot(uiRoot_)
end

function BuildForgeUI()
    uiRoot_ = ForgeState.BuildUI()
    UI.SetRoot(uiRoot_)
end

function BuildResultUI()
    uiRoot_ = ResultState.BuildUI()
    UI.SetRoot(uiRoot_)
end

function BuildTrialUI()
    uiRoot_ = TrialState.BuildUI()
    UI.SetRoot(uiRoot_)
end

-- ============================================================================
-- 全局事件（只订阅一次，通过状态分发）
-- ============================================================================

--- 状态 → 模块的映射表（统一分发，无需逐事件硬编码）
local STATE_MODULES = {
    [Config.States.MENU]   = MenuState,
    [Config.States.DRAW]   = DrawState,
    [Config.States.FORGE]  = ForgeState,
    [Config.States.RESULT] = ResultState,
    [Config.States.TRIAL]  = TrialState,
}

--- 获取当前活跃状态模块
local function GetActiveModule()
    return STATE_MODULES[currentState_]
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")
    SubscribeToEvent("TouchMove", "HandleTouchMove")
    SubscribeToEvent("TouchEnd", "HandleTouchEnd")
    
    -- NanoVG 渲染事件（唯一一次订阅，内部根据状态分发）
    SubscribeToEvent(NVG.Get(), "NanoVGRender", "HandleNanoVGRender")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    local mod = GetActiveModule()
    if mod then mod.Update(dt) end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnKeyDown(key) end
end

function HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    local mod = GetActiveModule()
    if mod and mod.OnKeyUp then mod.OnKeyUp(key) end
end

function HandleMouseDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnMouseDown(button) end
end

function HandleMouseUp(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnMouseUp(button) end
end

function HandleMouseMove(eventType, eventData)
    local mod = GetActiveModule()
    if mod then mod.OnMouseMove() end
end

function HandleTouchBegin(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnTouchBegin(x, y) end
end

function HandleTouchMove(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnTouchMove(x, y) end
end

function HandleTouchEnd(eventType, eventData)
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnTouchEnd(x, y) end
end

--- NanoVG 渲染分发（唯一渲染入口）
function HandleNanoVGRender(eventType, eventData)
    local vg = NVG.Get()
    if not vg then return end
    local mod = GetActiveModule()
    if mod then mod.Render(vg) end
end

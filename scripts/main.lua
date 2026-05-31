-- ============================================================================
-- 锻造师 - 主入口
-- 玩家绘制武器 → 锻造体验 → 试炼场使用
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")
local DrawState = require("States.DrawState")
local MaterialState = require("States.MaterialState")
local ForgeState = require("States.ForgeState")
local ResultState = require("States.ResultState")
local TrialState = require("States.TrialState")
local MenuState = require("States.MenuState")
local PhaseOverlay = require("PhaseOverlay")

-- ============================================================================
-- BGM 系统
-- ============================================================================
local BGM = {}
local bgmScene_ = nil
local bgmNode_ = nil
local bgmPrepSource_ = nil   -- 战前准备音乐
local bgmBattleSource_ = nil -- 试炼场战斗音乐
local bgmPrepSound_ = nil
local bgmBattleSound_ = nil
local bgmPrepBaseGain_ = 0.35  -- 战前准备基础音量（低于音效）
local bgmPrepTargetGain_ = 0.35
local bgmPrepCurrentGain_ = 0.35
local bgmDuckGain_ = 0.15      -- 音效播放时压低到的音量
local bgmBattleGain_ = 0.55    -- 试炼场战斗音量

function BGM.Init()
    bgmScene_ = Scene()
    bgmNode_ = bgmScene_:CreateChild("BGM")

    -- 加载音乐资源
    bgmPrepSound_ = cache:GetResource("Sound", "audio/bgm_battle_prep.ogg")
    if bgmPrepSound_ then
        bgmPrepSound_.looped = true
    end
    bgmBattleSound_ = cache:GetResource("Sound", "audio/bgm_arena_battle.ogg")
    if bgmBattleSound_ then
        bgmBattleSound_.looped = true
    end

    -- 创建音源
    bgmPrepSource_ = bgmNode_:CreateComponent("SoundSource")
    bgmPrepSource_.soundType = SOUND_MUSIC
    bgmPrepSource_.gain = 0.0

    bgmBattleSource_ = bgmNode_:CreateComponent("SoundSource")
    bgmBattleSource_.soundType = SOUND_MUSIC
    bgmBattleSource_.gain = 0.0
end

function BGM.Shutdown()
    BGM.StopAll()
    if bgmNode_ then
        bgmNode_:Remove()
        bgmNode_ = nil
    end
    if bgmScene_ then
        bgmScene_:Dispose()
        bgmScene_ = nil
    end
end

--- 播放战前准备音乐（贯穿五个锻造环节）
function BGM.PlayPrep()
    if not bgmPrepSource_ or not bgmPrepSound_ then return end
    -- 如果已经在播放，不重复启动
    if bgmPrepSource_.playing then return end
    bgmPrepSource_.gain = bgmPrepBaseGain_
    bgmPrepCurrentGain_ = bgmPrepBaseGain_
    bgmPrepTargetGain_ = bgmPrepBaseGain_
    bgmPrepSource_:Play(bgmPrepSound_)
end

--- 停止战前准备音乐
function BGM.StopPrep()
    if bgmPrepSource_ then
        bgmPrepSource_:Stop()
        bgmPrepSource_.gain = 0.0
    end
end

--- 播放试炼场战斗音乐
function BGM.PlayBattle()
    if not bgmBattleSource_ or not bgmBattleSound_ then return end
    BGM.StopPrep()  -- 停掉准备音乐
    bgmBattleSource_.gain = bgmBattleGain_
    bgmBattleSource_:Play(bgmBattleSound_)
end

--- 停止试炼场战斗音乐
function BGM.StopBattle()
    if bgmBattleSource_ then
        bgmBattleSource_:Stop()
        bgmBattleSource_.gain = 0.0
    end
end

--- 停止所有BGM
function BGM.StopAll()
    BGM.StopPrep()
    BGM.StopBattle()
end

--- 压低战前准备音乐（音效播放时调用）
function BGM.DuckPrep()
    bgmPrepTargetGain_ = bgmDuckGain_
end

--- 恢复战前准备音乐音量
function BGM.UnduckPrep()
    bgmPrepTargetGain_ = bgmPrepBaseGain_
end

--- 平滑更新音量（每帧调用）
function BGM.Update(dt)
    if not bgmPrepSource_ then return end
    -- 平滑过渡准备音乐音量
    if math.abs(bgmPrepCurrentGain_ - bgmPrepTargetGain_) > 0.001 then
        local speed = 3.0  -- 音量过渡速度
        if bgmPrepCurrentGain_ < bgmPrepTargetGain_ then
            bgmPrepCurrentGain_ = math.min(bgmPrepCurrentGain_ + speed * dt, bgmPrepTargetGain_)
        else
            bgmPrepCurrentGain_ = math.max(bgmPrepCurrentGain_ - speed * dt, bgmPrepTargetGain_)
        end
        bgmPrepSource_.gain = bgmPrepCurrentGain_
    end
end

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
    
    -- 3. 初始化阶段倒数系统
    PhaseOverlay.Init()
    
    -- 4. 初始化 BGM 系统
    BGM.Init()
    
    -- 5. 订阅全局事件（一次订阅，永不重复）
    SubscribeToEvents()
    
    -- 5. 进入主菜单
    SwitchState(Config.States.MENU)
    
    print("=== 锻造师 启动 ===")
end

function Stop()
    BGM.Shutdown()
    PhaseOverlay.Shutdown()
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
        theme = {
            colors = {
                -- 暗黑锻造风格按钮色
                primary = { 140, 100, 50, 255 },         -- 锻铁暗金
                primaryHover = { 170, 125, 60, 255 },    -- 悬停暖金
                primaryPressed = { 110, 80, 40, 255 },   -- 按下深铜

                secondary = { 70, 70, 75, 255 },         -- 铁灰
                secondaryHover = { 90, 90, 95, 255 },
                secondaryPressed = { 55, 55, 60, 255 },

                background = { 20, 22, 28, 255 },        -- 压抑黑蓝
                surface = { 40, 40, 45, 230 },           -- 深锻台面
                surfaceHover = { 55, 55, 60, 230 },

                text = { 200, 205, 210, 255 },           -- 哑光银
                textSecondary = { 120, 130, 140, 255 },  -- 钢灰
                textDisabled = { 60, 60, 65, 255 },

                border = { 70, 60, 45, 255 },            -- 暗褐边框
                borderFocus = { 150, 200, 255, 255 },    -- 冰霜蓝聚焦

                success = { 80, 160, 80, 255 },
                successHover = { 100, 180, 100, 255 },
                warning = { 160, 140, 90, 255 },         -- 旧金
                warningHover = { 180, 160, 110, 255 },
                error = { 200, 80, 40, 255 },            -- 炭火红
                errorHover = { 220, 100, 60, 255 },
                info = { 150, 200, 255, 255 },           -- 冰霜蓝

                disabled = { 45, 45, 50, 255 },
                disabledText = { 80, 80, 85, 255 },

                overlay = { 0, 0, 0, 180 },
                transparent = { 0, 0, 0, 0 },
                hover = { 255, 255, 255, 15 },
            },
        },
    })
end

-- ============================================================================
-- 状态切换（带阶段过渡）
-- ============================================================================

--- 直接切换（无黑屏过渡，内部使用）
local function DoSwitchState(newState)
    print("[State] " .. currentState_ .. " -> " .. newState)
    
    -- 离开旧状态
    LeaveState(currentState_)
    currentState_ = newState
    
    -- 进入新状态
    if newState == Config.States.MENU then
        BGM.StopAll()  -- 返回菜单时停止所有BGM
        MenuState.Enter(function()
            SwitchState(Config.States.DRAW)
        end)
        uiRoot_ = MenuState.BuildUI()
        UI.SetRoot(uiRoot_)
    elseif newState == Config.States.DRAW then
        BGM.PlayPrep()  -- 开始播放战前准备音乐（贯穿五个锻造环节）
        DrawState.Enter(gameData_, function()
            SwitchState(Config.States.MATERIAL)
        end)
        BuildDrawUI()
    elseif newState == Config.States.MATERIAL then
        MaterialState.Enter(gameData_, function()
            SwitchState(Config.States.FORGE)
        end)
        BuildMaterialUI()
    elseif newState == Config.States.FORGE then
        BGM.DuckPrep()  -- 锻造阶段有密集音效，压低BGM音量
        ForgeState.Enter(gameData_, function()
            BGM.UnduckPrep()  -- 锻造结束，恢复BGM音量
            SwitchState(Config.States.RESULT)
        end, function(forgePhase)
            -- ForgeState 内部阶段切换回调（非阻塞，只播放音效和碎片）
            -- forgePhase: "quench" → 倒数变2, "grind" → 倒数变1
            if forgePhase == "quench" then
                PhaseOverlay.TransitionTo(2, nil, false)
            elseif forgePhase == "grind" then
                PhaseOverlay.TransitionTo(1, nil, false)
            end
        end)
        BuildForgeUI()
    elseif newState == Config.States.RESULT then
        -- 进入结果/试炼前 → 最终破碎（从阶段1→0）
        ResultState.Enter(gameData_, function()
            -- 从 Result 进入 Trial 时触发最终破碎
            PhaseOverlay.TransitionTo(0, function()
                DoSwitchState(Config.States.TRIAL)
            end)
        end)
        BuildResultUI()
    elseif newState == Config.States.TRIAL then
        BGM.StopPrep()    -- 停止准备音乐
        BGM.PlayBattle()  -- 播放试炼场战斗音乐
        TrialState.Enter(gameData_, function()
            BGM.StopBattle()  -- 返回菜单时停止战斗音乐
            ResetGameData()
            SwitchState(Config.States.MENU)
        end)
        BuildTrialUI()
    end
end

--- 状态映射到阶段倒数
local STATE_TO_PHASE = {
    [Config.States.DRAW] = 5,
    [Config.States.MATERIAL] = 4,
    [Config.States.FORGE] = 3,  -- 锤击
}

--- 公共切换（带黑屏过渡）
function SwitchState(newState)
    local targetPhase = STATE_TO_PHASE[newState]
    
    -- 需要阶段过渡的状态
    if targetPhase then
        -- 首次进入绘制时，启动 PhaseOverlay
        if newState == Config.States.DRAW then
            PhaseOverlay.Start()
        end
        
        PhaseOverlay.TransitionTo(targetPhase, function()
            DoSwitchState(newState)
        end)
    else
        -- 不需要阶段过渡的直接切换（菜单、结果、试炼）
        DoSwitchState(newState)
    end
end

--- 离开状态时的清理
function LeaveState(state)
    if state == Config.States.MENU then
        MenuState.Leave()
    elseif state == Config.States.DRAW then
        DrawState.Leave()
    elseif state == Config.States.MATERIAL then
        MaterialState.Leave()
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

function BuildMaterialUI()
    uiRoot_ = MaterialState.BuildUI()
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
    [Config.States.MENU]     = MenuState,
    [Config.States.DRAW]     = DrawState,
    [Config.States.MATERIAL] = MaterialState,
    [Config.States.FORGE]    = ForgeState,
    [Config.States.RESULT]   = ResultState,
    [Config.States.TRIAL]    = TrialState,
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
    
    -- 更新 BGM 音量（平滑过渡）
    BGM.Update(dt)
    
    -- 更新 PhaseOverlay（始终更新，包括碎片和过渡动画）
    PhaseOverlay.Update(dt)
    
    -- 过渡中不更新游戏状态（防止输入干扰）
    if PhaseOverlay.IsTransitioning() then return end
    
    local mod = GetActiveModule()
    if mod then mod.Update(dt) end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    if PhaseOverlay.IsTransitioning() then return end
    local key = eventData["Key"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnKeyDown(key) end
end

function HandleKeyUp(eventType, eventData)
    if PhaseOverlay.IsTransitioning() then return end
    local key = eventData["Key"]:GetInt()
    local mod = GetActiveModule()
    if mod and mod.OnKeyUp then mod.OnKeyUp(key) end
end

function HandleMouseDown(eventType, eventData)
    if PhaseOverlay.IsTransitioning() then return end
    local button = eventData["Button"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnMouseDown(button) end
end

function HandleMouseUp(eventType, eventData)
    if PhaseOverlay.IsTransitioning() then return end
    local button = eventData["Button"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnMouseUp(button) end
end

function HandleMouseMove(eventType, eventData)
    if PhaseOverlay.IsTransitioning() then return end
    local mod = GetActiveModule()
    if mod then mod.OnMouseMove() end
end

function HandleTouchBegin(eventType, eventData)
    if PhaseOverlay.IsTransitioning() then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnTouchBegin(x, y) end
end

function HandleTouchMove(eventType, eventData)
    if PhaseOverlay.IsTransitioning() then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnTouchMove(x, y) end
end

function HandleTouchEnd(eventType, eventData)
    if PhaseOverlay.IsTransitioning() then return end
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
    
    -- PhaseOverlay 在所有状态之上渲染（倒数+碎片+黑屏过渡）
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    
    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)
    PhaseOverlay.Render(vg)
    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

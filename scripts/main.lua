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
local KeyBindings = require("KeyBindings")
local PauseMenu = require("PauseMenu")
local PhaseIntro = require("PhaseIntro")

-- ============================================================================
-- BGM 系统
-- ============================================================================
BGM = {}
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
local bgmDuckTimer_ = 0        -- 短暂压低计时器（>0 时处于压低状态）
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
    bgmDuckTimer_ = 0
end

--- 短暂压低战前准备音乐（音效播放时调用，duration 秒后自动恢复）
function BGM.DuckForSFX(duration)
    bgmPrepTargetGain_ = bgmDuckGain_
    bgmDuckTimer_ = duration or 0.5
end

--- 平滑更新音量（每帧调用）
function BGM.Update(dt)
    if not bgmPrepSource_ then return end
    -- 短暂压低计时器：到期自动恢复
    if bgmDuckTimer_ > 0 then
        bgmDuckTimer_ = bgmDuckTimer_ - dt
        if bgmDuckTimer_ <= 0 then
            bgmDuckTimer_ = 0
            bgmPrepTargetGain_ = bgmPrepBaseGain_
        end
    end
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
-- 开场动画系统
-- ============================================================================
local Intro = {}
local introActive_ = false        -- 是否正在播放开场动画
local introPlayer_ = nil          -- VideoPlayer 实例
local introNvgImage_ = nil        -- NanoVG 视频纹理句柄
local introFadeAlpha_ = 0         -- 淡入淡出 alpha (0~1)
local introPhase_ = "none"        -- "fadein" | "playing" | "fadeout" | "none"
local introOnDone_ = nil          -- 完成后的回调
local introSkipHintAlpha_ = 0     -- 跳过按钮透明度
local introSkipBtnRect_ = nil     -- 跳过按钮点击区域 {x,y,w,h} 逻辑像素

local INTRO_VIDEO_PATH = "video/开场动画.mp4"
local INTRO_FADE_IN_TIME = 0.4
local INTRO_FADE_OUT_TIME = 0.5
local introTimer_ = 0

function Intro.Start(onDone)
    introOnDone_ = onDone
    introActive_ = true
    introPhase_ = "fadein"
    introTimer_ = 0
    introFadeAlpha_ = 0
    introSkipHintAlpha_ = 0
    introSkipBtnRect_ = nil
    introNvgImage_ = nil

    -- 创建 VideoPlayer
    introPlayer_ = VideoPlayer:new()
    if introPlayer_ then
        local success = introPlayer_:Load(INTRO_VIDEO_PATH, 1280, 720)
        if success then
            introPlayer_:SetVolume(1.0)
            introPlayer_:SetLoop(false)
            print("[Intro] Video loaded: " .. INTRO_VIDEO_PATH)
        else
            print("[Intro] Video load failed, skipping intro")
            Intro.Finish()
            return
        end
    else
        print("[Intro] VideoPlayer not available, skipping intro")
        Intro.Finish()
        return
    end
end

function Intro.Skip()
    if not introActive_ then return end
    print("[Intro] Skipped by user")
    introPhase_ = "fadeout"
    introTimer_ = 0
end

function Intro.Finish()
    -- 清理视频资源
    if introPlayer_ then
        introPlayer_:Stop()
        introPlayer_ = nil
    end
    -- 释放 NanoVG 视频纹理（避免 GPU 泄漏）
    if introNvgImage_ and introNvgImage_ > 0 then
        local vg = NVG.Get()
        if vg then
            nvgDeleteImage(vg, introNvgImage_)
        end
    end
    introNvgImage_ = nil
    introActive_ = false
    introPhase_ = "none"

    -- 执行回调
    if introOnDone_ then
        local cb = introOnDone_
        introOnDone_ = nil
        cb()
    end
end

function Intro.Update(dt)
    if not introActive_ then return end

    introTimer_ = introTimer_ + dt

    if introPhase_ == "fadein" then
        introFadeAlpha_ = math.min(1.0, introTimer_ / INTRO_FADE_IN_TIME)
        if introTimer_ >= INTRO_FADE_IN_TIME then
            introPhase_ = "playing"
            introTimer_ = 0
            introFadeAlpha_ = 1.0
            -- 开始播放视频
            if introPlayer_ then
                introPlayer_:Play()
            end
        end
    elseif introPhase_ == "playing" then
        -- 更新视频帧
        if introPlayer_ then
            introPlayer_:Update()
            -- 检测视频是否播放完毕
            local duration = introPlayer_:GetDuration()
            local current = introPlayer_:GetCurrentTime()
            if duration > 0 and current >= duration - 0.1 then
                introPhase_ = "fadeout"
                introTimer_ = 0
            end
        end
        -- ESC跳过提示渐入（2秒后显示）
        if introTimer_ > 2.0 then
            introSkipHintAlpha_ = math.min(1.0, introSkipHintAlpha_ + dt * 2.0)
        end
    elseif introPhase_ == "fadeout" then
        introFadeAlpha_ = math.max(0, 1.0 - introTimer_ / INTRO_FADE_OUT_TIME)
        if introTimer_ >= INTRO_FADE_OUT_TIME then
            Intro.Finish()
        end
    end
end

function Intro.Render(vg)
    if not introActive_ then return end

    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local lw = w / dpr
    local lh = h / dpr

    -- 黑色背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, lw, lh)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
    nvgFill(vg)

    -- 渲染视频画面（带 fade alpha）
    if introPlayer_ and introPlayer_:IsReady() and introPhase_ == "playing" then
        local texture = introPlayer_:GetTexture()
        if texture then
            if not introNvgImage_ and nvgCreateVideo then
                introNvgImage_ = nvgCreateVideo(vg, texture)
            end
            if introNvgImage_ and introNvgImage_ > 0 then
                local videoW = introPlayer_:GetVideoWidth()
                local videoH = introPlayer_:GetVideoHeight()
                -- Aspect fit
                local containerRatio = lw / lh
                local videoRatio = (videoW > 0 and videoH > 0) and (videoW / videoH) or (16 / 9)
                local drawW, drawH
                if videoRatio > containerRatio then
                    drawW = lw
                    drawH = lw / videoRatio
                else
                    drawH = lh
                    drawW = lh * videoRatio
                end
                local drawX = (lw - drawW) / 2
                local drawY = (lh - drawH) / 2

                local imgPaint = nvgImagePattern(vg, drawX, drawY, drawW, drawH, 0, introNvgImage_, introFadeAlpha_)
                nvgBeginPath(vg)
                nvgRect(vg, drawX, drawY, drawW, drawH)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            end
        end
    elseif introPhase_ == "fadein" then
        -- fadein 阶段仅显示黑屏（已在上面绘制）
    end

    -- "跳过 >>" 按钮（右上角）
    if introSkipHintAlpha_ > 0.01 then
        local fontId = NVG.GetFont()
        if fontId ~= -1 then
            local btnText = "跳过 >>"
            local btnFontSize = 14
            local btnPadH = 14
            local btnPadV = 8
            local btnX = lw - 20   -- 右侧对齐（按钮右边缘）
            local btnY = 20        -- 顶部距离

            nvgFontFaceId(vg, fontId)
            nvgFontSize(vg, btnFontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

            -- 测量文本宽度
            local _, bounds = nvgTextBounds(vg, 0, 0, btnText)
            local textW = (bounds and bounds[3] and bounds[1]) and (bounds[3] - bounds[1]) or (btnFontSize * 4)
            local textH = btnFontSize

            local btnW = textW + btnPadH * 2
            local btnH = textH + btnPadV * 2
            local bx = btnX - btnW
            local by = btnY

            -- 保存按钮区域供点击检测
            introSkipBtnRect_ = { x = bx, y = by, w = btnW, h = btnH }

            local a = math.floor(introSkipHintAlpha_ * 200)

            -- 按钮背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, bx, by, btnW, btnH, 6)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(a * 0.5)))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(200, 200, 200, a))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            -- 按钮文字
            nvgFillColor(vg, nvgRGBA(220, 220, 220, a))
            nvgText(vg, bx + btnPadH, by + btnPadV, btnText, nil)
        end
    end
end

function Intro.IsActive()
    return introActive_
end

--- 检测点击/触摸是否命中跳过按钮（逻辑像素坐标）
function Intro.HitSkipButton(lx, ly)
    if not introActive_ then return false end
    if introSkipHintAlpha_ < 0.1 then return false end
    local r = introSkipBtnRect_
    if not r then return false end
    return lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h
end

function Intro.OnKeyDown(key)
    if not introActive_ then return false end
    if key == KEY_ESCAPE then
        Intro.Skip()
        return true
    end
    return true  -- 吞掉所有按键
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
    
    -- 3. 初始化按键绑定系统
    KeyBindings.Init()
    
    -- 4. 初始化阶段倒数系统
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
            -- 点击开始游戏 → 先播放开场动画 → 再进入绘制
            Intro.Start(function()
                SwitchState(Config.States.DRAW)
            end)
        end)
        uiRoot_ = MenuState.BuildUI()
        UI.SetRoot(uiRoot_)
    elseif newState == Config.States.DRAW then
        PhaseIntro.Show(newState, function()
            BGM.PlayPrep()  -- 开始播放战前准备音乐（贯穿五个锻造环节）
            DrawState.Enter(gameData_, function()
                SwitchState(Config.States.MATERIAL)
            end)
            BuildDrawUI()
        end)
    elseif newState == Config.States.MATERIAL then
        PhaseIntro.Show(newState, function()
            MaterialState.Enter(gameData_, function()
                SwitchState(Config.States.FORGE)
            end)
            BuildMaterialUI()
        end)
    elseif newState == Config.States.FORGE then
        PhaseIntro.Show(newState, function()
            ForgeState.Enter(gameData_, function()
                SwitchState(Config.States.RESULT)
            end, function(forgePhase, resumeFn)
                -- ForgeState 内部阶段切换回调：显示子阶段说明黑屏
                -- forgePhase: "quench"/"grind", resumeFn: 黑屏结束后调用恢复游戏
                if forgePhase == "quench" then
                    PhaseOverlay.TransitionTo(2, nil, false)
                    PhaseIntro.Show("forge_quench", function()
                        BuildForgeUI()
                        if resumeFn then resumeFn() end
                    end)
                elseif forgePhase == "grind" then
                    PhaseOverlay.TransitionTo(1, nil, false)
                    PhaseIntro.Show("forge_grind", function()
                        BuildForgeUI()
                        if resumeFn then resumeFn() end
                    end)
                end
            end)
            BuildForgeUI()
        end)
    elseif newState == Config.States.RESULT then
        PhaseIntro.Show(newState, function()
            ResultState.Enter(gameData_, function()
                -- 从 Result 进入 Trial 时触发最终破碎
                PhaseOverlay.TransitionTo(0, function()
                    DoSwitchState(Config.States.TRIAL)
                end)
            end)
            BuildResultUI()
        end)
    elseif newState == Config.States.TRIAL then
        PhaseIntro.Show(newState, function()
            BGM.StopPrep()    -- 停止准备音乐
            BGM.PlayBattle()  -- 播放试炼场战斗音乐
            TrialState.Enter(gameData_, function()
                BGM.StopBattle()  -- 返回菜单时停止战斗音乐
                ResetGameData()
                SwitchState(Config.States.MENU)
            end)
            BuildTrialUI()
        end)
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

--- 离开状态时的清理（完整释放上一环节所有资源）
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
    -- 强制 GC，立即回收上一环节释放的 Lua 内存
    collectgarbage("collect")
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
    
    -- 开场动画优先更新（激活时阻塞其他一切）
    if Intro.IsActive() then
        Intro.Update(dt)
        return
    end
    
    -- 更新 BGM 音量（平滑过渡）
    BGM.Update(dt)
    
    -- 更新 PhaseOverlay（始终更新，包括碎片和过渡动画）
    PhaseOverlay.Update(dt)
    
    -- 过渡中不更新游戏状态（防止输入干扰）
    if PhaseOverlay.IsTransitioning() then return end
    
    -- 环节说明界面显示中不更新游戏状态
    if PhaseIntro.IsActive() then return end

    -- 暂停菜单打开时不更新游戏逻辑
    if PauseMenu.IsVisible() then return end

    local mod = GetActiveModule()
    if mod then mod.Update(dt) end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    -- 开场动画激活时由 Intro 处理所有按键
    if Intro.IsActive() then
        Intro.OnKeyDown(key)
        return
    end
    if PhaseOverlay.IsTransitioning() then return end
    if PhaseIntro.IsActive() then return end

    -- ESC 暂停菜单拦截（非主菜单状态）
    if key == KEY_ESCAPE and currentState_ ~= Config.States.MENU then
        if PauseMenu.IsVisible() then
            -- 已在暂停菜单 → 关闭并恢复游戏 UI
            PauseMenu.Hide()
            UI.SetRoot(uiRoot_)
        else
            -- 打开暂停菜单
            local pauseOpts = {
                onResume = function()
                    -- 恢复游戏 UI
                    UI.SetRoot(uiRoot_)
                end,
                onReturnMenu = function()
                    -- 离开当前状态，重置并回到主界面
                    BGM.StopAll()
                    PhaseOverlay.Stop()
                    LeaveState(currentState_)
                    ResetGameData()
                    currentState_ = Config.States.MENU
                    MenuState.Enter(function()
                        Intro.Start(function()
                            SwitchState(Config.States.DRAW)
                        end)
                    end)
                    uiRoot_ = MenuState.BuildUI()
                    UI.SetRoot(uiRoot_)
                end,
            }
            -- 试炼场额外传入武器信息
            if currentState_ == Config.States.TRIAL then
                pauseOpts.weaponData = gameData_.weaponData
                pauseOpts.material = gameData_.material
                pauseOpts.quality = gameData_.quality
            end
            PauseMenu.Show(pauseOpts)
        end
        return
    end

    -- 暂停中不分发按键给游戏状态
    if PauseMenu.IsVisible() then return end

    local mod = GetActiveModule()
    if mod then mod.OnKeyDown(key) end
end

function HandleKeyUp(eventType, eventData)
    if Intro.IsActive() then return end
    if PhaseOverlay.IsTransitioning() then return end
    if PauseMenu.IsVisible() then return end
    local key = eventData["Key"]:GetInt()
    local mod = GetActiveModule()
    if mod and mod.OnKeyUp then mod.OnKeyUp(key) end
end

function HandleMouseDown(eventType, eventData)
    if Intro.IsActive() then
        -- 检测跳过按钮点击
        local dpr = graphics:GetDPR()
        local mx = input:GetMousePosition().x / dpr
        local my = input:GetMousePosition().y / dpr
        if Intro.HitSkipButton(mx, my) then
            Intro.Skip()
        end
        return
    end
    if PhaseOverlay.IsTransitioning() then return end
    if PhaseIntro.IsActive() then return end
    if PauseMenu.IsVisible() then return end
    local button = eventData["Button"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnMouseDown(button) end
end

function HandleMouseUp(eventType, eventData)
    if Intro.IsActive() then return end
    if PhaseOverlay.IsTransitioning() then return end
    if PhaseIntro.IsActive() then return end
    if PauseMenu.IsVisible() then return end
    local button = eventData["Button"]:GetInt()
    local mod = GetActiveModule()
    if mod then mod.OnMouseUp(button) end
end

function HandleMouseMove(eventType, eventData)
    if Intro.IsActive() then return end
    if PhaseOverlay.IsTransitioning() then return end
    if PhaseIntro.IsActive() then return end
    if PauseMenu.IsVisible() then return end
    local mod = GetActiveModule()
    if mod then mod.OnMouseMove() end
end

function HandleTouchBegin(eventType, eventData)
    if Intro.IsActive() then
        -- 触摸也可跳过视频
        Intro.Skip()
        return
    end
    if PhaseOverlay.IsTransitioning() then return end
    if PhaseIntro.IsActive() then return end
    if PauseMenu.IsVisible() then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local touchID = eventData["TouchID"]:GetInt()
    local mod = GetActiveModule()
    if mod and mod.OnTouchBegin then mod.OnTouchBegin(x, y, touchID) end
end

function HandleTouchMove(eventType, eventData)
    if Intro.IsActive() then return end
    if PhaseOverlay.IsTransitioning() then return end
    if PhaseIntro.IsActive() then return end
    if PauseMenu.IsVisible() then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local touchID = eventData["TouchID"]:GetInt()
    local mod = GetActiveModule()
    if mod and mod.OnTouchMove then mod.OnTouchMove(x, y, touchID) end
end

function HandleTouchEnd(eventType, eventData)
    if Intro.IsActive() then return end
    if PhaseOverlay.IsTransitioning() then return end
    if PhaseIntro.IsActive() then return end
    if PauseMenu.IsVisible() then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local touchID = eventData["TouchID"]:GetInt()
    local mod = GetActiveModule()
    if mod and mod.OnTouchEnd then mod.OnTouchEnd(x, y, touchID) end
end

--- NanoVG 渲染分发（唯一渲染入口）
function HandleNanoVGRender(eventType, eventData)
    local vg = NVG.Get()
    if not vg then return end
    
    -- 开场动画激活时，只渲染视频画面
    if Intro.IsActive() then
        local w = graphics:GetWidth()
        local h = graphics:GetHeight()
        local dpr = graphics:GetDPR()
        nvgBeginFrame(vg, w, h, 1.0)
        nvgScale(vg, dpr, dpr)
        Intro.Render(vg)
        nvgResetTransform(vg)
        nvgEndFrame(vg)
        return
    end
    
    -- 环节说明界面显示中不渲染游戏状态
    if not PhaseIntro.IsActive() then
        local mod = GetActiveModule()
        if mod then mod.Render(vg) end
    end

    -- PhaseOverlay 在所有状态之上渲染（倒数+碎片+黑屏过渡）
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    
    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)
    PhaseOverlay.Render(vg)
    nvgResetTransform(vg)
    nvgEndFrame(vg)

    -- 竖屏检测：宽 < 高时全屏覆盖提示旋转
    local lw = w / dpr
    local lh = h / dpr
    if lw < lh then
        nvgBeginFrame(vg, w, h, 1.0)
        nvgScale(vg, dpr, dpr)
        -- 全屏黑色遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, lw, lh)
        nvgFillColor(vg, nvgRGBA(15, 15, 20, 245))
        nvgFill(vg)
        -- 旋转图标（手机 + 旋转箭头简化表达）
        local cx, cy = lw / 2, lh / 2 - 30
        -- 手机矩形（竖向）
        nvgSave(vg)
        nvgTranslate(vg, cx, cy)
        nvgRotate(vg, math.rad(45))  -- 倾斜表示正在旋转
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -18, -30, 36, 60, 5)
        nvgStrokeColor(vg, nvgRGBA(200, 200, 210, 200))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
        -- 屏幕内部
        nvgBeginPath(vg)
        nvgRoundedRect(vg, -14, -24, 28, 48, 2)
        nvgFillColor(vg, nvgRGBA(60, 60, 80, 150))
        nvgFill(vg)
        nvgRestore(vg)
        -- 旋转箭头（弧形）
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, 45, math.rad(-60), math.rad(60), 2) -- NVG_CW=2
        nvgStrokeColor(vg, nvgRGBA(150, 200, 255, 200))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
        -- 箭头尖端
        local arrowX = cx + 45 * math.cos(math.rad(60))
        local arrowY = cy + 45 * math.sin(math.rad(60))
        nvgBeginPath(vg)
        nvgMoveTo(vg, arrowX - 6, arrowY - 8)
        nvgLineTo(vg, arrowX, arrowY)
        nvgLineTo(vg, arrowX + 8, arrowY - 4)
        nvgStrokeColor(vg, nvgRGBA(150, 200, 255, 200))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)
        -- 提示文字
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(200, 205, 210, 230))
        nvgText(vg, lw / 2, lh / 2 + 50, "请将设备旋转至横屏")
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(140, 140, 150, 180))
        nvgText(vg, lw / 2, lh / 2 + 78, "本游戏仅支持横屏模式")
        nvgResetTransform(vg)
        nvgEndFrame(vg)
    end
end

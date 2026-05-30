-- ============================================================================
-- States/ForgeState.lua - 锻造阶段状态
-- 包含两个简单小游戏：锤击（节奏点击）和 淬火（温度控制）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")

local ForgeState = {}

-- 颜色缓存（从 Config.Colors 统一引用，避免魔法数字）
local C_SUCCESS = Config.Colors.Success
local C_DANGER = Config.Colors.Danger
local C_GOLD = Config.Colors.Gold

local gameData_ = nil
local onComplete_ = nil

-- 音效
local hammerSound_ = nil
local quenchSound_ = nil
local audioScene_ = nil
local audioNode_ = nil
local hammerSource_ = nil  -- 锤击音源（预创建，复用）
local quenchSource_ = nil  -- 淬火循环音源（预创建，复用）

-- 锻造阶段
local PHASE_HAMMER = 1   -- 锤击
local PHASE_QUENCH = 2   -- 淬火
local PHASE_DONE = 3

local currentPhase_ = PHASE_HAMMER
local phaseTimer_ = 0
local totalScore_ = 0

-- 锤击阶段变量
local HAMMER_MAX_HITS = 5    -- 总共5次锤击
local hammerHits_ = 0        -- 已锤击次数
local hammerFlash_ = 0       -- 命中闪光效果
local hammerShake_ = 0       -- 铁砧震动效果
local hammerRhythm_ = 0      -- 节奏指示器当前位置 (0~1循环)
local hammerRhythmSpeed_ = 1.2  -- 节奏速度（秒/周期）
local hammerHitQuality_ = {}  -- 每次锤击的评分 (perfect/good/ok)
local hammerReady_ = true    -- 是否准备好接受下一次锤击（冷却中为false）
local hammerCooldown_ = 0    -- 锤击后短暂冷却
local hammerDone_ = false    -- 锤击是否已完成（等待展示结果）
local hammerResultTimer_ = 0 -- 锤击结果展示倒计时
local hammerScore_ = 0       -- 锤击阶段得分（用于展示）
local hammerWaitClick_ = false -- 锤击结果展示完毕后，等待玩家点击进入淬火
local hammerTimeLeft_ = 0    -- 锤击阶段剩余时间
local hammerZoneCenter_ = 0  -- 判定区域中心位置（-1~1范围内随机）
local HAMMER_RESULT_DURATION = 1.0  -- 锤击结果展示时间（秒）

-- 淬火阶段变量
local QUENCH_TIME_LIMIT = 5.0  -- 淬火时间限制（秒）
local quenchTemp_ = 800      -- 当前温度
local quenchTarget_ = 450    -- 目标温度
local quenchTolerance_ = 30  -- 目标容差范围（±30度内为完美）
local quenchHolding_ = false -- 是否正在按住冷却
local quenchHoldTime_ = 0    -- 本次按住持续时间（用于加速降温）
local quenchScore_ = 0       -- 淬火评分
local quenchDone_ = false
local quenchTimer_ = 0       -- 淬火已用时间

-- 延迟结束计时器（替代旧的匿名事件订阅）
local finishTimer_ = -1      -- <0 表示未激活

-- 前向声明内部函数（避免全局泄漏）
local InitHammerPhase
local InitQuenchPhase
local FinalizeHammer
local UpdateHammer
local UpdateQuench
local FinishQuench
local EvaluateHammerTiming
local PlayHammerSound
local StartQuenchSound
local StopQuenchSound
local OnForgeInput
local OnForgeInputRelease
local RenderHammerPhase
local RenderQuenchPhase

--- 进入锻造状态
function ForgeState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    currentPhase_ = PHASE_HAMMER
    phaseTimer_ = 0
    totalScore_ = 0
    finishTimer_ = -1
    
    -- 预创建音频节点和音源（避免首次播放延迟）
    audioScene_ = Scene()
    audioNode_ = audioScene_:CreateChild("ForgeSFX")
    
    -- 加载音效
    hammerSound_ = cache:GetResource("Sound", "audio/sfx/forge_hammer_hit.ogg")
    if hammerSound_ then
        hammerSound_.looped = false
    end
    quenchSound_ = cache:GetResource("Sound", "audio/sfx/forge_quench_loop.ogg")
    if quenchSound_ then
        quenchSound_.looped = true
    end
    
    -- 预创建音源并静音预播放（warm-up：不立即Stop，让音频管线真正解码）
    hammerSource_ = audioNode_:CreateComponent("SoundSource")
    hammerSource_.soundType = SOUND_EFFECT
    hammerSource_.gain = 0.0
    if hammerSound_ then
        hammerSource_:Play(hammerSound_)  -- 静音播放，非循环会自然结束
    end
    
    quenchSource_ = audioNode_:CreateComponent("SoundSource")
    quenchSource_.soundType = SOUND_EFFECT
    quenchSource_.gain = 0.0
    if quenchSound_ then
        quenchSource_:Play(quenchSound_)  -- 静音播放，触发解码管线
    end
    
    -- 初始化锤击
    InitHammerPhase()
    
    print("[ForgeState] Entered. Weapon type: " .. tostring(gameData_.weaponType))
end

--- 离开锻造状态
function ForgeState.Leave()
    finishTimer_ = -1
    quenchHolding_ = false
    StopQuenchSound()
    hammerSource_ = nil
    quenchSource_ = nil
    if audioNode_ then
        audioNode_:Remove()
        audioNode_ = nil
    end
    if audioScene_ then
        audioScene_:Dispose()
        audioScene_ = nil
    end
end

--- 随机生成判定区域位置
--- 区域结构：perfect(10%) + good两侧(30%) = 40%，需确保全部在[-1,1]内
local PERFECT_HALF = Config.Forge.PerfectHalf
local GOOD_HALF = Config.Forge.GoodHalf
local ZONE_MARGIN = Config.Forge.ZoneMargin

local function RandomizeZoneCenter()
    -- 区域中心范围：[-0.60, 0.60]
    hammerZoneCenter_ = (math.random() * 2 - 1) * (1.0 - ZONE_MARGIN)
end

--- 初始化锤击阶段
InitHammerPhase = function()
    hammerHits_ = 0
    hammerFlash_ = 0
    hammerShake_ = 0
    hammerRhythm_ = 0
    hammerHitQuality_ = {}
    hammerReady_ = true
    hammerCooldown_ = 0
    hammerDone_ = false
    hammerWaitClick_ = false
    hammerResultTimer_ = 0
    hammerScore_ = 0
    hammerTimeLeft_ = Config.Forge.HammerDuration
    phaseTimer_ = 0
    RandomizeZoneCenter()
    
    print("[Forge/Hammer] Ready for " .. HAMMER_MAX_HITS .. " strikes, time limit: " .. Config.Forge.HammerDuration .. "s")
end

--- 初始化淬火阶段
---@diagnostic disable-next-line: redefined-local
InitQuenchPhase = function()
    quenchTemp_ = 800 + math.random(0, 100)  -- 随机起始温度
    quenchTarget_ = 300 + math.random(0, 200) -- 随机目标（300~500）
    quenchTolerance_ = 30
    quenchHolding_ = false
    quenchHoldTime_ = 0
    quenchScore_ = 0
    quenchDone_ = false
    quenchTimer_ = 0
    phaseTimer_ = 0
    
    print("[Forge/Quench] Start temp: " .. quenchTemp_ .. " Target: " .. quenchTarget_)
end

--- 构建锻造 UI
function ForgeState.BuildUI()
    return UI.Panel {
        width = "100%", height = "100%",
        children = {
            -- 顶部信息
            UI.Panel {
                width = "100%",
                padding = 12,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                backgroundColor = Config.Colors.BgDark,
                children = {
                    UI.Label {
                        id = "forgePhaseLabel",
                        text = "🔨 锤击锻打",
                        fontSize = 16,
                        fontColor = Config.Colors.TextLight,
                    },
                    UI.Label {
                        id = "forgeScoreLabel",
                        text = "评分: 0",
                        fontSize = 14,
                        fontColor = Config.Colors.Gold,
                    },
                },
            },
            -- 中间区域由 NanoVG 渲染
            UI.Panel {
                width = "100%", flexGrow = 1,
                pointerEvents = "none",
            },
            -- 底部提示
            UI.Panel {
                width = "100%",
                padding = 12,
                alignItems = "center",
                backgroundColor = Config.Colors.BgDark,
                children = {
                    UI.Label {
                        id = "forgeHintLabel",
                        text = "跟随节拍点击屏幕！",
                        fontSize = 13,
                        fontColor = { 180, 180, 200, 200 },
                    },
                },
            },
        },
    }
end

--- 更新
function ForgeState.Update(dt)
    -- 延迟结束计时器
    if finishTimer_ >= 0 then
        finishTimer_ = finishTimer_ + dt
        if finishTimer_ >= Config.Forge.FinishDelay then
            finishTimer_ = -1
            if onComplete_ then onComplete_() end
        end
        return  -- 等待结束期间不再更新游戏逻辑
    end

    phaseTimer_ = phaseTimer_ + dt
    
    if currentPhase_ == PHASE_HAMMER then
        UpdateHammer(dt)
    elseif currentPhase_ == PHASE_QUENCH then
        UpdateQuench(dt)
    end
end

--- 计算锤击得分并进入结果展示
FinalizeHammer = function()
    if hammerDone_ then return end
    
    local hitCount = math.min(hammerHits_, HAMMER_MAX_HITS)
    if hitCount == 0 then
        -- 一次都没锤：最低分
        hammerScore_ = 10
    else
        local totalQuality = 0
        for i = 1, hitCount do
            local q = hammerHitQuality_[i]
            if q == "perfect" then totalQuality = totalQuality + 100
            elseif q == "good" then totalQuality = totalQuality + 70
            else totalQuality = totalQuality + 20  -- miss: 很低分
            end
        end
        -- 基础质量分 × 完成率
        local qualityAvg = totalQuality / hitCount
        local completionRate = hitCount / HAMMER_MAX_HITS
        hammerScore_ = math.floor(qualityAvg * completionRate)
    end
    
    totalScore_ = totalScore_ + hammerScore_
    hammerDone_ = true
    hammerResultTimer_ = 0
    
    print("[Forge/Hammer] Done! Hits: " .. hitCount .. "/" .. HAMMER_MAX_HITS .. " Score: " .. hammerScore_)
end

--- 锤击更新
UpdateHammer = function(dt)
    -- 衰减闪光和震动
    if hammerFlash_ > 0 then hammerFlash_ = hammerFlash_ - dt * 4 end
    if hammerShake_ > 0 then hammerShake_ = hammerShake_ - dt * 6 end
    
    -- 如果已完成锤击，等待结果展示时间，然后等待玩家点击
    if hammerDone_ then
        if not hammerWaitClick_ then
            hammerResultTimer_ = hammerResultTimer_ + dt
            if hammerResultTimer_ >= HAMMER_RESULT_DURATION then
                hammerWaitClick_ = true  -- 展示完毕，等待玩家点击
            end
        end
        return
    end
    
    -- 倒计时
    hammerTimeLeft_ = hammerTimeLeft_ - dt
    if hammerTimeLeft_ <= 0 then
        hammerTimeLeft_ = 0
        FinalizeHammer()
        return
    end
    
    -- 冷却计时（锤击后短暂不可再锤）
    if not hammerReady_ then
        hammerCooldown_ = hammerCooldown_ - dt
        if hammerCooldown_ <= 0 then
            hammerReady_ = true
        end
    end
    
    -- 节奏指示器循环 (0→1→0→1...)：使用 sin 曲线创造来回摆动效果
    hammerRhythm_ = hammerRhythm_ + dt / hammerRhythmSpeed_
    if hammerRhythm_ > 1.0 then
        hammerRhythm_ = hammerRhythm_ - 1.0
    end
    
    -- 5次锤击完成 → 计算得分并进入结果展示
    if hammerHits_ >= HAMMER_MAX_HITS then
        FinalizeHammer()
    end
end

--- 评估锤击时机质量
--- rhythmPos = sin(...) 范围 -1~1，光标位置：0=中心，±1=边缘
--- 黄色中心 = perfect，灰色中间 = good，黑色边缘 = miss
---@diagnostic disable-next-line: redefined-local
EvaluateHammerTiming = function()
    local pos = math.sin(hammerRhythm_ * math.pi * 2)  -- 光标位置 -1~1
    local dist = math.abs(pos - hammerZoneCenter_)      -- 离区域中心的距离
    
    if dist <= PERFECT_HALF then
        return "perfect"   -- 光标在黄色区域(10%)
    elseif dist <= GOOD_HALF then
        return "good"      -- 光标在灰色区域(30%)
    else
        return "miss"      -- 光标在黑色区域(60%)
    end
end

--- 淬火更新
UpdateQuench = function(dt)
    if quenchDone_ then return end
    
    -- 更新倒计时
    quenchTimer_ = quenchTimer_ + dt
    
    -- 只有按住时才降温（越按越快）
    if quenchHolding_ then
        quenchHoldTime_ = quenchHoldTime_ + dt
        -- 基础速率120°/s，每秒额外加速100°/s → 按住越久降温越猛
        local rate = 120 + quenchHoldTime_ * 100
        quenchTemp_ = quenchTemp_ - dt * rate
    end
    
    -- 3秒时间到，强制截止
    if quenchTimer_ >= QUENCH_TIME_LIMIT then
        FinishQuench()
        return
    end
    
    -- 温度降到0也结束
    if quenchTemp_ <= 0 then
        quenchTemp_ = 0
        FinishQuench()
    end
end

--- 结束淬火，计算得分
FinishQuench = function()
    if quenchDone_ then return end
    quenchDone_ = true
    quenchHolding_ = false
    StopQuenchSound()
    
    -- 计算精确度得分（温度距离目标越近分越高）
    local diff = math.abs(quenchTemp_ - quenchTarget_)
    if diff <= 15 then
        quenchScore_ = 100  -- 完美
    elseif diff <= 30 then
        quenchScore_ = 85   -- 优秀
    elseif diff <= 60 then
        quenchScore_ = 65   -- 良好
    elseif diff <= 100 then
        quenchScore_ = 45   -- 一般
    elseif diff <= 150 then
        quenchScore_ = 25   -- 较差
    else
        quenchScore_ = 10   -- 很差
    end
    
    -- 总分计算
    totalScore_ = totalScore_ + quenchScore_
    local finalScore = math.floor(totalScore_ / 2)  -- 两阶段平均
    gameData_.forgeScore = finalScore
    gameData_.hammerScore = hammerScore_
    gameData_.quenchScore = quenchScore_
    
    -- 确定品质
    for i = #Config.Quality, 1, -1 do
        if finalScore >= Config.Quality[i].threshold then
            gameData_.quality = Config.Quality[i]
            break
        end
    end
    
    print("[Forge/Quench] Done! Temp: " .. math.floor(quenchTemp_) .. " Target: " .. quenchTarget_ .. " Diff: " .. math.floor(diff) .. " Score: " .. quenchScore_)
    print("[Forge] Quality: " .. (gameData_.quality and gameData_.quality.name or "???"))
    
    -- 启动延迟结束计时器
    finishTimer_ = 0
end

--- 播放锤击音效（复用预创建音源，无首次延迟）
---@diagnostic disable-next-line: redefined-local
PlayHammerSound = function()
    if not hammerSound_ or not hammerSource_ then return end
    hammerSource_.gain = 1.0
    hammerSource_:Play(hammerSound_)
end

--- 开始播放淬火循环音效（复用预创建音源，无首次延迟）
---@diagnostic disable-next-line: redefined-local
StartQuenchSound = function()
    if not quenchSound_ or not quenchSource_ then return end
    if quenchSource_.gain > 0.5 and quenchSource_:IsPlaying() then return end  -- 已正式播放中
    quenchSource_.gain = 1.0
    quenchSource_:Play(quenchSound_)
end

--- 停止淬火循环音效
---@diagnostic disable-next-line: redefined-local
StopQuenchSound = function()
    if quenchSource_ then
        quenchSource_:Stop()
        quenchSource_.gain = 0.0
    end
end

--- 处理玩家点击（锤击判定）
OnForgeInput = function()
    if finishTimer_ >= 0 then return end  -- 等待结束中忽略输入

    if currentPhase_ == PHASE_HAMMER then
        -- 锤击完成后等待点击进入淬火
        if hammerWaitClick_ then
            currentPhase_ = PHASE_QUENCH
            InitQuenchPhase()
            return
        end
        -- 锤击结果展示中忽略输入
        if hammerDone_ then return end
        -- 必须冷却完毕才能再次锤击
        if not hammerReady_ then return end
        if hammerHits_ < HAMMER_MAX_HITS then
            -- 评估时机
            local quality = EvaluateHammerTiming()
            hammerHits_ = hammerHits_ + 1
            hammerHitQuality_[hammerHits_] = quality
            
            -- 视觉反馈强度根据时机质量变化
            if quality == "perfect" then
                hammerFlash_ = 1.0
                hammerShake_ = 1.0
            elseif quality == "good" then
                hammerFlash_ = 0.7
                hammerShake_ = 0.7
            else
                -- miss: 微弱反馈
                hammerFlash_ = 0.3
                hammerShake_ = 0.2
            end
            
            -- 短暂冷却防止连点
            hammerReady_ = false
            hammerCooldown_ = 0.3
            
            PlayHammerSound()
        end
    elseif currentPhase_ == PHASE_QUENCH then
        if not quenchDone_ then
            quenchHolding_ = true
            StartQuenchSound()
        end
    end
end

OnForgeInputRelease = function()
    if currentPhase_ == PHASE_QUENCH and not quenchDone_ then
        -- 松开即结束淬火（与超时效果相同）
        if quenchHolding_ then
            FinishQuench()
        end
    end
end

--- 按键
function ForgeState.OnKeyDown(key)
    if key == KEY_SPACE then
        OnForgeInput()
    end
end

function ForgeState.OnKeyUp(key)
    if key == KEY_SPACE then
        OnForgeInputRelease()
    end
end

-- ============================================================================
-- 输入（由 main.lua 分发）
-- ============================================================================

function ForgeState.OnMouseDown(button)
    if button == MOUSEB_LEFT then
        OnForgeInput()
    end
end

function ForgeState.OnMouseUp(button)
    if button == MOUSEB_LEFT then
        OnForgeInputRelease()
    end
end

function ForgeState.OnTouchBegin(x, y)
    OnForgeInput()
end

function ForgeState.OnMouseMove()
end

function ForgeState.OnTouchMove(x, y)
end

function ForgeState.OnTouchEnd(x, y)
    OnForgeInputRelease()
end

-- ============================================================================
-- NanoVG 渲染（由 main.lua HandleNanoVGRender 调用）
-- ============================================================================

function ForgeState.Render(vg)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local lw = w / dpr
    local lh = h / dpr
    
    nvgBeginFrame(vg, w, h, 1.0)
    nvgScale(vg, dpr, dpr)
    
    -- 背景（UI 根面板透明，由 NanoVG 绘制底色）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, lw, lh)
    nvgFillColor(vg, nvgRGBA(
        Config.Colors.BgDark[1],
        Config.Colors.BgDark[2],
        Config.Colors.BgDark[3],
        Config.Colors.BgDark[4]
    ))
    nvgFill(vg)
    
    if currentPhase_ == PHASE_HAMMER then
        RenderHammerPhase(vg, lw, lh)
    elseif currentPhase_ == PHASE_QUENCH then
        RenderQuenchPhase(vg, lw, lh)
    end
    
    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

--- 渲染铁砧和锤子动画
local function RenderAnvilAndHammer(vg, cx, cy, shakeX, shakeY)
    -- 命中闪光
    if hammerFlash_ > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, cx + shakeX, cy + shakeY, 60 + (1 - hammerFlash_) * 40)
        nvgFillColor(vg, nvgRGBA(200, 80, 40, math.floor(hammerFlash_ * 120)))
        nvgFill(vg)
    end
    
    -- 铁砧
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 80 + shakeX, cy - 20 + shakeY, 160, 50, 8)
    nvgFillColor(vg, nvgRGBA(80, 75, 70, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 70 + shakeX, cy - 15 + shakeY, 140, 8, 4)
    nvgFillColor(vg, nvgRGBA(120, 115, 110, 255))
    nvgFill(vg)
    
    -- 锤子（跟随节奏摆动）
    local rhythmPos = math.sin(hammerRhythm_ * math.pi * 2)
    local hammerRestY = cy - 80
    local hammerY = hammerRestY
    if hammerFlash_ > 0.5 then
        hammerY = cy - 30
    else
        local floatRange = 25
        hammerY = hammerRestY - (rhythmPos + 1) * 0.5 * floatRange
    end
    
    -- 锤柄
    nvgBeginPath(vg)
    nvgRect(vg, cx - 4 + shakeX, hammerY + shakeY, 8, 45)
    nvgFillColor(vg, nvgRGBA(120, 90, 60, 255))
    nvgFill(vg)
    -- 锤头
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 18 + shakeX, hammerY - 22 + shakeY, 36, 24, 4)
    nvgFillColor(vg, nvgRGBA(160, 150, 140, 255))
    nvgFill(vg)
end

--- 渲染节奏指示条（判定区域 + 移动光标）
local function RenderRhythmBar(vg, cx, cy)
    local barW = 200
    local barH = 18
    local barX = cx - barW / 2
    local barY = cy + 55
    
    -- 指示条背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 6)
    nvgFillColor(vg, nvgRGBA(35, 36, 42, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(80, 85, 95, 220))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    
    -- 区域中心像素位置
    local zoneCenterX = cx + hammerZoneCenter_ * (barW / 2 - 6)
    
    -- good 区域
    local goodZonePixelW = GOOD_HALF * 2 * (barW / 2 - 6)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, zoneCenterX - goodZonePixelW / 2, barY + 2, goodZonePixelW, barH - 4, 4)
    nvgFillColor(vg, nvgRGBA(70, 75, 85, 120))
    nvgFill(vg)
    
    -- perfect 区域
    local perfectZonePixelW = PERFECT_HALF * 2 * (barW / 2 - 6)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, zoneCenterX - perfectZonePixelW / 2, barY + 2, perfectZonePixelW, barH - 4, 4)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 100))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    
    -- 移动光标
    local rhythmPos = math.sin(hammerRhythm_ * math.pi * 2)
    local cursorX = cx + rhythmPos * (barW / 2 - 6)
    local distToZone = math.abs(rhythmPos - hammerZoneCenter_)
    
    -- 光标发光（在 perfect 区内时）
    if distToZone <= PERFECT_HALF then
        nvgBeginPath(vg)
        nvgCircle(vg, cursorX, barY + barH / 2, 14)
        nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 50))
        nvgFill(vg)
    end
    
    -- 光标本体
    nvgBeginPath(vg)
    nvgCircle(vg, cursorX, barY + barH / 2, 8)
    if distToZone <= PERFECT_HALF then
        nvgFillColor(vg, nvgRGBA(160, 140, 90, 255))
    elseif distToZone <= GOOD_HALF then
        nvgFillColor(vg, nvgRGBA(120, 130, 140, 255))
    else
        nvgFillColor(vg, nvgRGBA(90, 95, 105, 255))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    
    -- 冷却中显示暗淡
    if not hammerReady_ then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
        nvgFill(vg)
    end
end

--- 渲染锤击进度圆点
local function RenderHammerDots(vg, cx, cy)
    local dotSpacing = 32
    local dotsStartX = cx - (HAMMER_MAX_HITS - 1) * dotSpacing / 2
    local dotsY = cy + 95
    
    for i = 1, HAMMER_MAX_HITS do
        local dotX = dotsStartX + (i - 1) * dotSpacing
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotsY, 9)
        if i <= hammerHits_ then
            local q = hammerHitQuality_[i]
            if q == "perfect" then
                nvgFillColor(vg, nvgRGBA(C_SUCCESS[1], C_SUCCESS[2], C_SUCCESS[3], 255))
            elseif q == "good" then
                nvgFillColor(vg, nvgRGBA(120, 130, 140, 255))
            else
                nvgFillColor(vg, nvgRGBA(C_DANGER[1], C_DANGER[2], C_DANGER[3], 255))
            end
        else
            nvgFillColor(vg, nvgRGBA(20, 22, 28, 255))
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotsY, 9)
        nvgStrokeColor(vg, nvgRGBA(50, 50, 55, 180))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end
    
    return dotsY
end

--- 渲染锤击 HUD（倒计时、结果面板、提示、反馈）
local function RenderHammerHUD(vg, w, cx, cy, dotsY)
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    nvgFontFaceId(vg, fontId)
    
    -- 倒计时（右上角）
    if not hammerDone_ then
        local timeText = string.format("%.1f", math.max(0, hammerTimeLeft_))
        nvgFontSize(vg, 16)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        if hammerTimeLeft_ <= 3.0 then
            nvgFillColor(vg, nvgRGBA(C_DANGER[1], C_DANGER[2], C_DANGER[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(120, 130, 140, 200))
        end
        nvgText(vg, w - 16, 50, timeText .. "s", nil)
    end
    
    -- 锤击结果展示
    if hammerDone_ then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 110, cy - 60, 220, 90, 12)
        nvgFillColor(vg, nvgRGBA(20, 22, 28, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 150))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        
        nvgFontSize(vg, 20)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(160, 140, 90, 255))
        nvgText(vg, cx, cy - 40, "锤击完成!", nil)
        
        local gradeText
        local gr, gg, gb = 200, 205, 210
        if hammerScore_ >= 90 then
            gradeText = "完美锻造 " .. hammerScore_ .. "分"
            gr, gg, gb = 160, 140, 90
        elseif hammerScore_ >= 70 then
            gradeText = "优秀锻造 " .. hammerScore_ .. "分"
            gr, gg, gb = 80, 200, 120
        elseif hammerScore_ >= 50 then
            gradeText = "普通锻造 " .. hammerScore_ .. "分"
            gr, gg, gb = 120, 130, 140
        else
            gradeText = "粗糙锻造 " .. hammerScore_ .. "分"
            gr, gg, gb = 240, 80, 80
        end
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(gr, gg, gb, 255))
        nvgText(vg, cx, cy - 10, gradeText, nil)
        
        nvgFontSize(vg, 14)
        if hammerWaitClick_ then
            nvgFillColor(vg, nvgRGBA(160, 140, 90, 255))
            nvgText(vg, cx, cy + 16, "👆 点击进入淬火", nil)
        else
            nvgFillColor(vg, nvgRGBA(120, 130, 140, 180))
            nvgText(vg, cx, cy + 16, "准备进入淬火...", nil)
        end
        return
    end
    
    -- 锤击计数
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 255))
    nvgText(vg, cx, cy - 120, hammerHits_ .. " / " .. HAMMER_MAX_HITS, nil)
    
    -- 提示文字
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(120, 130, 140, 200))
    if hammerReady_ then
        nvgText(vg, cx, dotsY + 18, "光标到金色区域时点击!", nil)
    else
        nvgText(vg, cx, dotsY + 18, "等待...", nil)
    end
    
    -- 上次锤击质量反馈
    if hammerFlash_ > 0 and hammerHits_ > 0 then
        local lastQ = hammerHitQuality_[hammerHits_]
        local qText = ""
        local qr, qg, qb = 200, 205, 210
        if lastQ == "perfect" then
            qText = "完美!"
            qr, qg, qb = 160, 140, 90
        elseif lastQ == "good" then
            qText = "不错"
            qr, qg, qb = 120, 130, 140
        else
            qText = "失误!"
            qr, qg, qb = 200, 60, 60
        end
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(qr, qg, qb, math.floor(hammerFlash_ * 255)))
        nvgText(vg, cx, cy - 55, qText, nil)
    end
end

--- 锤击阶段主渲染入口
RenderHammerPhase = function(vg, w, h)
    local cx = w / 2
    local cy = h / 2
    
    -- 震动偏移
    local shakeX = 0
    local shakeY = 0
    if hammerShake_ > 0 then
        shakeX = (math.random() - 0.5) * hammerShake_ * 6
        shakeY = (math.random() - 0.5) * hammerShake_ * 6
    end
    
    RenderAnvilAndHammer(vg, cx, cy, shakeX, shakeY)
    RenderRhythmBar(vg, cx, cy)
    local dotsY = RenderHammerDots(vg, cx, cy)
    RenderHammerHUD(vg, w, cx, cy, dotsY)
end

--- 渲染淬火倒计时
local function RenderQuenchCountdown(vg, cx, cy, fontId)
    local remaining = math.max(0, QUENCH_TIME_LIMIT - quenchTimer_)
    local countdownText = string.format("%.1f", remaining)
    local countdownY = cy - 100
    local pulseScale = 1.0
    if remaining < 1.0 and not quenchDone_ then
        pulseScale = 1.0 + math.sin(phaseTimer_ * 12) * 0.08
    end
    
    nvgBeginPath(vg)
    nvgCircle(vg, cx, countdownY, 38 * pulseScale)
    if remaining < 1.0 then
        nvgFillColor(vg, nvgRGBA(240, 80, 80, 200))
    elseif remaining < 2.0 then
        nvgFillColor(vg, nvgRGBA(200, 80, 40, 180))
    else
        nvgFillColor(vg, nvgRGBA(50, 50, 55, 180))
    end
    nvgFill(vg)
    
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, 36 * pulseScale)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    if quenchDone_ then
        nvgText(vg, cx, countdownY, "停!", nil)
    else
        nvgText(vg, cx, countdownY, countdownText, nil)
    end
end

--- 渲染温度计（温度条 + 目标线 + 当前温度）
local function RenderThermometer(vg, cx, cy, fontId)
    local barW = 44
    local barH = 180
    local barX = cx - barW / 2
    local barY = cy - 30
    
    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 4, barY - 4, barW + 8, barH + 8, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 55, 255))
    nvgFill(vg)
    
    -- 温度填充
    local maxTemp = 900
    local fillRatio = math.max(0, math.min(1, quenchTemp_ / maxTemp))
    local fillH = barH * fillRatio
    
    local r, g, b
    if fillRatio > 0.6 then
        r, g, b = 200, 80, 40      -- 炭火红（高温）
    elseif fillRatio > 0.3 then
        r, g, b = 160, 140, 90     -- 旧金（中温）
    else
        r, g, b = 150, 200, 255    -- 冰霜蓝（低温）
    end
    
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY + (barH - fillH), barW, fillH, 4)
    nvgFillColor(vg, nvgRGBA(r, g, b, 230))
    nvgFill(vg)
    
    -- 目标区域高亮
    local targetRatio = quenchTarget_ / maxTemp
    local targetY = barY + barH * (1 - targetRatio)
    local tolRatioHalf = (quenchTolerance_ / maxTemp) * barH
    nvgBeginPath(vg)
    nvgRect(vg, barX - 12, targetY - tolRatioHalf, barW + 24, tolRatioHalf * 2)
    nvgFillColor(vg, nvgRGBA(150, 200, 255, 35))
    nvgFill(vg)
    
    -- 目标线
    nvgBeginPath(vg)
    nvgMoveTo(vg, barX - 16, targetY)
    nvgLineTo(vg, barX + barW + 16, targetY)
    nvgStrokeColor(vg, nvgRGBA(150, 200, 255, 255))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)
    
    -- 目标温度标签
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(150, 200, 255, 255))
    nvgText(vg, barX + barW + 20, targetY, math.floor(quenchTarget_) .. "°", nil)
    
    -- 当前温度数字
    nvgFontSize(vg, 22)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgText(vg, cx, barY + barH + 14, math.floor(quenchTemp_) .. "°", nil)
    
    return barY + barH  -- 返回底部 Y 坐标，供状态提示使用
end

--- 渲染淬火状态提示
local function RenderQuenchStatus(vg, cx, barBottom)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if quenchDone_ then
        local diff = math.abs(quenchTemp_ - quenchTarget_)
        local resultText
        if diff <= 15 then
            resultText = "完美淬火!"
            nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 255))
        elseif diff <= 30 then
            resultText = "优秀!"
            nvgFillColor(vg, nvgRGBA(C_SUCCESS[1], C_SUCCESS[2], C_SUCCESS[3], 255))
        elseif diff <= 60 then
            resultText = "良好"
            nvgFillColor(vg, nvgRGBA(150, 200, 255, 255))
        else
            resultText = "偏差较大"
            nvgFillColor(vg, nvgRGBA(120, 130, 140, 255))
        end
        nvgFontSize(vg, 22)
        nvgText(vg, cx, barBottom + 42, resultText, nil)
    else
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgFontSize(vg, 18)
        if quenchHolding_ then
            nvgText(vg, cx, barBottom + 42, "淬火中... 松开即停止!", nil)
        else
            nvgText(vg, cx, barBottom + 42, "按住淬火，松开停止!", nil)
            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(150, 200, 255, 200))
            nvgText(vg, cx, barBottom + 64, "停在蓝线上!", nil)
        end
    end
end

--- 淬火阶段主渲染入口
RenderQuenchPhase = function(vg, w, h)
    local cx = w / 2
    local cy = h / 2
    
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    
    RenderQuenchCountdown(vg, cx, cy, fontId)
    local barBottom = RenderThermometer(vg, cx, cy, fontId)
    RenderQuenchStatus(vg, cx, barBottom)
end

return ForgeState

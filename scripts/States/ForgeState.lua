-- ============================================================================
-- States/ForgeState.lua - 锻造阶段状态（自适应布局修复版）
-- 包含两个简单小游戏：锤击（节奏点击）和 淬火（温度控制）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")
local KeyBindings = require("KeyBindings")
local GameSettings = require("GameSettings")

local ForgeState = {}

-- 颜色缓存（从 Config.Colors 统一引用，避免魔法数字）
local C_SUCCESS = Config.Colors.Success
local C_DANGER  = Config.Colors.Danger
local C_GOLD     = Config.Colors.Gold

local gameData_ = nil
local onComplete_ = nil

-- 音效
local hammerSound_  = nil
local quenchSound_ = nil
local grindSound_   = nil
local audioScene_   = nil
local audioNode_    = nil
local hammerSource_ = nil  -- 锤击音源（预创建，复用）
local quenchSource_ = nil  -- 淬火循环音源（预创建，复用）
local grindSource_  = nil  -- 砥砺磨刀音源（预创建，复用）

-- 锻造阶段
local PHASE_HAMMER  = 1   -- 锤击
local PHASE_QUENCH  = 2   -- 淬火
local PHASE_GRIND   = 3   -- 砥砺
local PHASE_DONE    = 4

local currentPhase_    = PHASE_HAMMER
local phaseTimer_      = 0
local totalScore_      = 0

-- 锤击阶段变量
local HAMMER_MAX_HITS    = 5     -- 总共5次锤击
local hammerHits_        = 0      -- 已锤击次数
local hammerFlash_       = 0      -- 命中闪光效果
local hammerShake_       = 0      -- 铁砧震动效果
local hammerRhythm_      = 0      -- 节奏指示器当前位置 (0~1循环)
local hammerRhythmSpeed_ = 1.2    -- 节奏速度（秒/周期）
local hammerHitQuality_  = {}     -- 每次锤击的评分 (perfect/good/ok)
local hammerReady_       = true    -- 是否准备好接受下一次锤击（冷却中为false）
local hammerCooldown_    = 0      -- 锤击后短暂冷却
local hammerDone_        = false   -- 锤击是否已完成（等待展示结果）
local hammerResultTimer_  = 0      -- 锤击结果展示倒计时
local hammerScore_        = 0      -- 锤击阶段得分（用于展示）
local hammerWaitClick_    = false   -- 锤击结果展示完毕后，等待玩家点击进入淬火
local hammerTimeLeft_     = 0      -- 锤击阶段剩余时间
local hammerZoneCenter_   = 0      -- 判定区域中心位置（-1~1范围内随机）
local HAMMER_RESULT_DURATION = 1.0  -- 锤击结果展示时间（秒）

-- 淬火阶段变量
local QUENCH_TIME_LIMIT = GameSettings.GetQuenchTime()  -- 淬火时间限制（秒）
local quenchTemp_        = 800    -- 当前温度
local quenchTarget_      = 450    -- 目标温度
local quenchTolerance_   = 30     -- 目标容差范围（±30度内为完美）
local quenchHolding_     = false   -- 是否正在按住冷却
local quenchHoldTime_    = 0      -- 本次按住持续时间（用于加速降温）
local quenchScore_       = 0      -- 淬火评分
local quenchDone_        = false
local quenchTimer_       = 0      -- 淬火已用时间

-- 砥砺阶段变量
local GRIND_TIME_LIMIT   = GameSettings.GetGrindTime()  -- 砥砺时间限制
local GRIND_KEYS         = KeyBindings.GetGrindKeyNames() -- 从按键配置获取显示名
local grindCount_        = 0      -- 完成打磨次数
local grindKeyIndex_     = 1      -- 当前期待的按键序列索引（1~3）
local grindTimer_        = 0      -- 砥砺已用时间
local grindDone_         = false  -- 砥砺是否结束
local grindScore_        = 0      -- 砥砺得分
local grindFlash_        = 0      -- 按对闪光
local grindMissFlash_    = 0      -- 按错闪光
local grindWaitClick_    = false  -- 淬火结果展示后等待点击进入砥砺
local grindResultTimer_  = 0      -- 砥砺结果展示倒计时
local grindDragging_     = false  -- 鼠标/触摸拖动中
local grindLastDragZone_ = 0      -- 上次拖动经过的按键区域索引（0=无）

-- 延迟结束计时器（替代旧的匿名事件订阅）
local finishTimer_ = -1      -- <0 表示未激活

-- 前向声明内部函数（避免全局泄漏）
local InitHammerPhase
local InitQuenchPhase
local InitGrindPhase
local FinalizeHammer
local UpdateHammer
local UpdateQuench
local UpdateGrind
local FinishQuench
local FinishGrind
local EvaluateHammerTiming
local PlayHammerSound
local StartQuenchSound
local StopQuenchSound
local OnForgeInput
local OnForgeInputRelease
local GetGrindZoneAtPos
local HandleGrindDrag
local RenderHammerPhase
local RenderQuenchPhase
local RenderGrindPhase


-- 阶段切换回调（通知外部倒数系统）
local onPhaseChange_ = nil

--- 进入锻造状态
--- @param gameData table 游戏共享数据
--- @param onComplete function 锻造完成回调
--- @param onPhaseChange function|nil 阶段切换回调(phaseStr) "quench"/"grind"
function ForgeState.Enter(gameData, onComplete, onPhaseChange)
    gameData_    = gameData
    onComplete_  = onComplete
    onPhaseChange_ = onPhaseChange
    currentPhase_ = PHASE_HAMMER
    phaseTimer_   = 0
    totalScore_   = 0
    finishTimer_  = -1
    
    -- 预创建音频节点和音源（避免首次播放延迟）
    audioScene_ = Scene()
    audioNode_  = audioScene_:CreateChild("ForgeSFX")
    
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

    grindSound_ = cache:GetResource("Sound", "audio/sfx/forge_grind.ogg")
    if grindSound_ then
        grindSound_.looped = false
    end
    grindSource_ = audioNode_:CreateComponent("SoundSource")
    grindSource_.soundType = SOUND_EFFECT
    grindSource_.gain = 0.0
    if grindSound_ then
        grindSource_:Play(grindSound_)  -- 静音播放预热
    end
    
    -- 初始化锤击
    InitHammerPhase()
    
    print("[ForgeState] Entered. Weapon type: " .. tostring(gameData_.weaponType))
end


--- 离开锻造状态
function ForgeState.Leave()
    -- 停止所有播放中的音效
    StopQuenchSound()

    -- 释放音频子系统
    hammerSource_ = nil
    quenchSource_ = nil
    grindSource_  = nil
    if audioNode_ then
        audioNode_:Remove()
        audioNode_ = nil
    end
    if audioScene_ then
        audioScene_:Dispose()
        audioScene_ = nil
    end

    -- 释放 Sound 资源引用（让 ResourceCache 可以回收）
    hammerSound_ = nil
    quenchSound_ = nil
    grindSound_  = nil

    -- 重置全部状态变量，释放表内存
    currentPhase_    = PHASE_HAMMER
    phaseTimer_      = 0
    totalScore_      = 0
    finishTimer_     = -1
    hammerHits_      = 0
    hammerFlash_     = 0
    hammerShake_     = 0
    hammerRhythm_    = 0
    hammerHitQuality_ = {}
    hammerReady_     = true
    hammerCooldown_  = 0
    hammerDone_      = false
    hammerResultTimer_ = 0
    hammerScore_     = 0
    hammerWaitClick_ = false
    hammerTimeLeft_  = 0
    hammerZoneCenter_ = 0
    quenchTemp_      = 800
    quenchTarget_    = 450
    quenchHolding_   = false
    quenchHoldTime_  = 0
    quenchScore_     = 0
    quenchDone_      = false
    quenchTimer_     = 0
    grindCount_      = 0
    grindKeyIndex_   = 1
    grindTimer_      = 0
    grindDone_       = false
    grindScore_      = 0
    grindFlash_      = 0
    grindMissFlash_  = 0
    grindWaitClick_  = false
    grindResultTimer_ = 0
    grindDragging_   = false
    grindLastDragZone_ = 0
    gameData_        = nil
    onComplete_      = nil
    onPhaseChange_   = nil
end


--- 随机生成判定区域位置
--- 区域结构：perfect(10%) + good两侧(30%) = 40%，需确保全部在[-1,1]内
local PERFECT_HALF = Config.Forge.PerfectHalf
local GOOD_HALF    = Config.Forge.GoodHalf
local ZONE_MARGIN  = Config.Forge.ZoneMargin

local function RandomizeZoneCenter()
    -- 区域中心范围：[-0.60, 0.60]
    hammerZoneCenter_ = (math.random() * 2 - 1) * (1.0 - ZONE_MARGIN)
end


--- 初始化锤击阶段
InitHammerPhase = function()
    hammerHits_       = 0
    hammerFlash_      = 0
    hammerShake_       = 0
    hammerRhythm_      = 0
    hammerHitQuality_  = {}
    hammerReady_       = true
    hammerCooldown_    = 0
    hammerDone_        = false
    hammerWaitClick_   = false
    hammerResultTimer_  = 0
    hammerScore_        = 0
    hammerTimeLeft_     = GameSettings.GetHammerTime()
    phaseTimer_        = 0
    RandomizeZoneCenter()
    
    print("[Forge/Hammer] Ready for " .. HAMMER_MAX_HITS .. " strikes, time limit: " .. hammerTimeLeft_ .. "s")
end


--- 初始化淬火阶段
---@diagnostic disable-next-line: redefined-local
InitQuenchPhase = function()
    QUENCH_TIME_LIMIT = GameSettings.GetQuenchTime()  -- 刷新用户设置
    quenchTemp_     = 800 + math.random(0, 100)  -- 随机起始温度
    quenchTarget_    = 300 + math.random(0, 200)  -- 随机目标（300~500）
    quenchTolerance_ = 30
    quenchHolding_   = false
    quenchHoldTime_  = 0
    quenchScore_     = 0
    quenchDone_      = false
    quenchTimer_     = 0
    phaseTimer_      = 0
    
    print("[Forge/Quench] Start temp: " .. quenchTemp_ .. " Target: " .. quenchTarget_ .. " TimeLimit: " .. QUENCH_TIME_LIMIT .. "s")
end


--- 初始化砥砺阶段
---@diagnostic disable-next-line: redefined-local
InitGrindPhase = function()
    -- 刷新按键显示名（Init 已完成，此时 bindings_ 有值）
    GRIND_KEYS        = KeyBindings.GetGrindKeyNames()
    GRIND_TIME_LIMIT  = GameSettings.GetGrindTime()  -- 刷新用户设置
    grindCount_       = 0
    grindKeyIndex_    = 1
    grindTimer_       = 0
    grindDone_        = false
    grindScore_       = 0
    grindFlash_       = 0
    grindMissFlash_   = 0
    grindWaitClick_   = false
    grindResultTimer_ = 0
    grindDragging_    = false
    grindLastDragZone_ = 0
    phaseTimer_       = 0
    
    print("[Forge/Grind] Start! Press J→K→L or drag across keys to grind, time limit: " .. GRIND_TIME_LIMIT .. "s")
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
    elseif currentPhase_ == PHASE_GRIND then
        UpdateGrind(dt)
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
        local qualityAvg   = totalQuality / hitCount
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
        -- 基础速率180°/s，每秒额外加速150°/s → 按住越久降温越猛
        local rate = 180 + quenchHoldTime_ * 150
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


--- 结束淬火，计算得分，进入砥砺等待
FinishQuench = function()
    if quenchDone_ then return end
    quenchDone_  = true
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
    
    totalScore_ = totalScore_ + quenchScore_
    grindWaitClick_ = true  -- 等待玩家点击进入砥砺
    
    print("[Forge/Quench] Done! Temp: " .. math.floor(quenchTemp_) .. " Target: " .. quenchTarget_ .. " Diff: " .. math.floor(diff) .. " Score: " .. quenchScore_)
end


--- 砥砺更新
UpdateGrind = function(dt)
    -- 衰减闪光
    if grindFlash_ > 0 then grindFlash_ = grindFlash_ - dt * 5 end
    if grindMissFlash_ > 0 then grindMissFlash_ = grindMissFlash_ - dt * 5 end
    
    if grindDone_ then
        grindResultTimer_ = grindResultTimer_ + dt
        return
    end
    
    -- 倒计时
    grindTimer_ = grindTimer_ + dt
    if grindTimer_ >= GRIND_TIME_LIMIT then
        FinishGrind()
    end
end


--- 结束砥砺，计算最终得分
FinishGrind = function()
    if grindDone_ then return end
    grindDone_ = true
    
    -- 根据打磨次数查表得分
    local scoreTable = Config.Forge.GrindScoreTable
    local maxCount = Config.Forge.GrindMaxCount
    local count = math.min(grindCount_, maxCount)
    grindScore_ = scoreTable[count] or 100
    
    totalScore_ = totalScore_ + grindScore_
    
    -- 三阶段平均得最终分
    local finalScore = math.floor(totalScore_ / 3)
    gameData_.forgeScore = finalScore
    gameData_.hammerScore = hammerScore_
    gameData_.quenchScore = quenchScore_
    gameData_.grindScore = grindScore_
    gameData_.grindCount = grindCount_
    
    -- 攻速加成：砥砺得分越高，攻速越快（0%~30%加成）
    gameData_.attackSpeedBonus = grindScore_ / 100 * 0.3
    
    -- 确定品质
    for i = #Config.Quality, 1, -1 do
        if finalScore >= Config.Quality[i].threshold then
            gameData_.quality = Config.Quality[i]
            break
        end
    end
    
    print("[Forge/Grind] Done! Count: " .. grindCount_ .. " Score: " .. grindScore_)
    print("[Forge] Final score: " .. finalScore .. " Quality: " .. (gameData_.quality and gameData_.quality.name or "???"))
    print("[Forge] Attack speed bonus: " .. string.format("%.0f%%", gameData_.attackSpeedBonus * 100))
    
    -- 启动延迟结束计时器
    finishTimer_ = 0
end


--- 检测逻辑坐标(lx, ly)在哪个砥砺按键区域，返回1~3或0(不在任何区域)
GetGrindZoneAtPos = function(lx, ly)
    local w = graphics:GetWidth() / graphics:GetDPR()
    local h = graphics:GetHeight() / graphics:GetDPR()
    local cx = w / 2
    local cy = h / 2
    local wheelR = math.min(80, h * 0.15)
    local keyBoxW = 44
    local keySpacing = 56
    local keysStartX = cx - (#GRIND_KEYS - 1) * keySpacing / 2
    local keysY = cy + wheelR + 30
    local hitH = keyBoxW  -- 点击热区高度与按键方框一致

    for i = 1, #GRIND_KEYS do
        local kx = keysStartX + (i - 1) * keySpacing
        if lx >= kx - keyBoxW / 2 and lx <= kx + keyBoxW / 2 and
           ly >= keysY - hitH / 2 and ly <= keysY + hitH / 2 then
            return i
        end
    end
    return 0
end

--- 处理砥砺拖动：鼠标/触摸进入新的按键区域时触发
HandleGrindDrag = function(lx, ly)
    if currentPhase_ ~= PHASE_GRIND or grindDone_ then return end

    local zone = GetGrindZoneAtPos(lx, ly)
    if zone == 0 then return end
    if zone == grindLastDragZone_ then return end  -- 还在同一区域，不重复触发

    grindLastDragZone_ = zone

    -- 与按键逻辑相同：必须按顺序
    if zone == grindKeyIndex_ then
        grindKeyIndex_ = grindKeyIndex_ + 1
        grindFlash_ = 1.0
        if grindSource_ and grindSound_ then
            grindSource_.gain = 0.7
            grindSource_:Play(grindSound_)
            BGM.DuckForSFX(0.4)
        end
        if grindKeyIndex_ > #GRIND_KEYS then
            grindCount_ = grindCount_ + 1
            grindKeyIndex_ = 1
            grindLastDragZone_ = 0  -- 完成一轮后重置，允许从头再来
        end
    end
end


--- 播放锤击音效（复用预创建音源，无首次延迟）
---@diagnostic disable-next-line: redefined-local
PlayHammerSound = function()
    if not hammerSound_ or not hammerSource_ then return end
    hammerSource_.gain = 1.0
    hammerSource_:Play(hammerSound_)
    BGM.DuckForSFX(0.5)  -- 锤击音效短暂压低BGM
end


--- 开始播放淬火循环音效（复用预创建音源，无首次延迟）
---@diagnostic disable-next-line: redefined-local
StartQuenchSound = function()
    if not quenchSound_ or not quenchSource_ then return end
    if quenchSource_.gain > 0.5 and quenchSource_:IsPlaying() then return end  -- 已正式播放中
    quenchSource_.gain = 1.0
    quenchSource_:Play(quenchSound_)
    BGM.DuckPrep()  -- 淬火循环期间持续压低BGM
end


--- 停止淬火循环音效
---@diagnostic disable-next-line: redefined-local
StopQuenchSound = function()
    if quenchSource_ then
        quenchSource_:Stop()
        quenchSource_.gain = 0.0
    end
    BGM.UnduckPrep()  -- 淬火结束，恢复BGM音量
end


--- 处理玩家点击（锤击判定）
OnForgeInput = function()
    if finishTimer_ >= 0 then return end  -- 等待结束中忽略输入
    
    if currentPhase_ == PHASE_HAMMER then
        -- 锤击完成后等待点击进入淬火
        if hammerWaitClick_ then
            currentPhase_ = PHASE_QUENCH
            InitQuenchPhase()
            if onPhaseChange_ then onPhaseChange_("quench") end
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
                hammerShake_  = 1.0
            elseif quality == "good" then
                hammerFlash_ = 0.7
                hammerShake_  = 0.7
            else
                -- miss: 微弱反馈
                hammerFlash_ = 0.3
                hammerShake_  = 0.2
            end
            
            -- 短暂冷却防止连点
            hammerReady_     = false
            hammerCooldown_ = 0.3
            
            PlayHammerSound()
        end
    elseif currentPhase_ == PHASE_QUENCH then
        -- 淬火完成后等待点击进入砥砺
        if quenchDone_ and grindWaitClick_ then
            grindWaitClick_ = false
            currentPhase_ = PHASE_GRIND
            InitGrindPhase()
            if onPhaseChange_ then onPhaseChange_("grind") end
            return
        end
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
    if KeyBindings.IsKey("forge_hit", key) then
        OnForgeInput()
        return
    end
    
    -- 砥砺阶段：按键处理
    if currentPhase_ == PHASE_GRIND and not grindDone_ then
        local grindIdx = KeyBindings.GetGrindIndex(key)
        
        if grindIdx then
            -- grindKeyIndex_ 是当前期望的序列位置(1/2/3)
            if grindIdx == grindKeyIndex_ then
                -- 按对了，播放磨刀音效
                grindKeyIndex_ = grindKeyIndex_ + 1
                grindFlash_ = 1.0
                if grindSource_ and grindSound_ then
                    grindSource_.gain = 0.7
                    grindSource_:Play(grindSound_)
                    BGM.DuckForSFX(0.4)  -- 打磨音效短暂压低BGM
                end
                if grindKeyIndex_ > #GRIND_KEYS then
                    -- 完成一轮打磨
                    grindCount_ = grindCount_ + 1
                    grindKeyIndex_ = 1
                    print("[Forge/Grind] Completed cycle #" .. grindCount_)
                end
            else
                -- 按错了，重置当前轮序列
                grindKeyIndex_ = 1
                grindMissFlash_ = 1.0
            end
        end
    end
end

function ForgeState.OnKeyUp(key)
    if KeyBindings.IsKey("forge_hit", key) then
        OnForgeInputRelease()
    end
end


-- ============================================================================
-- 输入（由 main.lua 分发）
-- ============================================================================

function ForgeState.OnMouseDown(button)
    if button == MOUSEB_LEFT then
        -- 砥砺阶段：开始拖动追踪
        if currentPhase_ == PHASE_GRIND and not grindDone_ then
            grindDragging_ = true
            grindLastDragZone_ = 0
            local dpr = graphics:GetDPR()
            local lx = input.mousePosition.x / dpr
            local ly = input.mousePosition.y / dpr
            HandleGrindDrag(lx, ly)
        end
        OnForgeInput()
    end
end

function ForgeState.OnMouseUp(button)
    if button == MOUSEB_LEFT then
        grindDragging_ = false
        grindLastDragZone_ = 0
        OnForgeInputRelease()
    end
end

function ForgeState.OnTouchBegin(x, y)
    -- 砥砺阶段：开始拖动追踪
    if currentPhase_ == PHASE_GRIND and not grindDone_ then
        grindDragging_ = true
        grindLastDragZone_ = 0
        local dpr = graphics:GetDPR()
        HandleGrindDrag(x / dpr, y / dpr)
    end
    OnForgeInput()
end

function ForgeState.OnMouseMove()
    -- 砥砺阶段：拖动经过按键区域
    if grindDragging_ and currentPhase_ == PHASE_GRIND and not grindDone_ then
        local dpr = graphics:GetDPR()
        local lx = input.mousePosition.x / dpr
        local ly = input.mousePosition.y / dpr
        HandleGrindDrag(lx, ly)
    end
end

function ForgeState.OnTouchMove(x, y)
    -- 砥砺阶段：拖动经过按键区域
    if grindDragging_ and currentPhase_ == PHASE_GRIND and not grindDone_ then
        local dpr = graphics:GetDPR()
        HandleGrindDrag(x / dpr, y / dpr)
    end
end

function ForgeState.OnTouchEnd(x, y)
    grindDragging_ = false
    grindLastDragZone_ = 0
    OnForgeInputRelease()
end


-- ============================================================================
-- NanoVG 渲染（由 main.lua HandleNanoVGRender 调用）
-- ============================================================================

function ForgeState.Render(vg)
    local w   = graphics:GetWidth()
    local h   = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local lw  = w / dpr
    local lh  = h / dpr
    
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
    elseif currentPhase_ == PHASE_GRIND then
        RenderGrindPhase(vg, lw, lh)
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
    
    -- 倒计时（铁砧右侧，大字醒目）
    if not hammerDone_ then
        local timeText = string.format("%.1f", math.max(0, hammerTimeLeft_))
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if hammerTimeLeft_ <= 3.0 then
            nvgFillColor(vg, nvgRGBA(C_DANGER[1], C_DANGER[2], C_DANGER[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(200, 205, 210, 230))
        end
        nvgText(vg, cx + 100, cy - 10, timeText .. "s", nil)
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


-- ============================================================================
-- 淬火阶段渲染（自适应布局，适配任意宽高比）
-- ============================================================================

--- 淬火阶段主渲染入口（完全自适应布局）
--- 布局策略：在 UI 顶栏和底栏之间的可用区域内，紧凑排列所有元素并整体居中
RenderQuenchPhase = function(vg, w, h)
    local cx = w / 2
    
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    nvgFontFaceId(vg, fontId)
    
    -- ================================================================
    -- 可用区域：去除顶部 UI 栏(~44px) 和底部 UI 栏(~44px) 后的中间区域
    -- ================================================================
    local topMargin    = 44
    local bottomMargin = 44
    local availTop     = topMargin
    local availBottom  = h - bottomMargin
    local availH       = availBottom - availTop
    
    -- ================================================================
    -- 元素尺寸计算（全部基于 availH 按比例分配）
    -- 倒计时圆: 18%  间距: 4%  温度计: 50%  间距: 4%  提示: 余量
    -- ================================================================
    local countdownR   = math.min(32, availH * 0.08)      -- 倒计时圆半径
    local countdownH   = countdownR * 2                    -- 倒计时占据高度
    local gap1         = availH * 0.03                     -- 倒计时与温度计间距
    local barH         = math.min(160, availH * 0.48)      -- 温度计高度
    local barW         = math.min(44, availH * 0.12)       -- 温度计宽度
    local gap2         = availH * 0.03                     -- 温度计与温度数字间距
    local tempFontSize = math.max(12, math.min(20, math.floor(availH * 0.05)))
    local gap3         = availH * 0.02                     -- 温度数字与提示间距
    local statusFontSz = math.max(11, math.min(16, math.floor(availH * 0.04)))
    local subFontSz    = math.max(10, math.min(13, math.floor(availH * 0.032)))
    
    -- 总内容高度
    local totalContentH = countdownH + gap1 + barH + gap2 + tempFontSize + gap3 + statusFontSz + 4 + subFontSz
    
    -- 整体居中起始 Y
    local startY = availTop + (availH - totalContentH) / 2
    if startY < availTop + 4 then startY = availTop + 4 end
    
    -- ================================================================
    -- ① 倒计时圆
    -- ================================================================
    local countdownY = startY + countdownR
    local remaining = math.max(0, QUENCH_TIME_LIMIT - quenchTimer_)
    local countdownText = string.format("%.1f", remaining)
    local pulseScale = 1.0
    if remaining < 1.0 and not quenchDone_ then
        pulseScale = 1.0 + math.sin(phaseTimer_ * 12) * 0.08
    end
    
    nvgBeginPath(vg)
    nvgCircle(vg, cx, countdownY, countdownR * pulseScale)
    if remaining < 1.0 then
        nvgFillColor(vg, nvgRGBA(240, 80, 80, 200))
    elseif remaining < 2.0 then
        nvgFillColor(vg, nvgRGBA(200, 80, 40, 180))
    else
        nvgFillColor(vg, nvgRGBA(50, 50, 55, 180))
    end
    nvgFill(vg)
    
    nvgFontFaceId(vg, fontId)
    local baseFontSz = math.floor(math.min(32, countdownR * 1.8))
    nvgFontSize(vg, baseFontSz)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    -- 使用 nvgScale 做 pulse 缩放，避免每帧不同字号导致字体图集膨胀
    nvgSave(vg)
    nvgTranslate(vg, cx, countdownY)
    nvgScale(vg, pulseScale, pulseScale)
    if quenchDone_ then
        nvgText(vg, 0, 0, "停!", nil)
    else
        nvgText(vg, 0, 0, countdownText, nil)
    end
    nvgRestore(vg)
    
    -- ================================================================
    -- ② 温度计
    -- ================================================================
    local barTop = startY + countdownH + gap1
    local barX   = cx - barW / 2
    
    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 4, barTop - 4, barW + 8, barH + 8, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 55, 255))
    nvgFill(vg)
    
    -- 温度填充
    local maxTemp = 900
    local fillRatio = math.max(0, math.min(1, quenchTemp_ / maxTemp))
    local fillH = barH * fillRatio
    
    local r, g, b
    if fillRatio > 0.6 then
        r, g, b = 200, 80, 40
    elseif fillRatio > 0.3 then
        r, g, b = 160, 140, 90
    else
        r, g, b = 150, 200, 255
    end
    
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barTop + (barH - fillH), barW, fillH, 4)
    nvgFillColor(vg, nvgRGBA(r, g, b, 230))
    nvgFill(vg)
    
    -- 目标区域高亮
    local targetRatio = quenchTarget_ / maxTemp
    local targetY     = barTop + barH * (1 - targetRatio)
    local tolPixel    = (quenchTolerance_ / maxTemp) * barH
    nvgBeginPath(vg)
    nvgRect(vg, barX - 12, targetY - tolPixel, barW + 24, tolPixel * 2)
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
    nvgFontSize(vg, math.max(11, math.min(13, math.floor(barH * 0.08))))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(150, 200, 255, 255))
    nvgText(vg, barX + barW + 16, targetY, math.floor(quenchTarget_) .. "°", nil)
    
    -- ================================================================
    -- ③ 当前温度数字
    -- ================================================================
    local tempTextY = barTop + barH + gap2
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, tempFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgText(vg, cx, tempTextY, math.floor(quenchTemp_) .. "°", nil)
    
    -- ================================================================
    -- ④ 状态提示文字
    -- ================================================================
    local statusY = tempTextY + tempFontSize + gap3
    nvgFontFaceId(vg, fontId)
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
        nvgFontSize(vg, statusFontSz)
        nvgText(vg, cx, statusY, resultText, nil)
        
        -- 等待点击进入砥砺
        if grindWaitClick_ then
            nvgFontSize(vg, subFontSz)
            nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 220))
            nvgText(vg, cx, statusY + statusFontSz + 4, "👆 点击进入砥砺", nil)
        end
    else
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgFontSize(vg, statusFontSz)
        if quenchHolding_ then
            nvgText(vg, cx, statusY, "淬火中... 松开即停止!", nil)
        else
            nvgText(vg, cx, statusY, "按住淬火，松开停止!", nil)
        end
        -- 第二行提示
        nvgFontSize(vg, subFontSz)
        nvgFillColor(vg, nvgRGBA(150, 200, 255, 200))
        nvgText(vg, cx, statusY + statusFontSz + 4, "停在蓝线上!", nil)
    end
end


-- ============================================================================
-- 砥砺阶段渲染
-- ============================================================================

--- 砥砺阶段主渲染入口
RenderGrindPhase = function(vg, w, h)
    local cx = w / 2
    local cy = h / 2
    
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    nvgFontFaceId(vg, fontId)
    
    -- 淬火结果等待点击（显示在淬火阶段结束后、砥砺开始前）
    -- 注：此分支实际不会在 PHASE_GRIND 中触发，因为点击后才进入 PHASE_GRIND
    -- 但作为安全保护保留
    
    -- 倒计时
    local remaining = math.max(0, GRIND_TIME_LIMIT - grindTimer_)
    
    -- 背景砂轮装饰
    local wheelR = math.min(80, h * 0.15)
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy - 10, wheelR)
    nvgFillColor(vg, nvgRGBA(60, 58, 55, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(90, 85, 80, 255))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)
    
    -- 砂轮纹理（旋转线条）
    local rotAngle = phaseTimer_ * 3.0  -- 持续旋转
    for i = 0, 5 do
        local angle = rotAngle + i * (math.pi / 3)
        local x1 = cx + math.cos(angle) * wheelR * 0.3
        local y1 = cy - 10 + math.sin(angle) * wheelR * 0.3
        local x2 = cx + math.cos(angle) * wheelR * 0.85
        local y2 = cy - 10 + math.sin(angle) * wheelR * 0.85
        nvgBeginPath(vg)
        nvgMoveTo(vg, x1, y1)
        nvgLineTo(vg, x2, y2)
        nvgStrokeColor(vg, nvgRGBA(80, 75, 70, 150))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
    
    -- 正确按键闪光
    if grindFlash_ > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy - 10, wheelR + 10 + (1 - grindFlash_) * 20)
        nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], math.floor(grindFlash_ * 80)))
        nvgFill(vg)
    end
    
    -- 按错闪光
    if grindMissFlash_ > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy - 10, wheelR + 5)
        nvgFillColor(vg, nvgRGBA(C_DANGER[1], C_DANGER[2], C_DANGER[3], math.floor(grindMissFlash_ * 80)))
        nvgFill(vg)
    end
    
    -- 按键序列显示
    local keyBoxW = 44
    local keySpacing = 56
    local keysStartX = cx - (#GRIND_KEYS - 1) * keySpacing / 2
    local keysY = cy + wheelR + 30
    
    for i = 1, #GRIND_KEYS do
        local kx = keysStartX + (i - 1) * keySpacing
        local isActive = (i == grindKeyIndex_) and not grindDone_
        local isDone = i < grindKeyIndex_
        
        -- 按键方框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, kx - keyBoxW / 2, keysY - keyBoxW / 2, keyBoxW, keyBoxW, 8)
        if isDone then
            nvgFillColor(vg, nvgRGBA(C_SUCCESS[1], C_SUCCESS[2], C_SUCCESS[3], 180))
        elseif isActive then
            local pulse = math.abs(math.sin(phaseTimer_ * 4)) * 0.3 + 0.7
            nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], math.floor(pulse * 200)))
        else
            nvgFillColor(vg, nvgRGBA(40, 42, 48, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 100, 110, 200))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        
        -- 按键字母
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 22)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isDone then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        elseif isActive then
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        else
            nvgFillColor(vg, nvgRGBA(150, 150, 160, 200))
        end
        nvgText(vg, kx, keysY, GRIND_KEYS[i], nil)
    end
    
    -- 打磨次数
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 255))
    nvgText(vg, cx, cy - wheelR - 30, "打磨 × " .. grindCount_, nil)
    
    -- 倒计时（转盘左侧大字）
    if not grindDone_ then
        local timeText = string.format("%.1f", remaining)
        local timerX = cx - wheelR - 50
        local timerY = cy - 10
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if remaining <= 1.0 then
            -- 最后1秒闪烁警告
            local blink = math.abs(math.sin(phaseTimer_ * 6)) * 0.4 + 0.6
            nvgFillColor(vg, nvgRGBA(C_DANGER[1], C_DANGER[2], C_DANGER[3], math.floor(blink * 255)))
        else
            nvgFillColor(vg, nvgRGBA(220, 220, 230, 240))
        end
        nvgText(vg, timerX, timerY, timeText, nil)
        -- "秒"小字标注
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(150, 150, 160, 180))
        nvgText(vg, timerX, timerY + 28, "秒", nil)
    end
    
    -- 结果展示
    if grindDone_ then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - 120, cy - 60, 240, 100, 12)
        nvgFillColor(vg, nvgRGBA(20, 22, 28, 230))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 150))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
        
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 18)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 255))
        nvgText(vg, cx, cy - 40, "砥砺完成!", nil)
        
        nvgFontSize(vg, 15)
        local gradeText
        local gr, gg, gb = 200, 205, 210
        if grindScore_ >= 90 then
            gradeText = "大师磨砺 " .. grindScore_ .. "分"
            gr, gg, gb = 160, 140, 90
        elseif grindScore_ >= 65 then
            gradeText = "精细打磨 " .. grindScore_ .. "分"
            gr, gg, gb = 80, 200, 120
        elseif grindScore_ >= 40 then
            gradeText = "粗磨完成 " .. grindScore_ .. "分"
            gr, gg, gb = 120, 130, 140
        else
            gradeText = "草草了事 " .. grindScore_ .. "分"
            gr, gg, gb = 240, 80, 80
        end
        nvgFillColor(vg, nvgRGBA(gr, gg, gb, 255))
        nvgText(vg, cx, cy - 15, gradeText, nil)
        
        -- 攻速加成显示
        local bonusPct = math.floor(grindScore_ / 100 * 30)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(150, 200, 255, 220))
        nvgText(vg, cx, cy + 10, "攻速 +" .. bonusPct .. "%", nil)
        
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, 180))
        nvgText(vg, cx, cy + 30, "锻造完毕，准备试炼...", nil)
    else
        -- 操作提示
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 13)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, 200))
        nvgText(vg, cx, keysY + keyBoxW / 2 + 12, "依次按 J → K → L 完成一次打磨!", nil)
    end
end


return ForgeState

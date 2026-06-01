-- ============================================================================
-- States/ForgeState.lua - 锻造阶段状态（自适应布局修复版）
-- 包含两个简单小游戏：锤击（节奏点击）和 淬火（温度控制）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")
local KeyBindings = require("KeyBindings")
local GameSettings = require("GameSettings")
local PhaseRenderers = require("Forge.PhaseRenderers")

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

    -- 构建状态快照供渲染模块使用
    local S = {
        phaseTimer = phaseTimer_,
        -- 锤击
        hammerFlash = hammerFlash_,
        hammerShake = hammerShake_,
        hammerRhythm = hammerRhythm_,
        hammerHits = hammerHits_,
        hammerHitQuality = hammerHitQuality_,
        hammerReady = hammerReady_,
        hammerDone = hammerDone_,
        hammerScore = hammerScore_,
        hammerWaitClick = hammerWaitClick_,
        hammerTimeLeft = hammerTimeLeft_,
        hammerZoneCenter = hammerZoneCenter_,
        -- 淬火
        quenchTemp = quenchTemp_,
        quenchTarget = quenchTarget_,
        quenchTolerance = quenchTolerance_,
        quenchHolding = quenchHolding_,
        quenchDone = quenchDone_,
        quenchTimer = quenchTimer_,
        -- 砥砺
        grindCount = grindCount_,
        grindKeyIndex = grindKeyIndex_,
        grindTimer = grindTimer_,
        grindDone = grindDone_,
        grindScore = grindScore_,
        grindFlash = grindFlash_,
        grindMissFlash = grindMissFlash_,
        grindWaitClick = grindWaitClick_,
    }

    if currentPhase_ == PHASE_HAMMER then
        PhaseRenderers.RenderHammerPhase(vg, lw, lh, S)
    elseif currentPhase_ == PHASE_QUENCH then
        PhaseRenderers.RenderQuenchPhase(vg, lw, lh, S)
    elseif currentPhase_ == PHASE_GRIND then
        PhaseRenderers.RenderGrindPhase(vg, lw, lh, S)
    end

    nvgResetTransform(vg)
    nvgEndFrame(vg)
end

return ForgeState

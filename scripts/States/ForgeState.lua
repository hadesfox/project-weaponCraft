-- ============================================================================
-- States/ForgeState.lua - 锻造阶段状态
-- 包含两个简单小游戏：锤击（节奏点击）和 淬火（温度控制）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local NVG = require("NVG")

local ForgeState = {}

local gameData_ = nil
local onComplete_ = nil

-- 锻造阶段
local PHASE_HAMMER = 1   -- 锤击
local PHASE_QUENCH = 2   -- 淬火
local PHASE_DONE = 3

local currentPhase_ = PHASE_HAMMER
local phaseTimer_ = 0
local totalScore_ = 0

-- 锤击阶段变量
local hammerBeats_ = {}      -- 节拍时间表
local hammerNextBeat_ = 0    -- 下一个节拍索引
local hammerHits_ = 0        -- 命中次数
local hammerMisses_ = 0      -- 失误次数
local hammerTotal_ = 0       -- 总节拍数
local hammerFlash_ = 0       -- 命中闪光效果
local hammerMissFlash_ = 0   -- 失误闪光
local hammerProgress_ = 0    -- 进度条

-- 淬火阶段变量
local quenchTemp_ = 800      -- 当前温度
local quenchTarget_ = 450    -- 目标温度
local quenchHolding_ = false -- 是否正在按住冷却
local quenchScore_ = 0       -- 淬火评分
local quenchDone_ = false

-- 延迟结束计时器（替代旧的匿名事件订阅）
local finishTimer_ = -1      -- <0 表示未激活

--- 进入锻造状态
function ForgeState.Enter(gameData, onComplete)
    gameData_ = gameData
    onComplete_ = onComplete
    currentPhase_ = PHASE_HAMMER
    phaseTimer_ = 0
    totalScore_ = 0
    finishTimer_ = -1
    
    -- 初始化锤击
    InitHammerPhase()
    
    print("[ForgeState] Entered. Weapon type: " .. tostring(gameData_.weaponType))
end

--- 离开锻造状态
function ForgeState.Leave()
    finishTimer_ = -1
    quenchHolding_ = false
end

--- 初始化锤击阶段
function InitHammerPhase()
    hammerBeats_ = {}
    hammerHits_ = 0
    hammerMisses_ = 0
    hammerNextBeat_ = 1
    hammerFlash_ = 0
    hammerMissFlash_ = 0
    
    -- 生成节拍序列（随机间隔，让每个玩家体验不同）
    local t = 1.0
    local interval = Config.Forge.HammerBeatInterval
    while t < Config.Forge.HammerDuration - 1.0 do
        hammerBeats_[#hammerBeats_ + 1] = t
        -- 随机化间隔（0.6~1.0倍基础间隔）
        t = t + interval * (0.6 + math.random() * 0.4)
    end
    hammerTotal_ = #hammerBeats_
    
    print("[Forge/Hammer] Generated " .. hammerTotal_ .. " beats")
end

--- 初始化淬火阶段
function InitQuenchPhase()
    quenchTemp_ = 800 + math.random(0, 100)  -- 随机起始温度
    quenchTarget_ = 400 + math.random(0, 100) -- 随机目标
    quenchHolding_ = false
    quenchScore_ = 0
    quenchDone_ = false
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
    
    -- 衰减闪光
    if hammerFlash_ > 0 then hammerFlash_ = hammerFlash_ - dt * 4 end
    if hammerMissFlash_ > 0 then hammerMissFlash_ = hammerMissFlash_ - dt * 4 end
end

--- 锤击更新
function UpdateHammer(dt)
    hammerProgress_ = phaseTimer_ / Config.Forge.HammerDuration
    
    -- 检测过时的节拍（玩家没有按到）
    while hammerNextBeat_ <= hammerTotal_ do
        local beatTime = hammerBeats_[hammerNextBeat_]
        if phaseTimer_ > beatTime + Config.Forge.GoodWindow then
            -- 超时了，算 miss
            hammerMisses_ = hammerMisses_ + 1
            hammerNextBeat_ = hammerNextBeat_ + 1
            hammerMissFlash_ = 1.0
        else
            break
        end
    end
    
    -- 阶段结束
    if phaseTimer_ >= Config.Forge.HammerDuration then
        -- 计算锤击得分（满分100）
        local hitRate = hammerTotal_ > 0 and (hammerHits_ / hammerTotal_) or 0
        local hammerScore = math.floor(hitRate * 100)
        totalScore_ = totalScore_ + hammerScore
        
        print("[Forge/Hammer] Done! Hits: " .. hammerHits_ .. "/" .. hammerTotal_ .. " Score: " .. hammerScore)
        
        -- 进入淬火阶段
        currentPhase_ = PHASE_QUENCH
        InitQuenchPhase()
    end
end

--- 淬火更新
function UpdateQuench(dt)
    if quenchDone_ then return end
    
    -- 温度自然下降（慢）
    quenchTemp_ = quenchTemp_ - dt * 20
    
    -- 按住时加速冷却
    if quenchHolding_ then
        quenchTemp_ = quenchTemp_ - dt * 150
    end
    
    -- 温度到达目标范围
    local diff = math.abs(quenchTemp_ - quenchTarget_)
    if quenchTemp_ <= quenchTarget_ then
        -- 计算精确度得分
        if diff < 20 then
            quenchScore_ = 100
        elseif diff < 50 then
            quenchScore_ = 75
        elseif diff < 100 then
            quenchScore_ = 50
        else
            quenchScore_ = 25
        end
        quenchDone_ = true
        
        -- 总分计算
        totalScore_ = totalScore_ + quenchScore_
        local finalScore = math.floor(totalScore_ / 2)  -- 两阶段平均
        gameData_.forgeScore = finalScore
        
        -- 确定品质
        for i = #Config.Quality, 1, -1 do
            if finalScore >= Config.Quality[i].threshold then
                gameData_.quality = Config.Quality[i]
                break
            end
        end
        
        print("[Forge/Quench] Done! Score: " .. quenchScore_ .. " Final: " .. finalScore)
        print("[Forge] Quality: " .. (gameData_.quality and gameData_.quality.name or "???"))
        
        -- 启动延迟结束计时器
        finishTimer_ = 0
    end
    
    -- 超时（温度降到0也结束）
    if quenchTemp_ <= 0 then
        quenchTemp_ = 0
        quenchDone_ = true
        quenchScore_ = 10
        totalScore_ = totalScore_ + quenchScore_
        gameData_.forgeScore = math.floor(totalScore_ / 2)
        gameData_.quality = Config.Quality[1]
        finishTimer_ = 0
    end
end

--- 处理玩家点击（锤击判定）
function OnForgeInput()
    if finishTimer_ >= 0 then return end  -- 等待结束中忽略输入

    if currentPhase_ == PHASE_HAMMER then
        -- 判定锤击
        if hammerNextBeat_ <= hammerTotal_ then
            local beatTime = hammerBeats_[hammerNextBeat_]
            local diff = math.abs(phaseTimer_ - beatTime)
            
            if diff <= Config.Forge.PerfectWindow then
                hammerHits_ = hammerHits_ + 1
                hammerNextBeat_ = hammerNextBeat_ + 1
                hammerFlash_ = 1.0
            elseif diff <= Config.Forge.GoodWindow then
                hammerHits_ = hammerHits_ + 0.7
                hammerNextBeat_ = hammerNextBeat_ + 1
                hammerFlash_ = 0.7
            end
        end
    elseif currentPhase_ == PHASE_QUENCH then
        quenchHolding_ = true
    end
end

function OnForgeInputRelease()
    if currentPhase_ == PHASE_QUENCH then
        quenchHolding_ = false
    end
end

--- 按键
function ForgeState.OnKeyDown(key)
    if key == KEY_SPACE then
        OnForgeInput()
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

function RenderHammerPhase(vg, w, h)
    local cx = w / 2
    local cy = h / 2
    
    -- 铁砧背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 80, cy - 30, 160, 60, 8)
    nvgFillColor(vg, nvgRGBA(80, 75, 70, 255))
    nvgFill(vg)
    
    local timelineY = cy + 80
    local timelineW = w * 0.7
    local timelineX = (w - timelineW) / 2
    
    RenderHammerTimeline(vg, timelineX, timelineY, timelineW)
    RenderHammerFlash(vg, cx, cy)
    RenderHammerTool(vg, cx, cy)
    RenderHammerText(vg, cx, cy, timelineY)
end

--- 渲染锤击时间轴和节拍标记
function RenderHammerTimeline(vg, x, y, w)
    -- 时间轴底
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y - 3, w, 6, 3)
    nvgFillColor(vg, nvgRGBA(60, 60, 70, 255))
    nvgFill(vg)
    
    -- 当前位置指针
    local cursorX = x + w * hammerProgress_
    nvgBeginPath(vg)
    nvgCircle(vg, cursorX, y, 8)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
    nvgFill(vg)
    
    -- 节拍标记
    for i = 1, hammerTotal_ do
        local beatTime = hammerBeats_[i]
        local beatX = x + w * (beatTime / Config.Forge.HammerDuration)
        local isActive = (i >= hammerNextBeat_)
        
        nvgBeginPath(vg)
        nvgCircle(vg, beatX, y, isActive and 6 or 4)
        if i < hammerNextBeat_ then
            nvgFillColor(vg, nvgRGBA(80, 200, 120, 200))
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 210, 200))
        end
        nvgFill(vg)
    end
end

--- 渲染命中/失误闪光
function RenderHammerFlash(vg, cx, cy)
    if hammerFlash_ > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, 50 + (1 - hammerFlash_) * 30)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, math.floor(hammerFlash_ * 150)))
        nvgFill(vg)
    end
    if hammerMissFlash_ > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, 40)
        nvgFillColor(vg, nvgRGBA(240, 80, 80, math.floor(hammerMissFlash_ * 100)))
        nvgFill(vg)
    end
end

--- 渲染锤子动画
function RenderHammerTool(vg, cx, cy)
    local hammerY = cy - 60 - math.abs(math.sin(phaseTimer_ * 4)) * 30
    if hammerFlash_ > 0.5 then
        hammerY = cy - 30
    end
    
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - 15, hammerY - 20, 30, 20, 4)
    nvgFillColor(vg, nvgRGBA(140, 130, 120, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, cx - 4, hammerY, 8, 40)
    nvgFillColor(vg, nvgRGBA(120, 90, 60, 255))
    nvgFill(vg)
end

--- 渲染锤击阶段文字
function RenderHammerText(vg, cx, cy, timelineY)
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, 16)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 255))
    nvgText(vg, cx, timelineY + 30, "点击屏幕/空格 跟随节拍锤击", nil)
    
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
    nvgText(vg, cx, cy - 110, hammerHits_ .. " / " .. hammerTotal_, nil)
end

function RenderQuenchPhase(vg, w, h)
    local cx = w / 2
    local cy = h / 2
    
    local barW = 40
    local barH = 200
    local barX = cx - barW / 2
    local barY = cy - barH / 2
    
    -- 温度计背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 4, barY - 4, barW + 8, barH + 8, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 60, 255))
    nvgFill(vg)
    
    local r, g, b = RenderQuenchFill(vg, barX, barY, barW, barH)
    local targetY = RenderQuenchTarget(vg, barX, barY, barW, barH)
    RenderQuenchText(vg, cx, barX, barY, barW, barH, targetY, r, g, b)
end

--- 渲染淬火温度填充，返回当前颜色
function RenderQuenchFill(vg, barX, barY, barW, barH)
    local maxTemp = 900
    local fillRatio = math.max(0, math.min(1, quenchTemp_ / maxTemp))
    local fillH = barH * fillRatio
    
    local r, g, b
    if fillRatio > 0.6 then
        r, g, b = 240, 80, 40
    elseif fillRatio > 0.3 then
        r, g, b = 240, 160, 40
    else
        r, g, b = 60, 140, 240
    end
    
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY + (barH - fillH), barW, fillH, 4)
    nvgFillColor(vg, nvgRGBA(r, g, b, 230))
    nvgFill(vg)
    
    return r, g, b
end

--- 渲染目标线和区域，返回目标Y坐标
function RenderQuenchTarget(vg, barX, barY, barW, barH)
    local maxTemp = 900
    local targetRatio = quenchTarget_ / maxTemp
    local targetY = barY + barH * (1 - targetRatio)
    
    nvgBeginPath(vg)
    nvgMoveTo(vg, barX - 15, targetY)
    nvgLineTo(vg, barX + barW + 15, targetY)
    nvgStrokeColor(vg, nvgRGBA(80, 255, 120, 255))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
    
    nvgBeginPath(vg)
    nvgRect(vg, barX - 10, targetY - 10, barW + 20, 20)
    nvgFillColor(vg, nvgRGBA(80, 255, 120, 30))
    nvgFill(vg)
    
    return targetY
end

--- 渲染淬火阶段文字
function RenderQuenchText(vg, cx, barX, barY, barW, barH, targetY, r, g, b)
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, 18)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 255))
    nvgText(vg, cx, barY - 40, "淬火 - 按住冷却到绿线", nil)
    
    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgText(vg, cx, barY + barH + 20, math.floor(quenchTemp_) .. "°", nil)
    
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(80, 255, 120, 255))
    nvgText(vg, barX + barW + 20, targetY, "目标 " .. math.floor(quenchTarget_) .. "°", nil)
    
    if quenchDone_ then
        nvgFontSize(vg, 28)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 200, 50, 255))
        nvgText(vg, cx, barY - 70, "淬火完成！", nil)
    end
    
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(160, 160, 180, 200))
    nvgText(vg, cx, barY + barH + 50, quenchHolding_ and "冷却中..." or "点击/按住 = 加速冷却", nil)
end

return ForgeState

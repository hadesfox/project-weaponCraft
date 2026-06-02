-- ============================================================================
-- Forge/PhaseRenderers.lua - 锻造阶段渲染模块
-- 包含锤击、淬火、砥砺三个阶段的 NanoVG 渲染逻辑
-- 所有状态通过参数表 S 传入（只读快照），不持有可变状态
-- ============================================================================

local Config = require("Config")
local NVG = require("NVG")
local GameSettings = require("GameSettings")
local KeyBindings = require("KeyBindings")

local PhaseRenderers = {}

-- 常量
local HAMMER_MAX_HITS = 5
local QUENCH_TIME_LIMIT = GameSettings.GetQuenchTime()
local GRIND_TIME_LIMIT = GameSettings.GetGrindTime()
local GRIND_KEYS = KeyBindings.GetGrindKeyNames()
local PERFECT_HALF = Config.Forge.PerfectHalf
local GOOD_HALF = Config.Forge.GoodHalf

-- 颜色缓存
local C_SUCCESS = Config.Colors.Success
local C_DANGER = Config.Colors.Danger
local C_GOLD = Config.Colors.Gold


-- ============================================================================
-- 锤击阶段渲染
-- ============================================================================

--- 渲染铁砧和锤子动画
local function RenderAnvilAndHammer(vg, cx, cy, shakeX, shakeY, S)
    -- 命中闪光
    if S.hammerFlash > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, cx + shakeX, cy + shakeY, 60 + (1 - S.hammerFlash) * 40)
        nvgFillColor(vg, nvgRGBA(200, 80, 40, math.floor(S.hammerFlash * 120)))
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
    local rhythmPos = math.sin(S.hammerRhythm * math.pi * 2)
    local hammerRestY = cy - 80
    local hammerY = hammerRestY
    if S.hammerFlash > 0.5 then
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
local function RenderRhythmBar(vg, cx, cy, S)
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
    local zoneCenterX = cx + S.hammerZoneCenter * (barW / 2 - 6)

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
    local rhythmPos = math.sin(S.hammerRhythm * math.pi * 2)
    local cursorX = cx + rhythmPos * (barW / 2 - 6)
    local distToZone = math.abs(rhythmPos - S.hammerZoneCenter)

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
    if not S.hammerReady then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW, barH, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
        nvgFill(vg)
    end
end


--- 渲染锤击进度圆点
local function RenderHammerDots(vg, cx, cy, S)
    local dotSpacing = 32
    local dotsStartX = cx - (HAMMER_MAX_HITS - 1) * dotSpacing / 2
    local dotsY = cy + 95

    for i = 1, HAMMER_MAX_HITS do
        local dotX = dotsStartX + (i - 1) * dotSpacing
        nvgBeginPath(vg)
        nvgCircle(vg, dotX, dotsY, 9)
        if i <= S.hammerHits then
            local q = S.hammerHitQuality[i]
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
local function RenderHammerHUD(vg, w, cx, cy, dotsY, S)
    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    nvgFontFaceId(vg, fontId)

    -- 倒计时（铁砧右侧，大字醒目）
    if not S.hammerDone then
        local timeText = string.format("%.1f", math.max(0, S.hammerTimeLeft))
        nvgFontSize(vg, 36)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        if S.hammerTimeLeft <= 3.0 then
            nvgFillColor(vg, nvgRGBA(C_DANGER[1], C_DANGER[2], C_DANGER[3], 255))
        else
            nvgFillColor(vg, nvgRGBA(200, 205, 210, 230))
        end
        nvgText(vg, cx + 100, cy - 10, timeText .. "s", nil)
    end

    -- 锤击结果展示
    if S.hammerDone then
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
        if S.hammerScore >= 90 then
            gradeText = "完美锻造 " .. S.hammerScore .. "分"
            gr, gg, gb = 160, 140, 90
        elseif S.hammerScore >= 70 then
            gradeText = "优秀锻造 " .. S.hammerScore .. "分"
            gr, gg, gb = 80, 200, 120
        elseif S.hammerScore >= 50 then
            gradeText = "普通锻造 " .. S.hammerScore .. "分"
            gr, gg, gb = 120, 130, 140
        else
            gradeText = "粗糙锻造 " .. S.hammerScore .. "分"
            gr, gg, gb = 240, 80, 80
        end
        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(gr, gg, gb, 255))
        nvgText(vg, cx, cy - 10, gradeText, nil)

        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, 180))
        nvgText(vg, cx, cy + 16, "准备进入淬火...", nil)
        return
    end

    -- 锤击计数
    nvgFontSize(vg, 20)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], 255))
    nvgText(vg, cx, cy - 120, S.hammerHits .. " / " .. HAMMER_MAX_HITS, nil)

    -- 提示文字
    nvgFontSize(vg, 13)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(120, 130, 140, 200))
    if S.hammerReady then
        nvgText(vg, cx, dotsY + 18, "光标到金色区域时点击!", nil)
    else
        nvgText(vg, cx, dotsY + 18, "等待...", nil)
    end

    -- 上次锤击质量反馈
    if S.hammerFlash > 0 and S.hammerHits > 0 then
        local lastQ = S.hammerHitQuality[S.hammerHits]
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
        nvgFillColor(vg, nvgRGBA(qr, qg, qb, math.floor(S.hammerFlash * 255)))
        nvgText(vg, cx, cy - 55, qText, nil)
    end
end


--- 锤击阶段主渲染入口
--- @param vg userdata NanoVG context
--- @param w number logical width
--- @param h number logical height
--- @param S table state snapshot
function PhaseRenderers.RenderHammerPhase(vg, w, h, S)
    local cx = w / 2
    local cy = h / 2

    -- 震动偏移
    local shakeX = 0
    local shakeY = 0
    if S.hammerShake > 0 then
        shakeX = (math.random() - 0.5) * S.hammerShake * 6
        shakeY = (math.random() - 0.5) * S.hammerShake * 6
    end

    RenderAnvilAndHammer(vg, cx, cy, shakeX, shakeY, S)
    RenderRhythmBar(vg, cx, cy, S)
    local dotsY = RenderHammerDots(vg, cx, cy, S)
    RenderHammerHUD(vg, w, cx, cy, dotsY, S)
end


-- ============================================================================
-- 淬火阶段渲染（自适应布局，适配任意宽高比）
-- ============================================================================

--- 淬火阶段主渲染入口（完全自适应布局）
--- @param vg userdata NanoVG context
--- @param w number logical width
--- @param h number logical height
--- @param S table state snapshot
function PhaseRenderers.RenderQuenchPhase(vg, w, h, S)
    local cx = w / 2

    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    nvgFontFaceId(vg, fontId)

    -- 可用区域
    local topMargin = 44
    local bottomMargin = 44
    local availTop = topMargin
    local availBottom = h - bottomMargin
    local availH = availBottom - availTop

    -- 元素尺寸计算
    local countdownR = math.min(32, availH * 0.08)
    local countdownH = countdownR * 2
    local gap1 = availH * 0.03
    local barH = math.min(160, availH * 0.48)
    local barW = math.min(44, availH * 0.12)
    local gap2 = availH * 0.03
    local tempFontSize = math.max(12, math.min(20, math.floor(availH * 0.05)))
    local gap3 = availH * 0.02
    local statusFontSz = math.max(11, math.min(16, math.floor(availH * 0.04)))
    local subFontSz = math.max(10, math.min(13, math.floor(availH * 0.032)))

    -- 总内容高度
    local totalContentH = countdownH + gap1 + barH + gap2 + tempFontSize + gap3 + statusFontSz + 4 + subFontSz

    -- 整体居中起始 Y
    local startY = availTop + (availH - totalContentH) / 2
    if startY < availTop + 4 then startY = availTop + 4 end

    -- ① 倒计时圆
    local countdownY = startY + countdownR
    local remaining = math.max(0, QUENCH_TIME_LIMIT - S.quenchTimer)
    local countdownText = string.format("%.1f", remaining)
    local pulseScale = 1.0
    if remaining < 1.0 and not S.quenchDone then
        pulseScale = 1.0 + math.sin(S.phaseTimer * 12) * 0.08
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
    nvgSave(vg)
    nvgTranslate(vg, cx, countdownY)
    nvgScale(vg, pulseScale, pulseScale)
    if S.quenchDone then
        nvgText(vg, 0, 0, "停!", nil)
    else
        nvgText(vg, 0, 0, countdownText, nil)
    end
    nvgRestore(vg)

    -- ② 温度计
    local barTop = startY + countdownH + gap1
    local barX = cx - barW / 2

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX - 4, barTop - 4, barW + 8, barH + 8, 8)
    nvgFillColor(vg, nvgRGBA(50, 50, 55, 255))
    nvgFill(vg)

    -- 温度填充
    local maxTemp = 900
    local fillRatio = math.max(0, math.min(1, S.quenchTemp / maxTemp))
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
    local targetRatio = S.quenchTarget / maxTemp
    local targetY = barTop + barH * (1 - targetRatio)
    local tolPixel = (S.quenchTolerance / maxTemp) * barH
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
    nvgText(vg, barX + barW + 16, targetY, math.floor(S.quenchTarget) .. "°", nil)

    -- ③ 当前温度数字
    local tempTextY = barTop + barH + gap2
    nvgFontFaceId(vg, fontId)
    nvgFontSize(vg, tempFontSize)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(r, g, b, 255))
    nvgText(vg, cx, tempTextY, math.floor(S.quenchTemp) .. "°", nil)

    -- ④ 状态提示文字
    local statusY = tempTextY + tempFontSize + gap3
    nvgFontFaceId(vg, fontId)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    if S.quenchDone then
        local diff = math.abs(S.quenchTemp - S.quenchTarget)
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

        -- 淬火完成提示（自动过渡，无需点击）
    else
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 230))
        nvgFontSize(vg, statusFontSz)
        if S.quenchHolding then
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
--- @param vg userdata NanoVG context
--- @param w number logical width
--- @param h number logical height
--- @param S table state snapshot
function PhaseRenderers.RenderGrindPhase(vg, w, h, S)
    local cx = w / 2
    local cy = h / 2

    local fontId = NVG.GetFont()
    if fontId == -1 then return end
    nvgFontFaceId(vg, fontId)

    -- 倒计时
    local remaining = math.max(0, GRIND_TIME_LIMIT - S.grindTimer)

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
    local rotAngle = S.phaseTimer * 3.0
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
    if S.grindFlash > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy - 10, wheelR + 10 + (1 - S.grindFlash) * 20)
        nvgFillColor(vg, nvgRGBA(C_GOLD[1], C_GOLD[2], C_GOLD[3], math.floor(S.grindFlash * 80)))
        nvgFill(vg)
    end

    -- 按错闪光
    if S.grindMissFlash > 0 then
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy - 10, wheelR + 5)
        nvgFillColor(vg, nvgRGBA(C_DANGER[1], C_DANGER[2], C_DANGER[3], math.floor(S.grindMissFlash * 80)))
        nvgFill(vg)
    end

    -- 按键序列显示
    local keyBoxW = 44
    local keySpacing = 56
    local keysStartX = cx - (#GRIND_KEYS - 1) * keySpacing / 2
    local keysY = cy + wheelR + 30

    local dir = S.grindDirection or 1

    for i = 1, #GRIND_KEYS do
        local kx = keysStartX + (i - 1) * keySpacing
        local isActive = (i == S.grindKeyIndex) and not S.grindDone
        -- 已经过的按键：正向时 i < index，反向时 i > index
        local isDone = false
        if not S.grindDone then
            if dir == 1 then
                isDone = (i < S.grindKeyIndex)
            else
                isDone = (i > S.grindKeyIndex)
            end
        end

        -- 按键方框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, kx - keyBoxW / 2, keysY - keyBoxW / 2, keyBoxW, keyBoxW, 8)
        if isDone then
            nvgFillColor(vg, nvgRGBA(C_SUCCESS[1], C_SUCCESS[2], C_SUCCESS[3], 180))
        elseif isActive then
            local pulse = math.abs(math.sin(S.phaseTimer * 4)) * 0.3 + 0.7
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
    nvgText(vg, cx, cy - wheelR - 30, "打磨 × " .. S.grindCount, nil)

    -- 倒计时（转盘左侧大字）
    if not S.grindDone then
        local timeText = string.format("%.1f", remaining)
        local timerX = cx - wheelR - 50
        local timerY = cy - 10
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 42)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if remaining <= 1.0 then
            local blink = math.abs(math.sin(S.phaseTimer * 6)) * 0.4 + 0.6
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
    if S.grindDone then
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
        if S.grindScore >= 90 then
            gradeText = "大师磨砺 " .. S.grindScore .. "分"
            gr, gg, gb = 160, 140, 90
        elseif S.grindScore >= 65 then
            gradeText = "精细打磨 " .. S.grindScore .. "分"
            gr, gg, gb = 80, 200, 120
        elseif S.grindScore >= 40 then
            gradeText = "粗磨完成 " .. S.grindScore .. "分"
            gr, gg, gb = 120, 130, 140
        else
            gradeText = "草草了事 " .. S.grindScore .. "分"
            gr, gg, gb = 240, 80, 80
        end
        nvgFillColor(vg, nvgRGBA(gr, gg, gb, 255))
        nvgText(vg, cx, cy - 15, gradeText, nil)

        -- 攻速加成显示
        local bonusPct = math.floor(S.grindScore / 100 * 30)
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(150, 200, 255, 220))
        nvgText(vg, cx, cy + 10, "攻速 +" .. bonusPct .. "%", nil)

        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, 180))
        nvgText(vg, cx, cy + 30, "锻造完毕，准备试炼...", nil)
    end
end


return PhaseRenderers

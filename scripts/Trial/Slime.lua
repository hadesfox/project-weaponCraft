-- ============================================================================
-- Trial/Slime.lua - 史莱姆可操控角色模块
-- 弹跳式移动 + 拉伸压缩弹性动画
-- 替代默认玩家渲染，使用相同的输入和物理系统
-- ============================================================================

local NVG = require("NVG")

local Slime = {}

-- ============================================================================
-- 常量
-- ============================================================================
local SLIME_BASE_SIZE = 40          -- 基础直径（px，按 physScale 缩放）
local SQUASH_DURATION = 0.20        -- 落地压扁持续时间
local STRETCH_AMOUNT = 0.35         -- 拉伸/压缩幅度 (0~1)
local BOUNCE_ANIM_SPEED = 12        -- 弹跳动画频率
local IDLE_BOUNCE_SPEED = 3.0       -- 待机微弹频率
local IDLE_BOUNCE_AMP = 0.04        -- 待机微弹幅度
local SLIME_IMAGE_PATH = "image/史莱姆_20260530090540.png"

-- ============================================================================
-- 状态
-- ============================================================================
local slimeImage_ = nil
local physScale_ = 1.0
local screenW_ = 0
local screenH_ = 0
local groundY_ = 0

-- 弹性动画状态
local stretchX_ = 1.0
local stretchY_ = 1.0
local targetStretchX_ = 1.0
local targetStretchY_ = 1.0
local squashTimer_ = 0
local wasOnGround_ = true
local prevVY_ = 0  -- 上一帧的竖直速度（用于落地检测）

-- 弹跳移动动画
local moveAnimTimer_ = 0

-- 表情系统
local eyeOffset_ = 0
local blinkTimer_ = 0
local isBlinking_ = false

-- ============================================================================
-- 初始化 / 清理
-- ============================================================================

function Slime.Init(screenW, screenH, gY, pScale)
    screenW_ = screenW
    screenH_ = screenH
    groundY_ = gY
    physScale_ = pScale

    slimeImage_ = nvgCreateImage(NVG.Get(), SLIME_IMAGE_PATH, 0)

    stretchX_ = 1.0
    stretchY_ = 1.0
    targetStretchX_ = 1.0
    targetStretchY_ = 1.0
    squashTimer_ = 0
    wasOnGround_ = true
    moveAnimTimer_ = 0
    eyeOffset_ = 0
    blinkTimer_ = math.random() * 3 + 1
    isBlinking_ = false
end

function Slime.Shutdown()
    if slimeImage_ and slimeImage_ ~= 0 then
        nvgDeleteImage(NVG.Get(), slimeImage_)
        slimeImage_ = nil
    end
end

function Slime.OnResize(screenW, screenH, gY, pScale)
    screenW_ = screenW
    screenH_ = screenH
    groundY_ = gY
    physScale_ = pScale
end

-- ============================================================================
-- 更新
-- ============================================================================

---@param dt number
---@param player table {x, y, vx, vy, width, height, onGround, facingRight}
function Slime.Update(dt, player)
    -- === 着地瞬间：压扁（用上一帧速度计算冲击强度） ===
    if player.onGround and not wasOnGround_ then
        local fallSpeed = math.abs(prevVY_)
        local impactStrength = math.min(1.0, fallSpeed / 400)
        local squashAmount = STRETCH_AMOUNT * (0.6 + 0.4 * impactStrength)
        targetStretchX_ = 1.0 + squashAmount
        targetStretchY_ = 1.0 - squashAmount
        squashTimer_ = SQUASH_DURATION
        -- 直接设置当前值（让压扁瞬间可见）
        stretchX_ = 1.0 + squashAmount * 0.7
        stretchY_ = 1.0 - squashAmount * 0.7
    end

    -- === 起跳瞬间：纵向拉伸 ===
    if not player.onGround and wasOnGround_ then
        targetStretchX_ = 1.0 - STRETCH_AMOUNT * 0.8
        targetStretchY_ = 1.0 + STRETCH_AMOUNT * 0.8
        squashTimer_ = SQUASH_DURATION * 0.8
        -- 直接设置当前值（让拉伸瞬间可见）
        stretchX_ = 1.0 - STRETCH_AMOUNT * 0.5
        stretchY_ = 1.0 + STRETCH_AMOUNT * 0.5
    end

    wasOnGround_ = player.onGround
    prevVY_ = player.vy or 0

    -- === 压扁/拉伸恢复 ===
    if squashTimer_ > 0 then
        squashTimer_ = squashTimer_ - dt
        if squashTimer_ <= 0 then
            targetStretchX_ = 1.0
            targetStretchY_ = 1.0
        end
    end

    -- 弹簧插值
    local springK = 12.0
    stretchX_ = stretchX_ + (targetStretchX_ - stretchX_) * math.min(1.0, springK * dt)
    stretchY_ = stretchY_ + (targetStretchY_ - stretchY_) * math.min(1.0, springK * dt)
    -- 体积守恒
    local volume = stretchX_ * stretchY_
    if math.abs(volume - 1.0) > 0.01 then
        local correction = math.sqrt(1.0 / volume)
        stretchX_ = stretchX_ * correction
        stretchY_ = stretchY_ * correction
    end

    -- === 移动时弹跳节律 ===
    local isMoving = math.abs(player.vx or 0) > 10
    if isMoving and player.onGround then
        moveAnimTimer_ = moveAnimTimer_ + dt * BOUNCE_ANIM_SPEED
        local bounce = math.abs(math.sin(moveAnimTimer_))
        local hopStretch = bounce * 0.12
        if squashTimer_ <= 0 then
            targetStretchX_ = 1.0 - hopStretch * 0.5
            targetStretchY_ = 1.0 + hopStretch
        end
    elseif player.onGround and squashTimer_ <= 0 then
        -- 待机微弹
        moveAnimTimer_ = moveAnimTimer_ + dt * IDLE_BOUNCE_SPEED
        local idleBounce = math.sin(moveAnimTimer_) * IDLE_BOUNCE_AMP
        targetStretchX_ = 1.0 - idleBounce * 0.5
        targetStretchY_ = 1.0 + idleBounce
    end

    -- === 眼睛朝向 ===
    local targetEyeOff = player.facingRight and 1.5 or -1.5
    eyeOffset_ = eyeOffset_ + (targetEyeOff - eyeOffset_) * math.min(1.0, 10 * dt)

    -- === 眨眼 ===
    blinkTimer_ = blinkTimer_ - dt
    if blinkTimer_ <= 0 then
        if isBlinking_ then
            isBlinking_ = false
            blinkTimer_ = math.random() * 3 + 2
        else
            isBlinking_ = true
            blinkTimer_ = 0.12
        end
    end
end

-- ============================================================================
-- 渲染
-- ============================================================================

---@param vg userdata
---@param player table
function Slime.Render(vg, player)
    local size = SLIME_BASE_SIZE * physScale_
    -- 底部中心贴合地面
    local cx = player.x + player.width / 2
    local cy = player.y + player.height  -- 脚底位置（贴地）

    -- === 主体（弹性形变，锚点在底部中心） ===
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgScale(vg, stretchX_, stretchY_)

    if slimeImage_ and slimeImage_ ~= 0 then
        -- 使用贴图渲染（底部贴地）
        local drawSize = size
        local imgPat = nvgImagePattern(vg,
            -drawSize / 2, -drawSize * 0.72,
            drawSize, drawSize,
            0, slimeImage_, 1.0)
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, -drawSize * 0.25, drawSize * 0.5, drawSize * 0.32)
        nvgFillPaint(vg, imgPat)
        nvgFill(vg)
    else
        -- 程序化果冻绘制
        local bodyW = size * 0.5
        local bodyH = size * 0.45

        -- 主体椭圆（底部贴地）
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, -bodyH, bodyW, bodyH)
        local grad = nvgLinearGradient(vg, 0, -bodyH * 2, 0, 0,
            nvgRGBA(140, 220, 255, 220),
            nvgRGBA(40, 120, 220, 240))
        nvgFillPaint(vg, grad)
        nvgFill(vg)

        -- 高光
        nvgBeginPath(vg)
        nvgEllipse(vg, -bodyW * 0.25, -bodyH * 1.4, bodyW * 0.2, bodyH * 0.25)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 160))
        nvgFill(vg)

        -- 眼睛
        local eyeY = -bodyH * 1.0
        local eyeSpacing = bodyW * 0.3
        local eyeRadius = size * 0.06

        if not isBlinking_ then
            nvgBeginPath(vg)
            nvgCircle(vg, -eyeSpacing + eyeOffset_, eyeY, eyeRadius)
            nvgFillColor(vg, nvgRGBA(20, 20, 40, 255))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, eyeSpacing + eyeOffset_, eyeY, eyeRadius)
            nvgFillColor(vg, nvgRGBA(20, 20, 40, 255))
            nvgFill(vg)
            -- 眼睛高光
            nvgBeginPath(vg)
            nvgCircle(vg, -eyeSpacing + eyeOffset_ + 1.5, eyeY - 1.5, eyeRadius * 0.4)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgCircle(vg, eyeSpacing + eyeOffset_ + 1.5, eyeY - 1.5, eyeRadius * 0.4)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgFill(vg)
        else
            -- 眨眼
            nvgBeginPath(vg)
            nvgMoveTo(vg, -eyeSpacing + eyeOffset_ - eyeRadius, eyeY)
            nvgLineTo(vg, -eyeSpacing + eyeOffset_ + eyeRadius, eyeY)
            nvgMoveTo(vg, eyeSpacing + eyeOffset_ - eyeRadius, eyeY)
            nvgLineTo(vg, eyeSpacing + eyeOffset_ + eyeRadius, eyeY)
            nvgStrokeColor(vg, nvgRGBA(20, 20, 40, 255))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)
        end

        -- 嘴巴
        local mouthY = -bodyH * 0.7
        nvgBeginPath(vg)
        nvgArc(vg, eyeOffset_ * 0.5, mouthY, size * 0.06, 0.2, math.pi - 0.2, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(20, 20, 60, 180))
        nvgStrokeWidth(vg, 1.2)
        nvgStroke(vg)
    end

    nvgRestore(vg)
end

function Slime.GetSize()
    return SLIME_BASE_SIZE * physScale_
end

return Slime

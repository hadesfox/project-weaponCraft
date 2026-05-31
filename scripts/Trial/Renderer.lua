-- ============================================================================
-- Trial/Renderer.lua - 试炼场 NanoVG 渲染
-- ============================================================================

local Config = require("Config")
local NVG = require("NVG")
local Slime = require("Trial.Slime")

local Renderer = {}

-- 试炼场背景图
local BG_IMAGE_PATH = "image/kzpncvhk5eq10kyyiudqnhs-20260531125017.png"
local bgImage_ = nil

-- 锻造师贴图（木桩替代）
local DUMMY_IMAGE_PATH = "image/主角_锻造师_20260530003547.png"
local dummyImage_ = nil
local dummyImageAspect_ = 1.0  -- 图片宽高比 (w/h)

--- 计算突刺攻击长度（纯数学函数，从TrialState提取）
--- @param progress number 攻击进度 0~1
--- @param attackRange number 攻击范围
--- @param physScale number 物理缩放
--- @return number
local function GetThrustLength(progress, attackRange, physScale)
    local len = attackRange * physScale
    if progress < 0.3 then
        return len * (progress / 0.3)
    elseif progress < 0.7 then
        return len
    else
        return len * (1.0 - (progress - 0.7) / 0.3)
    end
end

--- 释放所有 NVG 图片资源（在视频播放前调用，腾出 GPU 内存）
--- @param vg userdata
function Renderer.ReleaseImages(vg)
    if bgImage_ and bgImage_ ~= 0 then
        nvgDeleteImage(vg, bgImage_)
    end
    bgImage_ = nil
    if dummyImage_ and dummyImage_ ~= 0 then
        nvgDeleteImage(vg, dummyImage_)
    end
    dummyImage_ = nil
end

--- 预加载所有图片资源（在 Enter 时调用，避免渲染时卡顿）
--- @param vg userdata
function Renderer.Preload(vg)
    if not bgImage_ then
        bgImage_ = nvgCreateImage(vg, BG_IMAGE_PATH, 0)
    end
    if not dummyImage_ then
        dummyImage_ = nvgCreateImage(vg, DUMMY_IMAGE_PATH, 0)
        if dummyImage_ and dummyImage_ > 0 then
            local iw = IntVector2()
            local ih = IntVector2()
            nvgImageSize(vg, dummyImage_, iw, ih)
            if ih.x > 0 then
                dummyImageAspect_ = iw.x / ih.x
            end
        end
    end
end

--- 背景图
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderBackground(vg, S)
    -- 已在 Preload 中加载，这里仅做兜底
    if not bgImage_ then
        bgImage_ = nvgCreateImage(vg, BG_IMAGE_PATH, 0)
    end

    if bgImage_ and bgImage_ > 0 then
        local imgPaint = nvgImagePattern(vg, 0, 0, S.screenW, S.screenH, 0, bgImage_, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, S.screenW, S.screenH)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
    else
        -- 加载失败时的备用渐变
        local bgPaint = nvgLinearGradient(vg, 0, 0, 0, S.screenH,
            nvgRGBA(20, 22, 28, 255),
            nvgRGBA(50, 50, 55, 255))
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, S.screenW, S.screenH)
        nvgFillPaint(vg, bgPaint)
        nvgFill(vg)
    end
end

--- 地面
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderGround(vg, S)
    local groundPaint = nvgLinearGradient(vg, 0, S.groundY, 0, S.screenH,
        nvgRGBA(40, 38, 35, 255),
        nvgRGBA(20, 22, 28, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, S.groundY, S.screenW, S.screenH - S.groundY)
    nvgFillPaint(vg, groundPaint)
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, S.groundY)
    nvgLineTo(vg, S.screenW, S.groundY)
    nvgStrokeColor(vg, nvgRGBA(100, 80, 50, 200))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)
end

--- 平台
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderPlatforms(vg, S)
    for i = 1, #S.platforms do
        local p = S.platforms[i]
        nvgBeginPath(vg)
        nvgRoundedRect(vg, p.x, p.y, p.w, p.h, 4)
        nvgFillColor(vg, nvgRGBA(45, 42, 38, 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(70, 60, 45, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        -- 平台顶部高光线
        nvgBeginPath(vg)
        nvgMoveTo(vg, p.x + 2, p.y)
        nvgLineTo(vg, p.x + p.w - 2, p.y)
        nvgStrokeColor(vg, nvgRGBA(100, 80, 50, 220))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

--- 渲染靶子（哥布林）
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderTargets(vg, S)
    for i = 1, #S.targets do
        local t = S.targets[i]
        local tx = t.x + t.knockX
        local ty = t.y + t.knockY

        if t.alive then
            local scale = 1.0 - math.max(0, t.spawnAnim) * 0.5
            local sz = t.size * scale
            local imgW = sz * 1.6
            local imgH = sz * 2.0

            if S.enemyImage and S.enemyImage ~= 0 then
                local def = S.targetDefs[i]
                local standY = S.groundY - S.groundY * (def and def.platformRy or 0)
                local imgY = standY - imgH * 0.80
                local imgPaint = nvgImagePattern(vg, tx - imgW / 2, imgY, imgW, imgH, 0, S.enemyImage, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, tx - imgW / 2, imgY, imgW, imgH)
                nvgFillPaint(vg, imgPaint)
                nvgFill(vg)
            else
                nvgBeginPath(vg)
                nvgRoundedRect(vg, tx - sz * 0.4, ty - sz, sz * 0.8, sz * 2, 3)
                nvgFillColor(vg, nvgRGBA(50, 50, 55, 230))
                nvgFill(vg)
            end

        elseif t.hitAnim > 0 then
            local alpha = math.floor(t.hitAnim * 200)
            local expand = (1 - t.hitAnim) * 30
            for a = 0, 4 do
                local angle = a * math.pi * 2 / 5 + t.hitAnim * 3
                local fx = tx + math.cos(angle) * expand
                local fy = ty + math.sin(angle) * expand
                nvgBeginPath(vg)
                nvgRect(vg, fx - 4, fy - 4, 8, 8)
                nvgFillColor(vg, nvgRGBA(200, 80, 40, alpha))
                nvgFill(vg)
            end
        end
    end
end

--- 渲染木桩（锻造师贴图）
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderDummy(vg, S)
    if not S.dummy then return end

    -- 懒加载贴图并获取宽高比
    if not dummyImage_ then
        dummyImage_ = nvgCreateImage(vg, DUMMY_IMAGE_PATH, 0)
        if dummyImage_ and dummyImage_ ~= 0 then
            local imgW, imgH = nvgImageSize(vg, dummyImage_)
            if imgH and imgH > 0 then
                dummyImageAspect_ = imgW / imgH
            end
        end
    end

    local dx = S.dummy.x
    local dy = S.dummy.y
    local dh = S.dummy.height
    -- 以高度为基准，按图片真实宽高比计算渲染宽度
    local dw = dh * dummyImageAspect_

    local shakeX = 0
    if S.dummy.hitAnim > 0 then
        shakeX = math.sin(S.dummy.hitAnim * 20) * 4 * S.dummy.hitAnim * S.dummy.hitDir
    end

    -- 移动时的上下晃动（走路动画）
    local bobY = 0
    if S.dummyMoving then
        bobY = math.sin(os.clock() * 12) * 3 * S.physScale
    end

    -- 用锻造师贴图渲染（朝向跟随攻击方向）
    if dummyImage_ and dummyImage_ ~= 0 then
        nvgSave(vg)
        -- 以脚底中心为锚点，翻转朝向
        local anchorX = dx + shakeX
        local anchorY = dy + bobY
        nvgTranslate(vg, anchorX, anchorY)
        -- 贴图原始朝左，dummyFacingRight 时翻转
        if S.dummyFacingRight then
            nvgScale(vg, -1, 1)
        end
        local drawX = -dw / 2
        local drawY = -dh
        local imgPat = nvgImagePattern(vg, drawX, drawY, dw, dh, 0, dummyImage_, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, drawX, drawY, dw, dh)
        nvgFillPaint(vg, imgPat)
        nvgFill(vg)
        nvgRestore(vg)
    else
        -- 贴图加载失败时的 fallback：简单矩形
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dx - dw / 2 + shakeX, dy - dh, dw, dh, 4)
        nvgFillColor(vg, nvgRGBA(50, 50, 55, 240))
        nvgFill(vg)
    end

    -- 受击闪光
    if S.dummy.hitAnim > 0.5 then
        local alpha = math.floor((S.dummy.hitAnim - 0.5) * 2 * 200)
        nvgBeginPath(vg)
        nvgCircle(vg, dx + shakeX, dy - dh / 2, 20 * S.physScale)
        nvgFillColor(vg, nvgRGBA(255, 255, 200, alpha))
        nvgFill(vg)
    end
end

--- 渲染突刺攻击
--- @param vg userdata
--- @param S table 共享状态表
--- @param atk table 攻击数据
--- @param progress number 进度
--- @param originX number
--- @param originY number
--- @param wc table 武器颜色
function Renderer.RenderThrustAttack(vg, S, atk, progress, originX, originY, wc)
    local dir = S.player.facingRight and 1 or -1
    local len = GetThrustLength(progress, atk.range, S.physScale)
    local tipX = originX + dir * len
    local tipY = originY

    local weaponAngle = S.player.facingRight and (math.pi / 2) or (-math.pi / 2)
    local flipX = not S.player.facingRight
    Renderer.RenderWeaponShape(vg, S, originX + dir * len * 0.5, originY, weaponAngle, wc, 0.8 * S.physScale, flipX)

    nvgBeginPath(vg)
    nvgMoveTo(vg, originX, originY)
    nvgLineTo(vg, tipX, tipY)
    nvgStrokeColor(vg, nvgRGBA(wc[1], wc[2], wc[3], 120))
    nvgStrokeWidth(vg, 3)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgCircle(vg, tipX, tipY, 4 * (1 - progress) * S.physScale)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(200 * (1 - progress))))
    nvgFill(vg)
end

--- 渲染挥动攻击
--- @param vg userdata
--- @param S table 共享状态表
--- @param atk table 攻击数据
--- @param progress number 进度
--- @param originX number
--- @param originY number
--- @param wc table 武器颜色
function Renderer.RenderSwingAttack(vg, S, atk, progress, originX, originY, wc)
    local range = atk.range * S.physScale
    local easedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
    local arcDir = (atk.direction or 1)
    local startAngle = math.rad(atk.startAngle or -60)
    local sweepAngle = math.rad(atk.arc) * arcDir * easedProgress

    local currentAngle
    if S.player.facingRight then
        currentAngle = startAngle + sweepAngle
    else
        currentAngle = math.pi - (startAngle + sweepAngle)
    end

    local tipX = originX + math.cos(currentAngle) * range
    local tipY = originY + math.sin(currentAngle) * range

    -- 挥动轨迹
    local trailAlpha = math.floor((1 - progress) * 40)
    nvgBeginPath(vg)
    nvgMoveTo(vg, originX, originY)
    local steps = 10
    for s = 0, steps do
        local t = easedProgress * s / steps
        local a
        if S.player.facingRight then
            a = startAngle + math.rad(atk.arc) * arcDir * t
        else
            a = math.pi - (startAngle + math.rad(atk.arc) * arcDir * t)
        end
        nvgLineTo(vg, originX + math.cos(a) * range, originY + math.sin(a) * range)
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(wc[1], wc[2], wc[3], trailAlpha))
    nvgFill(vg)

    -- 武器形状
    local weaponAngle = currentAngle + math.pi / 2
    local weaponX = originX + math.cos(currentAngle) * range * 0.6
    local weaponY = originY + math.sin(currentAngle) * range * 0.6
    local flipX = not S.player.facingRight
    Renderer.RenderWeaponShape(vg, S, weaponX, weaponY, weaponAngle, wc, 1.0 * S.physScale, flipX)

    -- 刃尖光芒
    local glowAlpha = math.floor(180 * (1 - progress))
    nvgBeginPath(vg)
    nvgCircle(vg, tipX, tipY, 5 * (1 - progress * 0.5) * S.physScale)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, glowAlpha))
    nvgFill(vg)
end

--- 渲染攻击效果入口
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderAttack(vg, S)
    if not S.attacking or not S.currentAttack then return end

    local atk = S.currentAttack
    local progress = S.attackTimer / S.attackDuration
    local dir = S.player.facingRight and 1 or -1
    local originX = S.player.x + S.player.width / 2 + dir * 10 * S.physScale
    local originY = S.player.y + S.player.height * 0.4
    local wc = S.gameData and S.gameData.weaponData and S.gameData.weaponData.typeInfo.color or {200, 200, 200}

    if atk.isThrust then
        Renderer.RenderThrustAttack(vg, S, atk, progress, originX, originY, wc)
    else
        Renderer.RenderSwingAttack(vg, S, atk, progress, originX, originY, wc)
    end
end

--- 渲染武器形状（玩家绘制的笔画）
--- @param vg userdata
--- @param S table 共享状态表
--- @param cx number
--- @param cy number
--- @param angle number
--- @param color table
--- @param scale number
--- @param flipX boolean
function Renderer.RenderWeaponShape(vg, S, cx, cy, angle, color, scale, flipX)
    if #S.weaponStrokes == 0 then
        Renderer.RenderDefaultWeapon(vg, cx, cy, angle, color)
        return
    end

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)
    if flipX then
        nvgScale(vg, -scale, scale)
    else
        nvgScale(vg, scale, scale)
    end

    for i = 1, #S.weaponStrokes do
        local stroke = S.weaponStrokes[i]
        local pts = stroke.points
        if #pts >= 2 then
            nvgBeginPath(vg)
            nvgMoveTo(vg, pts[1].x, pts[1].y)

            for j = 2, #pts do
                if j < #pts then
                    local mx = (pts[j].x + pts[j + 1].x) * 0.5
                    local my = (pts[j].y + pts[j + 1].y) * 0.5
                    nvgQuadTo(vg, pts[j].x, pts[j].y, mx, my)
                else
                    nvgLineTo(vg, pts[j].x, pts[j].y)
                end
            end

            if stroke.closed then
                nvgClosePath(vg)
                nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], 80))
                nvgFill(vg)
            end

            nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
            nvgStrokeWidth(vg, 3)
            nvgLineCap(vg, NVG_ROUND)
            nvgLineJoin(vg, NVG_ROUND)
            nvgStroke(vg)
        end
    end

    nvgRestore(vg)
end

--- 默认武器渲染（无笔画时）
--- @param vg userdata
--- @param cx number
--- @param cy number
--- @param angle number
--- @param color table
function Renderer.RenderDefaultWeapon(vg, cx, cy, angle, color)
    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    nvgRotate(vg, angle)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, -25)
    nvgLineTo(vg, 0, 25)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], 230))
    nvgStrokeWidth(vg, 4)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)

    -- 护手
    nvgBeginPath(vg)
    nvgMoveTo(vg, -8, 15)
    nvgLineTo(vg, 8, 15)
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    nvgRestore(vg)
end

--- 计算玩家动画参数
--- @param S table 共享状态表
--- @return number bobY, number lean, number scaleX, number scaleY
function Renderer.CalcPlayerAnimParams(S)
    local player = S.player
    local state = player.state
    local t = player.animTime
    local bobY = 0
    local lean = 0
    local scaleX = 1.0
    local scaleY = 1.0

    if state == "run" then
        bobY = math.sin(t) * 3 * S.physScale
        lean = (player.facingRight and 1 or -1) * 0.06
        local squishPhase = math.sin(t * 2)
        scaleX = 1.0 + squishPhase * 0.03
        scaleY = 1.0 - squishPhase * 0.03
    elseif state == "idle" then
        bobY = math.sin(t) * 1 * S.physScale
        scaleY = 1.0 + math.sin(t) * 0.015
        scaleX = 1.0 - math.sin(t) * 0.01
    end

    -- 着地压缩回弹
    if player.landSquash > 0 then
        local total = 0.15
        local t_norm = 1.0 - (player.landSquash / total)
        local squash
        if t_norm < 0.35 then
            squash = (t_norm / 0.35) * 0.12
        elseif t_norm < 0.65 then
            local p = (t_norm - 0.35) / 0.3
            squash = 0.12 * (1.0 - p * 2.0)
        else
            local p = (t_norm - 0.65) / 0.35
            squash = -0.12 * (1.0 - p)
        end
        scaleX = 1.0 + squash * 0.5
        scaleY = 1.0 - squash
    end

    return bobY, lean, scaleX, scaleY
end

--- 渲染玩家精灵
--- @param vg userdata
--- @param S table 共享状态表
--- @param bobY number
--- @param lean number
--- @param scaleX number
--- @param scaleY number
function Renderer.RenderPlayerSprite(vg, S, bobY, lean, scaleX, scaleY)
    local player = S.player
    local px = player.x
    local py = player.y
    local pw = player.width
    local ph = player.height

    local currentFrame = S.playerImage
    if player.state == "run" and #S.playerRunFrames > 0 then
        local idx = math.max(1, math.min(S.playerFrameIndex, #S.playerRunFrames))
        local frame = S.playerRunFrames[idx]
        if frame and frame ~= 0 then
            local fw, fh = nvgImageSize(vg, frame)
            if fw > 0 and fh > 0 then
                currentFrame = frame
            end
        end
    end

    if currentFrame and currentFrame ~= 0 then
        nvgSave(vg)
        local imgSize = ph / scaleY

        local anchorX = px + pw / 2
        local anchorY = py + ph
        nvgTranslate(vg, anchorX, anchorY + bobY)
        nvgRotate(vg, lean)
        nvgScale(vg, scaleX, scaleY)
        if player.facingRight then nvgScale(vg, -1, 1) end

        local drawX = -imgSize / 2
        local drawY = -imgSize
        local imgPaint = nvgImagePattern(vg, drawX, drawY, imgSize, imgSize, 0, currentFrame, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, drawX, drawY, imgSize, imgSize)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
        nvgRestore(vg)
    else
        nvgBeginPath(vg)
        nvgRoundedRect(vg, px, py + bobY, pw, ph, 4)
        nvgFillColor(vg, nvgRGBA(150, 200, 255, 230))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 180))
        nvgStrokeWidth(vg, 2)
        nvgStroke(vg)
    end
end

--- 渲染跑步烟尘
--- @param vg userdata
--- @param S table 共享状态表
--- @param bobY number
function Renderer.RenderRunDust(vg, S, bobY)
    local player = S.player
    if player.state ~= "run" or not player.onGround then return end

    local footX = player.x + player.width / 2
    local footY = player.y + player.height + bobY
    local dustPhase = math.sin(player.animTime + 1.5)
    if dustPhase > 0.7 then
        local alpha = math.floor((dustPhase - 0.7) / 0.3 * 80)
        local dustDir = player.facingRight and -1 or 1
        nvgBeginPath(vg)
        nvgCircle(vg, footX + dustDir * 6 * S.physScale, footY - 2 * S.physScale, 3 * S.physScale)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, alpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, footX + dustDir * 12 * S.physScale, footY - 4 * S.physScale, 2 * S.physScale)
        nvgFillColor(vg, nvgRGBA(120, 130, 140, math.floor(alpha * 0.6)))
        nvgFill(vg)
    end
end

--- 渲染玩家入口
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderPlayer(vg, S)
    local bobY, lean, scaleX, scaleY = Renderer.CalcPlayerAnimParams(S)
    Renderer.RenderPlayerSprite(vg, S, bobY, lean, scaleX, scaleY)
    Renderer.RenderRunDust(vg, S, bobY)
end

--- 命中特效渲染
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderHitEffects(vg, S)
    local fontId = NVG.GetFont()
    if fontId == -1 then return end

    nvgFontFaceId(vg, fontId)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for i = 1, #S.hitEffects do
        local e = S.hitEffects[i]
        local alpha = math.floor(e.timer * 255)
        local size = math.floor(14 + (1 - e.timer) * 4)
        nvgFontSize(vg, size)
        nvgFillColor(vg, nvgRGBA(e.color[1], e.color[2], e.color[3], alpha))
        nvgText(vg, e.x, e.y, e.text, nil)
    end
end

--- 连击渲染
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderCombo(vg, S)
    if S.combo < 2 then return end

    local fontId = NVG.GetFont()
    if fontId == -1 then return end

    nvgFontFaceId(vg, fontId)
    local size = math.min(32, 16 + S.combo * 2)
    local pulse = 1.0 + math.sin(S.comboTimer * 8) * 0.08
    nvgFontSize(vg, math.floor(size * pulse))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)

    local alpha = math.floor(255 * math.max(0, 1.0 - S.comboTimer / Config.Trial.ComboDecayTime))
    nvgFillColor(vg, nvgRGBA(160, 140, 90, alpha))
    nvgText(vg, S.screenW / 2, 90, S.combo .. " COMBO!", nil)
end

--- 变形特效渲染
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderTransformEffect(vg, S)
    if S.transformAnim <= 0 then return end

    local alpha = math.floor(S.transformAnim * 200)
    local expand = (1 - S.transformAnim) * 40
    local cx = S.player.x + S.player.width / 2
    local cy = S.player.y + S.player.height / 2

    -- 光环
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, 20 + expand)
    nvgStrokeColor(vg, nvgRGBA(160, 140, 90, alpha))
    nvgStrokeWidth(vg, 3 * S.transformAnim)
    nvgStroke(vg)

    -- 粒子
    for i = 0, 5 do
        local angle = i * math.pi * 2 / 6 + S.transformAnim * 5
        local r = 15 + expand * 0.5
        local px = cx + math.cos(angle) * r
        local py = cy + math.sin(angle) * r
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, 3 * S.transformAnim)
        nvgFillColor(vg, nvgRGBA(160, 140, 90, alpha))
        nvgFill(vg)
    end

    -- 形态名称闪现
    if S.transformAnim > 0.5 then
        local fontId = NVG.GetFont()
        if fontId ~= -1 then
            nvgFontFaceId(vg, fontId)
            nvgFontSize(vg, 16)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            local textAlpha = math.floor((S.transformAnim - 0.5) * 2 * 255)
            nvgFillColor(vg, nvgRGBA(160, 140, 90, textAlpha))
            nvgText(vg, cx, cy - 35, S.formNames[S.currentForm], nil)
        end
    end
end

--- 渲染木桩武器
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderDummyWeapon(vg, S)
    if not S.dummyWeapon or not S.dummy then return end
    -- 仅攻击时显示武器（平时隐藏，无法格挡）
    if not S.dummyAttacking then return end

    local dw = S.dummyWeapon

    -- 使用与玩家相同的绘制武器形状和颜色（略暗，表示敌方）
    local wc = S.gameData and S.gameData.weaponData and S.gameData.weaponData.typeInfo.color or {200, 200, 200}
    -- 木桩武器颜色偏暗红，区分于玩家
    local dummyColor = { math.min(255, wc[1] + 40), math.max(0, wc[2] - 60), math.max(0, wc[3] - 60) }

    -- 计算武器中心点和角度
    local midX = (dw.rootX + dw.tipX) / 2
    local midY = (dw.rootY + dw.tipY) / 2
    local weaponAngle = dw.angle + math.pi / 2
    local flipX = not S.dummyFacingRight

    -- 使用 RenderWeaponShape 渲染与玩家相同的武器形状
    Renderer.RenderWeaponShape(vg, S, midX, midY, weaponAngle, dummyColor, 1.0 * S.physScale, flipX)

    -- 挥动轨迹特效（仅挥砍时）
    if S.dummyCurrentAttack and not S.dummyCurrentAttack.isThrust then
        local progress = S.dummyAttackProgress or 0
        local trailAlpha = math.floor((1 - progress) * 30)
        if trailAlpha > 0 then
            nvgBeginPath(vg)
            nvgMoveTo(vg, dw.rootX, dw.rootY)
            nvgLineTo(vg, dw.tipX, dw.tipY)
            nvgStrokeColor(vg, nvgRGBA(dummyColor[1], dummyColor[2], dummyColor[3], trailAlpha))
            nvgStrokeWidth(vg, 6 * S.physScale)
            nvgLineCap(vg, NVG_ROUND)
            nvgStroke(vg)
        end
    end
end

--- 渲染被弹开的武器（格挡后武器飞出动画）
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderDeflectedWeapon(vg, S)
    if not S.deflecting then return end

    local t = S.deflectTimer / S.deflectDuration  -- 0~1 进度
    local alpha = math.floor((1 - t) * 255)       -- 逐渐消失
    local speed = 180 * S.physScale                -- 弹飞速度（像素/秒）

    -- 武器沿弹开方向飞出
    local dist = speed * S.deflectTimer
    local wx = S.deflectStartX + math.cos(S.deflectAngle) * dist
    local wy = S.deflectStartY + math.sin(S.deflectAngle) * dist - 30 * t  -- 轻微上抛弧线

    -- 武器旋转（快速旋转表示被弹飞）
    local weaponAngle = S.deflectWeaponAngle + S.deflectSpin * S.deflectTimer

    -- 缩放：略微缩小表示远离
    local scale = (1.0 - t * 0.3) * S.physScale

    -- 获取武器颜色
    local wc = S.gameData and S.gameData.weaponData and S.gameData.weaponData.typeInfo.color or {200, 200, 200}

    -- 用 RenderWeaponShape 渲染弹飞的武器（带透明度）
    nvgSave(vg)
    nvgGlobalAlpha(vg, alpha / 255)
    Renderer.RenderWeaponShape(vg, S, wx, wy, weaponAngle, wc, scale, false)
    nvgRestore(vg)

    -- 武器运动轨迹（残影效果）
    for i = 1, 3 do
        local trailT = math.max(0, S.deflectTimer - i * 0.03)
        local trailDist = speed * trailT
        local tx = S.deflectStartX + math.cos(S.deflectAngle) * trailDist
        local ty = S.deflectStartY + math.sin(S.deflectAngle) * trailDist - 30 * (trailT / S.deflectDuration)
        local trailAlpha = math.floor(alpha * (0.3 - i * 0.08))
        if trailAlpha > 0 then
            nvgSave(vg)
            nvgGlobalAlpha(vg, trailAlpha / 255)
            local trailAngle = S.deflectWeaponAngle + S.deflectSpin * trailT
            Renderer.RenderWeaponShape(vg, S, tx, ty, trailAngle, wc, scale * 0.9, false)
            nvgRestore(vg)
        end
    end
end

--- 渲染武器碰撞特效
--- @param vg userdata
--- @param S table 共享状态表
function Renderer.RenderWeaponClash(vg, S)
    if S.weaponClashAnim <= 0 then return end

    local alpha = math.floor(S.weaponClashAnim * 255)
    local expand = (1 - S.weaponClashAnim) * 25

    -- 中心闪光
    nvgBeginPath(vg)
    nvgCircle(vg, S.weaponClashX, S.weaponClashY, 8 + expand * 0.5)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, alpha))
    nvgFill(vg)

    -- 火花粒子
    for i = 0, 7 do
        local angle = i * math.pi * 2 / 8 + S.weaponClashAnim * 2
        local sparkDist = expand * (0.8 + math.sin(i * 1.7) * 0.3)
        local sx = S.weaponClashX + math.cos(angle) * sparkDist
        local sy = S.weaponClashY + math.sin(angle) * sparkDist
        local sparkSize = 2 + S.weaponClashAnim * 2
        nvgBeginPath(vg)
        nvgCircle(vg, sx, sy, sparkSize)
        nvgFillColor(vg, nvgRGBA(255, 180, 50, math.floor(alpha * 0.8)))
        nvgFill(vg)
    end

    -- 冲击波环
    nvgBeginPath(vg)
    nvgCircle(vg, S.weaponClashX, S.weaponClashY, 5 + expand * 1.5)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 200, math.floor(alpha * 0.5)))
    nvgStrokeWidth(vg, 2 * S.weaponClashAnim)
    nvgStroke(vg)
end

-- ============================================================================
-- 血条渲染
-- ============================================================================

--- 渲染单个血条
--- @param vg userdata
--- @param cx number 中心X
--- @param cy number 顶部Y（血条上沿）
--- @param hp number 当前HP
--- @param maxHp number 最大HP
--- @param physScale number 物理缩放
local function RenderHPBar(vg, cx, cy, hp, maxHp, physScale)
    if hp >= maxHp then return end  -- 满血不显示
    if hp <= 0 then return end      -- 已死不显示

    local barW = Config.Combat.HPBarWidth * physScale
    local barH = Config.Combat.HPBarHeight * physScale
    local x = cx - barW / 2
    local y = cy

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, barW, barH, barH / 2)
    nvgFillColor(vg, nvgRGBA(20, 20, 20, 180))
    nvgFill(vg)

    -- HP 填充
    local ratio = hp / maxHp
    local fillW = barW * ratio

    -- 颜色根据血量比例变化：绿→黄→红
    local r, g, b
    if ratio > 0.5 then
        local t = (ratio - 0.5) * 2
        r = math.floor(255 * (1 - t) + 80 * t)
        g = math.floor(200 * t + 200 * (1 - t))
        b = 60
    else
        local t = ratio * 2
        r = 240
        g = math.floor(200 * t)
        b = math.floor(60 * t)
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, fillW, barH, barH / 2)
    nvgFillColor(vg, nvgRGBA(r, g, b, 230))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, barW, barH, barH / 2)
    nvgStrokeColor(vg, nvgRGBA(40, 40, 40, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

--- 渲染所有靶子血条
--- @param vg userdata
--- @param S table
function Renderer.RenderTargetHPBars(vg, S)
    for i = 1, #S.targets do
        local t = S.targets[i]
        if t.alive and t.hp and t.maxHp then
            local tx = t.x + (t.knockX or 0)
            local ty = t.y + (t.knockY or 0)
            local offsetY = Config.Combat.HPBarOffsetY * S.physScale
            -- 血条位于敌人头顶
            local barY = ty - (t.size or 30) + offsetY
            RenderHPBar(vg, tx, barY, t.hp, t.maxHp, S.physScale)
        end
    end
end

--- 渲染木桩血条
--- @param vg userdata
--- @param S table
function Renderer.RenderDummyHPBar(vg, S)
    if not S.dummy then return end
    local d = S.dummy
    if not d.hp or not d.maxHp then return end

    local shakeX = 0
    if d.hitAnim > 0 then
        shakeX = math.sin(d.hitAnim * 20) * 4 * d.hitAnim * (d.hitDir or 0)
    end

    local cx = d.x + shakeX
    local barY = d.y - d.height - Config.Combat.HPBarHeight * S.physScale - 8 * S.physScale
    RenderHPBar(vg, cx, barY, d.hp, d.maxHp, S.physScale)
end

return Renderer
